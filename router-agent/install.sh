#!/bin/sh
set -e

AGENT_DIR="/opt/zash-agent"
PORT="9099"

echo "[zash-agent] installing into $AGENT_DIR"

if [ ! -d /opt ]; then
  echo "[zash-agent] /opt is missing. Install Entware first." >&2
  exit 1
fi

# Ensure HTTP daemon exists (BusyBox httpd is not always compiled in on Keenetic builds).
# We use uhttpd from Entware (keenetic feed) as a drop-in replacement.
if ! command -v uhttpd >/dev/null 2>&1; then
  echo "[zash-agent] uhttpd not found. Installing uhttpd_kn (Entware keenetic feed)..." >&2
  opkg update >/dev/null 2>&1 || true
  opkg install uhttpd_kn >/dev/null 2>&1 || opkg install uhttpd >/dev/null 2>&1 || true
fi

WAN_IF="$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n1)"
[ -n "$WAN_IF" ] || WAN_IF="eth0"

LAN_IF="br0"
if ! ip link show "$LAN_IF" >/dev/null 2>&1; then
  # try to find a bridge
  LAN_IF="$(ip -o link show 2>/dev/null | awk -F': ' '/: br/{print $2; exit}')"
  [ -n "$LAN_IF" ] || LAN_IF="br0"
fi

BIND_IP="$(ip -4 addr show "$LAN_IF" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
[ -n "$BIND_IP" ] || BIND_IP="0.0.0.0"

mkdir -p "$AGENT_DIR/www/cgi-bin" "$AGENT_DIR/var"

if [ ! -f "$AGENT_DIR/agent.env" ]; then
  cat > "$AGENT_DIR/agent.env" <<EOF
WAN_IF="$WAN_IF"
LAN_IF="$LAN_IF"
BIND_IP="$BIND_IP"
PORT="$PORT"
STATE_FILE="$AGENT_DIR/var/shapers.db"
BLOCKS_FILE="$AGENT_DIR/var/blocks.db"

# Path to Mihomo YAML config on the router
MIHOMO_CONFIG="/opt/etc/mihomo/config.yaml"

# Optional: explicit path to Mihomo log file (if log-file is not set in config)
MIHOMO_LOG=""

# Optional: custom GEO download URLs (used by cmd=geo_update)
GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip-lite.dat"
GEOSITE_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
ASN_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb"

# Optional: set a token to require Authorization: Bearer <token>
TOKEN=""

# Optional: backups to cloud via rclone (see /opt/zash-agent/backup.sh)
BACKUP_TMP_DIR="$AGENT_DIR/var/backups"
RCLONE_CONFIG=""   # optional explicit rclone config path
RCLONE_REMOTE=""   # legacy single remote, e.g. gdrive / yandex
RCLONE_REMOTES=""  # comma/space separated remotes, e.g. gdrive-crypt,yandex-crypt
RCLONE_PATH="NetcrazeBackups/zash-agent"
RCLONE_KEEP_DAYS="30"

# Root class rates (mbit). Keep high unless you want a global cap.
WAN_RATE="1000"
LAN_RATE="1000"
EOF
  echo "[zash-agent] created $AGENT_DIR/agent.env (edit if needed)"
else
  echo "[zash-agent] using existing $AGENT_DIR/agent.env"
fi

cat > "$AGENT_DIR/www/cgi-bin/api.sh" <<'EOF'
#!/bin/sh

ENV_FILE="/opt/zash-agent/agent.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

WAN_IF="${WAN_IF:-eth0}"
LAN_IF="${LAN_IF:-br0}"
PORT="${PORT:-9099}"
STATE_FILE="${STATE_FILE:-/opt/zash-agent/var/shapers.db}"
BLOCKS_FILE="${BLOCKS_FILE:-/opt/zash-agent/var/blocks.db}"
USERS_DB_FILE="${USERS_DB_FILE:-/opt/zash-agent/var/users-db.json}"
USERS_DB_META="${USERS_DB_META:-/opt/zash-agent/var/users-db.meta.json}"
USERS_DB_REVS_DIR="${USERS_DB_REVS_DIR:-/opt/zash-agent/var/users-db.revs}"
USERS_DB_REVS_MAX="${USERS_DB_REVS_MAX:-10}"
TOKEN="${TOKEN:-}"
MIHOMO_CONFIG="${MIHOMO_CONFIG:-/opt/etc/mihomo/config.yaml}"
MIHOMO_LOG="${MIHOMO_LOG:-}"
GEOIP_URL="${GEOIP_URL:-https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip-lite.dat}"
GEOSITE_URL="${GEOSITE_URL:-https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat}"
ASN_URL="${ASN_URL:-https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb}"
WAN_RATE="${WAN_RATE:-1000}"
LAN_RATE="${LAN_RATE:-1000}"
BACKUP_TMP_DIR="${BACKUP_TMP_DIR:-/opt/zash-agent/var/backups}"
RCLONE_CONFIG="${RCLONE_CONFIG:-}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}"
RCLONE_REMOTES="${RCLONE_REMOTES:-}"
RCLONE_PATH="${RCLONE_PATH:-NetcrazeBackups/zash-agent}"
RCLONE_KEEP_DAYS="${RCLONE_KEEP_DAYS:-30}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-${RCLONE_KEEP_DAYS:-30}}"
UI_ZIP_URL="${UI_ZIP_URL:-}"

json() {
  printf '{'
  first=1
  while [ "$#" -gt 0 ]; do
    k="$1"; v="$2"; shift 2
    [ $first -eq 0 ] && printf ','
    first=0
    # strings only (safe enough for our payload)
    printf '"%s":"%s"' "$k" "$(printf '%s' "$v" | sed 's/"/\\"/g')"
  done
  printf '}'
}

reply_ok() {
  echo "Content-Type: application/json"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type, Authorization"
  echo "Access-Control-Allow-Private-Network: true"
  echo "Cache-Control: no-store"
  echo
  echo "$1"
}


b64enc() {
  if command -v base64 >/dev/null 2>&1; then
    base64 -w 0 2>/dev/null || base64 2>/dev/null | tr -d '\n'
  elif command -v openssl >/dev/null 2>&1; then
    openssl base64 -A
  else
    cat | tr -d '\n'
  fi
}

ssl_not_after() {
  host="$1"; port="$2"
  [ -n "$host" ] || return 0
  [ -n "$port" ] || port="443"
  command -v openssl >/dev/null 2>&1 || return 0
  if command -v timeout >/dev/null 2>&1; then
    end="$(echo | timeout 7 openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
  else
    end="$(echo | openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
  fi
  printf '%s' "$end"
}

users_db_panel_urls_lines() {
  # Extract providerPanelUrls map from users-db JSON as lines: name<TAB>url
  # We support a few legacy filenames to be robust across upgrades.
  file=""
  for f in "$USERS_DB_FILE" "/opt/zash-agent/var/users_db.json" "/opt/zash-agent/var/usersdb.json"; do
    if [ -f "$f" ]; then
      file="$f"
      break
    fi
  done
  [ -n "$file" ] || return 0

  data="$(head -c 2097152 "$file" 2>/dev/null | tr -d '\n\r')"

  # providerPanelUrls is expected to be a JSON object: { "Provider": "https://...", ... }
  part="$(printf '%s' "$data" | sed -nE 's/.*"providerPanelUrls"[[:space:]]*:[[:space:]]*\{([^}]*)\}.*/\1/p' | head -n1)"
  [ -n "$part" ] || return 0

  printf '%s' "$part" | tr ',' '\n' | sed -nE 's/^[[:space:]]*"([^"]+)"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1\t\2/p'
  return 0
}


panel_url_for_provider() {
  # args: providerName, panelMapLines
  name="$1"
  lines="$2"
  [ -n "$name" ] || return 0
  [ -n "$lines" ] || return 0
  printf '%s\n' "$lines" | awk -F'\t' -v n="$name" 'tolower($1)==tolower(n){print $2; exit}'
}

remote_agent_version() {
  # Best-effort: fetch current agent version from the upstream install script.
  # Cached to avoid slowing down status calls.
  cache_v="/opt/zash-agent/var/remote-version.txt"
  cache_t="/opt/zash-agent/var/remote-version.ts"
  ttl=21600 # 6 hours

  now="$(date +%s 2>/dev/null || echo 0)"
  if [ -f "$cache_v" ] && [ -f "$cache_t" ]; then
    ts="$(cat "$cache_t" 2>/dev/null || echo 0)"
    if echo "$ts" | grep -qE '^[0-9]+$' && [ "$now" -gt 0 ] && [ $((now-ts)) -lt "$ttl" ]; then
      cat "$cache_v" 2>/dev/null || echo ""
      return 0
    fi
  fi

  url="https://raw.githubusercontent.com/messireL/ZashUIFork/main/router-agent/install.sh"
  wb="/opt/bin/wget"
  [ -x "$wb" ] || wb="wget"
  v=""

  if command -v timeout >/dev/null 2>&1; then
    v="$(timeout 4 "$wb" -qO- "$url" 2>/dev/null | sed -n 's/.*"version":"\([0-9.]*\)".*/\1/p' | head -n1)"
  else
    v="$("$wb" -qO- "$url" 2>/dev/null | sed -n 's/.*"version":"\([0-9.]*\)".*/\1/p' | head -n1)"
  fi

  if [ -n "$v" ]; then
    mkdir -p /opt/zash-agent/var >/dev/null 2>&1 || true
    echo "$v" > "$cache_v" 2>/dev/null || true
    echo "$now" > "$cache_t" 2>/dev/null || true
    printf '%s' "$v"
    return 0
  fi

  # fallback to cached value even if stale
  [ -f "$cache_v" ] && cat "$cache_v" 2>/dev/null || echo ""
  return 0
}

mihomo_config_json() {
  if [ ! -f "$MIHOMO_CONFIG" ]; then
    reply_ok '{"ok":false,"error":"config-not-found"}'
    return
  fi
  content="$(head -c 524288 "$MIHOMO_CONFIG" | b64enc)"
  reply_ok "$(json ok true contentB64 "$content")"
}

mihomo_providers_json() {
  if [ ! -f "$MIHOMO_CONFIG" ]; then
    reply_ok '{"ok":false,"error":"config-not-found"}'
    return
  fi

  checkedAtSec="$(date +%s 2>/dev/null || echo 0)"
  panel_map="$(users_db_panel_urls_lines)"

  in=0
  pname=""
  url=""
  emitted=0

  out="{\"ok\":true,\"checkedAtSec\":${checkedAtSec},\"providers\":["
  first=1

  emit_current_provider() {
    [ -n "$pname" ] || return 0

    scheme=""
    host=""
    port=""
    not_after=""

    if [ -n "$url" ]; then
      scheme="${url%%://*}"
      rest="${url#*://}"
      hostport="${rest%%/*}"

      host="$hostport"
      port="443"
      if echo "$hostport" | grep -q '^\['; then
        host="$(echo "$hostport" | sed -E 's/^\[([^\]]+)\].*/\1/')"
        port_part="$(echo "$hostport" | sed -nE 's/^\[[^\]]+\]:(.*)$/\1/p')"
        [ -n "$port_part" ] && port="$port_part"
      else
        host="$(printf '%s' "$hostport" | cut -d: -f1)"
        if echo "$hostport" | grep -q ':'; then
          port_part="$(printf '%s' "$hostport" | awk -F: '{print $NF}')"
          [ -n "$port_part" ] && port="$port_part"
        fi
      fi

      if [ "$scheme" = "https" ] || [ "$scheme" = "wss" ]; then
        not_after="$(ssl_not_after "$host" "$port")"
      fi
    fi

    panel_url="$(panel_url_for_provider "$pname" "$panel_map")"
    panel_na=""
    if [ -n "$panel_url" ]; then
      pscheme="${panel_url%%://*}"
      prest="${panel_url#*://}"
      phostport="${prest%%/*}"

      p_host="$phostport"
      p_port="443"
      if echo "$phostport" | grep -q '^\['; then
        p_host="$(echo "$phostport" | sed -E 's/^\[([^\]]+)\].*/\1/')"
        pport_part="$(echo "$phostport" | sed -nE 's/^\[[^\]]+\]:(.*)$/\1/p')"
        [ -n "$pport_part" ] && p_port="$pport_part"
      else
        p_host="$(printf '%s' "$phostport" | cut -d: -f1)"
        if echo "$phostport" | grep -q ':'; then
          pport_part="$(printf '%s' "$phostport" | awk -F: '{print $NF}')"
          [ -n "$pport_part" ] && p_port="$pport_part"
        fi
      fi

      if [ "$pscheme" = "https" ] || [ "$pscheme" = "wss" ]; then
        panel_na="$(ssl_not_after "$p_host" "$p_port")"
      fi
    fi

    [ $first -eq 0 ] && out="$out,"
    first=0

    esc_name="$(printf '%s' "$pname" | sed 's/"/\\\\\\"/g')"
    esc_url="$(printf '%s' "$url" | sed 's/"/\\\\\\"/g')"
    esc_host="$(printf '%s' "$host" | sed 's/"/\\\\\\"/g')"
    esc_port="$(printf '%s' "$port" | sed 's/"/\\\\\\"/g')"
    esc_na="$(printf '%s' "$not_after" | sed 's/"/\\\\\\"/g')"
    esc_purl="$(printf '%s' "$panel_url" | sed 's/"/\\\\\\"/g')"
    esc_pna="$(printf '%s' "$panel_na" | sed 's/"/\\\\\\"/g')"

    out="$out{\"name\":\"$esc_name\",\"url\":\"$esc_url\",\"host\":\"$esc_host\",\"port\":\"$esc_port\",\"sslNotAfter\":\"$esc_na\",\"panelUrl\":\"$esc_purl\",\"panelSslNotAfter\":\"$esc_pna\"}"
    emitted=1
  }

  while IFS= read -r line; do
    if [ $in -eq 0 ]; then
      case "$line" in
        proxy-providers:*) in=1; continue ;;
      esac
      continue
    fi

    # next top-level key -> stop
    echo "$line" | grep -qE '^[^[:space:]]' && break

    # provider name line: "  Name:"
    if echo "$line" | grep -qE '^[[:space:]]{2}[^[:space:]].*:[[:space:]]*$'; then
      # flush previous provider even if it had no url
      if [ -n "$pname" ] && [ $emitted -eq 0 ]; then
        emit_current_provider
      fi
      pname="$(echo "$line" | sed -E 's/^[[:space:]]{2}([^:]+):.*/\1/')"
      url=""
      emitted=0
      continue
    fi

    # url line (optional)
    if echo "$line" | grep -qE '^[[:space:]]{4}url:[[:space:]]*'; then
      url="$(echo "$line" | sed -E 's/^[[:space:]]{4}url:[[:space:]]*//')"
      url="$(echo "$url" | sed -E 's/^["\x27]?//; s/["\x27]?$//')"
      emitted=0
      emit_current_provider
      continue
    fi
  done < "$MIHOMO_CONFIG"

  # flush last provider if not emitted yet (e.g. no url)
  if [ $in -eq 1 ] && [ -n "$pname" ] && [ $emitted -eq 0 ]; then
    emit_current_provider
  fi

  out="$out]}"
  reply_ok "$out"
}

ssl_probe_batch_json() {
  checkedAtSec="$(date +%s 2>/dev/null || echo 0)"

  # Read POST body (text/plain). Each line: "<name>\t<url>".
  tab="$(printf '\t' 2>/dev/null || echo ' ' )"

  out="{\"ok\":true,\"checkedAtSec\":${checkedAtSec},\"items\":["
  first=1

  while IFS= read -r line; do
    # trim
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$line" ] || continue

    name=""
    url=""
    if echo "$line" | grep -q "$tab"; then
      name="${line%%$tab*}"
      url="${line#*$tab}"
    else
      # fallback: split by first space
      name="${line%% *}"
      url="${line#* }"
      [ "$name" = "$url" ] && url="$name"
    fi

    name="$(printf '%s' "$name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    url="$(printf '%s' "$url" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$name" ] || continue
    [ -n "$url" ] || continue

    scheme="${url%%://*}"
    rest="${url#*://}"
    hostport="${rest%%/*}"

    host=""
    port="443"

    if echo "$hostport" | grep -q '^\['; then
      host="$(echo "$hostport" | sed -E 's/^\[([^\]]+)\].*/\1/')"
      port_part="$(echo "$hostport" | sed -nE 's/^\[[^\]]+\]:(.*)$/\1/p')"
      [ -n "$port_part" ] && port="$port_part"
    else
      host="$(printf '%s' "$hostport" | cut -d: -f1)"
      if echo "$hostport" | grep -q ':'; then
        port_part="$(printf '%s' "$hostport" | awk -F: '{print $NF}')"
        [ -n "$port_part" ] && port="$port_part"
      fi
    fi

    na=""
    err=""
    if [ "$scheme" = "https" ] || [ "$scheme" = "wss" ]; then
      na="$(ssl_not_after "$host" "$port")"
      [ -n "$na" ] || err="probe-failed"
    else
      err="non-https"
    fi

    [ $first -eq 0 ] && out="$out,"
    first=0

    esc_name="$(jesc "$name")"
    esc_url="$(jesc "$url")"
    esc_na="$(jesc "$na")"
    esc_err="$(jesc "$err")"

    out="$out{\"name\":\"$esc_name\",\"url\":\"$esc_url\",\"sslNotAfter\":\"$esc_na\",\"error\":\"$esc_err\"}"
  done

  out="$out]}"
  reply_ok "$out"
}


