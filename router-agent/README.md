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

### status payload

In addition to capability flags (tc/iptables/hashlimit), `status` also reports basic system metrics (best-effort):

- `cpuPct` (0..100)
- `load1` (1-minute load average)
- `uptimeSec`
- `memUsedPct` (0..100)
- `memUsed`, `memTotal` (bytes)

## Backups (Google Drive / Yandex Disk)

The installer also creates `/opt/zash-agent/backup.sh` — it archives Mihomo config + zash-agent state (including `users-db.json`) and can optionally upload it to a cloud drive via **rclone**.

### 1) Install & configure rclone (Entware)

```sh
opkg update
opkg install rclone
rclone config
```

**Yandex Disk**: easiest is WebDAV (`type = webdav`, URL `https://webdav.yandex.ru`, user = Yandex login, pass = app password).

### 2) Enable upload in agent.env

Edit `/opt/zash-agent/agent.env` and set:

```sh
RCLONE_REMOTE="gdrive"     # or yandex
RCLONE_PATH="NetcrazeBackups/zash-agent"
RCLONE_KEEP_DAYS="30"
```

### 3) Run once

```sh
/opt/zash-agent/backup.sh
```

### 4) Schedule (cron)

Example: daily at 03:30

```sh
crontab -e
```

Add:

```cron
30 3 * * * /opt/zash-agent/backup.sh >/opt/zash-agent/var/backup.last.log 2>&1
```
