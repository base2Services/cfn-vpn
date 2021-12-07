import socket
import boto3
from botocore.exceptions import ClientError
from lib.slack import Slack
from states import *
import logging

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

SLACK_USERNAME = 'CfnVpn Route Table Event'

def delete_route(client, vpn_endpoint, subnet, cidr):
  try:
    client.delete_client_vpn_route(
      ClientVpnEndpointId=vpn_endpoint,
      TargetVpcSubnetId=subnet,
      DestinationCidrBlock=cidr,
    )
  except ClientError as e:
    if e.response['Error']['Code'] == 'InvalidClientVpnEndpointAuthorizationRuleNotFound':
      logger.info(f"route not found when deleting", exc_info=True)
    else:
      raise e

  
def create_route(client, event, cidr):
  description = f"cfnvpn auto generated route for endpoint {event['Record']}."
  if event['Description']:
    description += f" {event['Description']}"

  client.create_client_vpn_route(
    ClientVpnEndpointId=event['ClientVpnEndpointId'],
    DestinationCidrBlock=cidr,
    TargetVpcSubnetId=event['TargetSubnet'],
    Description=description
  )


def revoke_route_auth(client, event, cidr, group = None):
  args = {
    'ClientVpnEndpointId': event['ClientVpnEndpointId'],
    'TargetNetworkCidr': cidr
  }
  
  if group is None:
    args['RevokeAllGroups'] = True
  else:
    args['AccessGroupId'] = group
  
  try:
    client.revoke_client_vpn_ingress(**args)
  except ClientError as e:
    if e.response['Error']['Code'] == 'ConcurrentMutationLimitExceeded':
      logger.warn(f"revoking auth is being rate limited", exc_info=True)
    elif e.response['Error']['Code'] == 'InvalidClientVpnEndpointAuthorizationRuleNotFound':
      logger.info(f"rule not found when revoking", exc_info=True)
    else:
      raise e


def authorize_route(client, event, cidr, group = None):
  description = f"cfnvpn auto generated authorization for endpoint {event['Record']}."
  if event['Description']:
    description += f" {event['Description']}"

  args = {
    'ClientVpnEndpointId': event['ClientVpnEndpointId'],
    'TargetNetworkCidr': cidr,
    'Description': description
  }
  
  if group is None:
    args['AuthorizeAllGroups'] = True
  else:
    args['AccessGroupId'] = group
    
  client.authorize_client_vpn_ingress(**args)


def get_routes(client, event):
  response = client.describe_client_vpn_routes(
    ClientVpnEndpointId=event['ClientVpnEndpointId'],
    Filters=[
      {
        'Name': 'origin',
        'Values': ['add-route']
      }
    ]
  )
  
  routes = [route for route in response['Routes'] if event['Record'] in route['Description']]
  logger.info(f"found {len(routes)} exisiting routes for {event['Record']}")
  return routes


def get_rules(client, vpn_endpoint, cidr):
  response = client.describe_client_vpn_authorization_rules(
    ClientVpnEndpointId=vpn_endpoint,
    Filters=[
        {
            'Name': 'destination-cidr',
            'Values': [cidr]
        }
    ]
  )
  return response['AuthorizationRules']


