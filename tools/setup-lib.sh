#!/usr/bin/env bash
set -euo pipefail

readonly HYROVI_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HYROVI_DEVICE_SETUP_DIR="$HYROVI_SETUP_DIR/setup-device"
readonly HYROVI_DEVICE_DEFINITIONS_DIR="$HYROVI_DEVICE_SETUP_DIR/devices"
readonly HYROVI_PROFILE_DEFINITIONS_DIR="$HYROVI_DEVICE_SETUP_DIR/profiles"

readonly HYROVI_BASE_PACKAGES=(
  curl
  wget
  git
  nano
  htop
  jq
  unzip
  zip
  rsync
  ca-certificates
  software-properties-common
  apt-transport-https
  ufw
  fail2ban
)

readonly HYROVI_PYTHON_PACKAGES=(
  python3
  python3-pip
  python3-venv
  build-essential
)

info() { echo "[INFO] $*"; }
ok() { echo "[OK] $*"; }
warn() { echo "[WARNUNG] $*"; }
fail() { echo "[FEHLER] $*" >&2; exit 1; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_privileged() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
    return
  fi

  if command_exists sudo; then
    sudo "$@"
    return
  fi

  fail "Für diesen Schritt werden Root-Rechte benötigt. Bitte als root starten oder sudo installieren."
}

run_logged() {
  local description="$1"
  shift

  local logfile
  logfile="$(mktemp -t hyrovi-tool-setup-XXXXXX.log)"

  info "$description ..."
  if "$@" >"$logfile" 2>&1; then
    rm -f "$logfile"
    return 0
  fi

  warn "Schritt fehlgeschlagen. Details: $logfile"
  return 1
}

apt_update_quiet() {
  run_logged "APT-Paketlisten werden aktualisiert" \
    run_privileged env DEBIAN_FRONTEND=noninteractive apt-get update
}

is_package_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

is_package_available() {
  local candidate
  candidate="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

install_packages() {
  local requested=("$@")
  local missing=()
  local unavailable=()
  local pkg

  for pkg in "${requested[@]}"; do
    if is_package_installed "$pkg"; then
      continue
    fi

    if is_package_available "$pkg"; then
      missing+=("$pkg")
    else
      unavailable+=("$pkg")
    fi
  done

  if (( ${#unavailable[@]} > 0 )); then
    warn "Diese Pakete sind in den aktuellen Quellen nicht verfügbar und werden übersprungen: ${unavailable[*]}"
  fi

  if (( ${#missing[@]} == 0 )); then
    ok "Alle benötigten Pakete sind bereits installiert."
    return 0
  fi

  if ! run_logged "Installiere Pakete: ${missing[*]}" \
    run_privileged env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"; then
    fail "Paketinstallation fehlgeschlagen."
  fi

  ok "Pakete wurden installiert: ${missing[*]}"
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-yes}"
  local suffix
  local reply

  case "$default" in
    yes|y|Y|YES)
      suffix="J/n"
      default="yes"
      ;;
    no|n|N|NO)
      suffix="j/N"
      default="no"
      ;;
    *)
      suffix="j/n"
      default="none"
      ;;
  esac

  while true; do
    read -r -p "[INFO] $prompt [$suffix]: " reply || exit 1
    reply="${reply:-}"
    if [[ -z "$reply" && "$default" != "none" ]]; then
      [[ "$default" == "yes" ]]
      return
    fi

    case "${reply,,}" in
      j|ja|y|yes)
        return 0
        ;;
      n|nein|no)
        return 1
        ;;
    esac

    warn "Bitte mit j oder n antworten."
  done
}

prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  local reply

  if [[ -n "$default" ]]; then
    read -r -p "[INFO] $prompt [$default]: " reply || exit 1
    printf '%s\n' "${reply:-$default}"
    return
  fi

  read -r -p "[INFO] $prompt: " reply || exit 1
  printf '%s\n' "$reply"
}

