# CfnVpn

Manages the resources required to create a [client vpn](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html) in AWS.
Uses cloudformation to manage the state of the vpn resources.

## Installation

Install `cfn-vpn` gem

```bash
gem install cfn-vpn
```

Install [docker](https://docs.docker.com/install/)

Docker is required to generate the certificates required for the client vpn.
The gem uses [openvpn/easy-rsa](https://github.com/OpenVPN/easy-rsa) project in [base2/aws-client-vpn](https://hub.docker.com/r/base2/aws-client-vpn) dokcer image.

Setup your [AWS credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html) by either setting a profile or exporting them as environment variables.

## Usage

```bash
Commands:
  cfn-vpn --version, -v                                                            # print the version
  cfn-vpn client [name] --bucket=BUCKET --client-cn=CLIENT_CN                      # Create a new client certificate
  cfn-vpn config [name] --bucket=BUCKET --client-cn=CLIENT_CN                      # Retrieve the config for the AWS Client VPN
  cfn-vpn help [COMMAND]                                                           # Describe available commands or one specific command
  cfn-vpn init [name] --bucket=BUCKET --server-cn=SERVER_CN --subnet-id=SUBNET_ID  # Create a AWS Client VPN
  cfn-vpn modify [name]                                                            # Modify your AWS Client VPN
  cfn-vpn revoke [name] --bucket=BUCKET --client-cn=CLIENT_CN                      # Revoke a client certificate
  cfn-vpn routes [name]                                                            # List, add or delete client vpn routes
  cfn-vpn sessions [name]                                                          # List and kill current vpn connections
  cfn-vpn share [name] --bucket=BUCKET --client-cn=CLIENT_CN                       # Provide a user with a s3 signed download for certificates and config
```

Global options

```bash
p, [--profile=PROFILE]           # AWS Profile
r, [--region=REGION]             # AWS Region
                                 # Default: ENV['AWS_REGION']
    [--verbose], [--no-verbose]  # set log level to debug
```


### Create a new AWS Client VPN

This will create a new client vpn endpoint, associates it with a subnet and sets up a route to the internet.
During this process a new CA and certificate and keys are generated using [openvpn/easy-rsa](https://github.com/OpenVPN/easy-rsa) and uploaded to ACM.
These keys are bundled in a tar and stored encrypted in your provided s3 bucket.

`cfn-vpn init myvpn --bucket mybucket --server-cn myvpn.domain.tld --subnet-id subnet-123456ab`


### Create a new client

This will generate a new client certificate and key against the CA generated in the `init`.
It will be bundled into a tar and stored encrypted in your provided s3 bucket.

`cfn-vpn client myvpn --client-cn user1 --bucket mybucket`


### Revoke a client

This will revoke the client certificate and apply to the client VPN endpoint.
Note this wont terminate the session but will stop the client from reconnecting using the certificate.

`cfn-vpn revoke myvpn --client-cn user1 --bucket mybucket`


### Download the config file

This will download the client certificate bundle from s3 and the Client VPN config file from the endpoint.
The config will be modified to include the local path of the client cert and key.

`cfn-vpn config myvpn --client-cn user1 --bucket mybucket`

*Optional:*

`--ignore-routes` By deafult AWS Client VPN will push all routes from your local through the VPN connection. Select this flag to only push routes specified in the Client VPN route table.


### Modify the Client VPN config

This will modify some attributes of the client vpn endpoint.

`cfn-vpn config myvpn --dns-servers 8.8.8.8,8.8.4.4`

*Optional:*

`--dns-servers` Change the DNS servers pushed by the VPN.
`--subnet-id` Change the associated subnet.
`--cidr` Change the Client CIDR range.


### Share client certificates with a user

This will generate a presigned url for the client's certificate and config file to allow them to download them to their local computer.

`cfn-vpn share myvpn --client-cn user1 --bucket mybucket`

You can then share the output with your user

```
Download the certificates and config from the bellow presigned URLs which will expire in 1 hour.

Certificate:
<presigned url>

Config:
<presigned url>

Extract the certificates from the tar and place into a safe location.
	tar xzfv user1.tar.gz -C <path>

Modify base2-ciinabox.config.ovpn to include the full location of your extracted certificates
	echo "key /<path>/user1.key" >> myvpn.config.ovpn
	echo "cert /<path>/user1.crt" >> myvpn.config.ovpn

Open myvpn.config.ovpn with your favourite openvpn client.
```


### Show and Kill Current Connections

This is show a table of current connections on the vpn. You can then kill sessions by using the connection id.

```bash
$ cfn-vpn sessions myvpn
+-------------+---------------------+--------+-------------+-----------------------------------+---------------+--------------+
| Common Name | Connected (UTC)     | Status | IP Address  | Connection ID                     | Ingress Bytes | Egress Bytes |
+-------------+---------------------+--------+-------------+-----------------------------------+---------------+--------------+
| user1       | 2019-06-28 04:58:19 | active | 10.250.0.98 | cvpn-connection-05bcc579cb3fdf9a3 | 3000          | 2679         |
+-------------+---------------------+--------+-------------+-----------------------------------+---------------+--------------+
```

Specify the `--kill` flag with the connection id to kill the session.

`cfn-vpn sessions myvpn --kill cvpn-connection-05bcc579cb3fdf9a3`


### Show, Add and Remove Routes

This will display the route table from the Client VPN.

```bash
+---------------+-----------------------+--------+-----------------+------+-----------+
| Route         | Description           | Status | Target          | Type | Origin    |
+---------------+-----------------------+--------+-----------------+------+-----------+
| 10.0.0.0/16   | Default Route         | active | subnet-123456ab | Nat  | associate |
| 0.0.0.0/0     | Route to the internet | active | subnet-123456ab | Nat  | add-route |
+---------------+-----------------------+--------+-----------------+------+-----------+
```

to add a new route specify the `--add` flag with the cidr and a description with the `--desc` flag.

`cfn-vpn routes myvpn --add 10.10.0.0/16 --desc "route to peered vpc"`

to delete a route specify the `--del` flag with the cidr you want to delete.

`cfn-vpn routes myvpn --del 10.10.0.0/16`


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/base2services/aws-client-vpn.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
