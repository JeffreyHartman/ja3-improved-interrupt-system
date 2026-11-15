# An enemy interrupt ends the merc's command and runs the AI in its own thread

An enemy interrupt stops the merc and ends its command. Then a new game-time thread calls `AIExecutionController:Execute` for the AI interrupters. A player interrupt pauses the enemy mover's command thread and waits in it, but an enemy interrupt cannot do that: the AI controller waits until every unit is idle (`WaitAllCombatActionsEnd`, `WaitUnitsInIdle`), and a paused merc stays in `CombatGoto`, so the two threads wait for each other.

## Considered Options

- **Run `Execute` in the paused merc's command thread:** a playtest on 2026-11-15 deadlocked. It worked only when the mod cleared `CombatActions_RunningState[merc]` and made `IsIdleCommand` return true on the merc. That hack shows a false state to every AI wait. We did not choose it.

## Consequences

- The merc does not continue its action after an enemy interrupt. It stays on its tile and gets back the AP for the rest of its path.
- The mod must block player orders from the end of the merc's command until `Execute` sets `is_player_control` to false.
- Vanilla calls `Execute` in the player turn only for a reposition (`UnitAwareness.lua:634`, `UnitActions.lua:2537`). A full AI turn in the player turn worked in the playtest with no change to `g_CurrentTeam`.
