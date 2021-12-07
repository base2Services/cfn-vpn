import boto3
import logging
from lib.slack import Slack
from states import *

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SLACK_USERNAME = 'CfnVpn Scheduler'

def handler(event, context):

  logger.info(f"updating cfn-vpn stack {event['StackName']} parameter AssociateSubnets with value {event['AssociateSubnets']}")
  slack = Slack(username=SLACK_USERNAME)

  try:
    if event['AssociateSubnets'] == 'false':
      logger.info(f"terminating current vpn sessions to {event['ClientVpnEndpointId']}")
      ec2 = boto3.client('ec2')
      resp = ec2.describe_client_vpn_connections(ClientVpnEndpointId=event['ClientVpnEndpointId'])
      for conn in resp['Connections']:
        if conn['Status']['Code'] == 'active':
          ec2.terminate_client_vpn_connections(
            ClientVpnEndpointId=event['ClientVpnEndpointId'],
            ConnectionId=conn['ConnectionId']
          )
          logger.info(f"terminated session {conn['ConnectionId']}")

    client = boto3.client('cloudformation')
    logger.info(client.update_stack(
      StackName=event['StackName'],
      UsePreviousTemplate=True,
      Capabilities=['CAPABILITY_IAM'],
      Parameters=[
        {
          'ParameterKey': 'AssociateSubnets',
          'ParameterValue': event['AssociateSubnets']
        }
      ]
    ))
  except Exception as ex:
    logger.error(f"failed to start/stop client vpn", exc_info=True)
    if event['AssociateSubnets'] == 'true':
      slack.post_event(message=f"failed to associate subnets with the client vpn", state=START_FAILED, error=ex)
    else:
      slack.post_event(message=f"failed to disassociate subnets with the client vpn", state=STOP_FAILED, error=ex)
    return 'KO'

  if event['AssociateSubnets'] == 'true':
    slack.post_event(message=f"successfully associated subnets with the client vpn", state=START_IN_PROGRESS)
  else:
    slack.post_event(message=f"successfully disassociated subnets with the client vpn", state=STOP_IN_PROGRESS)

  return 'OK'