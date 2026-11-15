# An enemy interrupt runs the AI in its own thread

An enemy interrupt does not wait in the merc's command thread. The order is:

1. `RunEnemy` makes the interrupt active. From now on the mod blocks player orders.
2. The "Enemy Interrupt" banner shows.
3. If the merc moves, the mod stops it. The command of a merc that attacks ends by itself, so the mod does not stop it.
4. A new game-time thread calls `AIExecutionController:Execute` for the AI interrupters.
 A player interrupt pauses the enemy mover's command thread and waits in it, but an enemy interrupt cannot do that: the AI controller waits until every unit is idle (`WaitAllCombatActionsEnd`, `WaitUnitsInIdle`), and a paused merc stays in `CombatGoto`, so the two threads wait for each other.

## Considered Options

- **Run `Execute` in the paused merc's command thread:** a playtest on 2026-11-15 deadlocked. It worked only when the mod cleared `CombatActions_RunningState[merc]` and made `IsIdleCommand` return true on the merc. That hack shows a false state to every AI wait. We did not choose it.

## Consequences

- A merc that moves does not continue its move after an enemy interrupt. It stays on its tile and gets back the AP for the rest of its path.
- A merc that attacks finishes the attack. The AI runs while the command of the merc ends, or after it.
- The mod blocks player orders from the start of the interrupt, in the merc's command thread, until the interrupt ends.
- Vanilla calls `Execute` in the player turn only for a reposition (`UnitAwareness.lua:634`, `UnitActions.lua:2537`). A full AI turn in the player turn worked in the playtest with no change to `g_CurrentTeam`.
