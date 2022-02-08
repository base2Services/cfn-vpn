import json
import socket
from urllib.request import Request, urlopen
import logging

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

AWS_URL = 'https://ip-ranges.amazonaws.com/ip-ranges.json'

def dns_lookup(record):
  try:
    cidrs = [ ip + "/32" for ip in socket.gethostbyname_ex(record)[-1]]
    logger.info(f"resolved endpoint {record} to {cidrs}")
  except socket.gaierror as e:
    logger.error(f"failed to resolve record {record}", exc_info=True)
    return None

  return cidrs

def cloud_lookup(cloud, filters):
  if cloud == 'aws':
    return aws_lookup(filters)
  else:
    logger.error(f"unsupported cloud lookup : {cloud}")
    return None

def http_request(endpoint):
  request = Request(endpoint, headers={'User-Agent': 'Mozilla/5.0'})
  response = urlopen(request)
  return response.read().decode('utf-8')

def get_filter(filters, key):
  return next((filter['values'] for filter in filters if filter['name'] == key), None)

def aws_lookup(filters):
  response = http_request(AWS_URL)
  data = json.loads(response)
  regions = get_filter(filters, 'region')
  services = get_filter(filters, 'service')

  cidrs = []
  for prefix in data['prefixes']:
    if regions and services:
      if prefix['region'] in regions and prefix['service'] in services:
        cidrs.append(prefix['ip_prefix'])
    elif regions:
      if prefix['region'] in regions:
        cidrs.append(prefix['ip_prefix'])
    elif services:
      if prefix['service'] in services:
        cidrs.append(prefix['ip_prefix'])
    else:
      cidrs.append(prefix['ip_prefix'])

  return cidrs


