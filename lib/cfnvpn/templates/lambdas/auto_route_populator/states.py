"""
states:

FAILED: general failure
NEW_ROUTE: new route added to route table
EXPIRED_ROUTE: cidr is no longer associated with DNS entry and is removed from the route table
ROUTE_LIMIT_EXCEEDED: no new routes can be added to the route table due to aws route table limit
AUTH_RULE_LIMIT_EXCEEDED: no new authorization rules can be added to the rule list due to aws auth rule limit
RESOLVE_FAILED: failed to resolve the provided dns entry
SUBNET_NOT_ASSOCIATED: no subnets are associated with the client vpn
QUOTA_INCREASE_REQUEST: automatic quota increase made
"""

FAILED = 'FAILED'
NEW_ROUTE = 'NEW_ROUTE'
EXPIRED_ROUTE = 'EXPIRED_ROUTE'
ROUTE_LIMIT_EXCEEDED = 'ROUTE_LIMIT_EXCEEDED'
AUTH_RULE_LIMIT_EXCEEDED = 'AUTH_RULE_LIMIT_EXCEEDED'
RESOLVE_FAILED = 'RESOLVE_FAILED'
SUBNET_NOT_ASSOCIATED = 'SUBNET_NOT_ASSOCIATED'
QUOTA_INCREASE_REQUEST = 'QUOTA_INCREASE_REQUEST'