jesc() {
  # Minimal JSON string escape (quotes + backslashes)
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

normalize_rclone_path() {
  p="$1"
  p="$(printf '%s' "$p" | sed 's#^/*##; s#//*#/#g; s#/$##')"
  printf '%s' "$p"
}

stat_mtime_sec() {
  p="$1"

  # GNU/coreutils stat (Entware coreutils)
  out="$(stat -c %Y "$p" 2>/dev/null || true)"
  echo "$out" | grep -qE '^[0-9]+$' && { echo "$out"; return; }

  # BusyBox stat may exist but not support all flags depending on build
  if command -v busybox >/dev/null 2>&1; then
    out="$(busybox stat -c %Y "$p" 2>/dev/null || true)"
    echo "$out" | grep -qE '^[0-9]+$' && { echo "$out"; return; }
  fi

  # date -r (some BusyBox builds)
  out="$(date -r "$p" +%s 2>/dev/null || true)"
  echo "$out" | grep -qE '^[0-9]+$' && { echo "$out"; return; }
  if command -v busybox >/dev/null 2>&1; then
    out="$(busybox date -r "$p" +%s 2>/dev/null || true)"
    echo "$out" | grep -qE '^[0-9]+$' && { echo "$out"; return; }
  fi

  # Parse "Modify:" from BusyBox stat output and convert via date -d
  if command -v busybox >/dev/null 2>&1; then
    line="$(busybox stat "$p" 2>/dev/null | grep -E '^[[:space:]]*Modify:' | head -n1 || true)"
    if [ -n "$line" ]; then
      ts="$(echo "$line" | sed 's/^[[:space:]]*Modify:[[:space:]]*//')"
      out="$(date -d "$ts" +%s 2>/dev/null || true)"
      echo "$out" | grep -qE '^[0-9]+$' && { echo "$out"; return; }
      out="$(busybox date -d "$ts" +%s 2>/dev/null || true)"
      echo "$out" | grep -qE '^[0-9]+$' && { echo "$out"; return; }
    fi
  fi

  # BSD stat fallback (rare on routers)
  out="$(stat -f %m "$p" 2>/dev/null || true)"
  echo "$out" | grep -qE '^[0-9]+$' && { echo "$out"; return; }

  echo 0
}

stat_size_bytes() {
  p="$1"
  stat -c %s "$p" 2>/dev/null || stat -f %z "$p" 2>/dev/null || wc -c <"$p" 2>/dev/null || echo 0
}

geo_info_json() {
  echo "Content-Type: application/json"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type, Authorization"
  echo "Access-Control-Allow-Private-Network: true"
  echo "Cache-Control: no-store"
  echo

  cfg_dir="$(dirname "$MIHOMO_CONFIG" 2>/dev/null || echo /opt/etc/mihomo)"

  geoip_path=""
  geosite_path=""
  asn_path=""
  mmdb_path=""

  for d in "$cfg_dir" /opt/etc/mihomo /opt/share/mihomo /opt/var/lib/mihomo /opt/var/mihomo /opt/etc/mihomo/geodata /opt/var/mihomo/geodata; do
    [ -n "$geoip_path" ] || {
      for f in geoip.dat GeoIP.dat geoip.dat.new GeoIP.dat.new; do
        [ -f "$d/$f" ] && geoip_path="$d/$f" && break
      done
    }
    [ -n "$geosite_path" ] || {
      for f in geosite.dat GeoSite.dat geosite.dat.new GeoSite.dat.new; do
        [ -f "$d/$f" ] && geosite_path="$d/$f" && break
      done
    }
    [ -n "$mmdb_path" ] || {
      for f in Country.mmdb country.mmdb GeoLite2-Country.mmdb; do
        [ -f "$d/$f" ] && mmdb_path="$d/$f" && break
      done
    }

    [ -n "$asn_path" ] || {
      for f in ASN.mmdb asn.mmdb GeoLite2-ASN.mmdb; do
        [ -f "$d/$f" ] && asn_path="$d/$f" && break
      done
    }
  done

  printf '{"ok":true,"items":['
  first=1
  add_item() {
    kind="$1"; path="$2"
    [ -n "$path" ] || return 0
    ex=false
    m=0
    s=0
    if [ -f "$path" ]; then
      ex=true
      m="$(stat_mtime_sec "$path")"
      s="$(stat_size_bytes "$path")"
    fi
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '{"kind":"%s","path":"%s","exists":%s,"mtimeSec":%s,"sizeBytes":%s}' \
      "$(jesc "$kind")" "$(jesc "$path")" "$ex" "$m" "$s"
  }
  add_item geoip "$geoip_path"
  add_item geosite "$geosite_path"
  add_item asn "$asn_path"
  add_item mmdb "$mmdb_path"
  printf ']}'
}

geo_update_json() {
  # Update GeoIP/GeoSite/ASN database files on router.
  # Prefer xkeen if available (xkeen -ugi / -ugs). Fallback to direct downloads via wget/curl.

  echo "Content-Type: application/json"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type, Authorization"
  echo "Access-Control-Allow-Private-Network: true"
  echo "Cache-Control: no-store"
  echo

  cfg_dir="$(dirname "$MIHOMO_CONFIG" 2>/dev/null || echo /opt/etc/mihomo)"
  [ -d "$cfg_dir" ] || cfg_dir="/opt/etc/mihomo"

  pick_target() {
    kind="$1"
    case "$kind" in
      geoip)
        for f in GeoIP.dat geoip.dat; do
          [ -f "$cfg_dir/$f" ] && { echo "$cfg_dir/$f"; return; }
        done
        echo "$cfg_dir/GeoIP.dat"
        ;;
      geosite)
        for f in GeoSite.dat geosite.dat; do
          [ -f "$cfg_dir/$f" ] && { echo "$cfg_dir/$f"; return; }
        done
        echo "$cfg_dir/GeoSite.dat"
        ;;
      asn)
        for f in ASN.mmdb GeoLite2-ASN.mmdb asn.mmdb; do
          [ -f "$cfg_dir/$f" ] && { echo "$cfg_dir/$f"; return; }
        done
        echo "$cfg_dir/ASN.mmdb"
        ;;
    esac
  }

  pick_fetcher() {
    # Prefer Entware wget/curl for HTTPS
    if [ -x /opt/bin/wget ]; then echo '/opt/bin/wget'; return; fi
    if command -v wget >/dev/null 2>&1; then echo 'wget'; return; fi
    if [ -x /opt/bin/curl ]; then echo '/opt/bin/curl'; return; fi
    if command -v curl >/dev/null 2>&1; then echo 'curl'; return; fi
    echo ''
  }

  fetcher="$(pick_fetcher)"

  dl_to() {
    url="$1"
    out="$2"
    tmp="${out}.tmp.$$"
    rm -f "$tmp" 2>/dev/null || true

    if [ -z "$fetcher" ]; then
      return 2
    fi

    if echo "$fetcher" | grep -q wget; then
      "$fetcher" -qO "$tmp" "$url" 2>/dev/null || return 1
    else
      "$fetcher" -fsSL "$url" -o "$tmp" 2>/dev/null || return 1
    fi

    sz="$(wc -c < "$tmp" 2>/dev/null || echo 0)"
    echo "$sz" | grep -qE '^[0-9]+$' || sz=0
    # sanity check: avoid overwriting with a tiny HTML error page
    [ "$sz" -ge 1024 ] || { rm -f "$tmp" 2>/dev/null || true; return 3; }

    mv -f "$tmp" "$out" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 4; }
    return 0
  }

  dl_to_any() {
    out="$1"; shift
    last_rc=1
    last_url=""
    for url in "$@"; do
      last_url="$url"
      dl_to "$url" "$out"
      rc=$?
      if [ $rc -eq 0 ]; then
        echo "$url"
        return 0
      fi
      last_rc=$rc
    done
    echo "$last_url"
    return $last_rc
  }

  # Targets
  t_geoip="$(pick_target geoip)"
  t_geosite="$(pick_target geosite)"
  t_asn="$(pick_target asn)"

  b_geoip=0; [ -f "$t_geoip" ] && b_geoip="$(stat_mtime_sec "$t_geoip")"
  b_geosite=0; [ -f "$t_geosite" ] && b_geosite="$(stat_mtime_sec "$t_geosite")"
  b_asn=0; [ -f "$t_asn" ] && b_asn="$(stat_mtime_sec "$t_asn")"

  # Try xkeen built-in updater when present
  used_xkeen=0
  if command -v xkeen >/dev/null 2>&1; then
    used_xkeen=1
    xkeen -ugi >/dev/null 2>&1 || true
    xkeen -ugs >/dev/null 2>&1 || true
  fi

  items=''
  first=1
  add_res() {
    kind="$1"; path="$2"; changed="$3"; ok="$4"; method_="$5"; src="$6"; err="$7"
    m=0; s=0
    if [ -f "$path" ]; then
      m="$(stat_mtime_sec "$path")"
      s="$(stat_size_bytes "$path")"
    fi
    [ "$first" -eq 0 ] && items="$items,"
    first=0
    items="$items{\"kind\":\"$(jesc "$kind")\",\"path\":\"$(jesc "$path")\",\"ok\":$ok,\"changed\":$changed,\"mtimeSec\":$m,\"sizeBytes\":$s,\"method\":\"$(jesc "$method_")\",\"source\":\"$(jesc "$src")\",\"error\":\"$(jesc "$err")\"}"
  }

  # Snapshot after xkeen attempt
  a_geoip=0; [ -f "$t_geoip" ] && a_geoip="$(stat_mtime_sec "$t_geoip")"
  a_geosite=0; [ -f "$t_geosite" ] && a_geosite="$(stat_mtime_sec "$t_geosite")"
  a_asn=0; [ -f "$t_asn" ] && a_asn="$(stat_mtime_sec "$t_asn")"

  # GEOIP
  if [ $used_xkeen -eq 1 ] && [ -f "$t_geoip" ] && [ "$a_geoip" -gt "$b_geoip" ]; then
    add_res geoip "$t_geoip" true true 'xkeen' 'xkeen -ugi' ''
  else
    rc=0
    used="$(dl_to_any "$t_geoip" "$GEOIP_URL"       "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip-lite.dat"       "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"       "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat")"
    rc=$?
    if [ $rc -eq 0 ]; then
      add_res geoip "$t_geoip" true true 'download' "$used" ''
    else
      add_res geoip "$t_geoip" false false 'download' "$used" "download-failed($rc)"
    fi
  fi

  # GEOSITE
  if [ $used_xkeen -eq 1 ] && [ -f "$t_geosite" ] && [ "$a_geosite" -gt "$b_geosite" ]; then
    add_res geosite "$t_geosite" true true 'xkeen' 'xkeen -ugs' ''
  else
    rc=0
    used="$(dl_to_any "$t_geosite" "$GEOSITE_URL"       "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"       "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat")"
    rc=$?
    if [ $rc -eq 0 ]; then
      add_res geosite "$t_geosite" true true 'download' "$used" ''
    else
      add_res geosite "$t_geosite" false false 'download' "$used" "download-failed($rc)"
    fi
  fi

  # ASN
  if [ -f "$t_asn" ] && [ "$a_asn" -gt "$b_asn" ]; then
    add_res asn "$t_asn" true true 'xkeen' 'xkeen' ''
  else
    rc=0
    used="$(dl_to_any "$t_asn" "$ASN_URL"       "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb"       "https://github.com/xishang0128/geoip/releases/download/latest/GeoLite2-ASN.mmdb")"
    rc=$?
    if [ $rc -eq 0 ]; then
      add_res asn "$t_asn" true true 'download' "$used" ''
    else
      add_res asn "$t_asn" false false 'download' "$used" "download-failed($rc)"
    fi
  fi

  ok=true
  echo "$items" | grep -q '"ok":false' && ok=false

  if [ "$ok" = true ]; then
    reply_ok "{\"ok\":true,\"items\":[${items}],\"note\":\"Restart mihomo if geo data is cached.\"}"
  else
    reply_ok "{\"ok\":false,\"items\":[${items}],\"error\":\"some-downloads-failed\"}"
  fi
}



rules_info_json() {
  echo "Content-Type: application/json"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type, Authorization"
  echo "Access-Control-Allow-Private-Network: true"
  echo "Cache-Control: no-store"
  echo

  cfg_dir="$(dirname "$MIHOMO_CONFIG" 2>/dev/null || echo /opt/etc/mihomo)"
  rules_dir=""
  for d in "$cfg_dir/rules" /opt/etc/mihomo/rules /opt/var/mihomo/rules /opt/share/mihomo/rules; do
    [ -d "$d" ] && rules_dir="$d" && break
  done

  if [ -z "$rules_dir" ]; then
    printf '{"ok":true,"dir":"","count":0,"newestMtimeSec":0,"oldestMtimeSec":0,"items":[]}'
    return
  fi

  tmp="/tmp/zash_rules.$$"
  : > "$tmp" 2>/dev/null || tmp="/tmp/zash_rules"

  count=0
  newest=0
  oldest=0

  # Scan up to 2 levels deep (rules/* and rules/*/*), including dotfiles.
  for f in "$rules_dir"/* "$rules_dir"/.[!.]* "$rules_dir"/..?* "$rules_dir"/*/* "$rules_dir"/*/.[!.]* "$rules_dir"/*/..?*; do
    [ -f "$f" ] || continue
    count=$((count + 1))
    m="$(stat_mtime_sec "$f")"
    echo "$m" | grep -qE '^[0-9]+$' || m=0
    s="$(stat_size_bytes "$f")"
    echo "$s" | grep -qE '^[0-9]+$' || s=0
    printf '%s|%s|%s
' "$m" "$s" "$f" >> "$tmp"
    [ "$m" -gt "$newest" ] && newest="$m"
    if [ "$oldest" -eq 0 ] || [ "$m" -lt "$oldest" ]; then
      oldest="$m"
    fi
  done

  # Build a short list (top 30 by mtime) to avoid large payloads.
  printf '{"ok":true,"dir":"%s","count":%s,"newestMtimeSec":%s,"oldestMtimeSec":%s,"items":[' "$(jesc "$rules_dir")" "$count" "$newest" "$oldest"
  first=1
  sort -t'|' -k1,1nr "$tmp" 2>/dev/null | head -n 30 | while IFS='|' read -r m s path; do
    [ -n "$path" ] || continue
    name="$(basename "$path")"
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '{"name":"%s","path":"%s","mtimeSec":%s,"sizeBytes":%s}' "$(jesc "$name")" "$(jesc "$path")" "$m" "$s"
  done
  printf ']}'
  rm -f "$tmp" 2>/dev/null
}



users_db_now_iso() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo ''
}

users_db_load_meta() {
  udb_rev=0
  udb_updatedAt=''
  if [ -f "$USERS_DB_META" ]; then
    udb_rev="$(sed -nE 's/.*"rev"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$USERS_DB_META" 2>/dev/null | head -n1)"
    udb_updatedAt="$(sed -nE 's/.*"updatedAt"[[:space:]]*:[[:space:]]*"([^\"]*)".*/\1/p' "$USERS_DB_META" 2>/dev/null | head -n1)"
  fi
  echo "$udb_rev" | grep -qE '^[0-9]+$' || udb_rev=0
}

users_db_write_meta() {
  mkdir -p "$(dirname "$USERS_DB_META")" >/dev/null 2>&1 || true
  tmp="${USERS_DB_META}.tmp.$$"
  printf '{"rev":%s,"updatedAt":"%s"}' "$udb_rev" "$(jesc "$udb_updatedAt")" > "$tmp" 2>/dev/null || return 1
  mv -f "$tmp" "$USERS_DB_META" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  return 0
}

users_db_init_if_missing() {
  mkdir -p "$(dirname "$USERS_DB_FILE")" >/dev/null 2>&1 || true
  if [ ! -f "$USERS_DB_FILE" ]; then
    printf '[]' > "$USERS_DB_FILE" 2>/dev/null || true
  fi
  users_db_load_meta
  if [ ! -f "$USERS_DB_META" ]; then
    udb_rev=0
    udb_updatedAt="$(users_db_now_iso)"
    users_db_write_meta >/dev/null 2>&1 || true
  fi
}


users_db_prune_revs() {
  max="$USERS_DB_REVS_MAX"
  echo "$max" | grep -qE '^[0-9]+$' || max=10
  [ "$max" -le 0 ] && max=10
  [ -d "$USERS_DB_REVS_DIR" ] || return 0

  revs="$(ls "$USERS_DB_REVS_DIR"/users-db.rev-*.meta.json 2>/dev/null | sed -nE 's/.*rev-([0-9]+)\.meta\.json/\1/p' | sort -n)"
  cnt="$(printf '%s\n' "$revs" | sed '/^$/d' | wc -l 2>/dev/null || echo 0)"
  echo "$cnt" | grep -qE '^[0-9]+$' || cnt=0
  if [ "$cnt" -le "$max" ]; then
    return 0
  fi
  rm_cnt=$((cnt - max))
  i=0
  printf '%s\n' "$revs" | sed '/^$/d' | while read r; do
    i=$((i+1))
    [ "$i" -le "$rm_cnt" ] || break
    rm -f "$USERS_DB_REVS_DIR/users-db.rev-$r.json" "$USERS_DB_REVS_DIR/users-db.rev-$r.meta.json" 2>/dev/null || true
  done
  return 0
}

users_db_snapshot_current() {
  mkdir -p "$USERS_DB_REVS_DIR" >/dev/null 2>&1 || true
  [ -d "$USERS_DB_REVS_DIR" ] || return 0

  # Snapshot current state (rev + updatedAt) before overwrite.
  snap_json="$USERS_DB_REVS_DIR/users-db.rev-$udb_rev.json"
  snap_meta="$USERS_DB_REVS_DIR/users-db.rev-$udb_rev.meta.json"
  cp "$USERS_DB_FILE" "$snap_json" 2>/dev/null || return 0
  printf '{"rev":%s,"updatedAt":"%s"}' "$udb_rev" "$(jesc "$udb_updatedAt")" > "$snap_meta" 2>/dev/null || true

  users_db_prune_revs >/dev/null 2>&1 || true
  return 0
}

users_db_read_rev_meta() {
  rev="$1"
  meta="$USERS_DB_REVS_DIR/users-db.rev-$rev.meta.json"
  r_updatedAt=''
  if [ -f "$meta" ]; then
    r_updatedAt="$(sed -nE 's/.*"updatedAt"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$meta" 2>/dev/null | head -n1)"
  fi
  echo "$r_updatedAt"
}

