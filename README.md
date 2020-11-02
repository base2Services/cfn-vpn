# CfnVpn

Manages the resources required to create a [client vpn](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html) in AWS.
Uses cloudformation to manage the state of the vpn resources.

## Platforms

- osx
- linux

## Installation

Install `cfn-vpn` gem

```bash
gem install cfn-vpn
```

### easy-rsa

**Option 1 - Docker**

Install [docker](https://docs.docker.com/install/)

Docker is required to generate the certificates required for the client vpn.
The gem uses [openvpn/easy-rsa](https://github.com/OpenVPN/easy-rsa) project in [base2/aws-client-vpn](https://hub.docker.com/r/base2/aws-client-vpn) docker image. [repo](https://github.com/base2Services/ciinabox-containers/tree/master/easy-rsa)

**Option 1 - local**

If you would rather setup easy-rsa than install docker, you can use the `--easyrsa-local` flag when running the commands to use a local copy of easy-rsa, the binary just needs to be available in the `$PATH`. Install from [openvpn/easy-rsa](https://github.com/OpenVPN/easy-rsa)


### AWS Credentials

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

## Docker Image

[base2/cfn-vpn](https://hub.docker.com/r/base2/cfn-vpn) docker image for usage in a pipeline which comes pre packaged with all dependencies.

## Scenarios 

For further AWS documentation please visit https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/scenario.html

### SplitTunnel

Split tunnel when enabled will only push the routes defined on the client vpn. This is useful if you only want to push routes from your vpc through the vpn.

### Public subnet with Internet Access

This can be setup with default options selected. This will push all routes from through the vpn including all internet traffic. The ENI attached to the vpn client attaches a public IP which is used for natting between the vpn and the internet. This must be placed inside a public subnet with a internet gateway attached to the vpc.
Please read the AWS [documentation](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/scenario-internet.html) for troubleshooting any networking issues

### Private subnet with Internet Access

This is the same as above but the vpn attached to a subnet in a private subnet with the public route being routed through a nat gateway. **NOTE** the dns on the vpn must be set to the dns server of the vpc you've attached the vpn to, the reserved IP address at the base of the VPC IPv4 network range plus two. For example if you VPC cidr is 10.0.0.0/16 then the dns server for that vpc is 10.0.0.2.

```bash
cfn-vpn init myvpn --bucket mybucket --server-cn myvpn.domain.tld --subnet-id subnet-123456ab --dns-servers 10.0.0.2
```

If you are experiencing issue connecting to the internet check to see if your local dns configurations are overriding the ones set by the vpn. You can test this by using `dig` to query a domain from the vpc dns server. For example:

```bash
dig @10.0.0.2 google.com
```

## Usage

```bash
Commands:
  cfn-vpn --version, -v                                                            # print the version
  cfn-vpn client [name] --bucket=BUCKET --client-cn=CLIENT_CN                      # Create a new client certificate
  cfn-vpn config [name] --bucket=BUCKET --client-cn=CLIENT_CN                      # Retrieve the config for the AWS Client VPN
  cfn-vpn embedded [name] --bucket=BUCKET --client-cn=CLIENT_CN                    # Embed client certs into config and generate S3 presigned URL
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

```bash
cfn-vpn init myvpn --bucket mybucket --server-cn myvpn.domain.tld --subnet-id subnet-123456ab
```

*Optional:*

```bash
[--cidr=CIDR]                              # cidr from which to assign client IP addresses
                                           # Default: 10.250.0.0/16
[--dns-servers=DNS_SERVERS]                # DNS Servers to push to clients.
[--split-tunnel], [--no-split-tunnel]      # only push routes to the client on the vpn endpoint
[--internet-route], [--no-internet-route]  # create a default route to the internet
                                           # Default: true
[--protocol=PROTOCOL]                      # set the protocol for the vpn connections
                                           # Default: udp
                                           # Possible values: udp, tcp
```

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


### Modify the Client VPN config

This will modify some attributes of the client vpn endpoint.

`cfn-vpn config myvpn --dns-servers 8.8.8.8 8.8.4.4`

*Options:*

```bash
[--cidr=CIDR]                              # cidr from which to assign client IP addresses
                                           # Default: 10.250.0.0/16
[--dns-servers=DNS_SERVERS]                # DNS Servers to push to clients.
[--split-tunnel], [--no-split-tunnel]      # only push routes to the client on the vpn endpoint
[--internet-route], [--no-internet-route]  # create a default route to the internet
                                           # Default: true
[--protocol=PROTOCOL]                      # set the protocol for the vpn connections
                                           # Default: udp
                                           # Possible values: udp, tcp
```


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


### Embed client certificates into config file and share

This will pull the clients certificate and key archives from S3 and embed them into the config file, upload it back to S3 and generate a presigned URL for the user.
This allows the you to download or share a single, ready to import config file into a OpenVPN client.

`cfn-vpn embedded myvpn --client-cn user1 --bucket mybucket`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/base2services/aws-client-vpn.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
