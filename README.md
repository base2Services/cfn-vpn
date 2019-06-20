# CfnVpn

Manages the resources required to create a client vpn in AWS.
Uses cloudformation to manage the state of the vpn resources.

## Installation

Install `cfn-vpn` gem

```bash
gem install cfn-vpn
```

Install [docker](https://docs.docker.com/install/)

Docker is required to generate the certificates required for the client vpn.
The gem uses [openvpn/easy-rsa](https://github.com/OpenVPN/easy-rsa) project in [base2/aws-client-vpn](https://hub.docker.com/r/base2/aws-client-vpn) dokcer image.

## Usage

### help

Displays all possible commands

```bash
Commands:
  cfn-vpn --version, -v                                            # print the version
  cfn-vpn help [COMMAND]                                           # Describe available commands or one specific command
  cfn-vpn init [name] --server-cn=SERVER_CN --subnet-id=SUBNET_ID  # Ciinabox configuration initialization
```

### init

Initialises a new client vpn and creates all required resources to get it running.

```bash
Usage:
  cfn-vpn init [name] --server-cn=SERVER_CN --subnet-id=SUBNET_ID

Options:
  p, [--profile=PROFILE]       # AWS Profile
  r, [--region=REGION]         # AWS Region
      --server-cn=SERVER_CN    # server certificate common name
      [--client-cn=CLIENT_CN]  # client certificate common name
      --subnet-id=SUBNET_ID    # subnet id to associate your vpn with
      [--cidr=CIDR]            # cidr from which to assign client IP addresses
                               # Default: 10.250.0.0/16

Ciinabox configuration initialization
```

### config

Downloads the opvn config file for the client vpn

```bash
Usage:
  cfn-vpn config [name]

Options:
  [--profile=PROFILE]  # AWS Profile
  [--region=REGION]    # AWS Region
                       # Default: ap-southeast-2

Ciinabox configuration initialization
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/base2services/aws-client-vpn.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