users_db_history_json() {
  users_db_init_if_missing

  echo "$USERS_DB_REVS_MAX" | grep -qE '^[0-9]+$' || USERS_DB_REVS_MAX=10

  printf 'Content-Type: application/json\n'
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type, Authorization"
  echo "Access-Control-Allow-Private-Network: true"
  echo "Cache-Control: no-store"
  echo ""
  printf '{"ok":true,"items":['
  printf '{"rev":%s,"updatedAt":"%s","current":true}' "$udb_rev" "$(jesc "$udb_updatedAt")"

  if [ -d "$USERS_DB_REVS_DIR" ]; then
    # newest first (numeric)
    revs="$(ls "$USERS_DB_REVS_DIR"/users-db.rev-*.meta.json 2>/dev/null | sed -nE 's/.*rev-([0-9]+)\.meta\.json/\1/p' | sort -nr)"
    printf '%s\n' "$revs" | sed '/^$/d' | while read r; do
      [ -n "$r" ] || continue
      [ "$r" = "$udb_rev" ] && continue
      up="$(users_db_read_rev_meta "$r")"
      printf ',{"rev":%s,"updatedAt":"%s","current":false}' "$r" "$(jesc "$up")"
    done
  fi
  printf ']}'
}

users_db_get_rev_json() {
  req_rev="$1"
  echo "$req_rev" | grep -qE '^[0-9]+$' || req_rev=''
  [ -n "$req_rev" ] || { reply_ok '{"ok":false,"error":"bad-rev"}'; return; }

  users_db_init_if_missing
  if [ "$req_rev" = "$udb_rev" ]; then
    users_db_get_json
    return
  fi

  f="$USERS_DB_REVS_DIR/users-db.rev-$req_rev.json"
  if [ ! -f "$f" ]; then
    reply_ok '{"ok":false,"error":"not-found"}'
    return
  fi
  up="$(users_db_read_rev_meta "$req_rev")"
  content="$( (head -c 1048576 "$f" 2>/dev/null || cat "$f" 2>/dev/null || printf '[]') | b64enc )"
  reply_ok "$(printf '{"ok":true,"rev":%s,"updatedAt":"%s","contentB64":"%s"}' "$req_rev" "$(jesc "$up")" "$content")"
}

users_db_restore_json() {
  req_rev="$1"
  echo "$req_rev" | grep -qE '^[0-9]+$' || req_rev=''

  if [ "$REQUEST_METHOD" != "POST" ]; then
    reply_ok '{"ok":false,"error":"method-not-allowed"}'
    return
  fi

  [ -n "$req_rev" ] || { reply_ok '{"ok":false,"error":"bad-rev"}'; return; }

  users_db_init_if_missing

  # Acquire lock (best effort)
  lockdir="${USERS_DB_FILE}.lock"
  if [ -d "$lockdir" ]; then
    lm="$(stat_mtime_sec "$lockdir")"
    now="$(date +%s 2>/dev/null || echo 0)"
    echo "$lm" | grep -qE '^[0-9]+$' || lm=0
    echo "$now" | grep -qE '^[0-9]+$' || now=0
    if [ "$lm" -gt 0 ] && [ "$now" -gt 0 ] && [ $((now - lm)) -gt 120 ]; then
      rmdir "$lockdir" 2>/dev/null || true
    fi
  fi

  i=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    i=$((i+1))
    [ $i -ge 10 ] && { reply_ok '{"ok":false,"error":"busy"}'; return; }
    sleep 1 2>/dev/null || true
  done

  users_db_load_meta

  if [ "$req_rev" = "$udb_rev" ]; then
    rmdir "$lockdir" 2>/dev/null || true
    reply_ok "$(printf '{"ok":true,"rev":%s,"updatedAt":"%s","restoredFromRev":%s}' "$udb_rev" "$(jesc "$udb_updatedAt")" "$req_rev")"
    return
  fi

  f="$USERS_DB_REVS_DIR/users-db.rev-$req_rev.json"
  if [ ! -f "$f" ]; then
    rmdir "$lockdir" 2>/dev/null || true
    reply_ok '{"ok":false,"error":"not-found"}'
    return
  fi

  # Snapshot current before restore
  users_db_snapshot_current >/dev/null 2>&1 || true

  tmp="${USERS_DB_FILE}.tmp.$$"
  (head -c 1048576 "$f" 2>/dev/null || cat "$f" 2>/dev/null) > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; rmdir "$lockdir" 2>/dev/null || true; reply_ok '{"ok":false,"error":"write-failed"}'; return; }
  mv -f "$tmp" "$USERS_DB_FILE" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; rmdir "$lockdir" 2>/dev/null || true; reply_ok '{"ok":false,"error":"write-failed"}'; return; }

  udb_rev=$((udb_rev + 1))
  udb_updatedAt="$(users_db_now_iso)"
  users_db_write_meta >/dev/null 2>&1 || true

  rmdir "$lockdir" 2>/dev/null || true

  reply_ok "$(printf '{"ok":true,"rev":%s,"updatedAt":"%s","restoredFromRev":%s}' "$udb_rev" "$(jesc "$udb_updatedAt")" "$req_rev")"
}


users_db_get_json() {
  users_db_init_if_missing

  content="$( (head -c 1048576 "$USERS_DB_FILE" 2>/dev/null || cat "$USERS_DB_FILE" 2>/dev/null || printf '[]') | b64enc )"

  reply_ok "$(printf '{"ok":true,"rev":%s,"updatedAt":"%s","contentB64":"%s"}' "$udb_rev" "$(jesc "$udb_updatedAt")" "$content")"
}

users_db_put_json() {
  expected_rev="$1"
  [ -n "$expected_rev" ] || expected_rev='-1'

  if [ "$REQUEST_METHOD" != "POST" ]; then
    reply_ok '{"ok":false,"error":"method-not-allowed"}'
    return
  fi

  users_db_init_if_missing

  # Acquire lock (best effort)
  lockdir="${USERS_DB_FILE}.lock"

  # Cleanup stale lock (>120s) to avoid deadlocks after crashes/reboots.
  if [ -d "$lockdir" ]; then
    lm="$(stat_mtime_sec "$lockdir")"
    now="$(date +%s 2>/dev/null || echo 0)"
    echo "$lm" | grep -qE '^[0-9]+$' || lm=0
    echo "$now" | grep -qE '^[0-9]+$' || now=0
    if [ "$lm" -gt 0 ] && [ "$now" -gt 0 ] && [ $((now - lm)) -gt 120 ]; then
      rmdir "$lockdir" 2>/dev/null || true
    fi
  fi

  i=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    i=$((i+1))
    [ $i -ge 10 ] && { reply_ok '{"ok":false,"error":"busy"}'; return; }
    sleep 1 2>/dev/null || true
  done

  # Reload meta under lock
  users_db_load_meta

  echo "$expected_rev" | grep -qE '^-?[0-9]+$' || expected_rev='-1'
  if [ "$expected_rev" != "$udb_rev" ]; then
    content="$( (head -c 1048576 "$USERS_DB_FILE" 2>/dev/null || cat "$USERS_DB_FILE" 2>/dev/null || printf '[]') | b64enc )"
    rmdir "$lockdir" 2>/dev/null || true
    reply_ok "$(printf '{"ok":false,"error":"conflict","rev":%s,"updatedAt":"%s","contentB64":"%s"}' "$udb_rev" "$(jesc "$udb_updatedAt")" "$content")"
    return
  fi

  users_db_snapshot_current >/dev/null 2>&1 || true

  body=""
  if [ -n "$CONTENT_LENGTH" ] && echo "$CONTENT_LENGTH" | grep -qE '^[0-9]+$'; then
    # Read exactly Content-Length bytes to avoid blocking on CGI stdin.
    body="$(head -c "$CONTENT_LENGTH" 2>/dev/null || dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null || true)"
  else
    body="$(cat 2>/dev/null || true)"
  fi
  [ -n "$body" ] || body='[]'

  # Basic size guard (~1 MiB)
  sz="$(printf '%s' "$body" | wc -c 2>/dev/null || echo 0)"
  echo "$sz" | grep -qE '^[0-9]+$' || sz=0
  if [ "$sz" -gt 1048576 ]; then
    rmdir "$lockdir" 2>/dev/null || true
    reply_ok '{"ok":false,"error":"too-large"}'
    return
  fi

  tmp="${USERS_DB_FILE}.tmp.$$"
  printf '%s' "$body" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; rmdir "$lockdir" 2>/dev/null || true; reply_ok '{"ok":false,"error":"write-failed"}'; return; }
  mv -f "$tmp" "$USERS_DB_FILE" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; rmdir "$lockdir" 2>/dev/null || true; reply_ok '{"ok":false,"error":"write-failed"}'; return; }

  udb_rev=$((udb_rev + 1))
  udb_updatedAt="$(users_db_now_iso)"
  users_db_write_meta >/dev/null 2>&1 || true

  rmdir "$lockdir" 2>/dev/null || true

  reply_ok "$(printf '{"ok":true,"rev":%s,"updatedAt":"%s"}' "$udb_rev" "$(jesc "$udb_updatedAt")")"
}

if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
  reply_ok "{}"
  exit 0
fi

# Parse query string (key=value&...)
cmd=""; ip=""; up=""; down=""; mac=""; ports=""; token_q=""; type=""; lines=""; offset=""; rev_q=""; enabled_q=""; schedule_q=""; remote_q=""; remotes_q=""
IFS='&'
for kv in $QUERY_STRING; do
  key="${kv%%=*}"
  val="${kv#*=}"
  # URL decode for %2F etc. and '+' -> space for query params like cron schedules.
  val="${val//+/ }"
  val="$(printf '%b' "${val//%/\\x}")"
  case "$key" in
    cmd) cmd="$val" ;;
    ip) ip="$val" ;;
    up) up="$val" ;;
    down) down="$val" ;;
    mac) mac="$val" ;;
    ports) ports="$val" ;;
    type) type="$val" ;;
    lines) lines="$val" ;;
    offset) offset="$val" ;;
    rev) rev_q="$val" ;;
    token) token_q="$val" ;;
    enabled) enabled_q="$val" ;;
    schedule) schedule_q="$val" ;;
    file) file_q="$val" ;;
    scope) scope_q="$val" ;;
    env) env_q="$val" ;;
    remote) remote_q="$val" ;;
    remotes) remotes_q="$val" ;;
  esac
done
unset IFS

if [ -n "$TOKEN" ]; then
  auth="$HTTP_AUTHORIZATION"
  if [ "${auth#Bearer }" != "$TOKEN" ] && [ "$token_q" != "$TOKEN" ]; then
    reply_ok '{"ok":false,"error":"unauthorized"}'
    exit 0
  fi
fi

have_tc=0
command -v tc >/dev/null 2>&1 && have_tc=1

ensure_block_chain() {
  iptables -t filter -nL ZASH_BLOCK >/dev/null 2>&1 || iptables -t filter -N ZASH_BLOCK
  # Block both access to router and forwarded traffic from LAN.
  iptables -t filter -C INPUT -i "$LAN_IF" -j ZASH_BLOCK >/dev/null 2>&1 || iptables -t filter -I INPUT 1 -i "$LAN_IF" -j ZASH_BLOCK
  iptables -t filter -C FORWARD -i "$LAN_IF" -j ZASH_BLOCK >/dev/null 2>&1 || iptables -t filter -I FORWARD 1 -i "$LAN_IF" -j ZASH_BLOCK
}

ensure_iptables_chains() {
  iptables -t mangle -nL ZASH_UP >/dev/null 2>&1 || iptables -t mangle -N ZASH_UP
  iptables -t mangle -nL ZASH_DOWN >/dev/null 2>&1 || iptables -t mangle -N ZASH_DOWN
  iptables -t mangle -C FORWARD -j ZASH_UP >/dev/null 2>&1 || iptables -t mangle -I FORWARD 1 -j ZASH_UP
  iptables -t mangle -C FORWARD -j ZASH_DOWN >/dev/null 2>&1 || iptables -t mangle -I FORWARD 1 -j ZASH_DOWN
}

ensure_tc_base() {
  [ $have_tc -eq 1 ] || return 0

  # WAN
  tc qdisc show dev "$WAN_IF" 2>/dev/null | grep -q "htb 1:" || {
    tc qdisc add dev "$WAN_IF" root handle 1: htb default 1 2>/dev/null || true
    tc class add dev "$WAN_IF" parent 1: classid 1:1 htb rate "${WAN_RATE}mbit" ceil "${WAN_RATE}mbit" 2>/dev/null || true
  }
  # LAN
  tc qdisc show dev "$LAN_IF" 2>/dev/null | grep -q "htb 2:" || {
    tc qdisc add dev "$LAN_IF" root handle 2: htb default 1 2>/dev/null || true
    tc class add dev "$LAN_IF" parent 2: classid 2:1 htb rate "${LAN_RATE}mbit" ceil "${LAN_RATE}mbit" 2>/dev/null || true
  }
}

neighbors() {
  # Return LAN neighbor table (IP -> MAC). Useful to keep UI limits stable across DHCP changes.
  echo "Content-Type: application/json"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type, Authorization"
  echo "Access-Control-Allow-Private-Network: true"
  echo "Cache-Control: no-store"
  echo

  printf '{"ok":true,"items":['
  first=1
  ip neigh show dev "$LAN_IF" 2>/dev/null | while read -r line; do
    ipn="$(echo "$line" | awk '{print $1}')"
    macn="$(echo "$line" | awk '{print $5}')"
    stn="$(echo "$line" | awk '{print $6}')"
    echo "$macn" | grep -q ':' || continue
    [ -n "$ipn" ] || continue
    [ -n "$macn" ] || continue
    # skip incomplete
    [ "$macn" = "00:00:00:00:00:00" ] && continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '{"ip":"%s","mac":"%s","state":"%s"}' "$ipn" "$macn" "$stn"
  done
  printf ']}'
}

lan_hosts_json() {
  # Return LAN hosts from DHCP leases and ARP table (best effort).
  # items: {ip, mac, hostname, source}
  echo "Content-Type: application/json"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type, Authorization"
  echo "Access-Control-Allow-Private-Network: true"
  echo "Cache-Control: no-store"
  echo

  leases_tmp="/tmp/zash_leases.$$"
  arp_tmp="/tmp/zash_arp.$$"

  : > "$leases_tmp" 2>/dev/null || true
  : > "$arp_tmp" 2>/dev/null || true

  # Common dnsmasq lease locations (Keenetic/OpenWrt/Entware)
  for f in /tmp/dhcp.leases /var/lib/misc/dnsmasq.leases /opt/var/lib/misc/dnsmasq.leases /opt/var/state/dhcp/dhcp.leases; do
    if [ -f "$f" ]; then
      # expiry mac ip hostname clientid
      awk 'NF>=4 { ip=$3; mac=tolower($2); host=$4; exp=$1; if(host=="*" || host=="-") host=""; if(ip!="" && mac!="") print ip"|"mac"|"host"|"exp }' "$f" 2>/dev/null >> "$leases_tmp" || true
    fi
  done

  if [ -r /proc/net/arp ]; then
    awk 'NR>1 { ip=$1; mac=tolower($4); if(ip!="" && mac ~ /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/ && mac!="00:00:00:00:00:00") print ip"|"mac }' /proc/net/arp 2>/dev/null >> "$arp_tmp" || true
  fi

  # Merge: prefer DHCP hostname/mac; use ARP for missing entries.
  # Output lines: ip	mac	hostname	source
  merged_tmp="/tmp/zash_hosts.$$"
  awk -F'|' '
    FNR==NR {
      ip=$1; mac=$2; host=$3;
      if(ip!="") {
        dhcp_mac[ip]=mac;
        dhcp_host[ip]=host;
        ips[ip]=1;
      }
      next
    }
    {
      ip=$1; mac=$2;
      if(ip!="") {
        arp_mac[ip]=mac;
        ips[ip]=1;
      }
    }
    END {
      for(ip in ips) {
        mac=dhcp_mac[ip]; host=dhcp_host[ip]; src="dhcp";
        if(mac=="") { mac=arp_mac[ip]; src="arp"; }
        if(mac=="") mac="";
        if(host=="") src=src;
        print ip"	"mac"	"host"	"src;
      }
    }
  ' "$leases_tmp" "$arp_tmp" 2>/dev/null | sort > "$merged_tmp" 2>/dev/null || true

  printf '{"ok":true,"items":['
  first=1
  while IFS='	' read -r ipn macn hostn srcn; do
    [ -n "$ipn" ] || continue
    # Escape strings
    ipj="$(jesc "$ipn")"
    macj="$(jesc "$macn")"
    hostj="$(jesc "$hostn")"
    srcj="$(jesc "$srcn")"
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '{"ip":"%s","mac":"%s","hostname":"%s","source":"%s"}' "$ipj" "$macj" "$hostj" "$srcj"
  done < "$merged_tmp"
  printf ']}'

  rm -f "$leases_tmp" "$arp_tmp" "$merged_tmp" 2>/dev/null || true
}

