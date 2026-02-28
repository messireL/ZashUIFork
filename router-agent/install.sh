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
TOKEN="${TOKEN:-}"
MIHOMO_CONFIG="${MIHOMO_CONFIG:-/opt/etc/mihomo/config.yaml}"
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

if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
  reply_ok "{}"
  exit 0
fi

# Parse query string (key=value&...)
cmd=""; ip=""; up=""; down=""; mac=""; ports=""; token_q=""
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
  iptables -t filter -C INPUT -i "$LAN_IF" -j ZASH_BLOCK >/dev/null 2>&1 || iptables -t filter -I INPUT 1 -i "$LAN_IF" -j ZASH_BLOCK
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

  mac_=""
  mac_="$(ip neigh show dev "$LAN_IF" to "$ip_" 2>/dev/null | awk '/lladdr/{print $5; exit}' | tr 'A-Z' 'a-z')"
  if [ -z "$mac_" ]; then
    mac_="$(arp -n "$ip_" 2>/dev/null | awk 'NR==2{print $3; exit}' | tr 'A-Z' 'a-z')"
  fi

  if [ -n "$mac_" ] && echo "$mac_" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
    reply_ok "$(json ok true mac "$mac_")"
  else
    reply_ok '{"ok":false,"error":"not-found"}'
  fi
}

persist_block() {
  m="$1"; p="$2"
  mkdir -p "$(dirname "$BLOCKS_FILE")" >/dev/null 2>&1 || true
  tmp="${BLOCKS_FILE}.tmp"
  [ -f "$BLOCKS_FILE" ] && grep -vi "^${m} " "$BLOCKS_FILE" > "$tmp" 2>/dev/null || true
  echo "${m} ${p}" >> "$tmp"
  mv "$tmp" "$BLOCKS_FILE" 2>/dev/null || true
}

remove_persist_block() {
  m="$1"
  [ -f "$BLOCKS_FILE" ] || return 0
  tmp="${BLOCKS_FILE}.tmp"
  grep -vi "^${m} " "$BLOCKS_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$BLOCKS_FILE" 2>/dev/null || true
}

block_mac_ports() {
  m="$1"; p="$2"
  [ -n "$m" ] || { reply_ok '{"ok":false,"error":"missing-mac"}'; return; }
  ensure_block_chain

  # default ports if not provided
  [ -n "$p" ] || p="7890,7891,1080,1181,1182"

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

  persist_block "$m" "$p"
  reply_ok '{"ok":true}'
}

unblock_mac_ports() {
  m="$1"
  [ -n "$m" ] || { reply_ok '{"ok":false,"error":"missing-mac"}'; return; }
  ensure_block_chain

  # remove any rules for this MAC (best effort)
  while iptables -t filter -D ZASH_BLOCK -m mac --mac-source "$m" -j REJECT >/dev/null 2>&1; do :; done
  # Also remove with protocol/port (some iptables builds require exact match)
  iptables -t filter -S ZASH_BLOCK 2>/dev/null | grep -i "--mac-source $m" | while read -r rule; do
    # Convert -A to -D
    drule="$(echo "$rule" | sed 's/^-A /-D /')"
    iptables -t filter $drule >/dev/null 2>&1 || true
  done

  remove_persist_block "$m"
  reply_ok '{"ok":true}'
}

rehydrate_blocks() {
  [ -f "$BLOCKS_FILE" ] || return 0
  ensure_block_chain
  while read -r m p; do
    [ -n "$m" ] || continue
    [ -n "$p" ] || p="7890,7891,1080,1181,1182"
    # best-effort: re-add rules
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

  reply_ok "$(printf '{"ok":true,"version":"0.2","wan":"%s","lan":"%s","tc":%s,"iptables":%s,"hashlimit":%s}' \
    "$WAN_IF" "$LAN_IF" \
    $( [ $have_tc -eq 1 ] && echo true || echo false ) \
    $( [ $have_iptables -eq 1 ] && echo true || echo false ) \
    $( [ $have_hashlimit -eq 1 ] && echo true || echo false ))"
}

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
  blockmac)
    block_mac_ports "$mac" "$ports"
    ;;
  unblockmac)
    unblock_mac_ports "$mac"
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

PID_FILE="/opt/zash-agent/var/httpd.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "[zash-agent] already running (pid $(cat "$PID_FILE"))"
  exit 0
fi

echo "[zash-agent] starting uhttpd on $BIND_IP:$PORT"

UHTTPD_BIN="$(command -v uhttpd 2>/dev/null || true)"
[ -n "$UHTTPD_BIN" ] || UHTTPD_BIN="/opt/sbin/uhttpd"
"$UHTTPD_BIN" -f -p "$BIND_IP:$PORT" -h /opt/zash-agent/www -x /cgi-bin -t 15 -T 15 &
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
