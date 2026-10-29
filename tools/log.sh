#!/usr/bin/env bash
# Prints [Quickdraw] lines, Lua errors with their stack lines, and mod load errors
# from the newest game log.
# Usage: log.sh        print what is in the log now
#        log.sh -f     follow the log while the game runs
#        log.sh -a     print the whole newest log, unfiltered
set -euo pipefail

logs="/mnt/games/SteamLibrary/steamapps/compatdata/1084160/pfx/drive_c/users/steamuser/AppData/Roaming/Jagged Alliance 3/logs"
newest="$(ls -t "$logs"/JA3.exe-*.log | head -1)"

# Stack lines after [LUA ERROR] start with two spaces. A mod load error puts the message on the next line.
filter='
	/\[Quickdraw\]/ { print; fflush(); stack = 0; next }
	/\[LUA ERROR\]/ { print; fflush(); stack = 1; next }
	/Errors while loading mod/ { print; fflush(); stack = 0; modline = 1; next }
	modline { print; fflush(); modline = 0; next }
	stack && /^  / { print; fflush(); next }
	{ stack = 0 }
'

echo "== $newest" >&2
case "${1:-}" in
	-f) tail -n +1 -F "$newest" | awk "$filter" ;;
	-a) cat "$newest" ;;
	*)  awk "$filter" "$newest" ;;
esac
