import os
import json
import logging
import urllib

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

def post_event_to_slack(message, state, error=None):
    """Posts event to slack using an incoming webhook
    Parameters
    ----------
    message: str
        message to post to slack
    state: str
        the state of the event
    """

    slack_url = os.environ.get('SLACK_URL')

    if not slack_url.startswith('https://hooks.slack.com'):
        return

    if 'FAILED' in state or 'LIMIT_EXCEEDED' in state:
        colour = '#ad0614'
    elif 'NOT_ASSOCIATED' in state:
        colour = '#d4b126'
    else: 
        colour = '#3ead3e'

    text = f'Message: {message}\nState: {state}'
    if error:
        text += f'\nError: {error}'

    payload = {
        'username': 'CfnVpn Route Table Event',
        'attachments': [
            {
                'color': colour,
                'text': text,
                'mrkdwn_in': ['text','pretext']
            }
        ]
    }

    try:
        urllib.request.urlopen(urllib.request.Request(
            slack_url,
            headers={'Content-Type': 'application/json'},
            data=json.dumps(payload).encode('utf-8')
        ))
    except urllib.error.HTTPError as e:
        logger.error(f"failed to post slack notification. REASON: {e.reason} CODE: {e.code}", exc_info=True)

