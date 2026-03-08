#!/bin/sh
# Simple router backup helper (Mihomo config + zash-agent state) with optional cloud upload via rclone.
set -e

ENV_FILE="/opt/zash-agent/agent.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

BACKUP_TMP_DIR="${BACKUP_TMP_DIR:-/opt/zash-agent/var/backups}"
BACKUP_STATUS_FILE="${BACKUP_STATUS_FILE:-/opt/zash-agent/var/backup.last.json}"
BACKUP_LOG_FILE="${BACKUP_LOG_FILE:-/opt/zash-agent/var/backup.last.log}"

RCLONE_REMOTE="${RCLONE_REMOTE:-}"
RCLONE_PATH="${RCLONE_PATH:-NetcrazeBackups/zash-agent}"
RCLONE_KEEP_DAYS="${RCLONE_KEEP_DAYS:-30}"

# Optional: include current UI build (dist.zip) into the backup.
# NOTE: BusyBox wget may not support https; prefer /opt/bin/wget.
UI_ZIP_URL="${UI_ZIP_URL:-}"

MIHOMO_CONFIG="${MIHOMO_CONFIG:-/opt/etc/mihomo/config.yaml}"

ts="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo now)"
host="$(uname -n 2>/dev/null || echo router)"
started_at="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"

mkdir -p "$BACKUP_TMP_DIR" /opt/zash-agent/var >/dev/null 2>&1 || true

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g'
}

write_status() {
  printf '%s' "$1" > "$BACKUP_STATUS_FILE" 2>/dev/null || true
}

# Mark as running
write_status "$(printf '{\"ok\":true,\"running\":true,\"startedAt\":\"%s\"}' "$(json_escape "$started_at")")"

success=0
uploaded=false
out=""
err=""

finish() {
  code=$?
  trap - EXIT
  finished_at="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"
  if [ $code -ne 0 ] || [ $success -ne 1 ]; then
    e="${err:-exit $code}"
    write_status "$(printf '{\"ok\":true,\"running\":false,\"startedAt\":\"%s\",\"finishedAt\":\"%s\",\"success\":false,\"error\":\"%s\"}' \
      "$(json_escape "$started_at")" "$(json_escape "$finished_at")" "$(json_escape "$e")")"
    exit $code
  fi

  write_status "$(printf '{\"ok\":true,\"running\":false,\"startedAt\":\"%s\",\"finishedAt\":\"%s\",\"success\":true,\"file\":\"%s\",\"uploaded\":%s}' \
    "$(json_escape "$started_at")" "$(json_escape "$finished_at")" "$(json_escape "$out")" "$uploaded")"
}
trap finish EXIT

list="$BACKUP_TMP_DIR/.backup.list.$$"
rm -f "$list" 2>/dev/null || true

add() {
  p="$1"
  [ -e "$p" ] && echo "$p" >> "$list"
}

# Mihomo
add "$MIHOMO_CONFIG"
add "/opt/etc/mihomo/GeoIP.dat"
add "/opt/etc/mihomo/GeoSite.dat"
add "/opt/etc/mihomo/ASN.mmdb"
add "/opt/etc/mihomo/rules"

# zash-agent
add "/opt/zash-agent/agent.env"
add "/opt/zash-agent/var/users-db.json"
add "/opt/zash-agent/var/users-db.meta.json"
add "/opt/zash-agent/var/users-db.revs"
add "/opt/zash-agent/var/shapers.db"
add "/opt/zash-agent/var/blocks.db"
add "/opt/zash-agent/var/agent.log"

# Optional UI dist.zip
if [ -n "$UI_ZIP_URL" ]; then
  ui="$BACKUP_TMP_DIR/ui-dist-${host}-${ts}.zip"
  rm -f "$ui" 2>/dev/null || true
  set +e
  if [ -x /opt/bin/wget ]; then
    /opt/bin/wget -qO "$ui" "$UI_ZIP_URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$ui" "$UI_ZIP_URL"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$UI_ZIP_URL" -o "$ui"
  fi
  rc=$?
  set -e
  if [ $rc -eq 0 ] && [ -s "$ui" ]; then
    add "$ui"
  else
    rm -f "$ui" 2>/dev/null || true
  fi
fi

out="$BACKUP_TMP_DIR/zash-backup-${host}-${ts}.tar.gz"

# BusyBox tar may not support -z; fall back to gzip pipeline.
if tar -czf "$out" -T "$list" >/dev/null 2>&1; then
  :
else
  tar -cf - -T "$list" 2>/dev/null | gzip -c > "$out"
fi

rm -f "$list" 2>/dev/null || true

echo "[backup] created: $out" | tee -a "$BACKUP_LOG_FILE" >/dev/null 2>&1 || true

if [ -n "$RCLONE_REMOTE" ] && command -v rclone >/dev/null 2>&1; then
  dst="$RCLONE_REMOTE:$RCLONE_PATH"
  RCLONE_CONFIG="$RCLONE_CONFIG" rclone mkdir "$dst" >/dev/null 2>&1 || true
  RCLONE_CONFIG="$RCLONE_CONFIG" rclone copy "$out" "$dst" --transfers 1 --checkers 1 --retries 2
  uploaded=true
  echo "[backup] uploaded to: $dst" | tee -a "$BACKUP_LOG_FILE" >/dev/null 2>&1 || true
  # retention (best-effort)
  if echo "$RCLONE_KEEP_DAYS" | grep -qE '^[0-9]+$' && [ "$RCLONE_KEEP_DAYS" -gt 0 ]; then
    RCLONE_CONFIG="$RCLONE_CONFIG" rclone delete "$dst" --min-age "${RCLONE_KEEP_DAYS}d" --include "zash-backup-*.tar.gz" >/dev/null 2>&1 || true
  fi
else
  echo "[backup] rclone is not configured; set RCLONE_REMOTE in $ENV_FILE to enable cloud upload" | tee -a "$BACKUP_LOG_FILE" >/dev/null 2>&1 || true
fi

success=1
