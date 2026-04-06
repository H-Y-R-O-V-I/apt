#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'EOT'
hyrovi-tool 0.2.5

Verwendung:
  hyrovi-tool help
  hyrovi-tool version
  hyrovi-tool update

Commands:
  help       Zeigt diese Hilfe
  version    Zeigt die aktuelle Version
  update     Aktualisiert hyrovi-tool ueber APT
EOT
}

case "${1:-help}" in
  help|-h|--help)
    show_help
    ;;
  version|-v|--version)
    echo "0.2.5"
    ;;
  update)
    echo "[INFO] Starte Update fuer hyrovi-tool ..."
    sudo apt update
    sudo apt install --only-upgrade -y hyrovi-tool
    echo "[OK] Update abgeschlossen."
    ;;
  *)
    echo "[FEHLER] Unbekannter Befehl: $1" >&2
    echo
    show_help
    exit 1
    ;;
esac