ip2mac() {
  # Resolve a single IP to a MAC address (best effort).
  ip_="$1"
  [ -n "$ip_" ] || { reply_ok '{"ok":false,"error":"missing-ip"}'; return; }

  # Try to populate ARP/neighbor cache first.
  ping -c 1 -W 1 "$ip_" >/dev/null 2>&1 || true

  mac_=""
  # Prefer neighbor table without binding to a specific dev (bridges may differ).
  mac_="$(ip neigh show to "$ip_" 2>/dev/null | awk '/lladdr/{print $5; exit}' | tr 'A-Z' 'a-z')"
  if [ -z "$mac_" ]; then
    mac_="$(ip neigh show 2>/dev/null | awk -v ip="$ip_" '$1==ip && /lladdr/ {print $5; exit}' | tr 'A-Z' 'a-z')"
  fi
  if [ -z "$mac_" ]; then
    mac_="$(arp -n "$ip_" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/){print $i; exit}}' | tr 'A-Z' 'a-z')"
  fi

  if [ -n "$mac_" ] && echo "$mac_" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
    reply_ok "$(json ok true mac "$mac_")"
  else
    reply_ok '{"ok":false,"error":"not-found"}'
  fi
}

persist_block() {
  kind="$1"; k="$2"; p="$3"
  mkdir -p "$(dirname "$BLOCKS_FILE")" >/dev/null 2>&1 || true
  tmp="${BLOCKS_FILE}.tmp"
  # Remove previous entries for this key (kind+key) or legacy format.
  if [ -f "$BLOCKS_FILE" ]; then
    grep -vi "^${kind}[[:space:]]\+${k}[[:space:]]" "$BLOCKS_FILE" | grep -vi "^${k}[[:space:]]" > "$tmp" 2>/dev/null || true
  fi
  echo "${kind} ${k} ${p}" >> "$tmp"
  mv "$tmp" "$BLOCKS_FILE" 2>/dev/null || true
}

remove_persist_block() {
  kind="$1"; k="$2"
  [ -f "$BLOCKS_FILE" ] || return 0
  tmp="${BLOCKS_FILE}.tmp"
  grep -vi "^${kind}[[:space:]]\+${k}[[:space:]]" "$BLOCKS_FILE" | grep -vi "^${k}[[:space:]]" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$BLOCKS_FILE" 2>/dev/null || true
}

block_mac_ports() {
  m="$1"; p="$2"
  [ -n "$m" ] || { reply_ok '{"ok":false,"error":"missing-mac"}'; return; }
  ensure_block_chain

  # If ports are empty or 'all', block ALL traffic from this MAC (DROP).
  if [ -z "$p" ] || [ "$p" = "all" ] || [ "$p" = "ALL" ]; then
    iptables -t filter -C ZASH_BLOCK -m mac --mac-source "$m" -j DROP >/dev/null 2>&1 || \
      iptables -t filter -A ZASH_BLOCK -m mac --mac-source "$m" -j DROP
    persist_block "mac" "$m" "all"
    reply_ok '{"ok":true}'
    return
  fi

  oldIFS="$IFS"
  IFS=','
  for port in $p; do
    port="$(echo "$port" | tr -d ' ')"
    echo "$port" | grep -q '^[0-9]\+$' || continue
    iptables -t filter -C ZASH_BLOCK -m mac --mac-source "$m" -p tcp --dport "$port" -j REJECT >/dev/null 2>&1 || \
      iptables -t filter -A ZASH_BLOCK -m mac --mac-source "$m" -p tcp --dport "$port" -j REJECT
    iptables -t filter -C ZASH_BLOCK -m mac --mac-source "$m" -p udp --dport "$port" -j REJECT >/dev/null 2>&1 || \
      iptables -t filter -A ZASH_BLOCK -m mac --mac-source "$m" -p udp --dport "$port" -j REJECT
  done
  IFS="$oldIFS"

  persist_block "mac" "$m" "$p"
  reply_ok '{"ok":true}'
}

unblock_mac_ports() {
  m="$1"
  [ -n "$m" ] || { reply_ok '{"ok":false,"error":"missing-mac"}'; return; }
  ensure_block_chain

  # remove any rules for this MAC (best effort)
  while iptables -t filter -D ZASH_BLOCK -m mac --mac-source "$m" -j REJECT >/dev/null 2>&1; do :; done
  # Also remove with protocol/port (some iptables builds require exact match)
  # NOTE: pattern starts with "--" so we must pass "--" to grep to avoid it being parsed as an option
  iptables -t filter -S ZASH_BLOCK 2>/dev/null | grep -i -F -- "--mac-source $m" | while read -r rule; do
    # Convert -A to -D
    drule="$(echo "$rule" | sed 's/^-A /-D /')"
    iptables -t filter $drule >/dev/null 2>&1 || true
  done

  remove_persist_block "mac" "$m"
  reply_ok '{"ok":true}'
}

block_ip() {
  ip_="$1"
  [ -n "$ip_" ] || { reply_ok '{"ok":false,"error":"missing-ip"}'; return; }
  ensure_block_chain
  iptables -t filter -C ZASH_BLOCK -s "$ip_" -j DROP >/dev/null 2>&1 || \
    iptables -t filter -A ZASH_BLOCK -s "$ip_" -j DROP
  persist_block "ip" "$ip_" "all"
  reply_ok '{"ok":true}'
}

unblock_ip() {
  ip_="$1"
  [ -n "$ip_" ] || { reply_ok '{"ok":false,"error":"missing-ip"}'; return; }
  ensure_block_chain
  while iptables -t filter -D ZASH_BLOCK -s "$ip_" -j DROP >/dev/null 2>&1; do :; done
  remove_persist_block "ip" "$ip_"
  reply_ok '{"ok":true}'
}

rehydrate_blocks() {
  [ -f "$BLOCKS_FILE" ] || return 0
  ensure_block_chain
  while read -r a b c; do
    [ -n "$a" ] || continue

    kind="$a"
    key="$b"
    val="$c"

    # Legacy format: <mac> <ports>
    if [ "$kind" != "mac" ] && [ "$kind" != "ip" ]; then
      kind="mac"
      key="$a"
      val="$b"
    fi

    if [ "$kind" = "ip" ]; then
      [ -n "$key" ] || continue
      iptables -t filter -C ZASH_BLOCK -s "$key" -j DROP >/dev/null 2>&1 || \
        iptables -t filter -A ZASH_BLOCK -s "$key" -j DROP
      continue
    fi

    m="$key"
    p="$val"
    [ -n "$m" ] || continue
    [ -n "$p" ] || p="all"

    if [ "$p" = "all" ] || [ "$p" = "ALL" ]; then
      iptables -t filter -C ZASH_BLOCK -m mac --mac-source "$m" -j DROP >/dev/null 2>&1 || \
        iptables -t filter -A ZASH_BLOCK -m mac --mac-source "$m" -j DROP
      continue
    fi

    oldIFS="$IFS"; IFS=','
    for port in $p; do
      port="$(echo "$port" | tr -d ' ')"
      echo "$port" | grep -q '^[0-9]\+$' || continue
      iptables -t filter -C ZASH_BLOCK -m mac --mac-source "$m" -p tcp --dport "$port" -j REJECT >/dev/null 2>&1 || \
        iptables -t filter -A ZASH_BLOCK -m mac --mac-source "$m" -p tcp --dport "$port" -j REJECT
      iptables -t filter -C ZASH_BLOCK -m mac --mac-source "$m" -p udp --dport "$port" -j REJECT >/dev/null 2>&1 || \
        iptables -t filter -A ZASH_BLOCK -m mac --mac-source "$m" -p udp --dport "$port" -j REJECT
    done
    IFS="$oldIFS"
  done < "$BLOCKS_FILE"
  return 0
}

ip_to_int() {
  echo "$1" | awk -F. '{print ($1*256*256*256)+($2*256*256)+($3*256)+$4}'
}

minor_for_ip() {
  n="$(ip_to_int "$1")"
  echo $(( (n % 4095) + 10 ))
}

apply_tc_only() {
  ip="$1"; up="$2"; down="$3"
  [ $have_tc -eq 1 ] || return 1

  ensure_iptables_chains
  ensure_tc_base

  minor="$(minor_for_ip "$ip")"
  mark_up="$minor"
  mark_down=$((16384 + minor))

  # iptables marks (idempotent)
  iptables -t mangle -C ZASH_UP -s "$ip" -o "$WAN_IF" -j MARK --set-xmark "$mark_up/0xffff" >/dev/null 2>&1 || \
    iptables -t mangle -A ZASH_UP -s "$ip" -o "$WAN_IF" -j MARK --set-xmark "$mark_up/0xffff"

  iptables -t mangle -C ZASH_DOWN -d "$ip" -o "$LAN_IF" -j MARK --set-xmark "$mark_down/0xffff" >/dev/null 2>&1 || \
    iptables -t mangle -A ZASH_DOWN -d "$ip" -o "$LAN_IF" -j MARK --set-xmark "$mark_down/0xffff"

  # WAN class/filter
  tc class show dev "$WAN_IF" 2>/dev/null | grep -q "1:${minor}" && \
    tc class change dev "$WAN_IF" parent 1: classid "1:${minor}" htb rate "${up}mbit" ceil "${up}mbit" 2>/dev/null || \
    tc class add dev "$WAN_IF" parent 1: classid "1:${minor}" htb rate "${up}mbit" ceil "${up}mbit" 2>/dev/null || true

  tc filter show dev "$WAN_IF" parent 1: 2>/dev/null | grep -q "handle $mark_up" || \
    tc filter add dev "$WAN_IF" parent 1: protocol ip prio 1 handle "$mark_up" fw flowid "1:${minor}" 2>/dev/null || true

  # LAN class/filter
  tc class show dev "$LAN_IF" 2>/dev/null | grep -q "2:${minor}" && \
    tc class change dev "$LAN_IF" parent 2: classid "2:${minor}" htb rate "${down}mbit" ceil "${down}mbit" 2>/dev/null || \
    tc class add dev "$LAN_IF" parent 2: classid "2:${minor}" htb rate "${down}mbit" ceil "${down}mbit" 2>/dev/null || true

  tc filter show dev "$LAN_IF" parent 2: 2>/dev/null | grep -q "handle $mark_down" || \
    tc filter add dev "$LAN_IF" parent 2: protocol ip prio 1 handle "$mark_down" fw flowid "2:${minor}" 2>/dev/null || true

  return 0
}

shape_ip() {
  ip="$1"; up="$2"; down="$3"
  if [ $have_tc -ne 1 ]; then
    reply_ok '{"ok":false,"error":"no-tc"}'
    return
  fi

  apply_tc_only "$ip" "$up" "$down" || { reply_ok '{"ok":false,"error":"apply-failed"}'; return; }

  # Persist state
  mkdir -p "$(dirname "$STATE_FILE")" >/dev/null 2>&1 || true
  tmp="${STATE_FILE}.tmp"
  [ -f "$STATE_FILE" ] && grep -v "^${ip} " "$STATE_FILE" > "$tmp" 2>/dev/null || true
  echo "${ip} ${up} ${down}" >> "$tmp"
  mv "$tmp" "$STATE_FILE" 2>/dev/null || true

  reply_ok '{"ok":true}'
}

unshape_ip() {
  ip="$1"
  minor="$(minor_for_ip "$ip")"
  mark_up="$minor"
  mark_down=$((16384 + minor))

  # Remove iptables marks
  iptables -t mangle -D ZASH_UP -s "$ip" -o "$WAN_IF" -j MARK --set-xmark "$mark_up/0xffff" >/dev/null 2>&1 || true
  iptables -t mangle -D ZASH_DOWN -d "$ip" -o "$LAN_IF" -j MARK --set-xmark "$mark_down/0xffff" >/dev/null 2>&1 || true

  if [ $have_tc -eq 1 ]; then
    # Remove tc filters/classes (best effort)
    tc filter del dev "$WAN_IF" parent 1: protocol ip prio 1 handle "$mark_up" fw 2>/dev/null || true
    tc class del dev "$WAN_IF" classid "1:${minor}" 2>/dev/null || true
    tc filter del dev "$LAN_IF" parent 2: protocol ip prio 1 handle "$mark_down" fw 2>/dev/null || true
    tc class del dev "$LAN_IF" classid "2:${minor}" 2>/dev/null || true
  fi

  # Persist state
  if [ -f "$STATE_FILE" ]; then
    tmp="${STATE_FILE}.tmp"
    grep -v "^${ip} " "$STATE_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$STATE_FILE" 2>/dev/null || true
  fi

  reply_ok '{"ok":true}'
}

rehydrate() {
  if [ $have_tc -ne 1 ]; then
    reply_ok '{"ok":false,"error":"no-tc"}'
    return
  fi
  if [ ! -f "$STATE_FILE" ]; then
    rehydrate_blocks >/dev/null 2>&1 || true
    reply_ok '{"ok":true,"count":0}'
    return
  fi
  count=0
  while read -r ip up down; do
    [ -n "$ip" ] || continue
    [ -n "$up" ] || continue
    [ -n "$down" ] || down="$up"
    apply_tc_only "$ip" "$up" "$down" && count=$((count + 1))
  done < "$STATE_FILE"
  rehydrate_blocks >/dev/null 2>&1 || true
  reply_ok "$(printf '{"ok":true,"count":%s}' "$count")"
}

status() {
  have_iptables=0
  command -v iptables >/dev/null 2>&1 && have_iptables=1

  # detect hashlimit support
  have_hashlimit=0
  iptables -m hashlimit -h >/dev/null 2>&1 && have_hashlimit=1

  # --- System metrics (best effort) ---
  cpu_pct=0
  if [ -r /proc/stat ]; then
    read _ u1 n1 s1 i1 w1 irq1 sirq1 stl1 rest < /proc/stat
    t1=$((u1+n1+s1+i1+w1+irq1+sirq1+stl1))
    id1=$((i1+w1))
    # Some router builds have a sleep that doesn't support fractional seconds.
    # Prefer usleep if present, otherwise fall back to integer sleep.
    if command -v usleep >/dev/null 2>&1; then
      usleep 200000 2>/dev/null || true
    else
      sleep 0.2 2>/dev/null || sleep 1 2>/dev/null || true
    fi
    read _ u2 n2 s2 i2 w2 irq2 sirq2 stl2 rest < /proc/stat
    t2=$((u2+n2+s2+i2+w2+irq2+sirq2+stl2))
    id2=$((i2+w2))
    dt=$((t2-t1))
    did=$((id2-id1))
    if [ "$dt" -gt 0 ]; then
      cpu_pct=$(( (100*(dt-did))/dt ))
    fi
  fi
  [ "$cpu_pct" -lt 0 ] && cpu_pct=0
  [ "$cpu_pct" -gt 100 ] && cpu_pct=100

  load1="0"
  [ -r /proc/loadavg ] && load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
  [ -n "$load1" ] || load1="0"

  uptime_sec=0
  [ -r /proc/uptime ] && uptime_sec="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
  echo "$uptime_sec" | grep -qE '^[0-9]+$' || uptime_sec=0

  mem_total_kb=0
  mem_avail_kb=0
  if [ -r /proc/meminfo ]; then
    mem_total_kb="$(awk '/MemTotal:/{print $2; exit}' /proc/meminfo 2>/dev/null)"
    mem_avail_kb="$(awk '/MemAvailable:/{print $2; exit}' /proc/meminfo 2>/dev/null)"
    [ -n "$mem_avail_kb" ] || mem_avail_kb="$(awk '/MemFree:/{print $2; exit}' /proc/meminfo 2>/dev/null)"
  fi
  echo "$mem_total_kb" | grep -qE '^[0-9]+$' || mem_total_kb=0
  echo "$mem_avail_kb" | grep -qE '^[0-9]+$' || mem_avail_kb=0

  mem_used_kb=$((mem_total_kb-mem_avail_kb))
  [ "$mem_used_kb" -lt 0 ] && mem_used_kb=0
  mem_used_pct=0
  if [ "$mem_total_kb" -gt 0 ]; then
    mem_used_pct=$(( (100*mem_used_kb)/mem_total_kb ))
  fi
  mem_total_b=$((mem_total_kb*1024))
  mem_used_b=$((mem_used_kb*1024))

  server_ver="$(remote_agent_version 2>/dev/null || true)"

  reply_ok "$(printf '{"ok":true,"version":"0.5.43","serverVersion":"%s","wan":"%s","lan":"%s","tc":%s,"iptables":%s,"hashlimit":%s,"usersDb":true,"cpuPct":%s,"load1":"%s","uptimeSec":%s,"memTotal":%s,"memUsed":%s,"memUsedPct":%s}' \
    "$server_ver" "$WAN_IF" "$LAN_IF" \
    $( [ $have_tc -eq 1 ] && echo true || echo false ) \
    $( [ $have_iptables -eq 1 ] && echo true || echo false ) \
    $( [ $have_hashlimit -eq 1 ] && echo true || echo false ) \
    "$cpu_pct" "$load1" "$uptime_sec" "$mem_total_b" "$mem_used_b" "$mem_used_pct")"
}