def handler(event,context):

  logger.info(f"auto route populator triggered with event : {event}")
  slack = Slack(username=SLACK_USERNAME)
  
  # DNS lookup on the dns record and return all IPS for the endpoint
  try:
    cidrs = [ ip + "/32" for ip in socket.gethostbyname_ex(event['Record'])[-1]]
    logger.info(f"resolved endpoint {event['Record']} to {cidrs}")
  except socket.gaierror as e:
    logger.error(f"failed to resolve record {event['Record']}", exc_info=True)
    slack.post_event(message=f"failed to resolve record {event['Record']}", state=RESOLVE_FAILED, error=e)
    return 'KO'
  
  client = boto3.client('ec2')

  # describe vpn and check if subnets are associated with the vpn
  response = client.describe_client_vpn_endpoints(
    ClientVpnEndpointIds=[event['ClientVpnEndpointId']]
  )

  if not response['ClientVpnEndpoints']:
    logger.error(f"endpoint not found")
    slack.post_event(message=f"failed create routes for {event['Record']}", state=FAILED, error="endpoint not found")
    return 'KO'

  endpoint = response['ClientVpnEndpoints'][0]
  if endpoint['Status'] == 'pending-associate':
    logger.error(f"no subnets associated with endpoint")
    slack.post_event(message=f"failed create routes for {event['Record']}", state=FAILED, error="vpn is in a stopped state")
    return 'KO'

  routes = get_routes(client, event)

  for cidr in cidrs:
    route = next((route for route in routes if route['DestinationCidr'] == cidr), None)
    
    # if there are no existing routes for the endpoint cidr create a new route
    if route is None:
      try:
        create_route(client, event, cidr)
        if 'Groups' in event:
          for group in event['Groups']:
            authorize_route(client, event, cidr, group)
        else:
          authorize_route(client, event, cidr)
      except ClientError as e:
        if e.response['Error']['Code'] == 'InvalidClientVpnDuplicateRoute':
          logger.error(f"route for CIDR {cidr} already exists with a different endpoint")
          continue
        elif e.response['Error']['Code'] == 'ClientVpnRouteLimitExceeded':
          logger.error("vpn route table has reached the route limit", exc_info=True)
          slack.post_event(
            message=f"unable to create route {cidr} from {event['Record']}",
            state=ROUTE_LIMIT_EXCEEDED,
            error="vpn route table has reached the route limit"
          )
          continue
        elif e.response['Error']['Code'] == 'ClientVpnAuthorizationRuleLimitExceeded':
          logger.error("vpn has reached the authorization rule limit", exc_info=True)
          slack.post_event(
            message=f"unable add to authorization rule for route {cidr} from {event['Record']}",
            state=AUTH_RULE_LIMIT_EXCEEDED,
            error="vpn has reached the authorization rule limit"
          )
          continue
        elif e.response['Error']['Code'] == 'ConcurrentMutationLimitExceeded':
          logger.error("authorization rule modifications are being rated limited", exc_info=True)
          slack.post_event(
            message=f"unable to add authorization rule for route {cidr} from {event['Record']}", 
            state=RATE_LIMIT_EXCEEDED,
            error="authorization rule modifications are being rated limited"
          )
          continue
        elif e.response['Error']['Code'] == 'InvalidClientVpnActiveAssociationNotFound':
          logger.error("no subnets are associated with the vpn", exc_info=True)
          slack.post_event(
            message=f"unable to create the route {cidr} from {event['Record']}", 
            state=SUBNET_NOT_ASSOCIATED,
            error="no subnets are associated with the vpn"
          )
          continue
        raise e

      slack.post_event(message=f"added new route {cidr} for DNS entry {event['Record']}", state=NEW_ROUTE)
        
    # if the route already exists
    else:
      
      logger.info(f"route for cidr {cidr} is already in place")
      
      # if the target subnet has changed in the payload, recreate the routes to use the new subnet
      if route['TargetSubnet'] != event['TargetSubnet']:
        logger.info(f"target subnet for route for {cidr} has changed, recreating the route")
        delete_route(client, event['ClientVpnEndpointId'], route['TargetSubnet'], cidr)
        create_route(client, event, cidr)
      
      logger.info(f"checking authorization rules for the route")
      
      # check the rules match the payload
      rules = get_rules(client, event['ClientVpnEndpointId'], cidr)
      existing_groups = [rule['GroupId'] for rule in rules]
      if 'Groups' in event:
        # remove expired rules not defined in the payload anymore
        expired_rules = [rule for rule in rules if rule['GroupId'] not in event['Groups']]
        for rule in expired_rules:
          logger.info(f"removing expired authorization rule for group {rule['GroupId']} for route {cidr}")
          revoke_route_auth(client, event, cidr, rule['GroupId'])
        # add new rules defined in the payload
        new_rules =  [group for group in event['Groups'] if group not in existing_groups]
        for group in new_rules:
          logger.info(f"creating new authorization rule for group {rule['GroupId']} for route {cidr}")
          authorize_route(client, event, cidr, group)
      else:
        # if amount of rules for the cidr is greater than 1 when no groups are specified in the payload 
        # we'll assume that all groups have been removed from the payload so we'll remove all existing rules and add a rule for allow all 
        if len(rules) > 1:
          logger.info(f"creating an allow all rule for route {cidr}")
          revoke_route_auth(client, event, cidr)
          authorize_route(client, event, cidr)
          
      

  
  # clean up any expired routes when the ips for an endpoint change
  expired_routes = [route for route in routes if route['DestinationCidr'] not in cidrs]
  for route in expired_routes:
    logger.info(f"removing expired route {route['DestinationCidr']} for endpoint {event['Record']}")
    revoke_route_auth(client, event, route['DestinationCidr'])
    delete_route(client, event['ClientVpnEndpointId'], route['TargetSubnet'], route['DestinationCidr'])
    slack.post_event(message=f"removed expired route {route['DestinationCidr']} for endpoint {event['Record']}", state=EXPIRED_ROUTE)
  
  return 'OK'