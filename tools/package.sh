#!/usr/bin/env bash
# Writes release/dist/ImprovedInterruptSystem-<version>.zip for Nexus Mods, with mod/ as the folder ImprovedInterruptSystem/.
set -euo pipefail
cd "$(dirname "$0")/.."

tools/set-description.py
tools/test.sh >/dev/null

major=$(grep -oP "'version_major', \K[0-9]+" mod/metadata.lua)
minor=$(grep -oP "'version_minor', \K[0-9]+" mod/metadata.lua)
patch=$(grep -oP '^IIS.version = "[0-9]+\.[0-9]+\.\K[0-9]+' mod/Code/IIS.lua)
version="$major.$minor.$patch"

stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
cp -r mod "$stage/ImprovedInterruptSystem"

mkdir -p release/dist
zip_path="$PWD/release/dist/ImprovedInterruptSystem-$version.zip"
rm -f -- "$zip_path"
(cd "$stage" && python3 -m zipfile -c "$zip_path" ImprovedInterruptSystem)
python3 -m zipfile -l "$zip_path"
