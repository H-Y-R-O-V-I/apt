#!/usr/bin/env bash
set -Eeuo pipefail
APT_DIR="${APT_DIR:-$HOME/programmieren/apt}"
cd "$APT_DIR"

if tty -s; then
  export GPG_TTY
  GPG_TTY="$(tty)"
fi

if [[ -f repo/db/lockfile ]] && ! pgrep -af "reprepro .*$(pwd)/repo|reprepro -b repo" >/dev/null 2>&1; then
  echo "Entferne verwaistes reprepro-Lockfile"
  rm -f repo/db/lockfile
fi

pkg_dir="$(find packages -maxdepth 1 -mindepth 1 -type d -name 'hyrovi-tool_*' | sort -V | tail -n1)"
[[ -n "$pkg_dir" ]] || { echo "Kein Paketordner gefunden"; exit 1; }

mkdir -p \
  "$pkg_dir/usr/bin" \
  "$pkg_dir/usr/local/lib/hyrovi-auth" \
  "$pkg_dir/usr/local/lib/hyrovi-auth/setup-device/devices" \
  "$pkg_dir/usr/local/lib/hyrovi-auth/setup-device/profiles" \
  "$pkg_dir/etc/default"

cp tools/hyrovi-tool-real.sh "$pkg_dir/usr/local/lib/hyrovi-auth/REAL_HYROVI_TOOL"
cp tools/setup-lib.sh "$pkg_dir/usr/local/lib/hyrovi-auth/setup-lib.sh"
cp tools/setup-device.sh "$pkg_dir/usr/local/lib/hyrovi-auth/setup-device.sh"
cp tools/install-secure-package.sh "$pkg_dir/usr/local/lib/hyrovi-auth/install-secure-package.sh"
cp tools/setup-device/devices/*.sh "$pkg_dir/usr/local/lib/hyrovi-auth/setup-device/devices/"
cp tools/setup-device/profiles/*.sh "$pkg_dir/usr/local/lib/hyrovi-auth/setup-device/profiles/"

cp client-hooks/hyrovi-tool-wrapper-template.sh "$pkg_dir/usr/bin/hyrovi-tool"
cp tools/hyrovi-auth-guard.sh "$pkg_dir/usr/local/lib/hyrovi-auth/hyrovi-auth-guard.sh"

cat > "$pkg_dir/etc/default/hyrovi-tool-auth" <<EOT
HYROVI_SERVER_URL="https://tool.hyrovi.com"
HYROVI_OFFLINE_GRACE_DAYS="7"
HYROVI_TOOL_NAME="hyrovi-tool"
EOT

chmod +x \
  "$pkg_dir/usr/bin/hyrovi-tool" \
  "$pkg_dir/usr/local/lib/hyrovi-auth/REAL_HYROVI_TOOL" \
  "$pkg_dir/usr/local/lib/hyrovi-auth/hyrovi-auth-guard.sh" \
  "$pkg_dir/usr/local/lib/hyrovi-auth/install-secure-package.sh" \
  "$pkg_dir/usr/local/lib/hyrovi-auth/setup-lib.sh" \
  "$pkg_dir/usr/local/lib/hyrovi-auth/setup-device.sh" \
  "$pkg_dir/usr/local/lib/hyrovi-auth/setup-device/devices/"*.sh \
  "$pkg_dir/usr/local/lib/hyrovi-auth/setup-device/profiles/"*.sh

deb_path="${pkg_dir}.deb"
echo "Baue Paket: $deb_path"
dpkg-deb --build "$pkg_dir" "$deb_path"

echo "Nehme Paket ins Repo auf"
pkg_name="$(dpkg-deb -f "$deb_path" Package)"
reprepro -b repo remove hyrovi "$pkg_name" || true
reprepro -b repo includedeb hyrovi "$deb_path"

echo "Aktualisiere docs/"
rsync -a --delete repo/ docs/
cp public/hyrovi-archive-keyring.gpg docs/ 2>/dev/null || true
cp public/hyrovi-archive-key.asc docs/ 2>/dev/null || true
touch docs/.nojekyll

echo "Fertig."