agent_log() {
  # Best-effort command log for troubleshooting.
  # Stored locally on router, can be viewed via cmd=logs&type=agent.
  mkdir -p /opt/zash-agent/var >/dev/null 2>&1 || true
  printf '%s cmd=%s ip=%s mac=%s ports=%s type=%s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'date')" "$cmd" "$ip" "$mac" "$ports" "$type" >> /opt/zash-agent/var/agent.log 2>/dev/null || true
}

find_mihomo_log() {
  # Try to discover Mihomo/Clash log file.
  # Priority: explicit MIHOMO_LOG env -> config log-file -> common paths.
  if [ -n "$MIHOMO_LOG" ] && [ -f "$MIHOMO_LOG" ]; then
    echo "$MIHOMO_LOG"
    return 0
  fi

  cfg="$MIHOMO_CONFIG"
  if [ -f "$cfg" ]; then
    lf="$(awk -F: 'BEGIN{IGNORECASE=1} $1 ~ /^[[:space:]]*log[-_]?file[[:space:]]*$/ {sub(/^[[:space:]]+/,"",$2); sub(/[[:space:]]+$/,"",$2); gsub(/^"|"$/,"",$2); gsub(/^\x27|\x27$/,"",$2); print $2; exit}' "$cfg" 2>/dev/null)"
    if [ -n "$lf" ] && [ -f "$lf" ]; then
      echo "$lf"
      return 0
    fi
  fi

  for p in \
    /opt/var/log/mihomo.log \
    /opt/var/log/mihomo/mihomo.log \
    /opt/var/log/clash.log \
    /opt/var/log/clash/clash.log \
    /opt/etc/mihomo/mihomo.log \
    /opt/etc/mihomo/clash.log \
    /tmp/mihomo.log \
    /tmp/clash.log \
    /tmp/syslog.log \
    /var/log/mihomo.log \
    /var/log/clash.log \
    /var/log/messages \
    /var/log/syslog
  do
    [ -f "$p" ] && { echo "$p"; return 0; }
  done

  echo ""
  return 0
}

config_b64() {
  # Return Mihomo YAML config (best-effort).
  path="$MIHOMO_CONFIG"
  txt=""
  if [ -f "$path" ]; then
    txt="$(cat "$path" 2>/dev/null)"
  fi
  txt="$(printf '%s' "$txt" | tail -c 204800 2>/dev/null || printf '%s' "$txt")"
  b64="$(printf '%s' "$txt" | b64enc)"
  esc_path="$(printf '%s' "$path" | sed 's/"/\\\"/g')"
  reply_ok "$(printf '{"ok":true,"kind":"config","path":"%s","contentB64":"%s"}' "$esc_path" "$b64")"
}

tail_b64() {
  kind="$1"
  n="$2"
  echo "$n" | grep -qE '^[0-9]+$' || n=200
  [ "$n" -gt 2000 ] && n=2000

  path=""
  txt=""

  if [ "$kind" = "agent" ]; then
    path="/opt/zash-agent/var/agent.log"
    [ -f "$path" ] && txt="$(tail -n "$n" "$path" 2>/dev/null)"
  else
    path="$(find_mihomo_log)"
    if [ -n "$path" ] && [ -f "$path" ]; then
      txt="$(tail -n "$n" "$path" 2>/dev/null)"
    elif command -v logread >/dev/null 2>&1; then
      txt="$(logread 2>/dev/null | tail -n "$n" 2>/dev/null)"
      path="logread"
    fi
  fi

  if [ "$kind" != "agent" ] && [ -z "$path" ] && [ -z "$txt" ]; then
    txt="No Mihomo log found. Set 'log-file:' in $MIHOMO_CONFIG, or set MIHOMO_LOG in /opt/zash-agent/agent.env. You can also view the config via cmd=logs&type=config."
    path="$MIHOMO_CONFIG"
  fi

  # cap to ~200KB
  txt="$(printf '%s' "$txt" | tail -c 204800 2>/dev/null || printf '%s' "$txt")"
  b64="$(printf '%s' "$txt" | b64enc)"
  esc_path="$(printf '%s' "$path" | sed 's/"/\\"/g')"
  reply_ok "$(printf '{"ok":true,"kind":"%s","path":"%s","contentB64":"%s"}' "$kind" "$esc_path" "$b64")"
tail_follow_b64() {
  kind="$1"
  n="$2"
  off="$3"
  echo "$n" | grep -qE '^[0-9]+$' || n=200
  [ "$n" -gt 2000 ] && n=2000
  echo "$off" | grep -qE '^[0-9]+$' || off=0

  path=""
  txt=""
  mode="delta"
  truncated=false

  if [ "$kind" = "agent" ]; then
    path="/opt/zash-agent/var/agent.log"
  else
    path="$(find_mihomo_log)"
    if [ -z "$path" ] || [ ! -f "$path" ]; then
      if command -v logread >/dev/null 2>&1; then
        # logread cannot be tailed incrementally reliably; fall back to full snapshot
        txt="$(logread 2>/dev/null | tail -n "$n" 2>/dev/null)"
        path="logread"
        mode="full"
        off=0
      else
        path=""
      fi
    fi
  fi

  if [ -n "$path" ] && [ -f "$path" ]; then
    sz="$(wc -c < "$path" 2>/dev/null | tr -d ' ')"
    echo "$sz" | grep -qE '^[0-9]+$' || sz=0

    if [ "$off" -le 0 ] || [ "$off" -gt "$sz" ]; then
      txt="$(tail -n "$n" "$path" 2>/dev/null)"
      mode="full"
    else
      delta=$((sz-off))
      # cap per response
      if [ "$delta" -gt 204800 ]; then
        delta=204800
        truncated=true
      fi
      [ "$delta" -gt 0 ] && txt="$(tail -c "$delta" "$path" 2>/dev/null)" || txt=""
      mode="delta"
    fi
    off="$sz"
  fi

  if [ "$kind" != "agent" ] && [ -z "$path" ] && [ -z "$txt" ]; then
    txt="No Mihomo log found. Set 'log-file:' in $MIHOMO_CONFIG, or set MIHOMO_LOG in /opt/zash-agent/agent.env. You can also view the config via cmd=logs&type=config."
    path="$MIHOMO_CONFIG"
    mode="full"
    off=0
  fi

  # cap to ~200KB
  txt="$(printf '%s' "$txt" | tail -c 204800 2>/dev/null || printf '%s' "$txt")"
  b64="$(printf '%s' "$txt" | b64enc)"
  esc_path="$(printf '%s' "$path" | sed 's/"/\\"/g')"
  reply_ok "$(printf '{"ok":true,"kind":"%s","path":"%s","contentB64":"%s","offset":%s,"mode":"%s","truncated":%s}' "$kind" "$esc_path" "$b64" "$off" "$mode" "$truncated")"
}


}


rclone_configured_remotes() {
  src="$RCLONE_REMOTES"
  if [ -z "$src" ]; then
    src="$RCLONE_REMOTE"
  fi
  # BusyBox tr does not reliably interpret '\n' in all builds, so split with sed.
  printf '%s' "$src" \
    | sed 's/[;,[:space:]]\+/\n/g' \
    | sed 's/:$//; s/^ *//; s/ *$//' \
    | awk 'NF && !seen[$0]++ {print $0}'
}

rclone_list_remotes() {
  if ! command -v rclone >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$RCLONE_CONFIG" ]; then
    rclone listremotes --config "$RCLONE_CONFIG" 2>/dev/null || true
  else
    rclone listremotes 2>/dev/null || true
  fi
}

rclone_known_remotes() {
  cfg_path="$1"
  known="$(rclone_list_remotes)"
  if [ -n "$known" ]; then
    printf '%s\n' "$known"
    return 0
  fi
  [ -n "$cfg_path" ] || cfg_path="$RCLONE_CONFIG"
  if [ -n "$cfg_path" ] && [ -f "$cfg_path" ]; then
    awk '
      /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
        name=$0
        sub(/^[[:space:]]*\[/, "", name)
        sub(/\][[:space:]]*$/, "", name)
        if (name != "") print name ":"
      }
    ' "$cfg_path" | awk '!seen[$0]++'
  fi
}

rclone_json_bool() {
  [ "$1" = "true" ] && printf true || printf false
}

rclone_remote_accessible() {
  remote="$1"
  test_path="$2"
  [ -n "$remote" ] || return 1
  if ! command -v rclone >/dev/null 2>&1; then
    return 1
  fi
  rcfg=""
  if [ -n "$RCLONE_CONFIG" ]; then
    rcfg="--config $RCLONE_CONFIG"
  fi
  root_target="$remote:"
  # shellcheck disable=SC2086
  if RCLONE_CONFIG="$RCLONE_CONFIG" rclone lsf "$root_target" --max-depth 1 >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$test_path" ]; then
    path_target="$remote:$test_path"
    # shellcheck disable=SC2086
    if RCLONE_CONFIG="$RCLONE_CONFIG" rclone lsf "$path_target" --max-depth 1 >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

rclone_find_file_remote() {
  name="$1"
  path="$2"
  req_remote="$3"
  [ -n "$name" ] || return 1
  rems=""
  if [ -n "$req_remote" ]; then
    rems="$req_remote"
  else
    rems="$(rclone_configured_remotes)"
  fi
  [ -n "$rems" ] || return 1
  oldIFS="$IFS"
  IFS=$(printf '\n_'); IFS=${IFS%_}
  for remote in $rems; do
    [ -n "$remote" ] || continue
    src="$remote:$name"
    [ -n "$path" ] && src="$remote:$path/$name"
    rcfg=""
    if [ -n "$RCLONE_CONFIG" ]; then
      rcfg="--config $RCLONE_CONFIG"
    fi
    # shellcheck disable=SC2086
    if RCLONE_CONFIG="$RCLONE_CONFIG" rclone lsf "$src" --max-depth 1 >/dev/null 2>&1; then
      printf '%s' "$remote"
      IFS="$oldIFS"
      return 0
    fi
  done
  IFS="$oldIFS"
  return 1
}

rclone_latest_remote_name() {
  path="$1"
  req_remote="$2"
  rems=""
  if [ -n "$req_remote" ]; then
    rems="$req_remote"
  else
    rems="$(rclone_configured_remotes)"
  fi
  [ -n "$rems" ] || return 1
  rcfg=""
  if [ -n "$RCLONE_CONFIG" ]; then
    rcfg="--config $RCLONE_CONFIG"
  fi
  best_remote=""
  best_name=""
  best_key=""
  oldIFS="$IFS"
  IFS=$(printf '\n_'); IFS=${IFS%_}
  for remote in $rems; do
    [ -n "$remote" ] || continue
    remote_dir="$remote:"
    [ -n "$path" ] && remote_dir="$remote:$path"
    # shellcheck disable=SC2086
    line="$(RCLONE_CONFIG="$RCLONE_CONFIG" rclone lsl "$remote_dir" --include 'zash-backup-*.tar.gz' 2>/dev/null | sort -k2,3 | tail -n1)"
    [ -n "$line" ] || continue
    name="$(printf '%s' "$line" | awk '{print $4}')"
    key="$(printf '%s' "$line" | awk '{print $2" "$3}')"
    [ -n "$name" ] || continue
    if [ -z "$best_key" ] || [ "$key" \> "$best_key" ]; then
      best_key="$key"
      best_name="$name"
      best_remote="$remote"
    fi
  done
  IFS="$oldIFS"
  [ -n "$best_name" ] || return 1
  printf '%s	%s' "$best_remote" "$best_name"
}

backup_cloud_status_json() {
  path="$(normalize_rclone_path "$RCLONE_PATH")"
  cfg="$RCLONE_CONFIG"
  if [ -z "$cfg" ] && command -v rclone >/dev/null 2>&1; then
    cfg="$(rclone config file 2>/dev/null | awk 'NR==2{print $0}' | tail -n1)"
  fi

  rclone_installed=false
  cloud_ready=false
  remotes_json='[]'
  primary_remote=""
  primary_exists=false
  remote_names="$(rclone_configured_remotes)"

  if command -v rclone >/dev/null 2>&1; then
    rclone_installed=true
    known="$(rclone_known_remotes "$cfg")"
    items=""
    oldIFS="$IFS"
    IFS='
'
    for remote in $remote_names; do
      [ -n "$remote" ] || continue
      [ -z "$primary_remote" ] && primary_remote="$remote"
      exists=false
      if printf '%s\n' "$known" | grep -Fxq "$remote:"; then
        exists=true
      elif rclone_remote_accessible "$remote" "$path"; then
        exists=true
      fi
      if [ "$exists" = true ]; then
        cloud_ready=true
      fi
      [ "$remote" = "$primary_remote" ] && primary_exists="$exists"
      [ -n "$items" ] && items="$items,"
      items="$items$(printf '{"name":"%s","exists":%s}' "$(jesc "$remote")" "$(rclone_json_bool "$exists")")"
    done
    IFS="$oldIFS"
    remotes_json="[$items]"
  fi

  [ -n "$primary_remote" ] || primary_remote="$RCLONE_REMOTE"

  reply_ok "$(printf '{"ok":true,"rcloneInstalled":%s,"configPath":"%s","remote":"%s","remoteExists":%s,"path":"%s","cloudReady":%s,"keepDays":"%s","localKeepDays":"%s","uiZipEnabled":%s,"remotes":%s}'     "$rclone_installed" "$(jesc "$cfg")" "$(jesc "$primary_remote")" "$(rclone_json_bool "$primary_exists")" "$(jesc "$path")" "$(rclone_json_bool "$cloud_ready")" "$(jesc "$RCLONE_KEEP_DAYS")" "$(jesc "$BACKUP_KEEP_DAYS")" "$( [ -n "$UI_ZIP_URL" ] && echo true || echo false )" "$remotes_json")"
}


backup_cloud_list_json() {
  path="$(normalize_rclone_path "$RCLONE_PATH")"

  if ! command -v rclone >/dev/null 2>&1; then
    reply_ok '{"ok":true,"remote":"","path":"","dir":"","items":[]}'
    return
  fi

  remotes="$(rclone_configured_remotes)"
  if [ -z "$remotes" ]; then
    reply_ok "$(printf '{"ok":true,"remote":"%s","path":"%s","dir":"","items":[]}' "$(jesc "$RCLONE_REMOTE")" "$(jesc "$path")")"
    return
  fi

  rcfg=""
  if [ -n "$RCLONE_CONFIG" ]; then
    rcfg="--config $RCLONE_CONFIG"
  fi

  items=""
  first=1
  oldIFS="$IFS"
  IFS='
'
  for remote in $remotes; do
    [ -n "$remote" ] || continue
    dst="$remote:"
    [ -n "$path" ] && dst="$remote:$path"
    # shellcheck disable=SC2086
    json="$(RCLONE_CONFIG="$RCLONE_CONFIG" rclone lsjson "$dst" --files-only --max-depth 1 2>/dev/null || printf '[]')"
    [ -n "$json" ] || json='[]'
    tmp_json="/tmp/zash-cloud-list.$$"
    printf '%s\n' "$json" | sed 's/},{/}\n{/g' > "$tmp_json"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      [ "$line" = '[' ] && continue
      [ "$line" = ']' ] && continue
      line="$(printf '%s' "$line" | sed 's/^ *,*//; s/, *$//')"
      [ -n "$line" ] || continue
      item="$(printf '%s' "$line" | sed 's/^{//; s/}$//')"
      [ -n "$item" ] || continue
      [ $first -eq 1 ] || items="$items,"
      first=0
      items="$items$(printf '{"Remote":"%s","RemotePath":"%s",%s}' "$(jesc "$remote")" "$(jesc "$path")" "$item")"
    done < "$tmp_json"
    rm -f "$tmp_json" >/dev/null 2>&1 || true
  done
  IFS="$oldIFS"

  reply_ok "$(printf '{"ok":true,"remote":"%s","path":"%s","dir":"%s","items":[%s]}' "$(jesc "$RCLONE_REMOTE")" "$(jesc "$path")" "$(jesc "$path")" "$items")"
}

backup_status_json() {
  sf="/opt/zash-agent/var/backup.last.json"
  if [ -f "$sf" ]; then
    payload="$(cat "$sf" 2>/dev/null | tail -c 8192 2>/dev/null)"
    [ -n "$payload" ] || payload='{"ok":true,"running":false}'
    reply_ok "$payload"
  else
    reply_ok '{"ok":true,"running":false}'
  fi
}

backup_start_json() {
  mkdir -p /opt/zash-agent/var >/dev/null 2>&1 || true
  sf="/opt/zash-agent/var/backup.last.json"
  started="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"
  req_remotes="${remotes_q:-}"
  esc_started="$(jesc "$started")"
  esc_req_remotes="$(jesc "$req_remotes")"
  if [ -n "$req_remotes" ]; then
    printf '{"ok":true,"running":true,"startedAt":"%s","requestedRemotes":"%s"}' "$esc_started" "$esc_req_remotes" > "$sf" 2>/dev/null || true
  else
    printf '{"ok":true,"running":true,"startedAt":"%s"}' "$esc_started" > "$sf" 2>/dev/null || true
  fi
  # Run in background so CGI returns immediately.
  ( /opt/zash-agent/backup.sh "$req_remotes" > /opt/zash-agent/var/backup.last.log 2>&1 & ) >/dev/null 2>&1 || true
  if [ -n "$req_remotes" ]; then
    reply_ok "$(printf '{"ok":true,"running":true,"requestedRemotes":"%s"}' "$(jesc "$req_remotes")")"
  else
    reply_ok '{"ok":true,"running":true}'
  fi
}

backup_log_json() {
  lf="/opt/zash-agent/var/backup.last.log"
  n="$lines"
  echo "$n" | grep -qE '^[0-9]+$' || n=200
  [ "$n" -gt 2000 ] && n=2000
  txt=""
  [ -f "$lf" ] && txt="$(tail -n "$n" "$lf" 2>/dev/null)"
  txt="$(printf '%s' "$txt" | tail -c 204800 2>/dev/null || printf '%s' "$txt")"
  b64="$(printf '%s' "$txt" | b64enc)"
  esc_path="$(printf '%s' "$lf" | sed 's/"/\\"/g')"
  reply_ok "$(printf '{"ok":true,"path":"%s","contentB64":"%s"}' "$esc_path" "$b64")"
}

backup_list_json() {
  dir="$BACKUP_TMP_DIR"
  [ -n "$dir" ] || dir="/opt/zash-agent/var/backups"
  mkdir -p "$dir" >/dev/null 2>&1 || true

  items=""
  first=1
  # List up to 50 most recent backups (best-effort).
  for f in $(ls -1t "$dir"/zash-backup-*.tar.gz 2>/dev/null | head -n 50); do
    [ -f "$f" ] || continue
    name="$(basename "$f" 2>/dev/null || echo "$f")"
    size="$(wc -c < "$f" 2>/dev/null || echo 0)"
    mtime="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
    esc_name="$(printf '%s' "$name" | sed 's/"/\\\\"/g')"
    [ -n "$items" ] && items="$items,"
    items="$items$(printf '{"name":"%s","size":%s,"mtime":%s}' "$esc_name" "$size" "$mtime")"
  done

  esc_dir="$(printf '%s' "$dir" | sed 's/"/\\\\"/g')"
  reply_ok "$(printf '{"ok":true,"dir":"%s","items":[%s]}' "$esc_dir" "$items")"
}

backup_delete_json() {
  dir="$BACKUP_TMP_DIR"
  [ -n "$dir" ] || dir="/opt/zash-agent/var/backups"
  mkdir -p "$dir" >/dev/null 2>&1 || true

  req="${file_q:-}"
  name="$(basename "$req" 2>/dev/null || printf '%s' "$req")"
  case "$name" in
    zash-backup-*.tar.gz|ui-dist-*.zip) ;;
    *)
      reply_err 'invalid backup file'
      return
      ;;
  esac

  target="$dir/$name"
  if [ ! -f "$target" ]; then
    reply_ok "$(printf '{"ok":true,"deleted":false,"name":"%s"}' "$(jesc "$name")")"
    return
  fi

  rm -f "$target" >/dev/null 2>&1 || {
    reply_err 'delete failed'
    return
  }

  reply_ok "$(printf '{"ok":true,"deleted":true,"name":"%s"}' "$(jesc "$name")")"
}

