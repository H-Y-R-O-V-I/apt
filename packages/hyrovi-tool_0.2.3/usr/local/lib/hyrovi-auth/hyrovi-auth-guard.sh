#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hyrovi"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyrovi"
DEVICE_FILE="${CONFIG_DIR}/device.json"
AUTH_FILE="${CONFIG_DIR}/auth.json"
STATE_FILE="${STATE_DIR}/state.json"

TOOL_NAME="${HYROVI_TOOL_NAME:-hyrovi-tool}"
TOOL_VERSION="${HYROVI_TOOL_VERSION:-unknown}"
SERVER_URL="${HYROVI_SERVER_URL:-}"
OFFLINE_GRACE_DAYS="${HYROVI_OFFLINE_GRACE_DAYS:-7}"

mkdir -p "$CONFIG_DIR" "$STATE_DIR"

json_get() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || { echo ""; return 0; }
  python3 - "$file" "$key" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    value = data.get(sys.argv[2], "")
    print("" if value is None else value)
except Exception:
    print("")
PY
}

json_write() {
  local file="$1" content="$2"
  umask 077
  printf '%s\n' "$content" > "$file"
}

ensure_device_file() {
  if [[ ! -f "$DEVICE_FILE" ]]; then
    local device_id hostname device_name fingerprint machine_id
    device_id="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
    hostname="$(hostname 2>/dev/null || echo unknown-host)"
    device_name="${HYROVI_DEVICE_NAME:-$hostname}"
    machine_id="$(cat /etc/machine-id 2>/dev/null || true)"
    fingerprint="$(python3 - "$machine_id" "$hostname" <<'PY'
import hashlib, sys
print(hashlib.sha256((sys.argv[1] + "|" + sys.argv[2]).encode()).hexdigest())
PY
)"
    json_write "$DEVICE_FILE" "$(cat <<EOF2
{"device_id":"$device_id","hostname":"$hostname","device_name":"$device_name","fingerprint":"$fingerprint"}
EOF2
)"
  fi
}

register_if_needed() {
  [[ -n "$SERVER_URL" ]] || return 0
  if [[ ! -f "$AUTH_FILE" ]]; then
    local device_id fingerprint hostname device_name payload
    device_id="$(json_get "$DEVICE_FILE" device_id)"
    fingerprint="$(json_get "$DEVICE_FILE" fingerprint)"
    hostname="$(json_get "$DEVICE_FILE" hostname)"
    device_name="$(json_get "$DEVICE_FILE" device_name)"
    payload="$(cat <<EOF2
{"device_id":"$device_id","hostname":"$hostname","device_name":"$device_name","fingerprint":"$fingerprint","tool_version":"$TOOL_VERSION"}
EOF2
)"
    curl -fsS -X POST "${SERVER_URL%/}/api/register" -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
  fi
}

write_last_ok() {
  local now_epoch
  now_epoch="$(date +%s)"
  json_write "$STATE_FILE" "{\"last_ok_epoch\":$now_epoch}"
}

self_remove() {
  local reason="${1:-revoked}"
  echo "AUTH_REMOVE:$reason"
  if command -v sudo >/dev/null 2>&1; then
    sudo apt remove -y "$TOOL_NAME" || true
  fi
}

check_access() {
  [[ -n "$SERVER_URL" ]] || { echo "SERVER_URL fehlt"; return 2; }

  if [[ ! -f "$AUTH_FILE" ]] || [[ -z "$(json_get "$AUTH_FILE" token)" ]]; then
    register_if_needed

    local bootstrap_code bootstrap_body device_id fingerprint hostname payload tmpf bootstrap_token
    device_id="$(json_get "$DEVICE_FILE" device_id)"
    fingerprint="$(json_get "$DEVICE_FILE" fingerprint)"
    hostname="$(json_get "$DEVICE_FILE" hostname)"
    payload="$(cat <<EOF2
{"device_id":"$device_id","hostname":"$hostname","fingerprint":"$fingerprint","tool_version":"$TOOL_VERSION","token":""}
EOF2
)"
    tmpf="$(mktemp)"
    bootstrap_code="$(curl -sS -o "$tmpf" -w '%{http_code}' -X POST "${SERVER_URL%/}/api/check" -H 'Content-Type: application/json' -d "$payload" || echo "000")"
    bootstrap_body="$(cat "$tmpf" 2>/dev/null || true)"
    rm -f "$tmpf"

    if [[ "$bootstrap_code" == "200" ]]; then
      bootstrap_token="$(python3 - "$bootstrap_body" <<'PY'
import json, sys
try:
    print(json.loads(sys.argv[1]).get("bootstrap_token",""))
except Exception:
    print("")
PY
)"
      if [[ -n "$bootstrap_token" ]]; then
        json_write "$AUTH_FILE" "$(cat <<EOF2
{"token":"$bootstrap_token"}
EOF2
)"
      fi
    fi

    if [[ ! -f "$AUTH_FILE" ]] || [[ -z "$(json_get "$AUTH_FILE" token)" ]]; then
      echo "Gerät ist registriert, aber noch nicht freigegeben."
      return 1
    fi
  fi

  local device_id fingerprint hostname token payload response http_code body status allowed now_epoch last_ok_epoch grace_seconds
  device_id="$(json_get "$DEVICE_FILE" device_id)"
  fingerprint="$(json_get "$DEVICE_FILE" fingerprint)"
  hostname="$(json_get "$DEVICE_FILE" hostname)"
  token="$(json_get "$AUTH_FILE" token)"

  payload="$(cat <<EOF2
{"device_id":"$device_id","hostname":"$hostname","fingerprint":"$fingerprint","tool_version":"$TOOL_VERSION","token":"$token"}
EOF2
)"

  response="$(mktemp)"
  http_code="$(curl -sS -o "$response" -w '%{http_code}' -X POST "${SERVER_URL%/}/api/check" -H 'Content-Type: application/json' -d "$payload" || echo "000")"
  body="$(cat "$response" 2>/dev/null || true)"
  rm -f "$response"

  now_epoch="$(date +%s)"
  grace_seconds=$(( OFFLINE_GRACE_DAYS * 86400 ))
  last_ok_epoch="$(json_get "$STATE_FILE" last_ok_epoch)"
  [[ "$last_ok_epoch" =~ ^[0-9]+$ ]] || last_ok_epoch=0

  if [[ "$http_code" == "200" ]]; then
    allowed="$(python3 - "$body" <<'PY'
import json, sys
try:
    print(str(json.loads(sys.argv[1]).get("allowed", False)).lower())
except Exception:
    print("false")
PY
)"
    if [[ "$allowed" == "true" ]]; then
      write_last_ok
      return 0
    fi
  fi

  if [[ "$http_code" == "403" ]]; then
    status="$(python3 - "$body" <<'PY'
import json, sys
try:
    print(json.loads(sys.argv[1]).get("status",""))
except Exception:
    print("")
PY
)"
    case "$status" in
      pending)
        register_if_needed
        echo "Gerät ist registriert, aber noch nicht freigegeben."
        return 1
        ;;
      revoked|blocked|unknown_device|invalid_token)
        self_remove "$status"
        return 1
        ;;
      *)
        echo "Zugriff verweigert: $status"
        return 1
        ;;
    esac
  fi

  if (( last_ok_epoch > 0 && now_epoch - last_ok_epoch <= grace_seconds )); then
    return 0
  fi

  echo "Server nicht erreichbar und keine gültige Grace-Zeit mehr vorhanden."
  return 1
}

ensure_device_file
check_access
