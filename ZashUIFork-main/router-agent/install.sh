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
TOKEN="${TOKEN:-}"
MIHOMO_CONFIG="${MIHOMO_CONFIG:-/opt/etc/mihomo/config.yaml}"
MIHOMO_LOG="${MIHOMO_LOG:-}"
GEOIP_URL="${GEOIP_URL:-https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip-lite.dat}"
GEOSITE_URL="${GEOSITE_URL:-https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat}"
ASN_URL="${ASN_URL:-https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb}"
WAN_RATE="${WAN_RATE:-1000}"
LAN_RATE="${LAN_RATE:-1000}"

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

  in=0
  pname=""
  url=""
  out='{"ok":true,"providers":['
  first=1

  while IFS= read -r line; do
    if [ $in -eq 0 ]; then
      case "$line" in
        proxy-providers:*) in=1; continue ;;
      esac
      continue
    fi

    echo "$line" | grep -qE '^[^[:space:]]' && break

    if echo "$line" | grep -qE '^[[:space:]]{2}[^[:space:]].*:[[:space:]]*$'; then
      pname="$(echo "$line" | sed -E 's/^[[:space:]]{2}([^:]+):.*/\1/')"
      url=""
      continue
    fi

    if echo "$line" | grep -qE '^[[:space:]]{4}url:[[:space:]]*'; then
      url="$(echo "$line" | sed -E 's/^[[:space:]]{4}url:[[:space:]]*//')"
      url="$(echo "$url" | sed -E 's/^["\x27]?//; s/["\x27]?$//')"

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

      not_after=""
      if [ "$scheme" = "https" ] || [ "$scheme" = "wss" ]; then
        not_after="$(ssl_not_after "$host" "$port")"
      fi

      [ $first -eq 0 ] && out="$out,"
      first=0
      esc_name="$(printf '%s' "$pname" | sed 's/"/\\\"/g')"
      esc_url="$(printf '%s' "$url" | sed 's/"/\\\"/g')"
      esc_host="$(printf '%s' "$host" | sed 's/"/\\\"/g')"
      esc_port="$(printf '%s' "$port" | sed 's/"/\\\"/g')"
      esc_na="$(printf '%s' "$not_after" | sed 's/"/\\\"/g')"

      out="$out{\"name\":\"$esc_name\",\"url\":\"$esc_url\",\"host\":\"$esc_host\",\"port\":\"$esc_port\",\"sslNotAfter\":\"$esc_na\"}"
    fi
  done < "$MIHOMO_CONFIG"

  out="$out]}"
  reply_ok "$out"
}

jesc() {
  # Minimal JSON string escape (quotes + backslashes)
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
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
cmd=""; ip=""; up=""; down=""; mac=""; ports=""; token_q=""; type=""; lines=""; offset=""; rev_q=""
IFS='&'
for kv in $QUERY_STRING; do
  key="${kv%%=*}"
  val="${kv#*=}"
  # basic URL decode for %2F etc.
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

  reply_ok "$(printf '{"ok":true,"version":"0.5.13","serverVersion":"%s","wan":"%s","lan":"%s","tc":%s,"iptables":%s,"hashlimit":%s,"usersDb":true,"cpuPct":%s,"load1":"%s","uptimeSec":%s,"memTotal":%s,"memUsed":%s,"memUsedPct":%s}' \
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

# Save a lightweight trace of requests (best effort).
agent_log

case "$cmd" in
  status|"") status ;;
  neighbors) neighbors ;;
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
  *) reply_ok '{"ok":false,"error":"unknown-cmd"}' ;;
esac

EOF

chmod +x "$AGENT_DIR/www/cgi-bin/api.sh"

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
