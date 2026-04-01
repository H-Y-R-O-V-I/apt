#!/usr/bin/env bash
set -Eeuo pipefail
sudo install -d -m 0755 /etc/default
sudo tee /etc/default/hyrovi-tool-auth >/dev/null <<EOT
HYROVI_SERVER_URL="https://tool.hyrovi.com"
HYROVI_OFFLINE_GRACE_DAYS="7"
HYROVI_TOOL_NAME="hyrovi-tool"
EOT
echo "Datei geschrieben: /etc/default/hyrovi-tool-auth"
