# Stop and Start Client-VPN

Stopping and starting the VPN can help save AWS costs when you're not using the VPN. AWS pricing model for Client-VPN is per associated subnet per hour so we can achieve this by disassociating the subnets when the VPN is not required and the associated them again when required.

This can be achieved through `cfn-vpn` in 2 ways, by a cli command or via a cloudwatch event schedule.

## CLI Command

Use the following commands to stop and start your Client-VPN

### Disassociate

```sh
cfn-vpn subnets [name] --disassociate
```

### Associate

```sh
cfn-vpn subnets [name] --associate
```

## Schedule

A CloudWatch cron schedule with a lambda function can be setup to stop and start your Client-VPN. This can be achieved by modifying the `cfn-vpn` stack with the required cron schedules.
To see the CloudWatch cron syntax please visit the [AWS docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html#CronExpressions) for further info

```sh
cfn-vpn modify [name] --stop "10 6 * * ? *" --start "00 20 ? * MON-FRI *"
```

One or both of `--start` and `--stop` can be supplied, for example if you wanted an on demand start with a scheduled stop.
