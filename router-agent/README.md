# zash-agent (router helper)

This is an **optional** helper agent that runs on the router and enables "adult" features that are not available via Mihomo API:

- Per-client **bandwidth shaping** (Mbps) via `tc` (recommended)
- Fallback policing via `iptables` (optional)

The dashboard (Zashboard UI) can call this agent to apply/remove per-IP shaping rules.

## Install (Entware)

On the router:

```sh
opkg update
opkg install tc ip-full

sh /opt/zash-agent/install.sh
```

The installer will start a tiny HTTP server on **port 9099** bound to the LAN IP (br0).

## UI config

Router → **Router agent**:

- Enable agent
- Agent URL: `http://<router_lan_ip>:9099`
- Enable "Enforce bandwidth"

## Endpoints

- `GET /cgi-bin/api.sh?cmd=status`
- `GET /cgi-bin/api.sh?cmd=ip2mac&ip=192.168.1.2`
- `GET /cgi-bin/api.sh?cmd=shape&ip=192.168.1.2&up=10&down=30`
- `GET /cgi-bin/api.sh?cmd=unshape&ip=192.168.1.2`
- `GET /cgi-bin/api.sh?cmd=neighbors`

If you set a token in `/opt/zash-agent/agent.env` (TOKEN=...), UI should send `Authorization: Bearer <token>`.
