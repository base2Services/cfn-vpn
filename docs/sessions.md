# Managing Client-VPN Sessions

## Show Sessions

This is show a table of current connections on the vpn. You can then kill sessions by using the connection id.

```sh
cfn-vpn sessions [name]
```

The sessions are displayed in a table format

```bash
+-------------+---------------------+--------+-------------+-----------------------------------+---------------+--------------+
| Common Name | Connected (UTC)     | Status | IP Address  | Connection ID                     | Ingress Bytes | Egress Bytes |
+-------------+---------------------+--------+-------------+-----------------------------------+---------------+--------------+
| user1       | 2019-06-28 04:58:19 | active | 10.250.0.98 | cvpn-connection-05bcc579cb3fdf9a3 | 3000          | 2679         |
+-------------+---------------------+--------+-------------+-----------------------------------+---------------+--------------+
```

## Terminate a Session

To terminate a Client-VPN session specify the `--kill` flag with the connection id to kill the session.

```sh
cfn-vpn sessions myvpn --kill cvpn-connection-05bcc579cb3fdf9a3
```