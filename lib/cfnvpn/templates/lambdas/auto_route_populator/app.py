import os
import boto3
from botocore.exceptions import ClientError
from lib.slack import Slack
from lookup import dns_lookup, cloud_lookup
from states import *
import logging
from quotas import increase_quota, AUTH_RULE_TABLE_QUOTA_CODE, ROUTE_TABLE_QUOTA_CODE

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

  
def create_route(client, event, cidr, target_subnet, lookup_item):
  description = f"cfnvpn auto generated route for lookup {lookup_item}."
  if event['Description']:
    description += f" {event['Description']}"

  client.create_client_vpn_route(
    ClientVpnEndpointId=event['ClientVpnEndpointId'],
    DestinationCidrBlock=cidr,
    TargetVpcSubnetId=target_subnet,
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


def authorize_route(client, event, cidr, lookup_item, group = None):
  description = f"cfnvpn auto generated authorization for lookup {lookup_item}."
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


def get_routes(client, event, lookup_item):
  paginator = client.get_paginator('describe_client_vpn_routes')
  response_iterator = paginator.paginate(
    ClientVpnEndpointId=event['ClientVpnEndpointId'],
    Filters=[
      {
        'Name': 'origin',
        'Values': ['add-route']
      }
    ]
  )
 
  return [route for page in response_iterator 
            for route in page['Routes'] 
            if 'Description' in route and lookup_item in route['Description']]


def get_auth_rules(client, event, lookup_item):
  paginator = client.get_paginator('describe_client_vpn_authorization_rules')
  response_iterator = paginator.paginate(
    ClientVpnEndpointId=event['ClientVpnEndpointId']
  )

  return [rule for page in response_iterator 
            for rule in page['AuthorizationRules']
            if 'Description' in rule and lookup_item in rule['Description']]


def expired_auth_rules(auth_rules, cidrs, groups):
  for rule in auth_rules:
    # if there is a rule for the record with an old cidr
    if rule['DestinationCidr'] not in cidrs:
      yield rule
    # if there is a rule for a group that is no longer in the event
    if groups and rule['GroupId'] not in groups:
      yield rule
    # if there is a rule for allow all but groups are in the event
    if groups and rule['AccessAll']:
      yield rule


def expired_routes(routes, cidrs):
  for route in routes:
    if route['DestinationCidr'] not in cidrs:
      yield route


def handler(event,context):

  logger.info(f"auto route populator triggered with event : {event}")
  slack = Slack(username=SLACK_USERNAME)

  lookup_type = None
  
  if 'Record' in event:
    cidrs = dns_lookup(event['Record'])
    lookup_item = event['Record']
    if cidrs is None:
      slack.post_event(message=f"failed to resolve record {event['Record']}", state=RESOLVE_FAILED)
    logger.info(f"dns lookup found {len(cidrs)} IP's")
  elif 'Cloud' in event:
    cidrs = cloud_lookup(event['Cloud'], event.get('Filters', []))
    lookup_item = f"cloud:{event['Cloud']}"
    logger.info(f"cloud {event['Cloud']} lookup found {len(cidrs)} IP address ranges")
  else:
    logger.error("one of [ Record | Cloud ] not found in event")
    return 'KO'

  if not cidrs:
    logger.error(f"no cidrs found")
    return 'KO'

  client = boto3.client('ec2')

  # describe vpn and check if subnets are associated with the vpn
  response = client.describe_client_vpn_endpoints(
    ClientVpnEndpointIds=[event['ClientVpnEndpointId']]
  )

  if not response['ClientVpnEndpoints']:
    logger.error(f"endpoint not found")
    slack.post_error(lookup_item, FAILED, "endpoint not found")
    return 'KO'

  endpoint = response['ClientVpnEndpoints'][0]
  if endpoint['Status'] == 'pending-associate':
    logger.error(f"no subnets associated with endpoint")
    slack.post_error(lookup_item, FAILED, "vpn is in a stopped state")
    return 'KO'

  routes = get_routes(client, event, lookup_item)
  auth_rules = get_auth_rules(client, event, lookup_item)

  auto_limit_increase = os.environ.get('AUTO_LIMIT_INCREASE')
  route_limit_increase_required = False
  auth_rules_limit_increase_required = False

  for cidr in cidrs:
    # create route if doesn't exist
    for subnet in event['TargetSubnets']:
      if not any(route['DestinationCidr'] == cidr and route['TargetSubnet'] == subnet for route in routes):
        try:
          create_route(client, event, cidr, subnet, lookup_item)
        except ClientError as e:
          if e.response['Error']['Code'] == 'ClientVpnRouteLimitExceeded':
            route_limit_increase_required = True
            logger.error("vpn route table has reached the route limit", exc_info=True)
            slack.post_error(lookup_item, ROUTE_LIMIT_EXCEEDED, "vpn route table has reached the route limit")
          elif e.response['Error']['Code'] == 'InvalidClientVpnActiveAssociationNotFound':
            logger.warn("no subnets are associated with the vpn", exc_info=True)
            slack.post_error(lookup_item, SUBNET_NOT_ASSOCIATED, "no subnets are associated with the vpn")
          else:
            logger.error("encountered a unexpected client error when creating a route", exc_info=True)
        else:
          slack.post_event(
            message=f"created new route {cidr} ({lookup_item}) to target subnet {subnet}",
            state=NEW_ROUTE
          )
    
    # remove route if target subnet has changed
    for route in routes:
      if route['DestinationCidr'] == cidr and route['TargetSubnet'] not in event['TargetSubnets']:
        delete_route(client, event['ClientVpnEndpointId'], route['TargetSubnet'], cidr)

    # collect all rules that matches the current cidr
    cidr_auth_rules = [rule for rule in auth_rules if rule['DestinationCidr'] == cidr]

    try:
      # create rules for newly added groups
      if 'Groups' in event:
        existing_groups = list(set(rule['GroupId'] for rule in cidr_auth_rules))
        new_groups = [group for group in event['Groups'] if group not in existing_groups]

        for group in new_groups:
          authorize_route(client, event, cidr, lookup_item, group)

      # create an allow all rule
      elif 'Groups' not in event and not cidr_auth_rules:
        authorize_route(client, event, cidr, lookup_item)

    except ClientError as e:
        if e.response['Error']['Code'] == 'ClientVpnAuthorizationRuleLimitExceeded':
          auth_rules_limit_increase_required = True
          logger.error("vpn has reached the authorization rule limit", exc_info=True)
          slack.post_event(
            message=f"unable add to authorization rule for route {cidr} from lookup {lookup_item}",
            state=AUTH_RULE_LIMIT_EXCEEDED,
            error="vpn has reached the authorization rule limit"
          )
          continue
        else:
            logger.error("encountered a unexpected client error when creating an auth rule", exc_info=True)

  # request route limit increase
  if route_limit_increase_required and auto_limit_increase:
    case_id = increase_quota(10, ROUTE_TABLE_QUOTA_CODE, event['ClientVpnEndpointId'])
    if case_id is not None:
      slack.post_event(message=f"requested an increase for the routes per vpn service quota", state=QUOTA_INCREASE_REQUEST, support_case=case_id)
    else:
      logger.info(f"routes per vpn service quota increase request pending")

  # request auth rule limit increase
  if auth_rules_limit_increase_required and auto_limit_increase:
    case_id = increase_quota(20, AUTH_RULE_TABLE_QUOTA_CODE, event['ClientVpnEndpointId'])
    if case_id is not None:
      slack.post_event(message=f"requested an increase for the authorization rules per vpn service quota", state=QUOTA_INCREASE_REQUEST, support_case=case_id)
    else:
      logger.info(f"authorization rules per vpn service quota increase request pending")

  # remove expired auth rules
  for rule in expired_auth_rules(auth_rules, cidrs, event.get('Groups', [])):
    logger.info(f"removing expired auth rule {rule['DestinationCidr']} for lookup {lookup_item}")
    revoke_route_auth(client, event, rule['DestinationCidr'])

  # remove expired routes
  for route in expired_routes(routes, cidrs):
    logger.info(f"removing expired route {route['DestinationCidr']} for lookup {lookup_item}")
    delete_route(client, event['ClientVpnEndpointId'], route['TargetSubnet'], route['DestinationCidr'])
    slack.post_event(message=f"removed expired route {route['DestinationCidr']} for lookup {lookup_item}", state=EXPIRED_ROUTE)
  
  return 'OK'