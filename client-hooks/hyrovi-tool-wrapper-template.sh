#!/usr/bin/env bash
set -Eeuo pipefail
[[ -f /etc/default/hyrovi-tool-auth ]] && source /etc/default/hyrovi-tool-auth || true
/usr/local/lib/hyrovi-auth/hyrovi-auth-guard.sh
exec /usr/local/lib/hyrovi-auth/REAL_HYROVI_TOOL "$@"
