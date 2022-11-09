# Managing Client-VPN Routes

Management of the VPN routes can be altered using the `routes` command or by using the `modify` command along with the yaml config file.

**Note:** The default route via subnet association cannot be modified through this command. Use the `modify` command to alter the subnet associations.

There are 3 different types of routes, [Static](#Static CIDR Routes), [DNS Lookup](#DNS Lookup Routes) and [Cloud](#Cloud Routes).

## Static CIDR Routes

Static routes create a static entry in the cfnvpn route table with the CIDR provided.

#### CLI Commands

new route run the routes command along with the `--cidr` option

```sh
cfn-vpn routes [name] --cidr 10.151.0.0/16
```

delete a route run the routes command along with the `--cidr` option of the route to delete and the delete option

```sh
cfn-vpn routes [name] --cidr 10.151.0.0/16 --delete
```

#### YAML Config

```yaml
routes:
- cidr: 10.151.0.0/16
  desc: route to dev peered vpc
  schedule: rate(5 minutes)
  groups:
  - devs
  - ops
```

## DNS Lookup Routes

Dynamic DNS routes takes a dns endpoint and will query the record every 5 minutes to see if the IPs have changed and update the routes in the vpn route table.

**NOTE** This should not be used for cloutfront endpoints

#### CLI Commands

new route run the routes command along with the `--dns` option

```sh
cfn-vpn routes [name] --dns example.com
```

delete a route run the routes command along with the `--dns` option of the route to delete and the delete option

```sh
cfn-vpn routes [name] --dns example.com --delete
```

#### YAML Config

```yaml
routes:
- dns: example.com
  desc: my dev alb
  schedule: rate(10 minutes)
  groups:
  - dev
```

## Cloud Routes

Automatically lookup and create routes to push cloud provider IP ranges through the VPN. Cloud routes can only be configured through the yaml config.

Supported clouds:
- [AWS](#AWS)

### AWS

Using AWS published [IP address ranges](https://docs.aws.amazon.com/general/latest/gr/aws-ip-ranges.html) cfn-vpn can lookup and add the CIDR ranges published the the vpn route table.

The list can be filtered by AWS `region` and `service`.

AWS services that can be used to filter the address ranges. **Note:** not all regions contain all services.

```
API_GATEWAY
EBS
EC2_INSTANCE_CONNECT
CHIME_VOICECONNECTOR
CHIME_MEETINGS
CODEBUILD
CLOUDFRONT
ROUTE53_HEALTHCHECKS_PUBLISHING
AMAZON_APPFLOW
S3
CLOUD9
ROUTE53
AMAZON
KINESIS_VIDEO_STREAMS
ROUTE53_HEALTHCHECKS
GLOBALACCELERATOR
WORKSPACES_GATEWAYS
CLOUDFRONT_ORIGIN_FACING
EC2
DYNAMODB
ROUTE53_RESOLVER
AMAZON_CONNECT
```

**Warning:** AWS publish 100's of IP address ranges and with Client VPN soft limit of 10 routes per vpn endpoint you will hit the limit without filtering the published ranges.

#### YAML Config

```yaml
routes:
- cloud: aws
  schedule: rate(1 hour)
  groups:
  - ops
  filters:
  - name: region
    values:
    - ap-southeast-2
  - name: service
    values:
    - API_GATEWAY
```

## Manage Authorization Groups

When using federated or active directory authentication groups can be used to control access to certain routes. These can be managed on the routes by providing the `--groups [list of groups]` along with a space delimited list of groups to the `routes` command. This is available for both DNS and CIDR routes

To add groups to a new route or to override all groups on an exiting route use the `--groups` options

```sh
cfn-vpn routes [name] [--cidr 10.151.0.0/16] [--dns example.com] --groups devs ops
```

To add groups to an existing route use the `--add-groups` options

```sh
cfn-vpn routes [name] [--cidr 10.151.0.0/16] [--dns example.com] --add-groups admin
```

To delete groups from an existing route use the `--del-groups` options

```sh
cfn-vpn routes [name] [--cidr 10.151.0.0/16] [--dns example.com] --del-groups dev
```


## Route Limits

Client VPN have a number of service limits associated with it some of which can be increased and may need to be increased by default.

| Name | Default | Adjustable | 
| --- | --- | --- | 
| Authorization rules per Client VPN endpoint | 50 | [Yes](https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas/L-9A1BC94B) | 
| Client VPN disconnect timeout | 24 hours | No | 
| Client VPN endpoints per Region | 5 | [Yes](https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas/L-8EA77D34) | 
| Concurrent client connections per Client VPN endpoint |  This value depends on the number of subnet associations per endpoint\. [\[See the AWS documentation website for more details\]](http://docs.aws.amazon.com/vpn/latest/clientvpn-admin/limits.html)  | [Yes](https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas/L-C4B238BF) | 
| Concurrent operations per Client VPN endpoint † | 10 | No | 
| Entries in a client certificate revocation list for Client VPN endpoints | 20,000 | No | 
| Routes per Client VPN endpoint | 10 | [Yes](https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas/L-401D78F7) | 

† Operations include:
+ Associate or disassociate subnets
+ Create or delete routes
+ Create or delete inbound and outbound rules
+ Create or delete security groups

Check out the AWS [docs](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/limits.html) for up to date details

### Increasing Limits

**Automatic**

cfn-vpn supports automatically creating requests to increase the limits for `Routes per Client VPN endpoint` (by 10) and `Authorization rules per Client VPN endpoint` (by 20).

This functionality is enabled by default but can be disabled by modifying the vpn setting the `--no-auto-limit-increase` flag

```sh
cfn-vpn modify [name] --no-auto-limit-increase
```

**Manual**

`Routes per Client VPN endpoint`

```sh
aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-401D78F7 --desired-value [value]
```

`Authorization rules per Client VPN endpoint`

```sh
aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-9A1BC94B --desired-value [value]
```
