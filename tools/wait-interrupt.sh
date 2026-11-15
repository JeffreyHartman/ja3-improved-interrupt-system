#!/usr/bin/env bash
# Ends each player turn in the running debug build until an IIS interrupt is active, through the ja3-play skill.
# Usage: wait-interrupt.sh [-q] [-t SECONDS]
#   -q           quick save at the start of each player turn. This replaces the quick save of the campaign.
#   -t SECONDS   give up after this time, default 480
# Prints "ACTIVE ..." and exits 0, or prints "no combat ..." or "timeout ..." and exits 1.
# Turn on GodMode for player1 first (see the ja3-play reference), or the mercs can die before an interrupt.
set -uo pipefail
S="${JA3_PLAY:-$HOME/.claude/skills/ja3-play}/scripts"

quicksave="" timeout=480
while getopts "qt:" opt; do
	case "$opt" in
		q) quicksave=1 ;;
		t) timeout="$OPTARG" ;;
		*) sed -n '2,6p' "$0" >&2; exit 2 ;;
	esac
done

state='tostring(table.find_value(ModsLoaded, "id", "ImprovedInterruptSystem").env.IISControl.Active() and true)
	.. " team=" .. tostring(g_CurrentTeam and g_Teams[g_CurrentTeam].side)
	.. " combat=" .. tostring(g_Combat and g_Combat.current_turn)'

end=$((SECONDS + timeout))
while ((SECONDS < end)); do
	r=$("$S/lua.py" -e "$state")
	case "$r" in
		"OK true"*) echo "ACTIVE $r"; exit 0 ;;
		*"combat=nil"* | *"combat=false"*) echo "no combat: $r"; exit 1 ;;
		*"team=player1"*)
			if [ -n "$quicksave" ]; then
				"$S/lua.py" -e '(function() QuickSave() return "saved" end)()' >/dev/null
				sleep 6
			fi
			"$S/lua.py" -e '(function() NetSyncEvent("EndTurn", netUniqueId) return "ended" end)()' >/dev/null
			echo "end turn: $r"
			;;
	esac
	sleep 3
done
echo "timeout: $r"
exit 1
