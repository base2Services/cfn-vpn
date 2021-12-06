"""
states:

NEW_ROUTE: new route added to route table
EXPIRED_ROUTE: cidr is no longer associated with DNS entry and is removed from the route table
ROUTE_LIMIT_EXCEEDED: no new routes can be added to the route table due to aws route table limit
AUTH_RULE_LIMIT_EXCEEDED: no new athorization rules can be added to the rule list due to aws auth rule limit
RESOLVE_FAILED: failed to resolve the provided dns entry
RATE_LIMIT_EXCEEDED: concurrent modifcations of the route table is being rated limited
SUBNET_NOT_ASSOCIATED: no subnets are associated with the client vpn
"""

NEW_ROUTE = 'NEW_ROUTE'
EXPIRED_ROUTE = 'EXPIRED_ROUTE'
ROUTE_LIMIT_EXCEEDED = 'ROUTE_LIMIT_EXCEEDED'
AUTH_RULE_LIMIT_EXCEEDED = 'AUTH_RULE_LIMIT_EXCEEDED'
RESOLVE_FAILED = 'RESOLVE_FAILED'
RATE_LIMIT_EXCEEDED = 'RATE_LIMIT_EXCEEDED'
SUBNET_NOT_ASSOCIATED = 'SUBNET_NOT_ASSOCIATED'