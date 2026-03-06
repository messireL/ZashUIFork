# router-agent (helper for UI Mihomo/Ultra)

This is an **optional** helper agent that runs on the router and enables "adult" features that are not available via Mihomo API:

- Per-client **bandwidth shaping** (Mbps) via `tc` (recommended)
- Fallback policing via `iptables` (optional)

Дашборд **UI Mihomo/Ultra** может вызывать этот агент для применения/удаления shaping‑правил по IP.

## Install (Entware)

On the router:

```sh
opkg update
opkg install tc ip-full

sh /opt/zash-agent/install.sh
```

Инсталлятор поднимает простой HTTP сервер на **9099** (LAN / br0).

## UI config

В UI: Router → **Router agent**:

- Enable agent
- Agent URL: `http://<router_lan_ip>:9099`
- Enable "Enforce bandwidth"

## Endpoints

- `GET /cgi-bin/api.sh?cmd=status`
- `GET /cgi-bin/api.sh?cmd=ip2mac&ip=192.168.1.2`
- `GET /cgi-bin/api.sh?cmd=shape&ip=192.168.1.2&up=10&down=30`
- `GET /cgi-bin/api.sh?cmd=unshape&ip=192.168.1.2`
- `GET /cgi-bin/api.sh?cmd=neighbors`
- `GET /cgi-bin/api.sh?cmd=backup_start`
- `GET /cgi-bin/api.sh?cmd=backup_status`
- `GET /cgi-bin/api.sh?cmd=backup_log`
- `GET /cgi-bin/api.sh?cmd=backup_list`
- `GET /cgi-bin/api.sh?cmd=backup_cron_get`
- `GET /cgi-bin/api.sh?cmd=backup_cron_set&enabled=1&schedule=0%204%20*%20*%20*`
- `GET /cgi-bin/api.sh?cmd=restore_start&file=latest&scope=all&env=0`
- `GET /cgi-bin/api.sh?cmd=restore_status`
- `GET /cgi-bin/api.sh?cmd=restore_log`

Если в `/opt/zash-agent/agent.env` задан `TOKEN=...`, UI будет слать `Authorization: Bearer <token>`.

### status payload

In addition to capability flags (tc/iptables/hashlimit), `status` also reports basic system metrics (best-effort):

- `cpuPct` (0..100)
- `load1` (1-minute load average)
- `uptimeSec`
- `memUsedPct` (0..100)
- `memUsed`, `memTotal` (bytes)

## Backups (Google Drive / Yandex Disk)

Подробная инструкция: `../docs/backup.md`.

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
# optional, to include UI dist.zip in the archive
UI_ZIP_URL="https://github.com/messireL/ZashUIFork/releases/download/rolling/dist.zip"

# local retention (days)
BACKUP_KEEP_DAYS="30"

# cloud upload via rclone
RCLONE_REMOTE="gdrive"     # or yandex
RCLONE_PATH="NetcrazeBackups/zash-agent"
RCLONE_KEEP_DAYS="30"      # remote retention (best-effort)
```

### 3) Run once

```sh
/opt/zash-agent/backup.sh
```

### 4) Schedule (cron)

В UI (Router → Router agent → **Backup schedule**) можно задать время (по умолчанию **04:00**) и нажать **Apply** — UI установит cron-строку на роутере (помечается комментарием `# zash-backup`).

Если хочешь вручную:

```sh
crontab -e
```

Example: daily at 04:00

```cron
0 4 * * * /opt/zash-agent/backup.sh >/opt/zash-agent/var/backup.cron.log 2>&1 # zash-backup
```


## Restore

Restore works with local archives from `/opt/zash-agent/var/backups` (created by `backup.sh`).

- `file=latest` (default) or a specific filename from `backup_list`
- `scope=all|mihomo|agent`
- `env=1` to also restore `/opt/zash-agent/agent.env` (disabled by default)

**Note:** after restoring Mihomo config, you may need to restart Mihomo; after restoring agent settings/state — restart `zash-agent`.
