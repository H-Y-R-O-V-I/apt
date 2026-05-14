#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hyrovi"
DEVICE_FILE="${CONFIG_DIR}/device.json"
AUTH_FILE="${CONFIG_DIR}/auth.json"
SERVER_URL="${HYROVI_SERVER_URL:-}"
DOWNLOAD_DIR="/var/lib/hyrovi/packages"

info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }
fail() { echo "[FEHLER] $1" >&2; exit 1; }

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

[[ -n "$SERVER_URL" ]] || fail "Server-URL fehlt."

device_id="$(json_get "$DEVICE_FILE" device_id)"
token="$(json_get "$AUTH_FILE" token)"

[[ -n "$device_id" ]] || fail "Geräte-ID fehlt."
[[ -n "$token" ]] || fail "Authentifizierungstoken fehlt."

info "Fordere privates Paket an ..."

payload="$(cat <<EOF2
{"device_id":"$device_id","token":"$token"}
EOF2
)"

resp="$(mktemp)"
code="$(curl -sS -o "$resp" -w "%{http_code}" -X POST "${SERVER_URL%/}/api/package/request" -H "Content-Type: application/json" -d "$payload" || echo "000")"
body="$(cat "$resp" 2>/dev/null || true)"
rm -f "$resp"

[[ "$code" == "200" ]] || fail "Paketanforderung fehlgeschlagen."

download_url="$(python3 - "$body" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("download_url",""))
PY
)"
package_name="$(python3 - "$body" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("package_name",""))
PY
)"
sha256_expected="$(python3 - "$body" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("sha256",""))
PY
)"

[[ -n "$download_url" && -n "$package_name" && -n "$sha256_expected" ]] || fail "Ungültige Serverantwort."

info "Lade privates Paket ..."
sudo install -d -m 0755 "$DOWNLOAD_DIR"
sudo curl -fsSL "$download_url" -o "$DOWNLOAD_DIR/$package_name" >/dev/null 2>&1 || fail "Download fehlgeschlagen."

info "Prüfe Paketintegrität ..."
sha256_actual="$(sha256sum "$DOWNLOAD_DIR/$package_name" | awk "{print \$1}")"
[[ "$sha256_actual" == "$sha256_expected" ]] || fail "Integritätsprüfung fehlgeschlagen."

if dpkg -s hyrovi-tool-secure >/dev/null 2>&1; then
  installed_version="$(dpkg-query -W -f='${Version}' hyrovi-tool-secure 2>/dev/null || true)"
else
  installed_version=""
fi

deb_version="$(dpkg-deb -f "$DOWNLOAD_DIR/$package_name" Version 2>/dev/null || true)"

if [[ -n "$installed_version" && -n "$deb_version" && "$installed_version" == "$deb_version" ]]; then
  ok "Privates Tool ist bereits aktuell."
  exit 0
fi

info "Installiere privates Paket ..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y "$DOWNLOAD_DIR/$package_name" >/dev/null 2>&1 || fail "Installation fehlgeschlagen."

ok "Privates Tool wurde erfolgreich installiert."
