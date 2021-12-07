import boto3

ROUTE_TABLE_QUOTA_CODE = 'L-401D78F7'
AUTH_RULE_TABLE_QUOTA_CODE = 'L-9A1BC94B'
EC2_SERVICE_CODE = 'ec2'
IN_PROGRESS = ['PENDING', 'CASE_OPENED']

def get_route_count(endpoint) -> int:
  client = boto3.client('ec2')
  response = client.describe_client_vpn_routes(
    ClientVpnEndpointId=endpoint,
  )
  return len(response['Routes'])

def quota_request_open(quota_code) -> bool:
  client = boto3.client('service-quotas')
  response = client.list_requested_service_quota_change_history_by_quota(
    ServiceCode=EC2_SERVICE_CODE,
    QuotaCode=quota_code
  )
  # Status='PENDING'|'CASE_OPENED'|'APPROVED'|'DENIED'|'CASE_CLOSED'
  return any(req['status'] in IN_PROGRESS for req in response['RequestedQuotas'])

def increase_quota(increase_value, quota_code, endpoint) -> str:
  if quota_request_open(quota_code):
    return None

  current_route_count = get_route_count(endpoint)
  desired_value = current_route_count + increase_value

  client = boto3.client('service-quotas')
  response = client.request_service_quota_increase(
    ServiceCode=EC2_SERVICE_CODE,
    QuotaCode=quota_code,
    DesiredValue=desired_value
  )
  return response['CaseId']