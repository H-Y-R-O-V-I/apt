#!/usr/bin/env bash
set -Eeuo pipefail

APT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APT_DIR"

latest_dir="$(find packages -maxdepth 1 -mindepth 1 -type d -name 'hyrovi-tool_*' | sort -V | tail -n 1)"
[[ -n "$latest_dir" ]] || { echo "Kein Paketordner gefunden"; exit 1; }

version="$(basename "$latest_dir" | sed 's/^hyrovi-tool_//')"
deb_path="packages/hyrovi-tool_${version}.deb"

echo "Baue Paket: $deb_path"
dpkg-deb --build "$latest_dir" "$deb_path"

echo "Nehme Paket ins Repo auf"
reprepro -b repo includedeb hyrovi "$deb_path"

echo "Spiegele Repo nach docs/"
rsync -a --delete repo/ docs/
cp public/hyrovi-archive-keyring.gpg docs/ 2>/dev/null || true
cp public/hyrovi-archive-key.asc docs/ 2>/dev/null || true
touch docs/.nojekyll

echo "Fertig. Jetzt noch git add/commit/push."
