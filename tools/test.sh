#!/usr/bin/env bash
# Checks the syntax of the mod's Lua files and runs tests/run.lua outside the game.
set -euo pipefail
cd "$(dirname "$0")/.."

lua="$(command -v lua5.4 || command -v lua)"
luac="$(command -v luac5.4 || command -v luac)"

for f in mod/*.lua mod/Code/*.lua; do
	"$luac" -p "$f"
done
echo "syntax ok: $(ls mod/*.lua mod/Code/*.lua | wc -l) files"
"$lua" tests/run.lua
