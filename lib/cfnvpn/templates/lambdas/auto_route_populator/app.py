import socket
import boto3
from botocore.exceptions import ClientError
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def delete_route(client, vpn_endpoint, subnet, cidr):
    client.delete_client_vpn_route(
      ClientVpnEndpointId=vpn_endpoint,
      TargetVpcSubnetId=subnet,
      DestinationCidrBlock=cidr,
    )

  
def create_route(client, event, cidr):
  client.create_client_vpn_route(
    ClientVpnEndpointId=event['ClientVpnEndpointId'],
    DestinationCidrBlock=cidr,
    TargetVpcSubnetId=event['TargetSubnet'],
    Description=f"cfnvpn auto generated route for endpoint {event['Record']}. {event['Description']}"
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
    
  client.revoke_client_vpn_ingress(**args)


def authorize_route(client, event, cidr, group = None):
  args = {
    'ClientVpnEndpointId': event['ClientVpnEndpointId'],
    'TargetNetworkCidr': cidr,
    'Description': f"cfnvpn auto generated authorization for endpoint {event['Record']}. {event['Description']}"
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
  
  # DNS lookup on the dns record and return all IPS for the endpoint
  try:
    cidrs = [ ip + "/32" for ip in socket.gethostbyname_ex(event['Record'])[-1]]
    logger.info(f"resolved endpoint {event['Record']} to {cidrs}")
  except socket.gaierror as e:
    logger.exception(f"failed to resolve record {event['Record']}")
    return 'KO'
  
  client = boto3.client('ec2')
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
        raise e
        
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
    
    try:
      revoke_route_auth(client, event, route['DestinationCidr'])
    except ClientError as e:
      if e.response['Error']['Code'] == 'InvalidClientVpnEndpointAuthorizationRuleNotFound':
        pass
      else:
        raise e
                          
    try:
      delete_route(client, event['ClientVpnEndpointId'], route['TargetSubnet'], route['DestinationCidr'])
    except ClientError as e:
      if e.response['Error']['Code'] == 'InvalidClientVpnRouteNotFound':
        pass
      else:
        raise e
  
  return 'OK'