import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):

  logger.info(f"updating cfn-vpn stack {event['StackName']} parameter AssociateSubnets with value {event['AssociateSubnets']}")

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

  return 'OK'