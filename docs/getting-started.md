## Getting Started with CfnVpn

## Installation

Install `cfn-vpn` gem

```bash
gem install cfn-vpn --source "https://rubygems.pkg.github.com/base2services"
```

## Setup Easy-RSA

**Option 1 - Docker**

Install [docker](https://docs.docker.com/install/)

Docker is required to generate the certificates required for the client vpn.
The gem uses [openvpn/easy-rsa](https://github.com/OpenVPN/easy-rsa) project in [base2/aws-client-vpn](https://hub.docker.com/r/base2/aws-client-vpn) docker image. [repo](https://github.com/base2Services/ciinabox-containers/tree/master/easy-rsa)

**Option 2 - local**

If you would rather setup easy-rsa than install docker, you can use the `--easyrsa-local` flag when running the commands to use a local copy of easy-rsa, the binary just needs to be available in the `$PATH`. Install from [openvpn/easy-rsa](https://github.com/OpenVPN/easy-rsa)


## Setup Your AWS Credentials

Setup your [AWS credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html) by either setting a profile or exporting them as environment variables.

```bash
export AWS_ACCESS_KEY_ID="XXXXXXXXXXXXXXXXXXXXX"
export AWS_SECRET_ACCESS_KEY="XXXXXXXXXXXXXXXXXXXXX"
export AWS_SESSION_TOKEN="XXXXXXXXXXXXXXXXXXXXX"
```

Optionally export the AWS region if not providing `--region` flag

```bash
export AWS_REGION="us-east-1"
```

## Initialising CfnVpn

to launch a new CfnVpn stack run the `init` command along with the options.

### Certificate Authenticated VPN

The following command and required option will launch a new certificate based Client-VPN

```sh
cfn-vpn init [name] --bucket [s3-bucket] --server-cn [server certificate name] --subnet-ids [list of subets to associate with the vpn]
```

### Federated SAML Authenticated VPN

**Prerequisites:** Client-VPN requires a IAM SAML identity provider ARN, see the [AWS docs](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_saml.html) to create one.

The following command and required option will launch a new federated based Client-VPN

```sh
cfn-vpn init [name] --server-cn [server certificate name] --subnet-ids [list of subets to associate with the vpn] --saml-arn [identity providor arn]
```

## Subnet Associations and Authorisation

AWS ClientVPN requires one or more subnets to be associated with the vpn. These subnets setup the default routes and by default cfn-vpn creates a allow all auth for the default routes.
When using a federated ClientVPN you can modify the default auth to only allow specific groups by setting the groups in the `--default-groups` flag. This can also be modified later using the `modify` command.

## Additional Initialising Options

```
Options:
  r, [--region=REGION]                         # AWS Region
                                               # Default: ap-southeast-2
      [--verbose], [--no-verbose]              # set log level to debug
      --server-cn=SERVER_CN                    # server certificate common name
      [--client-cn=CLIENT_CN]                  # client certificate common name
      [--easyrsa-local], [--no-easyrsa-local]  # run the easyrsa executable from your local rather than from docker
      [--bucket=BUCKET]                        # s3 bucket
      --subnet-ids=one two three               # subnet id to associate your vpn with
      [--default-groups=one two three]         # groups to allow through the subnet associations when using federated auth
      [--cidr=CIDR]                            # cidr from which to assign client IP addresses
                                               # Default: 10.250.0.0/16
      [--dns-servers=one two three]            # DNS Servers to push to clients.
      [--split-tunnel], [--no-split-tunnel]    # only push routes to the client on the vpn endpoint
                                               # Default: true
      [--internet-route=INTERNET_ROUTE]        # [subnet-id] create a default route to the internet through a subnet
      [--protocol=PROTOCOL]                    # set the protocol for the vpn connections
                                               # Default: udp
                                               # Possible values: udp, tcp
      [--start=START]                          # cloudwatch event cron schedule in UTC to associate subnets to the client vpn
      [--stop=STOP]                            # cloudwatch event cron schedule in UTC to disassociate subnets to the client vpn
      [--saml-arn=SAML_ARN]                    # IAM SAML idenditiy providor arn if using SAML federated authentication
```