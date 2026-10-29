#!/usr/bin/env bash
# Copies mod/ into the game's local Mods folder as Mods/Quickdraw.
set -euo pipefail

src="$(cd "$(dirname "$0")/.." && pwd)/mod/"
dest="/mnt/games/SteamLibrary/steamapps/compatdata/1084160/pfx/drive_c/users/steamuser/AppData/Roaming/Jagged Alliance 3/Mods/Quickdraw/"

mkdir -p "$dest"
rsync -a --delete --itemize-changes "$src" "$dest"
echo "Deployed to $dest"