choose_from_files() {
  local prompt="$1"
  local dir="$2"
  local prefix="$3"

  local -a files=()
  local -a labels=()
  local file

  while IFS= read -r file; do
    files+=("$file")
    unset ITEM_ID ITEM_LABEL
    # shellcheck disable=SC1090
    source "$file"
    labels+=("${ITEM_LABEL:-$(basename "${file%.sh}")}")
  done < <(find "$dir" -maxdepth 1 -type f -name '*.sh' | sort)

  (( ${#files[@]} > 0 )) || fail "Keine Auswahloptionen in $dir gefunden."

  printf '[INFO] %s\n' "$prompt" >&2
  local index=1
  local label
  for label in "${labels[@]}"; do
    printf '[INFO]   %d) %s\n' "$index" "$label" >&2
    index=$((index + 1))
  done

  local selection
  while true; do
    read -r -p "[INFO] $prefix: " selection || exit 1
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#files[@]} )); then
      printf '%s\n' "${files[selection-1]}"
      return 0
    fi
    warn "Bitte eine gültige Nummer auswählen." >&2
  done
}

load_defaults() {
  local device_file="$1"
  local profile_file="$2"

  DEFAULT_SYSTEM_UPDATE=""
  DEFAULT_BASE_PACKAGES=""
  DEFAULT_PYTHON_STACK=""
  DEFAULT_UFW=""
  DEFAULT_FAIL2BAN=""
  DEFAULT_SSH_KEY_CHECK=""
  DEFAULT_DOCKER=""
  DEFAULT_TAILSCALE=""
  DEFAULT_SET_HOSTNAME=""
  DEFAULT_SET_TIMEZONE=""
  DEFAULT_SSH_HARDENING=""

  unset ITEM_ID ITEM_LABEL
  # shellcheck disable=SC1090
  source "$device_file"
  # shellcheck disable=SC1090
  source "$profile_file"
}

normalize_default_choice() {
  local value="${1:-}"
  [[ "$value" == "1" ]] && echo "yes" || echo "no"
}

current_login_user() {
  printf '%s\n' "${SUDO_USER:-${USER:-$(id -un)}}"
}

current_login_home() {
  local user_name
  user_name="$(current_login_user)"
  getent passwd "$user_name" | cut -d: -f6
}

check_ssh_keys() {
  local user_name home_dir key_file
  user_name="$(current_login_user)"
  home_dir="$(current_login_home)"
  key_file="$home_dir/.ssh/authorized_keys"

  info "Prüfe SSH-Key-Setup für Benutzer $user_name ..."
  if [[ -s "$key_file" ]]; then
    ok "SSH-Keys vorhanden in $key_file."
  else
    warn "Keine SSH-Keys in $key_file gefunden."
  fi

  if [[ -s /root/.ssh/authorized_keys ]]; then
    info "Auch für root sind SSH-Keys hinterlegt."
  else
    warn "Für root wurden keine SSH-Keys gefunden."
  fi
}

set_hostname_interactive() {
  local current hostname
  current="$(hostname 2>/dev/null || echo unknown-host)"
  hostname="$(prompt_input "Neuen Hostnamen eingeben" "$current")"

  [[ -n "$hostname" ]] || {
    warn "Hostname leer. Schritt wird übersprungen."
    return 0
  }

  if [[ "$hostname" == "$current" ]]; then
    ok "Hostname bleibt unverändert: $current"
    return 0
  fi

  if command_exists hostnamectl; then
    run_logged "Setze Hostnamen auf $hostname" run_privileged hostnamectl set-hostname "$hostname" \
      || fail "Hostname konnte nicht gesetzt werden."
  else
    fail "hostnamectl ist nicht verfügbar."
  fi

  ok "Hostname wurde auf $hostname gesetzt."
}

timezone_exists() {
  local tz="$1"

  if command_exists timedatectl; then
    timedatectl list-timezones 2>/dev/null | grep -Fx "$tz" >/dev/null 2>&1
    return
  fi

  [[ -e "/usr/share/zoneinfo/$tz" ]]
}

set_timezone_interactive() {
  local current tz
  current="$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo UTC)"
  tz="$(prompt_input "Zeitzone setzen (z. B. Europe/Berlin)" "$current")"

  [[ -n "$tz" ]] || {
    warn "Zeitzone leer. Schritt wird übersprungen."
    return 0
  }

  if ! timezone_exists "$tz"; then
    fail "Unbekannte Zeitzone: $tz"
  fi

  if [[ "$tz" == "$current" ]]; then
    ok "Zeitzone bleibt unverändert: $current"
    return 0
  fi

  if command_exists timedatectl; then
    run_logged "Setze Zeitzone auf $tz" run_privileged timedatectl set-timezone "$tz" \
      || fail "Zeitzone konnte nicht gesetzt werden."
  else
    run_logged "Schreibe Zeitzone nach /etc/timezone" bash -lc \
      "printf '%s\n' '$tz' | $(command -v sudo 2>/dev/null || echo '') tee /etc/timezone >/dev/null" \
      || fail "Zeitzone konnte nicht gesetzt werden."
  fi

  ok "Zeitzone wurde auf $tz gesetzt."
}

configure_fail2ban() {
  install_packages fail2ban

  if command_exists systemctl; then
    run_logged "Aktiviere und starte Fail2ban" \
      run_privileged systemctl enable --now fail2ban \
      || fail "Fail2ban konnte nicht aktiviert werden."
  else
    warn "systemctl ist nicht verfügbar. Bitte Fail2ban manuell starten."
    return 0
  fi

  ok "Fail2ban ist aktiv."
}

configure_ufw() {
  install_packages ufw

  run_logged "Setze UFW Standardregeln" \
    run_privileged bash -lc "ufw default deny incoming && ufw default allow outgoing" \
    || fail "UFW-Standardregeln konnten nicht gesetzt werden."

  run_logged "Erlaube OpenSSH in UFW" run_privileged ufw allow OpenSSH \
    || fail "OpenSSH-Regel konnte nicht gesetzt werden."

  if prompt_yes_no "Soll Port 80/tcp erlaubt werden?" "no"; then
    run_logged "Erlaube 80/tcp in UFW" run_privileged ufw allow 80/tcp \
      || fail "Port 80/tcp konnte nicht freigeschaltet werden."
    ok "Port 80/tcp ist erlaubt."
  fi

  if prompt_yes_no "Soll Port 443/tcp erlaubt werden?" "no"; then
    run_logged "Erlaube 443/tcp in UFW" run_privileged ufw allow 443/tcp \
      || fail "Port 443/tcp konnte nicht freigeschaltet werden."
    ok "Port 443/tcp ist erlaubt."
  fi

  local ufw_status
  ufw_status="$(run_privileged ufw status 2>/dev/null | head -n1 || true)"
  if [[ "$ufw_status" == *"Status: active"* ]]; then
    ok "UFW ist bereits aktiv."
    return 0
  fi

  warn "UFW ist noch nicht aktiviert. Eingehend wird standardmäßig blockiert, ausgehend erlaubt."
  if prompt_yes_no "UFW jetzt wirklich aktivieren?" "no"; then
    run_logged "Aktiviere UFW" run_privileged ufw --force enable \
      || fail "UFW konnte nicht aktiviert werden."
    ok "UFW wurde aktiviert."
  else
    warn "UFW wurde nicht aktiviert."
  fi
}

install_docker_stack() {
  local packages=(docker.io docker-compose-plugin)
  install_packages "${packages[@]}"

  if command_exists systemctl; then
    run_logged "Aktiviere und starte Docker" run_privileged systemctl enable --now docker \
      || fail "Docker konnte nicht aktiviert werden."
  fi

  ok "Docker-Stack ist eingerichtet."
}

install_tailscale_stack() {
  if ! is_package_available tailscale && ! is_package_installed tailscale; then
    warn "Das Paket tailscale ist in den aktuellen APT-Quellen nicht verfügbar."
    warn "Füge bei Bedarf zuerst das offizielle Tailscale-Repository hinzu und starte das Setup danach erneut."
    return 0
  fi

  install_packages tailscale

  if command_exists systemctl; then
    run_logged "Aktiviere und starte tailscaled" run_privileged systemctl enable --now tailscaled \
      || fail "tailscaled konnte nicht aktiviert werden."
  fi

  ok "Tailscale ist installiert."
}

write_sshd_option() {
  local option="$1"
  local value="$2"
  local config="/etc/ssh/sshd_config"
  local tmp_file

  [[ -f "$config" ]] || fail "SSH-Konfiguration $config wurde nicht gefunden."

  tmp_file="$(mktemp)"
  awk -v option="$option" -v value="$value" '
    BEGIN { changed = 0 }
    {
      if ($0 ~ "^[[:space:]]*#?[[:space:]]*" option "([[:space:]]+|$)") {
        if (!changed) {
          print option " " value
          changed = 1
        }
        next
      }
      print
    }
    END {
      if (!changed) {
        print option " " value
      }
    }
  ' "$config" >"$tmp_file"

  if command_exists sshd; then
    run_logged "Prüfe neue SSH-Konfiguration" run_privileged sshd -t -f "$tmp_file" || {
      rm -f "$tmp_file"
      fail "SSH-Konfiguration wäre ungültig. Änderungen werden verworfen."
    }
  fi

  run_logged "Übernehme SSH-Konfiguration: $option $value" \
    run_privileged install -m 600 "$tmp_file" "$config" \
    || {
      rm -f "$tmp_file"
      fail "SSH-Konfiguration konnte nicht geschrieben werden."
    }

  rm -f "$tmp_file"
}

reload_ssh_service() {
  if ! command_exists systemctl; then
    warn "systemctl ist nicht verfügbar. Bitte SSH-Dienst manuell neu laden."
    return 0
  fi

  if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
    run_logged "Lade SSH-Dienst neu" run_privileged systemctl reload ssh \
      || run_logged "Starte SSH-Dienst neu" run_privileged systemctl restart ssh \
      || fail "SSH-Dienst konnte nicht neu geladen werden."
    return 0
  fi

  if systemctl list-unit-files sshd.service >/dev/null 2>&1; then
    run_logged "Lade SSHD-Dienst neu" run_privileged systemctl reload sshd \
      || run_logged "Starte SSHD-Dienst neu" run_privileged systemctl restart sshd \
      || fail "SSHD-Dienst konnte nicht neu geladen werden."
    return 0
  fi

  warn "Kein SSH-Dienst unter systemd gefunden. Bitte Konfiguration manuell übernehmen."
}

offer_ssh_hardening() {
  if ! prompt_yes_no "SSH-Härtung konfigurieren?" "no"; then
    info "SSH-Härtung wird übersprungen."
    return 0
  fi

  check_ssh_keys
  warn "SSH-Härtung verändert die Server-Anmeldung. Falsche Werte können den Fernzugriff blockieren."

  local changed=0
  if prompt_yes_no "Passwort-Login für SSH deaktivieren?" "no"; then
    write_sshd_option "PasswordAuthentication" "no"
    changed=1
  fi

  if prompt_yes_no "Root-Login per SSH deaktivieren?" "no"; then
    write_sshd_option "PermitRootLogin" "no"
    changed=1
  fi

  if (( changed == 0 )); then
    info "Keine SSH-Härtungsänderungen ausgewählt."
    return 0
  fi

  reload_ssh_service
  ok "SSH-Härtung wurde angewendet."
}

upgrade_system() {
  if ! run_logged "Führe System-Upgrade aus" \
    run_privileged env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; then
    fail "System-Upgrade fehlgeschlagen."
  fi

  ok "System wurde aktualisiert."
}
