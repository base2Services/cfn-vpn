import os
import json
import logging
import urllib

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

class Slack:

    def __init__(self, username):
        self.username = username
        self.slack_url = os.environ.get('SLACK_URL')

    def post_error(self, lookup_item, state, error):
        self.post_event(message=f"failed create routes for lookup {lookup_item}", state=state, error=error)

    def post_event(self, message, state, error=None, support_case=None):
        """Posts event to slack using an incoming webhook
        Parameters
        ----------
        message: str
            message to post to slack
        state: str
            the state of the event
        error: str
            error message to add to the message
        support_case: str
            displays a aws console link to the support case in the message
        """

        if not self.slack_url.startswith('https://hooks.slack.com'):
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
        
        if support_case:
            text += f'\nSupport Case: <https://console.aws.amazon.com/support/cases#/{support_case}|{support_case}>'

        payload = {
            'username': self.username,
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
                self.slack_url,
                headers={'Content-Type': 'application/json'},
                data=json.dumps(payload).encode('utf-8')
            ))
        except urllib.error.HTTPError as e:
            logger.error(f"failed to post slack notification. REASON: {e.reason} CODE: {e.code}", exc_info=True)

