#!/usr/bin/env bash
# Probe the remote Redis used by the LiteLLM stack.
#
# Usage:
#   scripts/redis-probe.sh            # status + key overview (read-only)
#   scripts/redis-probe.sh keys       # list all keys (capped at SCAN_COUNT)
#   scripts/redis-probe.sh dump       # keys + type/size for each, top namespaces
#
# Reads REDIS_HOST / REDIS_PORT / REDIS_PASSWORD from .env.json (preferred) or
# the environment / .env. Requires `redis-cli` on PATH, or Docker (`docker`)
# running, in which case the probe runs inside redis:7.2-alpine.
#
# This script is READ-ONLY: it never calls DEL/FLUSHDB/SET. Safe to run in prod.
set -euo pipefail

cd "$(dirname "$0")/.."

# --- resolve connection params ---
get_json() {  # key
  python3 -c "import json,sys; d=json.load(open('.env.json')); print(d.get('$1',''))" 2>/dev/null || true
}

REDIS_HOST="${REDIS_HOST:-$(get_json REDIS_HOST)}"
REDIS_PORT="${REDIS_PORT:-$(get_json REDIS_PORT)}"
REDIS_PASSWORD="${REDIS_PASSWORD:-$(get_json REDIS_PASSWORD)}"
SCAN_COUNT="${SCAN_COUNT:-1000}"
ACTION="${1:-status}"

if [[ -z "$REDIS_HOST" || -z "$REDIS_PASSWORD" ]]; then
  echo "REDIS_HOST or REDIS_PASSWORD not found in .env.json / env." >&2
  exit 1
fi

# --- pick a redis-cli invocation ---
if command -v redis-cli >/dev/null 2>&1; then
  CLI=(redis-cli -h "$REDIS_HOST" -p "${REDIS_PORT:-6379}" -a "$REDIS_PASSWORD" --no-auth-warning)
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  IMG=redis:7.2-alpine
  docker image inspect "$IMG" >/dev/null 2>&1 || docker pull "$IMG" >/dev/null
  CLI=(docker run --rm -i --network host "$IMG" redis-cli \
       -h "$REDIS_HOST" -p "${REDIS_PORT:-6379}" -a "$REDIS_PASSWORD" --no-auth-warning)
else
  echo "Need 'redis-cli' on PATH, or a running 'docker' daemon." >&2
  exit 1
fi

run() { "${CLI[@]}" "$@"; }   # convenience wrapper

hr() { printf '\n--- %s ---\n' "$*"; }

case "$ACTION" in
  status)
    hr "PING"
    run PING
    hr "INFO server"
    run INFO server | grep -E "redis_version|tcp_port|uptime_in_(seconds|days)|os|config_file|run_id|configured_pass"
    hr "INFO memory"
    run INFO memory | grep -E "used_memory_human|maxmemory_human|maxmemory_policy|connected_clients|connected_slaves"
    hr "INFO keyspace"
    run INFO keyspace
    hr "DBSIZE (db0)"
    run DBSIZE
    ;;

  keys)
    hr "SCAN all keys (cap $SCAN_COUNT)"
    # SCAN is non-blocking and safe; we just collect keys.
    run --scan --count "$SCAN_COUNT" | sort -u | head - "$SCAN_COUNT"
    ;;

  dump)
    hr "DBSIZE"
    run DBSIZE
    hr "Keys + type/size"
    keys=$(run --scan --count "$SCAN_COUNT" | sort -u)
    if [[ -z "$keys" ]]; then
      echo "(empty)"
    else
      while IFS= read -r k; do
        t=$(run TYPE "$k")
        sz=""
        case "$t" in
          string) sz="len=$(run STRLEN "$k" | tr -d '\r\n')";;
          list)   sz="llen=$(run LLEN "$k" | tr -d '\r\n')";;
          hash)   sz="hlen=$(run HLEN "$k" | tr -d '\r\n')";;
          set)    sz="scard=$(run SCARD "$k" | tr -d '\r\n')";;
          zset)   sz="zcard=$(run ZCARD "$k" | tr -d '\r\n')";;
          stream) sz="xlen=$(run XLEN "$k" | tr -d '\r\n')";;
        esac
        printf '%s\t%s\t%s\n' "$k" "$t" "$sz"
      done <<< "$keys"
    fi
    hr "Top key namespaces (prefix before first ':' )"
    <<<"$keys" awk -F: '{print $1}' | sort | uniq -c | sort -rn | head -25
    ;;

  *)
    echo "Unknown action: $ACTION (use: status|keys|dump)" >&2
    exit 1
    ;;
esac