backup_cloud_delete_json() {
  path="$(normalize_rclone_path "$RCLONE_PATH")"
  req_remote="${remote_q:-}"
  req="${file_q:-}"
  name="$(basename "$req" 2>/dev/null || printf '%s' "$req")"
  case "$name" in
    zash-backup-*.tar.gz|ui-dist-*.zip) ;;
    *)
      reply_err 'invalid backup file'
      return
      ;;
  esac

  if ! command -v rclone >/dev/null 2>&1; then
    reply_err 'rclone is not installed'
    return
  fi

  remotes=""
  if [ -n "$req_remote" ]; then
    remotes="$req_remote"
  else
    remotes="$(rclone_configured_remotes)"
  fi
  if [ -z "$remotes" ]; then
    reply_err 'cloud backup is not configured'
    return
  fi

  rcfg=""
  if [ -n "$RCLONE_CONFIG" ]; then
    rcfg="--config $RCLONE_CONFIG"
  fi

  deleted=false
  oldIFS="$IFS"
  IFS='
'
  for remote in $remotes; do
    [ -n "$remote" ] || continue
    dst="$remote:$name"
    [ -n "$path" ] && dst="$remote:$path/$name"
    # shellcheck disable=SC2086
    if RCLONE_CONFIG="$RCLONE_CONFIG" rclone deletefile "$dst" >/dev/null 2>&1; then
      deleted=true
      [ -n "$req_remote" ] && break
    fi
  done
  IFS="$oldIFS"

  if [ "$deleted" != true ]; then
    reply_err 'cloud delete failed'
    return
  fi

  reply_ok "$(printf '{"ok":true,"deleted":true,"name":"%s","remote":"%s"}' "$(jesc "$name")" "$(jesc "$req_remote")")"
}

backup_cloud_download_json() {
  path="$(normalize_rclone_path "$RCLONE_PATH")"
  req_remote="${remote_q:-}"
  req="${file_q:-}"
  name="$(basename "$req" 2>/dev/null || printf '%s' "$req")"
  case "$name" in
    zash-backup-*.tar.gz|ui-dist-*.zip) ;;
    *)
      reply_err 'invalid backup file'
      return
      ;;
  esac

  if ! command -v rclone >/dev/null 2>&1; then
    reply_err 'rclone is not installed'
    return
  fi

  dir="$BACKUP_TMP_DIR"
  [ -n "$dir" ] || dir="/opt/zash-agent/var/backups"
  mkdir -p "$dir" >/dev/null 2>&1 || true

  local_file="$dir/$name"
  if [ -f "$local_file" ]; then
    size="$(wc -c < "$local_file" 2>/dev/null || echo 0)"
    mtime="$(stat -c %Y "$local_file" 2>/dev/null || stat -f %m "$local_file" 2>/dev/null || echo 0)"
    reply_ok "$(printf '{"ok":true,"downloaded":true,"existed":true,"name":"%s","path":"%s","size":%s,"mtime":%s,"remote":"%s"}' "$(jesc "$name")" "$(jesc "$local_file")" "$size" "$mtime" "$(jesc "$req_remote")")"
    return
  fi

  remote="$(rclone_find_file_remote "$name" "$path" "$req_remote")"
  if [ -z "$remote" ]; then
    reply_err 'cloud backup is not configured'
    return
  fi

  src="$remote:$name"
  [ -n "$path" ] && src="$remote:$path/$name"

  rcfg=""
  if [ -n "$RCLONE_CONFIG" ]; then
    rcfg="--config $RCLONE_CONFIG"
  fi

  # shellcheck disable=SC2086
  if ! RCLONE_CONFIG="$RCLONE_CONFIG" rclone copyto "$src" "$local_file" >/dev/null 2>&1; then
    rm -f "$local_file" >/dev/null 2>&1 || true
    reply_err 'cloud download failed'
    return
  fi

  size="$(wc -c < "$local_file" 2>/dev/null || echo 0)"
  mtime="$(stat -c %Y "$local_file" 2>/dev/null || stat -f %m "$local_file" 2>/dev/null || echo 0)"
  reply_ok "$(printf '{"ok":true,"downloaded":true,"existed":false,"name":"%s","path":"%s","size":%s,"mtime":%s,"remote":"%s"}' "$(jesc "$name")" "$(jesc "$local_file")" "$size" "$mtime" "$(jesc "$remote")")"
}

restore_status_json() {
  sf="/opt/zash-agent/var/restore.last.json"
  if [ -f "$sf" ]; then
    payload="$(cat "$sf" 2>/dev/null | tail -c 8192 2>/dev/null)"
    [ -n "$payload" ] || payload='{"ok":true,"running":false}'
    reply_ok "$payload"
  else
    reply_ok '{"ok":true,"running":false}'
  fi
}

restore_start_json() {
  mkdir -p /opt/zash-agent/var >/dev/null 2>&1 || true
  sf="/opt/zash-agent/var/restore.last.json"
  started="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"
  esc_started="$(jesc "$started")"

  f="${file_q:-}"
  scope="${scope_q:-all}"
  env="${env_q:-0}"
  source="${source_q:-local}"
  remote="${remote_q:-}"
  runner="/opt/zash-agent/restore.sh"
  case "$source" in
    cloud) runner="/opt/zash-agent/restore-cloud.sh" ;;
    *) source="local" ;;
  esac

  printf '{"ok":true,"running":true,"startedAt":"%s","source":"%s","stage":"queued","progressPct":0}' "$esc_started" "$source" > "$sf" 2>/dev/null || true

  # Run in background so CGI returns immediately.
  if [ "$source" = "cloud" ]; then
    ( "$runner" "$f" "$scope" "$env" "$remote" > /opt/zash-agent/var/restore.last.log 2>&1 & ) >/dev/null 2>&1 || true
  else
    ( "$runner" "$f" "$scope" "$env" > /opt/zash-agent/var/restore.last.log 2>&1 & ) >/dev/null 2>&1 || true
  fi
  reply_ok '{"ok":true,"running":true}'
}

restore_log_json() {
  lf="/opt/zash-agent/var/restore.last.log"
  n="$lines"
  echo "$n" | grep -qE '^[0-9]+$' || n=200
  [ "$n" -gt 2000 ] && n=2000
  txt=""
  [ -f "$lf" ] && txt="$(tail -n "$n" "$lf" 2>/dev/null)"
  txt="$(printf '%s' "$txt" | tail -c 204800 2>/dev/null || printf '%s' "$txt")"
  b64="$(printf '%s' "$txt" | b64enc)"
  esc_path="$(printf '%s' "$lf" | sed 's/"/\\\\"/g')"
  reply_ok "$(printf '{"ok":true,"path":"%s","contentB64":"%s"}' "$esc_path" "$b64")"
}


cron_tab_path() {
  if [ -f /opt/etc/crontabs/root ] || [ -d /opt/etc/crontabs ]; then
    echo "/opt/etc/crontabs/root"
    return 0
  fi
  if [ -f /opt/var/spool/cron/crontabs/root ] || [ -d /opt/var/spool/cron/crontabs ]; then
    echo "/opt/var/spool/cron/crontabs/root"
    return 0
  fi
  if [ -f /etc/crontabs/root ] || [ -d /etc/crontabs ]; then
    echo "/etc/crontabs/root"
    return 0
  fi
  if [ -f /var/spool/cron/crontabs/root ] || [ -d /var/spool/cron/crontabs ]; then
    echo "/var/spool/cron/crontabs/root"
    return 0
  fi
  echo ""
  return 0
}

cron_reload_best_effort() {
  if command -v crontab >/dev/null 2>&1; then
    crontab "$tab" >/dev/null 2>&1 || true
  fi

  for init in /opt/etc/init.d/S10cron /opt/etc/init.d/S10crond /etc/init.d/cron /etc/init.d/crond; do
    [ -x "$init" ] || continue
    "$init" restart >/dev/null 2>&1 || "$init" start >/dev/null 2>&1 || true
    return 0
  done

  if command -v service >/dev/null 2>&1; then
    service cron restart >/dev/null 2>&1 || service crond restart >/dev/null 2>&1 || true
  fi

  if command -v pidof >/dev/null 2>&1; then
    pid="$(pidof crond 2>/dev/null | awk '{print $1}')"
    if [ -n "$pid" ]; then
      kill -HUP "$pid" >/dev/null 2>&1 || true
      return 0
    fi
  fi

  if command -v crond >/dev/null 2>&1; then
    crond >/dev/null 2>&1 || true
  fi
}

backup_cron_get_json() {
  tab="$(cron_tab_path)"
  if [ -z "$tab" ]; then
    reply_ok '{"ok":false,"error":"cron-not-found"}'
    return
  fi

  if [ ! -f "$tab" ]; then
    reply_ok "$(printf '{"ok":true,"enabled":false,"path":"%s"}' "$(jesc "$tab")")"
    return
  fi

  line="$(grep -E 'zash-backup' "$tab" 2>/dev/null | tail -n 1 2>/dev/null)"
  if [ -n "$line" ]; then
    sched="$(printf '%s' "$line" | awk '{print $1" "$2" "$3" "$4" "$5}' 2>/dev/null)"
    reply_ok "$(printf '{"ok":true,"enabled":true,"schedule":"%s","line":"%s","path":"%s"}' "$(jesc "$sched")" "$(jesc "$line")" "$(jesc "$tab")")"
  else
    reply_ok "$(printf '{"ok":true,"enabled":false,"path":"%s"}' "$(jesc "$tab")")"
  fi
}

backup_cron_set_json() {
  tab="$(cron_tab_path)"
  if [ -z "$tab" ]; then
    reply_ok '{"ok":false,"error":"cron-not-found"}'
    return
  fi

  mkdir -p "$(dirname "$tab")" >/dev/null 2>&1 || true
  mkdir -p /opt/zash-agent/var >/dev/null 2>&1 || true

  enabled="$enabled_q"
  case "$enabled" in
    1|true|yes|on) enabled=1 ;;
    *) enabled=0 ;;
  esac

  sched="$schedule_q"
  sched="$(printf '%s' "$sched" | tr -d '\r\n')"
  [ -n "$sched" ] || sched="0 4 * * *"

  # Basic validation: 5 fields with safe chars.
  echo "$sched" | grep -qE '^[0-9A-Za-z*/,-]+[[:space:]]+[0-9A-Za-z*/,-]+[[:space:]]+[0-9A-Za-z*/,-]+[[:space:]]+[0-9A-Za-z*/,-]+[[:space:]]+[0-9A-Za-z*/,-]+$' || {
    reply_ok '{"ok":false,"error":"bad-schedule"}'
    return
  }

  line="$sched /opt/zash-agent/backup.sh >/opt/zash-agent/var/backup.cron.log 2>&1 # zash-backup"

  tmp="${tab}.tmp.$$"
  if [ -f "$tab" ]; then
    grep -v 'zash-backup' "$tab" > "$tmp" 2>/dev/null || true
  else
    : > "$tmp" 2>/dev/null || true
  fi

  if [ "$enabled" -eq 1 ]; then
    printf '%s\n' "$line" >> "$tmp" 2>/dev/null || true
  fi

  mv -f "$tmp" "$tab" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null || true
    reply_ok '{"ok":false,"error":"write-failed"}'
    return
  }

  cron_reload_best_effort >/dev/null 2>&1 || true

  if [ "$enabled" -eq 1 ]; then
    reply_ok "$(printf '{"ok":true,"enabled":true,"schedule":"%s","path":"%s"}' "$(jesc "$sched")" "$(jesc "$tab")")"
  else
    reply_ok "$(printf '{"ok":true,"enabled":false,"schedule":"%s","path":"%s"}' "$(jesc "$sched")" "$(jesc "$tab")")"
  fi
}

# Save a lightweight trace of requests (best effort).
agent_log

