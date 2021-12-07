"""
states:

START_IN_PROGRESS: associating subnets with the Client VPN
STOP_IN_PROGRESS: disassociating subnets with the Client VPN
START_FAILED: failed to associated subnets with the Client VPN
STOP_FAILED: failed to disassociated subnets with the Client VPN
"""

START_IN_PROGRESS = 'START_IN_PROGRESS'
STOP_IN_PROGRESS = 'STOP_IN_PROGRESS'
START_FAILED = 'START_FAILED'
STOP_FAILED = 'STOP_FAILED'