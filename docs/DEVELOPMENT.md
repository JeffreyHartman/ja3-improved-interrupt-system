# Development

## Code layout

| File | What it does |
|---|---|
| `mod/Code/Rules.lua` | The 1.13 formulas. It makes no engine calls. |
| `mod/Code/Memory.lua` | The Watcher memory (counters, Seen this turn, Seen before) and the move plans. It makes no engine calls. |
| `mod/Code/Interrupt.lua` | The interrupters, the action queue of the interrupters, activity, the stuck timer, the End Turn presses and the end decision of the active interrupt. It makes no engine calls. |
| `mod/Code/IIS.lua` | Settings, log, trigger checks and the handler for `"iis"` entries. `IIS.E` holds every engine read, so the tests can replace it. |
| `mod/Code/Control.lua` | `IISControl`: the provoke-list wrapper, Free Move removal, the interrupt run, the end of the interrupt and the Stop. It gives control to the interrupters. |
| `mod/Code/UI.lua` | Banner, portrait marks, End Turn label, camera and sounds. |

`mod/metadata.lua` lists the code files in load order: `Rules.lua`, `Memory.lua`, `Interrupt.lua`, `IIS.lua`, `Control.lua`, `UI.lua`. `Control.lua` reads `IIS.E` and the log functions of `IIS.lua` when it loads, so it loads after `IIS.lua`. `IIS.lua` calls `IISControl` only after the code files load. It registers its handler for `"iis"` entries on `ModsReloaded`, which the game sends after it runs the code files of all mods.

The wrapper of `Unit:CheckProvokeOpportunityAttacks` in `IIS.lua` adds an `"iis"` entry to the vanilla interrupt list. It returns nothing for a mover that the Stop stopped. The game then calls `Unit:ProvokeOpportunityAttacksFromList` in the enemy's command thread, and the AI turn waits until the interrupt ends.

The wrapper of `Unit:ProvokeOpportunityAttacksFromList` in `Control.lua` keeps a handler for each entry type. `IISControl.Handle(entry_type, handler)` registers one. The wrapper puts the entries that have a handler in groups. A group holds all entries of one type on one step (`entry[4]`). The `"overwatch"` groups go first, then the `"iis"` groups, then the other types. The list order does not change this order. For each group:

1. `IISControl` checks that the thread can yield, that no interrupt is active, and that the mover is valid and alive. If a check fails, it logs the skip reason and does not call the handler.
2. `IISControl` calls the handler with the mover, the first entry of the group, the next interrupt number and the list of all entries of the group.
3. The handler returns nothing, or a request. If it returns nothing, no interrupt starts and the interrupt number does not change.
4. A request gives the interrupters (the top interrupter first), the stop step, the Stop decision, the text of the `BEGIN` log line and an optional note for each interrupter.
5. The handler takes each entry of the group whose unit (`entry[2]`) is an interrupter. The wrapper changes the type of a taken entry to `IISControl.HANDLED` (`"iis_handled"`).
6. `IISControl` removes the Free Move AP of each interrupter and runs the interrupt.

A request can also have these fields for each interrupter:

| Field | What it does |
|---|---|
| `ap_grants[unit]` | A raw AP value. At the start, `IISControl` sets the interrupter's AP to the grant. At the end, it puts back the AP that the interrupter had before the grant. It writes `ActionPoints` directly, because `Unit:GainAP` does nothing for a unit on Overwatch. |
| `on_end(ap_left)` | A function. At the end, `IISControl` calls it with the raw AP that each granted interrupter had left. |
| `action_limits[unit]` | A function `limit(action_id, target)`. The `StartCombatAction` override calls it before it takes the AP. When the limit does not return true, or fails, the action does not start and costs no AP. |

The handler for `"iis"` entries is `IIS.InterruptRequest`, the 1.13 trigger adapter in `IIS.lua`. It refuses an entry from an older version, drops the winners that can no longer act, rolls the collective joiners and commits the counters in the Watcher memory. It sends Stop when the "Interrupted enemy" option is "Stop" and the trigger is a move.

When the interrupt starts, `IISControl` takes engine state from the game, and it gives the state back when the interrupt ends. The takeover list in `Control.lua` holds each take together with its give-back: the mover destructor, the visibility override, the camera locks, the AI camera fields and the player control. The start runs the list from the top, and the end runs it from the bottom. An error in one give-back is logged, and the other give-backs still run. The selection and the interface mode are taken but not given back. The counters for the `END` log line are in a separate table.

After the handlers, the wrapper gives the full list to vanilla. Vanilla ignores the `"iis"` and `"iis_handled"` entry types, so it fires no attack for them. It still adds each entry to the mover's `passed_interrupts`, so the unit of a taken entry cannot trigger again in the same mover command. An entry that no handler took, and an entry type with no handler, go to vanilla unchanged.

These overrides change behavior only while an interrupt is active:

| Override | Why |
|---|---|
| `IsNetPlayerTurn` | Returns true. The UI and the action start code ask it whose turn it is. |
| `Unit:CanBeControlled` | True for the interrupters. False, with the reason `iis_not_interrupter`, for the other player units. |
| `CombatActionCannotBeStarted` | Counts only the interrupters' running actions. The frozen enemy's action never ends during the interrupt. |
| `StartCombatAction` | Runs the interrupters' actions in a queue with the vanilla start rule. It refuses an action that the interrupter's action limit refuses. |
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
  Its full interrupt tests go through the provoke-list wrapper. The `sleep` that they give to `IISControl.Setup` advances the game time and runs scripted steps, such as an End Turn press.
- `tests/test_ui.lua` loads `UI.lua` and checks the combat log text at the start and end of an interrupt.

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
