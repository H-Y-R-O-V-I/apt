#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup-lib.sh"

show_summary() {
  info "Auswahl: Gerätetyp=$1 | Profil=$2"
  info "Geplante Schritte: System aktualisieren=$( [[ "$DO_SYSTEM_UPDATE" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: Standardpakete=$( [[ "$DO_BASE_PACKAGES" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: Python-Stack=$( [[ "$DO_PYTHON_STACK" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: UFW-Firewall=$( [[ "$DO_UFW" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: Fail2ban=$( [[ "$DO_FAIL2BAN" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: SSH-Key-Prüfung=$( [[ "$DO_SSH_KEY_CHECK" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: Docker=$( [[ "$DO_DOCKER" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: Tailscale=$( [[ "$DO_TAILSCALE" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: Hostname setzen=$( [[ "$DO_SET_HOSTNAME" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: Zeitzone setzen=$( [[ "$DO_SET_TIMEZONE" == "1" ]] && echo Ja || echo Nein )"
  info "Geplante Schritte: SSH-Härtung=$( [[ "$DO_SSH_HARDENING" == "1" ]] && echo Ja || echo Nein )"
}

configure_components() {
  DO_SYSTEM_UPDATE="$(prompt_yes_no "System aktualisieren?" "$(normalize_default_choice "$DEFAULT_SYSTEM_UPDATE")" && echo 1 || echo 0)"
  DO_BASE_PACKAGES="$(prompt_yes_no "Standardpakete installieren?" "$(normalize_default_choice "$DEFAULT_BASE_PACKAGES")" && echo 1 || echo 0)"
  DO_PYTHON_STACK="$(prompt_yes_no "Python, pip und venv installieren?" "$(normalize_default_choice "$DEFAULT_PYTHON_STACK")" && echo 1 || echo 0)"
  DO_UFW="$(prompt_yes_no "UFW-Firewall konfigurieren?" "$(normalize_default_choice "$DEFAULT_UFW")" && echo 1 || echo 0)"
  DO_FAIL2BAN="$(prompt_yes_no "Fail2ban aktivieren?" "$(normalize_default_choice "$DEFAULT_FAIL2BAN")" && echo 1 || echo 0)"
  DO_SSH_KEY_CHECK="$(prompt_yes_no "SSH-Key-Setup prüfen?" "$(normalize_default_choice "$DEFAULT_SSH_KEY_CHECK")" && echo 1 || echo 0)"
  DO_DOCKER="$(prompt_yes_no "Docker installieren?" "$(normalize_default_choice "$DEFAULT_DOCKER")" && echo 1 || echo 0)"
  DO_TAILSCALE="$(prompt_yes_no "Tailscale installieren?" "$(normalize_default_choice "$DEFAULT_TAILSCALE")" && echo 1 || echo 0)"
  DO_SET_HOSTNAME="$(prompt_yes_no "Hostname setzen?" "$(normalize_default_choice "$DEFAULT_SET_HOSTNAME")" && echo 1 || echo 0)"
  DO_SET_TIMEZONE="$(prompt_yes_no "Zeitzone setzen?" "$(normalize_default_choice "$DEFAULT_SET_TIMEZONE")" && echo 1 || echo 0)"
  DO_SSH_HARDENING="$(prompt_yes_no "SSH-Härtung anbieten?" "$(normalize_default_choice "$DEFAULT_SSH_HARDENING")" && echo 1 || echo 0)"
}

main() {
  info "Interaktives Geräte-Setup für neue Systeme."
  warn "Destruktive Firewall- oder SSH-Änderungen werden nur nach expliziter Bestätigung angewendet."

  local device_file profile_file device_label profile_label
  device_file="$(choose_from_files "Gerätetyp auswählen:" "$HYROVI_DEVICE_DEFINITIONS_DIR" "Gerät")"
  unset ITEM_ID ITEM_LABEL
  # shellcheck disable=SC1090
  source "$device_file"
  device_label="$ITEM_LABEL"

  profile_file="$(choose_from_files "Profil auswählen:" "$HYROVI_PROFILE_DEFINITIONS_DIR" "Profil")"
  unset ITEM_ID ITEM_LABEL
  # shellcheck disable=SC1090
  source "$profile_file"
  profile_label="$ITEM_LABEL"

  load_defaults "$device_file" "$profile_file"
  configure_components

  show_summary "$device_label" "$profile_label"

  if ! prompt_yes_no "Setup mit diesen Optionen starten?" "yes"; then
    fail "Setup wurde abgebrochen."
  fi

  if (( DO_SYSTEM_UPDATE == 1 || DO_BASE_PACKAGES == 1 || DO_PYTHON_STACK == 1 || DO_DOCKER == 1 || DO_TAILSCALE == 1 )); then
    apt_update_quiet || fail "APT-Paketlisten konnten nicht aktualisiert werden."
  fi

  if (( DO_SYSTEM_UPDATE == 1 )); then
    upgrade_system
  fi

  if (( DO_BASE_PACKAGES == 1 )); then
    install_packages "${HYROVI_BASE_PACKAGES[@]}"
  fi

  if (( DO_PYTHON_STACK == 1 )); then
    install_packages "${HYROVI_PYTHON_PACKAGES[@]}"
  fi

  if (( DO_UFW == 1 )); then
    configure_ufw
  fi

  if (( DO_FAIL2BAN == 1 )); then
    configure_fail2ban
  fi

  if (( DO_SSH_KEY_CHECK == 1 )); then
    check_ssh_keys
  fi

  if (( DO_DOCKER == 1 )); then
    install_docker_stack
  fi

  if (( DO_TAILSCALE == 1 )); then
    install_tailscale_stack
  fi

  if (( DO_SET_HOSTNAME == 1 )); then
    set_hostname_interactive
  fi

  if (( DO_SET_TIMEZONE == 1 )); then
    set_timezone_interactive
  fi

  if (( DO_SSH_HARDENING == 1 )); then
    offer_ssh_hardening
  fi

  ok "Geräte-Setup abgeschlossen."
}

main "$@"
