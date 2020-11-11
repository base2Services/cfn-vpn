# Managing Client-VPN Routes

Management of the VPN routes can be altered using the `routes` command or by using the `modify` command along with the yaml config file.

## Routes Command

### Add New

to add a new route run the routes command along with the `--cidr` option

```sh
cfn-vpn routes [name] --cidr 10.151.0.0/16
```

### Delete

to delete a  route run the routes command along with the `--cidr` option of the route to delete and the delete option

```sh
cfn-vpn routes [name] --cidr 10.151.0.0/16 --delete
```

### Manage Authorization Groups

When using federated authentication groups can be used to control access to certain routes. These can be managed on the routes by providing the `--groups [list of groups]` along with a space delimited list of groups to the `routes` command.

To add groups to a new route or to override all groups on an exiting route use the `--groups` options

```sh
cfn-vpn routes [name] --cidr 10.151.0.0/16 --groups devs ops
```

To add groups to an existing route use the `--add-groups` options

```sh
cfn-vpn routes [name] --cidr 10.151.0.0/16 --add-groups admin
```

To delete groups from an existing route use the `--del-groups` options

```sh
cfn-vpn routes [name] --cidr 10.151.0.0/16 --del-groups dev
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
```

run the `modify` command and supply the yaml file to apply the changes

```sh
cfn-vpn routes [name] --params-yaml cfnvpn.[name].yaml
```
