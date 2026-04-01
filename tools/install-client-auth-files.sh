#!/usr/bin/env bash
set -Eeuo pipefail

SERVER_URL="${HYROVI_SERVER_URL:-${1:-}}"
TOOL_NAME="${HYROVI_TOOL_NAME:-hyrovi-tool}"
TOOL_VERSION="${HYROVI_TOOL_VERSION:-0.1.0}"
OFFLINE_GRACE_DAYS="${HYROVI_OFFLINE_GRACE_DAYS:-7}"

[[ -n "$SERVER_URL" ]] || { echo "SERVER_URL fehlt"; exit 1; }

sudo mkdir -p /etc/hyrovi
sudo tee /etc/hyrovi/auth.json >/dev/null <<EOF
{"server_url":"${SERVER_URL}","token":""}
EOF
sudo chmod 600 /etc/hyrovi/auth.json

sudo tee /etc/default/hyrovi-tool-auth >/dev/null <<EOF
HYROVI_SERVER_URL=${SERVER_URL}
HYROVI_TOOL_NAME=${TOOL_NAME}
HYROVI_TOOL_VERSION=${TOOL_VERSION}
HYROVI_OFFLINE_GRACE_DAYS=${OFFLINE_GRACE_DAYS}
EOF

echo "Client-Auth-Dateien angelegt."
echo "Jetzt noch ggf. Token nach Approval in /etc/hyrovi/auth.json eintragen."
