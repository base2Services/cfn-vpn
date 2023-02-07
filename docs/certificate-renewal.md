# Certificate Renewal

To update the client certificate you can use the `renew` command.

```sh
Usage:
  cfn-vpn renew [name]

Options:
  r, [--region=REGION]                           # AWS Region
                                                 # Default: ap-southeast-2
      [--verbose], [--no-verbose]                # set log level to debug
      [--easyrsa-local], [--no-easyrsa-local]    # run the easyrsa executable from your local rather than from docker
      [--certificate-expiry=CERTIFICATE_EXPIRY]  # value in days for when the server certificates expire, defaults to 825 days
      [--rebuild], [--no-rebuild]                # generates new certificates from the existing CA for certiciate type VPNs
      [--bucket=BUCKET]                          # s3 bucket, if not set one will be generated for you
```

## Certificate Authenticated VPN

When renewing the server and client certificates for the Client VPN there are 2 options [renew](#renew) or [rebuild](#rebuild).

In both cases the Client VPN is recreated along with a new vpn endpoint which means once the update is complete each client must [update their config](#updating-client-config) to point to the new VPN endpoint.

The Update process can take as long as 1-2 hours.

### renew

This is the default option and should be used

```sh
cfn-vpn renew [name] --bucket [s3-bucket]
```

### rebuild 

This creates new certificates and should only be used if renew doesn't work.

```sh
cfn-vpn renew [name] --bucket [s3-bucket] --rebuild
```

### Updating Client Config

Once the VPN has been updated you will need to retrieve the new vpn endpoint such as

```
*.cvpn-endpoint-<id>.prod.clientvpn.<aws-region>.amazonaws.com
```

Replace the endpoint value in each of the clients opvn configs and reimport them into the vpn client.

```
remote kdipkcte.cvpn-endpoint-<replace-id>.prod.clientvpn.<aws-region>.amazonaws.com 443
```

## VPNs Using Federated Access

run the renew command with the default options

```sh
cfn-vpn renew [name] --bucket [s3-bucket]
```

This will recreate the vpn with the updated server certificate.

This process can take 1-2 hours.

Once complete users will need to log into the self service portal and download new copies of the client config and import them into their vpn client.