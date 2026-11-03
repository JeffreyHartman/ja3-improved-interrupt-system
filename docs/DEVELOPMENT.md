# Development

## Code layout

| File | What it does |
|---|---|
| `mod/Code/Rules.lua` | The 1.13 formulas. It makes no engine calls. |
| `mod/Code/Memory.lua` | The Watcher memory (counters, Seen this turn, Seen before) and the move plans. It makes no engine calls. |
| `mod/Code/Interrupt.lua` | The interrupters, activity, the stuck timer, the End Turn presses and the end decision of the active interrupt. It makes no engine calls. |
| `mod/Code/IIS.lua` | Settings, log and trigger checks. `IIS.E` holds every engine read, so the tests can replace it. |
| `mod/Code/Control.lua` | Runs an interrupt and gives control to the interrupters. |
| `mod/Code/UI.lua` | Banner, portrait marks, End Turn label, camera and sounds. |

The wrapper of `Unit:CheckProvokeOpportunityAttacks` adds an `"iis"` entry to the vanilla interrupt list. The game then calls `Unit:ProvokeOpportunityAttacksFromList` in the enemy's command thread, and the AI turn waits until the interrupt ends.

These overrides change behavior only while an interrupt is active:

| Override | Why |
|---|---|
| `IsNetPlayerTurn` | Returns true. The UI and the action start code ask it whose turn it is. |
| `Unit:CanBeControlled` | True for the interrupters. False, with the reason `iis_not_interrupter`, for the other player units. |
| `CombatActionCannotBeStarted` | Counts only the interrupters' running actions. The frozen enemy's action never ends during the interrupt. |
| `StartCombatAction` | Runs the interrupters' actions in a queue with the vanilla start rule. |
| `Unit:IsIdleOrRunningBehavior` | Returns true for the frozen enemy, because `Unit:FirearmAttack` waits until its target is idle. |
| `WaitOtherCombatActionsEnd` | An interrupter waits only for the other interrupters. |
| `IModeCombatMovement:OnMouseButtonDown` | Sets `g_CurrentTeam` to the player team during the click handler. |
| `NetSyncEvents.EndTurn`, `NetSyncLocalEffects.EndTurn` | End the interrupt instead of the turn. |
| `HUDMercClass.SetupStyle` (in `UI.lua`) | Marks the portraits. |
| `OnMsg.CanSaveGameQuery` | Blocks saves during an interrupt. |

## Tests

Run `tools/test.sh`. It needs `lua5.4` and `luac5.4`.

- `tests/test_rules.lua` checks the formulas against worked examples from the 1.13 source code.
- `tests/test_memory.lua` checks `IISMemory` with a plain store table.
- `tests/test_interrupt.lua` checks `IISInterrupt` with a fake clock and plain units.
- `tests/test_engine.lua` loads `IIS.lua` and `Control.lua` with fake engine functions and the real `IISMemory` and `IISInterrupt`.
- `tests/test_ui.lua` loads `UI.lua` and checks the combat log text for each end reason code.

The tests do not cover the rest of `UI.lua` or anything that needs the game.

## Testing in the game

`tools/deploy.sh` copies `mod/` to the game's Mods folder. `tools/log.sh -f` follows the game log. Both scripts have the paths of a Steam Proton install on Linux. Change the paths for your system.

For a quick combat test, open the Mod Editor from the main menu. Its Cheats menu has "Place test mercs" and "Spawn enemy". The in-game Esc menu then has Cheats, "Start Combat Now".

## Log

All mod lines in the game log start with `[IIS]`. `tools/log.sh` also shows `[LUA ERROR]` lines with their stack, and mod load errors.

| Line | Meaning |
|---|---|
| `loaded`, `control loaded`, `UI loaded` | The game ran the code files. Each hook status must say `ours`. |
| `mods loaded` | The title, id and version of each loaded mod. |
| `check #N ... TRIGGER` | A check found winners, with their points (Classic) or count and reaction time (IIS). |
| `trigger in an AI planning check` | The AI ran the same check to group its units. Nothing happens. |
| `IIS register`, `IIS commit` | A seen enemy action or move added AP to the mercs' counters. |
| `enemy attack exec begin`, `enemy attack exec end` | An enemy firearm attack started or ended. A `begin` without an `end` means that the enemy's command stopped inside the attack. |
| `after-attack check` | The check after an enemy attack, with its result or the reason that it did not run. |
| `INT #N BEGIN`, `INT #N END` | The interrupt started or ended. `END` gives the reason and the AP of each interrupter. |
| `INT #N collective` | A collective interrupt roll, or the reason that a teammate did not roll. |
| `INT #N run action`, `action ended` | An interrupter action started or ended. |
| `INT #N waiting` | The state of a waiting interrupt. It is written when the state changes, and every 30 seconds. |
| `INT #N STUCK?` | A merc stayed busy for more than 10 seconds. |
| `INT #N ... failed` | A part of the interrupt failed with a Lua error. The interrupt continues without that part. |
| `stops at`, `re-plans from its tile` | "Stop" mode: the enemy stays on its tile, gets back AP and plans its attacks again. |
| `TurnEnded` | The check counts of the turn, the skip reasons and the IIS counters by session id (`a<-enemy=5`). |
