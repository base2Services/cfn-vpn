# Modifying The Client-VPN

The Client-VPN properties such as the DNS servers and the associated subnets can be modified using the `modify` command


## CfnVpn Configuration

By default `cfn-vpn` configuration is managed in a SSM parameter name `/cfnvpn/config/[name]`. This config can be dumped to a YAML file if you wish to manage through source control and use for updating `cfn-vpn` configuration.

to dump the config to a yaml file use the `params` command. this will create a file call `cfnvpn.[name].yaml` in your current directory

```sh
cfn-vpn params [name] --dump
```

the `params` command can also be used to view the current deployed config and diff the deployed config against your local yaml file

### View

```sh
cfn-vpn params [name]
```

### Diff

```sh
cfn-vpn params [name] --diff-yaml cfnvpn.[name].yaml
```

## Modifying

### With CLI Options

to modify the VPN properties run the modify command with the desired options

```
cfn-vpn modify [name] --dns-servers 10.15.0.2
```

a cloudformation changeset is created with the desired changes and approval is asked

```
INFO: - Creating cloudformation changeset for stack [name]-cfnvpn in [region]

+-----------------------------------+---------------------------------------------+-------------+---------------------+
|                                                       Modify                                                        |
+-----------------------------------+---------------------------------------------+-------------+---------------------+
| Logical Resource Id               | Resource Type                               | Replacement | Changes             |
+-----------------------------------+---------------------------------------------+-------------+---------------------+
| CfnVpnConfig                      | AWS::SSM::Parameter                         | Conditional | Value               |
| ClientVpnEndpoint                 | AWS::EC2::ClientVpnEndpoint                 | Conditional | DnsServers          |
| ClientVpnTargetNetworkAssociation | AWS::EC2::ClientVpnTargetNetworkAssociation | Conditional | ClientVpnEndpointId |
| TargetNetworkAuthorizationRule    | AWS::EC2::ClientVpnAuthorizationRule        | Conditional | ClientVpnEndpointId |
+-----------------------------------+---------------------------------------------+-------------+---------------------+
INFO: - Cloudformation changeset changes:

Continue? y
INFO: - Waiting for changeset to UPDATE
INFO: - Changeset UPDATE complete
INFO: - Client VPN [endpoint-id] modified
```

### With YAML File

```
cfn-vpn modify [name] --params-yaml cfnvpn.[name].yaml
```