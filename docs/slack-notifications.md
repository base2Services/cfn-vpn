# Slack Notifications

Slack notifications can be enabled for both the [dynamic route populator](routes.md#dynamic-dns-routes) and the [scheduler](scheduling.md) to show events.

## Enable

Setup a Slack [incoming-webhook](https://api.slack.com/messaging/webhooks#getting_started) in your desired slack channel and grab the webhook url that'll look something like this:

```
https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX
```

Next modify your VPN stack using the modify command and pass in url

**CLI**

```sh
cfn-vpn modify [name] --slack-webhook-url "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
```

**YAML**

```yaml
slack_webhook_url: https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX
```


## Route Events

- `FAILED`: general failure
- `NEW_ROUTE`: new route added to route table
- `EXPIRED_ROUTE`: CIDR is no longer associated with DNS entry and is removed from the route table
- `ROUTE_LIMIT_EXCEEDED`: no new routes can be added to the route table due to AWS route table limit
- `AUTH_RULE_LIMIT_EXCEEDED`: no new authorization rules can be added to the rule list due to AWS auth rule limit
- `RESOLVE_FAILED`: failed to resolve the provided dns entry
- `SUBNET_NOT_ASSOCIATED`: no subnets are associated with the Client VPN
- `QUOTA_INCREASE_REQUEST`: automatic quota increase made 

## Scheduler Events

- `START_IN_PROGRESS`: associating subnets with the Client VPN
- `STOP_IN_PROGRESS`: disassociating subnets with the Client VPN
- `START_FAILED`: failed to associated subnets with the Client VPN
- `STOP_FAILED`: failed to disassociated subnets with the Client VPN