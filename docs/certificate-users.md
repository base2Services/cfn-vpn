# Managing Certificate Authenticated Users

This section explains how to generate, revoke VPN clients and share config the config with the users

## Create a new user

This will generate a new client certificate and key against the CA generated in the `init`.
It will be bundled into a tar and stored encrypted in your provided s3 bucket.

```
cfn-vpn client myvpn --client-cn user1 --bucket mybucket
```

## Short Term Client

By default the expiry of client certificate is 825 days. You can shorten this value with the `--certificate-expiry` flag specify a int value in days for how long you want the certificate to stay valid.

```
cfn-vpn client myvpn --client-cn user1 --bucket mybucket --certificate-expiry 7
```

## Revoke a user

This will revoke the client certificate and apply to the client VPN endpoint.
Note this wont terminate the session but will stop the client from reconnecting using the certificate.

```sh
cfn-vpn revoke myvpn --client-cn user1 --bucket mybucket
```

## Modify the Client VPN config

This will modify some attributes of the client vpn endpoint.

```sh
cfn-vpn config myvpn --dns-servers 8.8.8.8 8.8.4.4
```

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


## Share client certificates with a user

The users vpn config and certificates can be passed to the user securely using S3 signed URLs to allow the user to directly download them.
There are 2 ways to generate the vpn config file, by having the certificates and config file separate or by embedding the certificates into the config file.


### Certificate embedded into config

This will pull the clients certificate and key archives from S3 and embed them into the config file, upload it back to S3 and generate a presigned URL for the user.
This allows the you to download or share a single, ready to import config file into a OpenVPN client.

```sh
cfn-vpn embedded myvpn --client-cn user1 --bucket mybucket
```

### Separate certificate and config

This will generate a presigned url for the client's certificate and config file to allow them to download them to their local computer.

```sh
cfn-vpn share myvpn --client-cn user1 --bucket mybucket
```

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

Open myvpn.config.ovpn with your favorite openvpn client.
```
