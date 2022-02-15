# YAML Configuration File

cfn-vpn configuration can be managed through a YAML file using the `modify` command to apply the config changes to the vpn stack

## Applying changes

run the `modify` command and supply the yaml file to apply the changes

```sh
cfn-vpn routes [name] --params-yaml cfnvpn.[name].yaml
```

## Dump Current Config to YAML File

the following command will take the current config of a cfn-vpn stack and dump the contents into a YAML file named `cfnvpn.[name].yaml`

```sh
cfn-vpn params [name] --dump
```

## Configuration Options

### VPN Config

```yaml
region: ap-southeast-2
subnet_ids:
- subnet-abc123
- subnet-def456
cidr: 10.250.0.0/16
dns_servers:
- 10.250.0.2
split_tunnel: true
protocol: udp
bucket: my-vpn-bucket
server_cert_arn: arn:aws:acm:us-east-1:000000000000:certificate/123456
```

### Certificate Authentication

```yaml
type: certificate
```

### SAML Authentication

```yaml
type: federated
saml_arn: arn:aws:iam::000000000000:saml-provider/VpnSamlRole
saml_self_service_arn: arn:aws:iam::000000000000:saml-provider/VpnSelfServiceSamlRole
```

### AWS Directory Services Authentication

```yaml
type: active-directory
directory_id: d-a1b2c3d4e5
```

### Routes

**Static CIDR Route**

```yaml
routes:
- cidr: 10.151.0.0/16
  desc: route to dev peered vpc
  groups:
  - devs
  - ops
```

**DNS Lookup Route**

```yaml
routes:
- dns: example.com
  desc: my dev alb
  schedule: rate(10 minutes)
  groups:
  - dev
```

**Cloud Lookup Route**

```yaml
routes:
- cloud: aws
  schedule: rate(1 hour)
  groups:
  - ops
  filters:
  - name: region
    values:
    - ap-southeast-2
  - name: service
    values:
    - API_GATEWAY
```

### Default Auth Groups

```yaml
default_groups:
- group-a
```

### Auto Route Limit Increase

```yaml
auto_limit_increase: true
```

### Slack Notifications

```yaml
slack_webhook_url: https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX
```