case "$cmd" in
  status|"") status ;;
  neighbors) neighbors ;;
  lan_hosts) lan_hosts_json ;;
  ip2mac)
    [ -n "$ip" ] || { reply_ok '{"ok":false,"error":"missing-ip"}'; exit 0; }
    ip2mac "$ip"
    ;;
  shape)
    [ -n "$ip" ] || { reply_ok '{"ok":false,"error":"missing-ip"}'; exit 0; }
    [ -n "$up" ] || up="0"
    [ -n "$down" ] || down="$up"
    shape_ip "$ip" "$up" "$down"
    ;;
  unshape)
    [ -n "$ip" ] || { reply_ok '{"ok":false,"error":"missing-ip"}'; exit 0; }
    unshape_ip "$ip"
    ;;
  rehydrate)
    rehydrate
    ;;
  logs)
    [ -n "$type" ] || type="mihomo"
    [ -n "$lines" ] || lines="200"
    if [ "$type" = "agent" ]; then
      tail_b64 agent "$lines"
    elif [ "$type" = "config" ]; then
      config_b64
    else
      tail_b64 mihomo "$lines"
    fi
    ;;
  logs_follow)
    [ -n "$type" ] || type="mihomo"
    [ -n "$lines" ] || lines="200"
    [ -n "$offset" ] || offset="0"
    # Fallback for older/partial agent installs: if tail_follow_b64 is missing, return full tail.
    type tail_follow_b64 >/dev/null 2>&1 || {
      if [ "$type" = "agent" ]; then
        tail_b64 agent "$lines"
      elif [ "$type" = "config" ]; then
        config_b64
      else
        tail_b64 mihomo "$lines"
      fi
      exit 0
    }
    if [ "$type" = "agent" ]; then
      tail_follow_b64 agent "$lines" "$offset"
    elif [ "$type" = "config" ]; then
      config_b64
    else
      tail_follow_b64 mihomo "$lines" "$offset"
    fi
    ;;
  blockmac)
    block_mac_ports "$mac" "$ports"
    ;;
  unblockmac)
    unblock_mac_ports "$mac"
    ;;
  blockip)
    [ -n "$ip" ] || { reply_ok '{"ok":false,"error":"missing-ip"}'; exit 0; }
    block_ip "$ip"
    ;;
  unblockip)
    [ -n "$ip" ] || { reply_ok '{"ok":false,"error":"missing-ip"}'; exit 0; }
    unblock_ip "$ip"
    ;;
  mihomo_config)
    mihomo_config_json
    ;;
  mihomo_providers)
    mihomo_providers_json
    ;;
  ssl_probe_batch)
    ssl_probe_batch_json
    ;;
  geo_info)
    geo_info_json
    ;;
  geo_update)
    geo_update_json
    ;;
  rules_info)
    rules_info_json
    ;;
  users_db_get)
    users_db_get_json
    ;;
  users_db_put)
    users_db_put_json "$rev_q"
    ;;
  backup_start)
    backup_start_json
    ;;
  backup_status)
    backup_status_json
    ;;
  backup_cloud_status)
    backup_cloud_status_json
    ;;
  backup_cloud_list)
    backup_cloud_list_json
    ;;
  backup_log)
    backup_log_json
    ;;
  backup_list)
    backup_list_json
    ;;
  backup_delete)
    backup_delete_json
    ;;
  backup_cloud_delete)
    backup_cloud_delete_json
    ;;
  backup_cloud_download)
    backup_cloud_download_json
    ;;
  restore_start)
    restore_start_json
    ;;
  restore_status)
    restore_status_json
    ;;
  restore_log)
    restore_log_json
    ;;
  backup_cron_get)
    backup_cron_get_json
    ;;
  backup_cron_set)
    backup_cron_set_json
    ;;
  *) reply_ok '{"ok":false,"error":"unknown-cmd"}' ;;
esac

EOF

chmod +x "$AGENT_DIR/www/cgi-bin/api.sh"

cat > "$AGENT_DIR/backup.sh" <<'EOF'
#!/bin/sh
# Simple router backup helper (Mihomo config + zash-agent state) with optional cloud upload via rclone.
set -e

ENV_FILE="/opt/zash-agent/agent.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

BACKUP_TMP_DIR="${BACKUP_TMP_DIR:-/opt/zash-agent/var/backups}"
BACKUP_STATUS_FILE="${BACKUP_STATUS_FILE:-/opt/zash-agent/var/backup.last.json}"
BACKUP_LOG_FILE="${BACKUP_LOG_FILE:-/opt/zash-agent/var/backup.last.log}"
BACKUP_STATE_DIR="${BACKUP_STATE_DIR:-/opt/zash-agent/var}"

RCLONE_CONFIG="${RCLONE_CONFIG:-}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}"
RCLONE_REMOTES="${RCLONE_REMOTES:-}"
RCLONE_PATH="${RCLONE_PATH:-NetcrazeBackups/zash-agent}"
RCLONE_KEEP_DAYS="${RCLONE_KEEP_DAYS:-30}"
REQUESTED_REMOTES="${1:-}"

normalize_rclone_path() {
  p="$1"
  p="$(printf '%s' "$p" | sed 's#^/*##; s#//*#/#g; s#/$##')"
  printf '%s' "$p"
}

rclone_configured_remotes() {
  src="$RCLONE_REMOTES"
  if [ -z "$src" ]; then
    src="$RCLONE_REMOTE"
  fi
  printf '%s' "$src" \
    | sed 's/[;,[:space:]]\+/\n/g' \
    | sed 's/:$//; s/^ *//; s/ *$//' \
    | awk 'NF && !seen[$0]++ {print $0}'
}

RCLONE_PATH="$(normalize_rclone_path "$RCLONE_PATH")"

BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-${RCLONE_KEEP_DAYS:-30}}"

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

append_upload_result() {
  remote_name="$1"
  remote_ok="$2"
  remote_error="$3"
  item="$(printf '{\"remote\":\"%s\",\"ok\":%s' "$(json_escape "$remote_name")" "$remote_ok")"
  if [ -n "$remote_error" ]; then
    item="$item$(printf ' ,"error":"%s" ' "$(json_escape "$remote_error")")"
  fi
  item="$item}"
  if [ -n "$upload_results" ]; then
    upload_results="$upload_results,$item"
  else
    upload_results="$item"
  fi
  if [ "$remote_ok" = "true" ]; then
    upload_ok_count=$((upload_ok_count + 1))
  else
    upload_fail_count=$((upload_fail_count + 1))
  fi
}

# Mark as running
if [ -n "$REQUESTED_REMOTES" ]; then
  write_status "$(printf '{"ok":true,"running":true,"startedAt":"%s","requestedRemotes":"%s"}' "$(json_escape "$started_at")" "$(json_escape "$REQUESTED_REMOTES")")"
else
  write_status "$(printf '{"ok":true,"running":true,"startedAt":"%s"}' "$(json_escape "$started_at")")"
fi

success=0
uploaded=false
out=""
err=""
upload_results=""
upload_ok_count=0
upload_fail_count=0

finish() {
  code=$?
  trap - EXIT
  finished_at="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"
  if [ $code -ne 0 ] || [ $success -ne 1 ]; then
    e="${err:-exit $code}"
    write_status "$(printf '{"ok":true,"running":false,"startedAt":"%s","finishedAt":"%s","success":false,"error":"%s","uploadOkCount":%s,"uploadFailCount":%s,"uploadResults":[%s],"requestedRemotes":"%s"}' \
      "$(json_escape "$started_at")" "$(json_escape "$finished_at")" "$(json_escape "$e")" "$upload_ok_count" "$upload_fail_count" "$upload_results" "$(json_escape "$REQUESTED_REMOTES")")"
    exit $code
  fi

  write_status "$(printf '{"ok":true,"running":false,"startedAt":"%s","finishedAt":"%s","success":true,"file":"%s","uploaded":%s,"uploadOkCount":%s,"uploadFailCount":%s,"uploadResults":[%s],"requestedRemotes":"%s"}' \
    "$(json_escape "$started_at")" "$(json_escape "$finished_at")" "$(json_escape "$out")" "$uploaded" "$upload_ok_count" "$upload_fail_count" "$upload_results" "$(json_escape "$REQUESTED_REMOTES")")"
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

# local retention (best-effort)
if echo "$BACKUP_KEEP_DAYS" | grep -qE '^[0-9]+$' && [ "$BACKUP_KEEP_DAYS" -gt 0 ]; then
  find "$BACKUP_TMP_DIR" -maxdepth 1 -type f \( -name "zash-backup-*.tar.gz" -o -name "ui-dist-*.zip" \) -mtime +"$BACKUP_KEEP_DAYS" -print -delete 2>/dev/null || true
fi

rems_source="$REQUESTED_REMOTES"
if [ -z "$rems_source" ]; then
  rems_source="$RCLONE_REMOTES"
fi
if [ -z "$rems_source" ]; then
  rems_source="$RCLONE_REMOTE"
fi
rems="$(printf '%s' "$rems_source" | sed 's/[;,[:space:]]\+/\n/g' | sed 's/:$//; s/^ *//; s/ *$//' | awk 'NF && !seen[$0]++ {print $0}')"
if [ -n "$rems" ] && command -v rclone >/dev/null 2>&1; then
  rcfg=""
  if [ -n "$RCLONE_CONFIG" ]; then
    rcfg="--config $RCLONE_CONFIG"
  fi
  upload_ok=0
  oldIFS="$IFS"
  IFS=$(printf '\n_'); IFS=${IFS%_}
  for remote in $rems; do
    [ -n "$remote" ] || continue
    dst="$remote:"
    [ -n "$RCLONE_PATH" ] && dst="$remote:$RCLONE_PATH"
    echo "[backup] uploading to: $dst" | tee -a "$BACKUP_LOG_FILE" >/dev/null 2>&1 || true
    copy_log="$BACKUP_STATE_DIR/rclone-upload-${remote}.log"
    rm -f "$copy_log" 2>/dev/null || true
    set +e
    # shellcheck disable=SC2086
    RCLONE_CONFIG="$RCLONE_CONFIG" rclone mkdir "$dst" >/dev/null 2>&1
    # shellcheck disable=SC2086
    RCLONE_CONFIG="$RCLONE_CONFIG" rclone copy "$out" "$dst" --transfers 1 --checkers 1 --retries 2 > "$copy_log" 2>&1
    rc=$?
    set -e
    if [ $rc -eq 0 ]; then
      upload_ok=1
      append_upload_result "$remote" true ""
      echo "[backup] uploaded to: $dst" | tee -a "$BACKUP_LOG_FILE" >/dev/null 2>&1 || true
      if echo "$RCLONE_KEEP_DAYS" | grep -qE '^[0-9]+$' && [ "$RCLONE_KEEP_DAYS" -gt 0 ]; then
        set +e
        # shellcheck disable=SC2086
        RCLONE_CONFIG="$RCLONE_CONFIG" rclone delete "$dst" --min-age "${RCLONE_KEEP_DAYS}d" --include "zash-backup-*.tar.gz" >/dev/null 2>&1
        set -e
      fi
    else
      upload_err="$(tail -n 2 "$copy_log" 2>/dev/null | tr '
' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
      [ -n "$upload_err" ] || upload_err='upload failed'
      append_upload_result "$remote" false "$upload_err"
      echo "[backup] upload failed: $dst" | tee -a "$BACKUP_LOG_FILE" >/dev/null 2>&1 || true
      [ -s "$copy_log" ] && tail -n 20 "$copy_log" >> "$BACKUP_LOG_FILE" 2>/dev/null || true
    fi
  done
  IFS="$oldIFS"
  [ $upload_ok -eq 1 ] && uploaded=true || uploaded=false
else
  if [ -n "$rems" ] && ! command -v rclone >/dev/null 2>&1; then
    oldIFS="$IFS"
    IFS=$(printf '\n_'); IFS=${IFS%_}
    for remote in $rems; do
      [ -n "$remote" ] || continue
      append_upload_result "$remote" false "rclone missing"
    done
    IFS="$oldIFS"
  fi
  echo "[backup] rclone is not configured; set RCLONE_REMOTES (or RCLONE_REMOTE) in $ENV_FILE to enable cloud upload" | tee -a "$BACKUP_LOG_FILE" >/dev/null 2>&1 || true
fi

success=1

EOF

chmod +x "$AGENT_DIR/backup.sh"


cat > "$AGENT_DIR/restore-cloud.sh" <<'EOF'
#!/bin/sh
# Download a backup from cloud (rclone) and restore from it.
# Usage: restore-cloud.sh [file|latest] [scope=all|mihomo|agent] [include_env=0|1]
set -e

ENV_FILE="/opt/zash-agent/agent.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

BACKUP_TMP_DIR="${BACKUP_TMP_DIR:-/opt/zash-agent/var/backups}"
RESTORE_STATUS_FILE="${RESTORE_STATUS_FILE:-/opt/zash-agent/var/restore.last.json}"
RCLONE_CONFIG="${RCLONE_CONFIG:-}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}"
RCLONE_REMOTES="${RCLONE_REMOTES:-}"
RCLONE_PATH="${RCLONE_PATH:-NetcrazeBackups/zash-agent}"

file_arg="${1:-latest}"
scope="${2:-all}"
include_env="${3:-0}"
remote_req="${4:-}"

normalize_rclone_path() {
  p="$1"
  p="$(printf '%s' "$p" | sed 's#^/*##; s#//*#/#g; s#/$##')"
  printf '%s' "$p"
}

rclone_configured_remotes() {
  src="$RCLONE_REMOTES"
  if [ -z "$src" ]; then
    src="$RCLONE_REMOTE"
  fi
  printf '%s' "$src" \
    | sed 's/[;,[:space:]]\+/\n/g' \
    | sed 's/:$//; s/^ *//; s/ *$//' \
    | awk 'NF && !seen[$0]++ {print $0}'
}

rclone_find_file_remote() {
  name="$1"
  path="$2"
  req_remote="$3"
  [ -n "$name" ] || return 1
  rems=""
  if [ -n "$req_remote" ]; then
    rems="$req_remote"
  else
    rems="$(rclone_configured_remotes)"
  fi
  [ -n "$rems" ] || return 1
  rcfg=""
  if [ -n "$RCLONE_CONFIG" ]; then
    rcfg="--config $RCLONE_CONFIG"
  fi
  oldIFS="$IFS"
  IFS=$(printf '\n_'); IFS=${IFS%_}
  for remote in $rems; do
    [ -n "$remote" ] || continue
    src="$remote:$name"
    [ -n "$path" ] && src="$remote:$path/$name"
    # shellcheck disable=SC2086
    if RCLONE_CONFIG="$RCLONE_CONFIG" rclone lsf "$src" --max-depth 1 >/dev/null 2>&1; then
      printf '%s' "$remote"
      IFS="$oldIFS"
      return 0
    fi
  done
  IFS="$oldIFS"
  return 1
}

rclone_latest_remote_name() {
  path="$1"
  req_remote="$2"
  rems=""
  if [ -n "$req_remote" ]; then
    rems="$req_remote"
  else
    rems="$(rclone_configured_remotes)"
  fi
  [ -n "$rems" ] || return 1
  rcfg=""
  if [ -n "$RCLONE_CONFIG" ]; then
    rcfg="--config $RCLONE_CONFIG"
  fi
  best_remote=""
  best_name=""
  best_key=""
  oldIFS="$IFS"
  IFS=$(printf '\n_'); IFS=${IFS%_}
  for remote in $rems; do
    [ -n "$remote" ] || continue
    remote_dir="$remote:"
    [ -n "$path" ] && remote_dir="$remote:$path"
    # shellcheck disable=SC2086
    line="$(RCLONE_CONFIG="$RCLONE_CONFIG" rclone lsl "$remote_dir" --include 'zash-backup-*.tar.gz' 2>/dev/null | sort -k2,3 | tail -n1)"
    [ -n "$line" ] || continue
    name="$(printf '%s' "$line" | awk '{print $4}')"
    key="$(printf '%s' "$line" | awk '{print $2" "$3}')"
    [ -n "$name" ] || continue
    if [ -z "$best_key" ] || [ "$key" \> "$best_key" ]; then
      best_key="$key"
      best_name="$name"
      best_remote="$remote"
    fi
  done
  IFS="$oldIFS"
  [ -n "$best_name" ] || return 1
  printf '%s\t%s' "$best_remote" "$best_name"
}

RCLONE_PATH="$(normalize_rclone_path "$RCLONE_PATH")"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g'
}

write_status() {
  printf '%s' "$1" > "$RESTORE_STATUS_FILE" 2>/dev/null || true
}

write_running_status() {
  stage="$1"
  pct="$2"
  detail="$3"
  bytes_done="$4"
  bytes_total="$5"
  file_name="$6"
  printf '%s' "$pct" | grep -qE '^[0-9]+$' || pct=0
  printf '%s' "$bytes_done" | grep -qE '^[0-9]+$' || bytes_done=0
  printf '%s' "$bytes_total" | grep -qE '^[0-9]+$' || bytes_total=0
  write_status "$(printf '{"ok":true,"running":true,"startedAt":"%s","file":"%s","source":"cloud","stage":"%s","progressPct":%s,"bytesDone":%s,"bytesTotal":%s,"detail":"%s"}' \
    "$(json_escape "$started_at")" "$(json_escape "$file_name")" "$(json_escape "$stage")" "$pct" "$bytes_done" "$bytes_total" "$(json_escape "$detail")")"
}

file_size() {
  f="$1"
  [ -f "$f" ] || {
    echo 0
    return 0
  }
  stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || wc -c < "$f" 2>/dev/null || echo 0
}

log() {
  echo "$@"
}

started_at="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"
used_file=""
success=0
err=""

finish() {
  code=$?
  trap - EXIT
  finished_at="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"
  if [ $code -ne 0 ] || [ $success -ne 1 ]; then
    e="${err:-exit $code}"
    write_status "$(printf '{"ok":true,"running":false,"startedAt":"%s","finishedAt":"%s","success":false,"file":"%s","source":"cloud","stage":"failed","error":"%s"}' \
      "$(json_escape "$started_at")" "$(json_escape "$finished_at")" "$(json_escape "$used_file")" "$(json_escape "$e")")"
    exit $code
  fi
}
trap finish EXIT

