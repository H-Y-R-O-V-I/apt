#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="/etc/hyrovi"
DEVICE_FILE="${CONFIG_DIR}/device.json"
AUTH_FILE="${CONFIG_DIR}/auth.json"
STATE_FILE="${CONFIG_DIR}/state.json"
TOOL_NAME="${HYROVI_TOOL_NAME:-hyrovi-tool}"
TOOL_VERSION="${HYROVI_TOOL_VERSION:-unknown}"
SERVER_URL="${HYROVI_SERVER_URL:-}"
OFFLINE_GRACE_DAYS="${HYROVI_OFFLINE_GRACE_DAYS:-7}"

mkdir -p "$CONFIG_DIR"

json_get() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import json, sys
p=sys.argv[1]; key=sys.argv[2]
try:
    with open(p,"r",encoding="utf-8") as f:
        data=json.load(f)
    print(data.get(key,""))
except Exception:
    print("")
PY
}

json_write() {
  local target="$1"
  local content="$2"
  printf '%s\n' "$content" | sudo tee "$target" >/dev/null
  sudo chmod 600 "$target" || true
}

ensure_device() {
  if [[ ! -f "$DEVICE_FILE" ]]; then
    local device_id fingerprint hostname device_name
    device_id="$(python3 - <<'PY'
import uuid; print(uuid.uuid4())
PY
)"
    fingerprint="$(python3 - <<'PY'
import hashlib, socket
from pathlib import Path
parts = []
for p in ("/etc/machine-id",):
    try:
        parts.append(Path(p).read_text(encoding="utf-8").strip())
    except Exception:
        pass
parts.append(socket.gethostname())
print(hashlib.sha256("|".join(parts).encode()).hexdigest())
PY
)"
    hostname="$(hostname)"
    device_name="${HYROVI_DEVICE_NAME:-$hostname}"
    json_write "$DEVICE_FILE" "$(cat <<EOF
{"device_id":"$device_id","hostname":"$hostname","device_name":"$device_name","fingerprint":"$fingerprint"}
EOF
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
    payload="$(cat <<EOF
{"device_id":"$device_id","hostname":"$hostname","device_name":"$device_name","fingerprint":"$fingerprint","tool_version":"$TOOL_VERSION"}
EOF
)"
    curl -fsS -X POST "${SERVER_URL%/}/api/register" -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
  fi
}

check_access() {
  [[ -n "$SERVER_URL" ]] || { echo "SERVER_URL fehlt"; return 2; }

  local device_id fingerprint hostname token payload response http_code body status allowed now_epoch last_ok_epoch grace_seconds
  device_id="$(json_get "$DEVICE_FILE" device_id)"
  fingerprint="$(json_get "$DEVICE_FILE" fingerprint)"
  hostname="$(json_get "$DEVICE_FILE" hostname)"
  token="$(json_get "$AUTH_FILE" token)"

  payload="$(cat <<EOF
{"device_id":"$device_id","hostname":"$hostname","fingerprint":"$fingerprint","tool_version":"$TOOL_VERSION","token":"$token"}
EOF
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
    status="$(python3 - <<'PY' "$body"
import json, sys
try:
    print(json.loads(sys.argv[1]).get("status",""))
except Exception:
    print("")
PY
)"
    allowed="$(python3 - <<'PY' "$body"
import json, sys
try:
    print(str(json.loads(sys.argv[1]).get("allowed", False)).lower())
except Exception:
    print("false")
PY
)"
    if [[ "$allowed" == "true" && "$status" == "approved" ]]; then
      json_write "$STATE_FILE" "{\"last_ok_epoch\":$now_epoch}"
      return 0
    fi
  fi

  if [[ "$http_code" == "403" ]]; then
    status="$(python3 - <<'PY' "$body"
import json, sys
try:
    print(json.loads(sys.argv[1]).get("status",""))
except Exception:
    print("")
PY
)"
    case "$status" in
      revoked|blocked|invalid_token|unknown_device)
        echo "AUTH_REMOVE:$status"
        return 10
        ;;
      pending)
        echo "Gerät ist registriert, aber noch nicht freigegeben."
        return 11
        ;;
      *)
        echo "Server hat Zugriff verweigert: $status"
        return 12
        ;;
    esac
  fi

  if (( last_ok_epoch > 0 && now_epoch - last_ok_epoch <= grace_seconds )); then
    echo "Server aktuell nicht erreichbar, aber noch in Offline-Grace-Zeit."
    return 0
  fi

  echo "Server nicht erreichbar und keine gültige Grace-Zeit mehr vorhanden."
  return 20
}

self_remove() {
  local reason="${1:-revoked}"
  echo "Entferne nur Paket ${TOOL_NAME} wegen Status: ${reason}"
  sudo apt remove -y "$TOOL_NAME" || true
}

main() {
  ensure_device
  register_if_needed
  check_access
  rc=$?
  case "$rc" in
    0) exit 0 ;;
    10)
      self_remove "revoked"
      exit 10
      ;;
    *)
      exit "$rc"
      ;;
  esac
}

main "$@"
