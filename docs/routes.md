# Managing Client-VPN Routes

Management of the VPN routes can be altered using the `routes` command or by using the `modify` command along with the yaml config file.

**Note:** The default route via subnet association cannot be modified through this command. Use the `modify` command to alter the subnet associations.

CfnVpn can create static routes for CIDRs as well as dynamically lookup IPs for dns endpoints and continue to monitor and update the routes if the IPs change.

```sh
cfn-vpn help routes
```

## Dynamic DNS Routes

Dynamic DNS routes takes a dns endpoint and will query the record every 5 minutes to see if the IPs have changed and update the routes.

### Add New

to add a new route run the routes command along with the `--dns` option

```sh
cfn-vpn routes [name] --dns example.com
```

### Delete

to delete a route run the routes command along with the `--dns` option of the route to delete and the delete option

```sh
cfn-vpn routes [name] --dns example.com --delete
```

## Static CIDR Routes

### Add New

to add a new route run the routes command along with the `--cidr` option

```sh
cfn-vpn routes [name] --cidr 10.151.0.0/16
```

### Delete

to delete a route run the routes command along with the `--cidr` option of the route to delete and the delete option

```sh
cfn-vpn routes [name] --cidr 10.151.0.0/16 --delete
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

## Modify Command

add or modify the `routes:` key in your config yaml file

```yaml
routes:
- cidr: 10.151.0.0/16
  desc: route to dev peered vpc
  groups:
  - devs
  - ops
- cidr: 10.152.0.0/16
  desc: route to prod peered vpc
  groups:
  - ops
- dns: example.com
  desc: my dev alb
  groups:
  - dev
```

run the `modify` command and supply the yaml file to apply the changes

```sh
cfn-vpn routes [name] --params-yaml cfnvpn.[name].yaml
```

## Route Limits

Client VPN have a number or service limits associated with it some of which can be increased and may need to be increased by default.

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

Routes per Client VPN endpoint

```sh
aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-401D78F7 --desired-value 20
```

Authorization rules per Client VPN endpoint

```sh
aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-9A1BC94B --desired-value 75
```