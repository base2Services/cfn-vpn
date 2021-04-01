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
- cidr: example.com
  desc: my dev alb
  groups:
  - dev
```

run the `modify` command and supply the yaml file to apply the changes

```sh
cfn-vpn routes [name] --params-yaml cfnvpn.[name].yaml
```
