# CfnVpn for AWS Client-VPN

`cfn-vpn` is a wrapper around [AWS Client-VPN](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html) to improve the management experience of the VPN. The tool utilises Cloudformation to manage the AWS resources required by the Client-VPN and automates the certificate management process with the [openvpn/easy-rsa](https://github.com/OpenVPN/easy-rsa) library.

## VPN Scenarios 

For further AWS documentation please visit https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/scenario.html

### Split Tunnel

Split tunnel when enabled will only push the routes defined on the client vpn. This is useful if you only want to push routes from your vpc through the vpn.

### Public Subnet with Internet Access

This can be setup with default options selected. This will push all routes from through the vpn including all internet traffic. The ENI attached to the vpn client attaches a public IP which is used for natting between the vpn and the internet. This must be placed inside a public subnet with a internet gateway attached to the vpc.
Please read the AWS [documentation](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/scenario-internet.html) for troubleshooting any networking issues

### Private Subnet with Internet Access

This is the same as above but the vpn attached to a subnet in a private subnet with the public route being routed through a nat gateway. **NOTE** the dns on the vpn must be set to the dns server of the vpc you've attached the vpn to, the reserved IP address at the base of the VPC IPv4 network range plus two. For example if you VPC cidr is 10.0.0.0/16 then the dns server for that vpc is 10.0.0.2.

```bash
cfn-vpn init myvpn --bucket mybucket --server-cn myvpn.domain.tld --subnet-id subnet-123456ab --dns-servers 10.0.0.2
```

If you are experiencing issue connecting to the internet check to see if your local dns configurations are overriding the ones set by the vpn. You can test this by using `dig` to query a domain from the vpc dns server. For example:

```bash
dig @10.0.0.2 google.com
```

## Authentication Types

`cfn-vpn` supports certificate, federated and active directory type authentication for AWS Client-VPN.
For further information on the authentication types please visit https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/client-authentication.html

## CfnVpn Documentation

1. [Getting Started](getting-started.md)
2. [Modifying The Client-VPN](modifying.md)
3. [Managing Certificate Users](certificate-users.md)
4. [Managing Routes](routes.md)
5. [Stop and Start Client-VPN](scheduling.md)
6. [Managing Sessions](sessions.md)
