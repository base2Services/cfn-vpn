"""
states:

START_COMPLETE: associated subnets with the client vpn successfully
STOP_COMPLETE: dissassociated subnets with the client vpn successfully
START_FAILED: failed to associated subnets with the client vpn
STOP_FAILED: failed to dissassociated subnets with the client vpn
"""

START_COMPLETE = 'START_COMPLETE'
STOP_COMPLETE = 'STOP_COMPLETE'
START_FAILED = 'START_FAILED'
STOP_FAILED = 'STOP_FAILED'