rems="$(rclone_configured_remotes)"
if [ -z "$rems" ] || ! command -v rclone >/dev/null 2>&1; then
  err="cloud-not-ready"
  log "[restore-cloud] ERROR: rclone/remote is not configured"
  exit 1
fi

rcfg=""
if [ -n "$RCLONE_CONFIG" ]; then
  rcfg="--config $RCLONE_CONFIG"
fi

write_running_status "resolve-cloud" 2 "Resolving cloud backup" 0 0 "$file_arg"

selected_remote=""
remote_name=""
if [ -z "$file_arg" ] || [ "$file_arg" = "latest" ]; then
  if [ -n "$remote_req" ]; then
    remote_dir="$remote_req:"
    [ -n "$RCLONE_PATH" ] && remote_dir="$remote_req:$RCLONE_PATH"
    # shellcheck disable=SC2086
    remote_name="$(RCLONE_CONFIG="$RCLONE_CONFIG" rclone lsl "$remote_dir" --include 'zash-backup-*.tar.gz' 2>/dev/null | sort -k2,3 | tail -n1 | awk '{print $4}')"
    selected_remote="$remote_req"
  else
    best_line="$(rclone_latest_remote_name "$RCLONE_PATH" "")"
    selected_remote="$(printf '%s' "$best_line" | awk -F '	' '{print $1}')"
    remote_name="$(printf '%s' "$best_line" | awk -F '	' '{print $2}')"
  fi
else
  remote_name="$(basename "$file_arg")"
  if [ -n "$remote_req" ]; then
    selected_remote="$remote_req"
  else
    selected_remote="$(rclone_find_file_remote "$remote_name" "$RCLONE_PATH" "")"
  fi
fi

if [ -z "$remote_name" ] || [ -z "$selected_remote" ]; then
  err="cloud-backup-not-found"
  log "[restore-cloud] ERROR: backup file not found in cloud (arg='$file_arg', remote='$remote_req')"
  exit 1
fi

used_file="$remote_name"
remote_file="$selected_remote:$remote_name"
[ -n "$RCLONE_PATH" ] && remote_file="$selected_remote:$RCLONE_PATH/$remote_name"
mkdir -p "$BACKUP_TMP_DIR" >/dev/null 2>&1 || true
local_file="$BACKUP_TMP_DIR/$remote_name"
tmp_file="$local_file.part.$$"
rm -f "$tmp_file" >/dev/null 2>&1 || true

remote_size=0
# shellcheck disable=SC2086
remote_size="$(RCLONE_CONFIG="$RCLONE_CONFIG" rclone lsl "$remote_file" 2>/dev/null | awk 'NR==1{print $1}' | tr -d '\r')"
printf '%s' "$remote_size" | grep -qE '^[0-9]+$' || remote_size=0

log "[restore-cloud] remote: $remote_file"
log "[restore-cloud] selected remote: $selected_remote"
log "[restore-cloud] local:  $local_file"
write_running_status "downloading" 5 "Downloading from cloud" 0 "$remote_size" "$remote_name"

copy_log="/opt/zash-agent/var/restore-cloud.copy.log"
: > "$copy_log" 2>/dev/null || true
# shellcheck disable=SC2086
RCLONE_CONFIG="$RCLONE_CONFIG" rclone copyto "$remote_file" "$tmp_file" --transfers 1 --checkers 1 --retries 2 > "$copy_log" 2>&1 &
copy_pid=$!

while kill -0 "$copy_pid" 2>/dev/null; do
  done_bytes="$(file_size "$tmp_file")"
  pct=5
  if [ "$remote_size" -gt 0 ]; then
    pct=$(( done_bytes * 100 / remote_size ))
    [ "$pct" -lt 5 ] && pct=5
    [ "$pct" -gt 95 ] && pct=95
  fi
  write_running_status "downloading" "$pct" "Downloading from cloud" "$done_bytes" "$remote_size" "$remote_name"
  sleep 1
done

if ! wait "$copy_pid"; then
  err="cloud-download-failed"
  tail_line="$(tail -n 1 "$copy_log" 2>/dev/null || true)"
  [ -n "$tail_line" ] && err="$err: $tail_line"
  log "[restore-cloud] ERROR: download failed"
  exit 1
fi

mv -f "$tmp_file" "$local_file"
done_bytes="$(file_size "$local_file")"
log "[restore-cloud] downloaded: $local_file"
write_running_status "downloaded" 100 "Archive downloaded" "$done_bytes" "$remote_size" "$remote_name"

success=1
trap - EXIT
exec /opt/zash-agent/restore.sh "$remote_name" "$scope" "$include_env" "cloud"

EOF

chmod +x "$AGENT_DIR/restore-cloud.sh"

cat > "$AGENT_DIR/restore.sh" <<'EOF'
#!/bin/sh
# Restore from a zash-backup-*.tar.gz archive created by /opt/zash-agent/backup.sh
# Usage: restore.sh [file|latest] [scope=all|mihomo|agent] [include_env=0|1] [source=local|cloud]
set -e

ENV_FILE="/opt/zash-agent/agent.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

BACKUP_TMP_DIR="${BACKUP_TMP_DIR:-/opt/zash-agent/var/backups}"
RESTORE_STATUS_FILE="${RESTORE_STATUS_FILE:-/opt/zash-agent/var/restore.last.json}"
RESTORE_LOG_FILE="${RESTORE_LOG_FILE:-/opt/zash-agent/var/restore.last.log}"

MIHOMO_CONFIG="${MIHOMO_CONFIG:-/opt/etc/mihomo/config.yaml}"

file_arg="${1:-}"
scope="${2:-all}"
include_env="${3:-0}"
source="${4:-local}"

ts="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo now)"
host="$(uname -n 2>/dev/null || echo router)"
started_at="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"

mkdir -p "$BACKUP_TMP_DIR" /opt/zash-agent/var >/dev/null 2>&1 || true

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g'
}

write_status() {
  printf '%s' "$1" > "$RESTORE_STATUS_FILE" 2>/dev/null || true
}

write_running_status() {
  stage="$1"
  pct="$2"
  detail="$3"
  printf '%s' "$pct" | grep -qE '^[0-9]+$' || pct=0
  write_status "$(printf '{"ok":true,"running":true,"startedAt":"%s","file":"%s","scope":"%s","source":"%s","includeEnv":%s,"stage":"%s","progressPct":%s,"detail":"%s"}' \
    "$(json_escape "$started_at")" "$(json_escape "$used_file")" "$(json_escape "$scope")" "$(json_escape "$source")" "$include_env" "$(json_escape "$stage")" "$pct" "$(json_escape "$detail")")"
}

log() {
  echo "$@" | tee -a "$RESTORE_LOG_FILE" >/dev/null 2>&1 || true
}

success=0
used_file=""
err=""

finish() {
  code=$?
  trap - EXIT
  finished_at="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"
  if [ $code -ne 0 ] || [ $success -ne 1 ]; then
    e="${err:-exit $code}"
    write_status "$(printf '{"ok":true,"running":false,"startedAt":"%s","finishedAt":"%s","success":false,"file":"%s","scope":"%s","source":"%s","includeEnv":%s,"stage":"failed","progressPct":100,"error":"%s"}' \
      "$(json_escape "$started_at")" "$(json_escape "$finished_at")" "$(json_escape "$used_file")" "$(json_escape "$scope")" "$(json_escape "$source")" "$include_env" "$(json_escape "$e")")"
    exit $code
  fi
  write_status "$(printf '{"ok":true,"running":false,"startedAt":"%s","finishedAt":"%s","success":true,"file":"%s","scope":"%s","source":"%s","includeEnv":%s,"stage":"done","progressPct":100}' \
    "$(json_escape "$started_at")" "$(json_escape "$finished_at")" "$(json_escape "$used_file")" "$(json_escape "$scope")" "$(json_escape "$source")" "$include_env")"
}
trap finish EXIT

pick_latest() {
  ls -1t "$BACKUP_TMP_DIR"/zash-backup-*.tar.gz 2>/dev/null | head -n 1
}

# Decide archive file
if [ -z "$file_arg" ] || [ "$file_arg" = "latest" ]; then
  archive="$(pick_latest || true)"
else
  # sanitize: only basename inside BACKUP_TMP_DIR
  bn="$(basename "$file_arg")"
  archive="$BACKUP_TMP_DIR/$bn"
fi

if [ -z "$archive" ] || [ ! -f "$archive" ]; then
  err="backup-not-found"
  log "[restore] ERROR: backup file not found (arg='$file_arg')"
  exit 1
fi

used_file="$archive"
log "[restore] using backup: $archive"
log "[restore] scope=$scope include_env=$include_env source=$source"
write_running_status "preparing" 96 "Preparing restore"

tmp="/opt/zash-agent/var/restore.tmp.$$"
rm -rf "$tmp" >/dev/null 2>&1 || true
mkdir -p "$tmp" >/dev/null 2>&1 || true

# Extract (best effort)
if tar -xzf "$archive" -C "$tmp" >/dev/null 2>&1; then
  :
else
  gzip -dc "$archive" 2>/dev/null | tar -xf - -C "$tmp" 2>/dev/null
fi

# Determine extracted root
root="$tmp"
[ -d "$root/opt" ] || [ -d "$root/opt" ] || true

src_of() {
  dest="$1"           # absolute like /opt/...
  rel="${dest#/}"     # opt/...
  echo "$root/$rel"
}

ensure_parent() {
  d="$(dirname "$1")"
  mkdir -p "$d" >/dev/null 2>&1 || true
}

restore_file() {
  src="$1"
  dst="$2"
  if [ -f "$src" ]; then
    ensure_parent "$dst"
    cp -af "$src" "$dst" >/dev/null 2>&1 || cp -f "$src" "$dst"
    log "[restore] file: $dst"
  else
    log "[restore] skip (missing in backup): $dst"
  fi
}

restore_dir_replace() {
  src="$1"
  dst="$2"
  if [ -d "$src" ]; then
    rm -rf "$dst" >/dev/null 2>&1 || true
    ensure_parent "$dst"
    cp -a "$src" "$dst" >/dev/null 2>&1 || cp -r "$src" "$dst"
    log "[restore] dir:  $dst"
  else
    log "[restore] skip (missing in backup): $dst"
  fi
}

# Safety snapshot before overwriting (best effort)
pre="/opt/zash-agent/var/restore.pre-${host}-${ts}.tar.gz"
list="$tmp/.pre.list.$$"
rm -f "$list" >/dev/null 2>&1 || true

add_pre() { [ -e "$1" ] && echo "$1" >> "$list"; }

# Build list according to scope
want_mihomo=0
want_agent=0

case "$scope" in
  mihomo) want_mihomo=1 ;;
  agent) want_agent=1 ;;
  all|*) want_mihomo=1; want_agent=1 ;;
esac

if [ $want_mihomo -eq 1 ]; then
  add_pre "$MIHOMO_CONFIG"
  add_pre "/opt/etc/mihomo/GeoIP.dat"
  add_pre "/opt/etc/mihomo/GeoSite.dat"
  add_pre "/opt/etc/mihomo/ASN.mmdb"
  add_pre "/opt/etc/mihomo/rules"
fi

if [ $want_agent -eq 1 ]; then
  add_pre "/opt/zash-agent/var/users-db.json"
  add_pre "/opt/zash-agent/var/users-db.meta.json"
  add_pre "/opt/zash-agent/var/users-db.revs"
  add_pre "/opt/zash-agent/var/shapers.db"
  add_pre "/opt/zash-agent/var/blocks.db"
  if [ "$include_env" = "1" ]; then
    add_pre "/opt/zash-agent/agent.env"
  fi
fi

if [ -s "$list" ]; then
  if tar -czf "$pre" -T "$list" >/dev/null 2>&1; then
    log "[restore] pre-snapshot: $pre"
  else
    tar -cf - -T "$list" 2>/dev/null | gzip -c > "$pre" || true
    [ -s "$pre" ] && log "[restore] pre-snapshot: $pre"
  fi
fi
rm -f "$list" >/dev/null 2>&1 || true

# Apply restore
write_running_status "restoring" 98 "Applying files"
if [ $want_mihomo -eq 1 ]; then
  restore_file "$(src_of "$MIHOMO_CONFIG")" "$MIHOMO_CONFIG"
  restore_file "$(src_of "/opt/etc/mihomo/GeoIP.dat")" "/opt/etc/mihomo/GeoIP.dat"
  restore_file "$(src_of "/opt/etc/mihomo/GeoSite.dat")" "/opt/etc/mihomo/GeoSite.dat"
  restore_file "$(src_of "/opt/etc/mihomo/ASN.mmdb")" "/opt/etc/mihomo/ASN.mmdb"
  restore_dir_replace "$(src_of "/opt/etc/mihomo/rules")" "/opt/etc/mihomo/rules"
  log "[restore] NOTE: restart Mihomo manually if needed."
fi

if [ $want_agent -eq 1 ]; then
  restore_file "$(src_of "/opt/zash-agent/var/users-db.json")" "/opt/zash-agent/var/users-db.json"
  restore_file "$(src_of "/opt/zash-agent/var/users-db.meta.json")" "/opt/zash-agent/var/users-db.meta.json"
  restore_dir_replace "$(src_of "/opt/zash-agent/var/users-db.revs")" "/opt/zash-agent/var/users-db.revs"
  restore_file "$(src_of "/opt/zash-agent/var/shapers.db")" "/opt/zash-agent/var/shapers.db"
  restore_file "$(src_of "/opt/zash-agent/var/blocks.db")" "/opt/zash-agent/var/blocks.db"
  if [ "$include_env" = "1" ]; then
    restore_file "$(src_of "/opt/zash-agent/agent.env")" "/opt/zash-agent/agent.env"
  fi
  log "[restore] NOTE: restart zash-agent manually if needed."
fi

rm -rf "$tmp" >/dev/null 2>&1 || true
success=1
log "[restore] done"

EOF

chmod +x "$AGENT_DIR/restore.sh"

cat > "$AGENT_DIR/start.sh" <<'EOF'
#!/bin/sh
set -e

ENV_FILE="/opt/zash-agent/agent.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

PORT="${PORT:-9099}"
BIND_IP="${BIND_IP:-0.0.0.0}"
LAN_IF="${LAN_IF:-br0}"

PID_FILE="/opt/zash-agent/var/httpd.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "[zash-agent] already running (pid $(cat "$PID_FILE"))"
  exit 0
fi

echo "[zash-agent] starting uhttpd on $BIND_IP:$PORT"

# Allow LAN access to agent port (best effort)
if command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -i "$LAN_IF" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null ||     iptables -I INPUT 1 -i "$LAN_IF" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true
fi


UHTTPD_BIN="$(command -v uhttpd 2>/dev/null || true)"
[ -n "$UHTTPD_BIN" ] || UHTTPD_BIN="/opt/sbin/uhttpd"

LOG_DIR="/opt/var/log/zash-agent"
LOG_FILE="$LOG_DIR/uhttpd.log"
mkdir -p "$LOG_DIR" || true
# Prevent huge log growth (keep last ~2000 lines if >1 MiB)
if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  tail -n 2000 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE" || true
fi

"$UHTTPD_BIN" -f -p "$BIND_IP:$PORT" -h /opt/zash-agent/www -x /cgi-bin -t 15 -T 15 >>"$LOG_FILE" 2>&1 </dev/null &
echo $! > "$PID_FILE"

# Re-apply saved shaping rules
HOST="$BIND_IP"
[ "$HOST" = "0.0.0.0" ] && HOST="127.0.0.1"
sleep 1
(wget -qO- "http://$HOST:$PORT/cgi-bin/api.sh?cmd=rehydrate" >/dev/null 2>&1 || busybox wget -qO- "http://$HOST:$PORT/cgi-bin/api.sh?cmd=rehydrate" >/dev/null 2>&1 || true)

EOF

chmod +x "$AGENT_DIR/start.sh"

mkdir -p /opt/etc/init.d
cat > /opt/etc/init.d/S99zash-agent <<'EOF'
#!/bin/sh

case "$1" in
  start)
    /opt/zash-agent/start.sh
    ;;
  stop)
    PID_FILE="/opt/zash-agent/var/httpd.pid"
    if [ -f "$PID_FILE" ]; then
      pid="$(cat "$PID_FILE")"
      kill "$pid" 2>/dev/null || true
      rm -f "$PID_FILE"
    fi
    # Remove firewall allow rule (best effort)
    ENV_FILE="/opt/zash-agent/agent.env"
    [ -f "$ENV_FILE" ] && . "$ENV_FILE"
    PORT="${PORT:-9099}"
    LAN_IF="${LAN_IF:-br0}"
    if command -v iptables >/dev/null 2>&1; then
      iptables -D INPUT -i "$LAN_IF" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true
    fi
    ;;
  restart)
    "$0" stop
    "$0" start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac

EOF

chmod +x /opt/etc/init.d/S99zash-agent

echo "[zash-agent] installing: done"

"$AGENT_DIR/start.sh"

echo "[zash-agent] test: curl http://$BIND_IP:$PORT/cgi-bin/api.sh?cmd=status"
