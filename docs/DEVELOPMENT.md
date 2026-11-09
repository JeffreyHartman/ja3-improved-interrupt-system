# Development

## Code layout

| File | What it does |
|---|---|
| `mod/Code/Rules.lua` | The 1.13 formulas. It makes no engine calls. |
| `mod/Code/Memory.lua` | The Watcher memory (counters, Seen this turn, Seen before) and the move plans. It makes no engine calls. |
| `mod/Code/Interrupt.lua` | The interrupters, the action queue of the interrupters, activity, the stuck timer, the End Turn presses and the end decision of the active interrupt. It makes no engine calls. |
| `mod/Code/IIS.lua` | Settings, log, trigger checks and the handler for `"iis"` entries. `IIS.E` holds every engine read, so the tests can replace it. |
| `mod/Code/Control.lua` | `IISControl`: the provoke-list wrapper, Free Move removal, the interrupt run, the end of the interrupt and the Stop. It gives control to the interrupters. |
| `mod/Code/IOS.lua` | `IOS`: the handler for `"overwatch"` entries and the AP pool of each overwatcher. |
| `mod/Code/UI.lua` | Banner, portrait marks, End Turn label, camera and sounds. |
| `mod/Code/MovingTarget.lua` | The "Moving target" to-hit modifier for a shot by an interrupter at the mover. |
| `mod/Code/Aim.lua` | The wrap of `Unit:GetBaseAimLevelRange` that applies the aim limit of the active interrupt. |

`mod/metadata.lua` lists the code files in load order: `Rules.lua`, `Memory.lua`, `Interrupt.lua`, `IIS.lua`, `Control.lua`, `IOS.lua`, `UI.lua`, `MovingTarget.lua`, `Aim.lua`. `IOS.lua` adds its engine reads to `IIS.E` and calls `IISControl.Handle`, so it loads after `Control.lua`. `Control.lua` reads `IIS.E` and the log functions of `IIS.lua` when it loads, so it loads after `IIS.lua`. `IIS.lua` calls `IISControl` only after the code files load. It registers its handler for `"iis"` entries on `ModsReloaded`, which the game sends after it runs the code files of all mods.

The wrapper of `Unit:CheckProvokeOpportunityAttacks` in `IIS.lua` adds an `"iis"` entry to the vanilla interrupt list. It returns nothing for a mover that the Stop stopped. The game then calls `Unit:ProvokeOpportunityAttacksFromList` in the enemy's command thread, and the AI turn waits until the interrupt ends.

The wrapper of `Unit:ProvokeOpportunityAttacksFromList` in `Control.lua` keeps a handler for each entry type. `IISControl.Handle(entry_type, handler)` registers one. The wrapper puts the entries that have a handler in groups. A group holds all entries of one type on one step (`entry[4]`). The `"overwatch"` groups go first, then the `"iis"` groups, then the other types. The list order does not change this order. For each group:

1. `IISControl` checks that the thread can yield, that no interrupt is active, and that the mover is valid, alive and not incapacitated. Thus after an IOS interrupt, the `"iis"` group of the same step starts no interrupt when the overwatchers killed or downed the mover. If a check fails, it logs the skip reason and does not call the handler.
2. `IISControl` calls the handler with the mover, the first entry of the group, the next interrupt number and the list of all entries of the group. An error in the handler is logged, no interrupt starts, and vanilla gets the entries of the group unchanged.
3. The handler returns nothing, or a request. If it returns nothing, no interrupt starts and the interrupt number does not change.
4. A request gives the interrupters (the top interrupter first), the stop step, the Stop decision, the text of the `BEGIN` log line and an optional note for each interrupter.
5. The handler takes each entry of the group whose unit (`entry[2]`) is an interrupter. The wrapper changes the type of a taken entry to `IISControl.HANDLED` (`"iis_handled"`).
6. `IISControl` removes the Free Move AP of each interrupter and runs the interrupt.

A request can also have these fields for each interrupter:

| Field | What it does |
|---|---|
| `ap_grants[unit]` | A raw AP value. At the start, `IISControl` sets the interrupter's AP to the grant. At the end, it puts back the AP that the interrupter had before the grant. It writes `ActionPoints` directly, because `Unit:GainAP` does nothing for a unit on Overwatch. The AP of a queued action that did not start goes back to the grant in the same way. |
| `on_end(ap_left)` | A function. At the end, `IISControl` calls it with the raw AP that each granted interrupter had left. |
| `banner` | A text. The banner shows "`banner`: interrupter names" in place of "INTERRUPT!". |
| `aim_limit` | A percent. The maximum aim level of each interrupter is this percent of the maximum that the game gives, rounded up, and never below the minimum. The `"iis"` handler gives the "Interrupt aim limit" option, and the `"overwatch"` handler gives the "IOS aim limit" option, both read when the interrupt starts. |
| `action_limits[unit]` | A function `limit(action_id, target)`. The `StartCombatAction` override calls it before it takes the AP. When the limit does not return true, or fails, the action does not start and costs no AP. |

The handler for `"iis"` entries is `IIS.InterruptRequest`, the 1.13 trigger adapter in `IIS.lua`. It refuses an entry from an older version, drops the winners that can no longer act, rolls the collective joiners and commits the counters in the Watcher memory. It sends Stop when the "Interrupted enemy" option is "Stop" and the trigger is a move.

The handler for `"overwatch"` entries is `IOS.InterruptRequest` in `IOS.lua`. `IOS.Install` registers it when the IOS option is on, on `ModsReloaded` and when the options change. When the option is off, no handler is registered, and vanilla gets each `"overwatch"` entry unchanged. The handler:

- takes each entry of a merc (a unit of a UI-controlled team) on Overwatch whose pool can pay for one default attack. An entry of an enemy overwatcher goes to vanilla unchanged;
- does the bookkeeping of `Unit:ProvokeOpportunityAttack_Overwatch` without calling it: it adds the mover to the overwatcher's `triggered_by`, removes Hidden from the mover and writes the vanilla combat log line;
- sends a request with each overwatcher's pool as its AP grant, `stop = false` and the banner "Overwatch". The "Interrupted enemy" option does not apply;
- gives each overwatcher an action limit from the "IOS actions" option. With "Shot only", the limit allows a reload, and an attack on an enemy unit that the overwatcher sees (`E.SeesNow`) and that is in its Overwatch cone (`E.InOverwatchCone`, the cone check of `Unit:IsThreatened`). With "Any action", the limit allows every action. An attack is an action of the `WeaponAttacks` or `FiringModeMetaAction` group with a ranged or melee `ActionType`, except the attacks that move the attacker (`MobileShot`, `RunAndGun`, `Charge`, `HyenaCharge`);
- in `on_end`, ends Overwatch with `Unit:InterruptPreparedAttack` when the overwatcher started an action that is not an attack or a reload, such as a move or a stance change. The rest of the pool is lost. Otherwise it stores the AP that each overwatcher has left as its new pool, and sets `num_attacks` to the pool divided by the cost of one default attack, rounded down. The Overwatch marker and RatoAI read `num_attacks`. When the pool cannot pay for one attack, it ends Overwatch with `Unit:InterruptPreparedAttack`. A permanent Overwatch (a set-up machine gun) stays at 0 attacks, as in vanilla.

`IOS.IsOverwatcher(unit)` is true while an IOS interrupt is active and `unit` is one of its overwatchers. The wrapper of `Unit:PrepareAttackArgs` in `IOS.lua` sets `opportunity_attack = true` and `opportunity_attack_type = "Overwatch"` in the attack args of an overwatcher's firearm attack. The crosshair's to-hit preview and `Unit:FirearmAttack` both get their attack args from `Unit:PrepareAttackArgs`, through `CombatAction:GetActionResults`. Thus the Overwatch to-hit modifier, the vanilla crit rule and the Overwatch perks apply to the shot, and under GBO 4 Settled does not. A shot by an IIS or JA2 Classic interrupter does not get the flag. GBO 4 also wraps `Unit:PrepareAttackArgs`, so the load order of the two mods does not matter.

The pool is in the Overwatch state, `g_Overwatch[unit]`, which the game saves. `ios_pool` is the raw AP, and `ios_count` and `ios_turn` are the attack count and the combat turn when IOS stored it. When the game changed the attack count or the turn since then, or when the state has no pool (a save from before IOS), the pool is `num_attacks` multiplied by the cost of one default attack. Thus a set-up machine gun gets its pool from the attack count that the game calculates again at each turn start. The handler gets each cost from `E.AttackCostRaw`, a live game call.

`Aim.lua` wraps `Unit:GetBaseAimLevelRange` on `ModsReloaded`, and `IISControl.Request()` gives it the request of the active interrupt. The wrap calls the function that was in place and changes its result only while an interrupt is active, for an interrupter, when the request has an `aim_limit`. GBO 4 replaces the function when its code loads, and its version calls the vanilla one. Thus, in either load order, the chain is the wrap of this mod, then GBO 4, then vanilla. The wrap checks its identity, so a second `ModsReloaded` does not wrap it again.

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

## Options

`mod/items.lua` has the options, and `mod/metadata.lua` has their defaults in `default_options`. `IIS.lua` reads the options into `IIS.Config` when it loads and on `ApplyModOptions`.

Each option has the color tag of its group in its display name:

| Group | Color tag |
|---|---|
| Interrupt System | `<color AmmoHPColor>` |
| IOS | `<color AmmoMatchColor>` |
| Both systems | `<color AmmoTracerColor>` |

The tags are text styles of the game. GBO 4 and RatoAI use the same text styles for their option groups.

The game does not remove a stored option value when the mod removes the option. Thus the values of version 0.7.3 and earlier stay in the storage:

- `Enabled = false` gives `InterruptSystem = "Off"`.
- `System = "Classic"` gives `InterruptSystem = "JA2 Classic"`.

`IIS.lua` reads these old values only while no `InterruptSystem` value is stored. It then writes the result into the options, so that the options menu shows it and stores it when the player applies a change. For this reason, `default_options` must not give a default for `InterruptSystem`. When you save the mod in the Mod Editor, the Mod Editor writes `default_options` again from the options. Then remove the `InterruptSystem` default by hand. A test in `tests/test_engine.lua` fails until you do.

## Tests

Run `tools/test.sh`. It needs `lua5.4` and `luac5.4`.

- `tests/test_rules.lua` checks the formulas against worked examples from the 1.13 source code.
- `tests/test_memory.lua` checks `IISMemory` with a plain store table.
- `tests/test_interrupt.lua` checks `IISInterrupt` with a fake clock and plain units.
- `tests/test_engine.lua` loads `IIS.lua`, `Control.lua` and `IOS.lua` with fake engine functions and the real `IISMemory` and `IISInterrupt`.
  Its option tests give the options to `IIS.lua` as the game does, and they read `mod/items.lua` and `mod/metadata.lua`.
  Its full interrupt tests go through the provoke-list wrapper. The `sleep` that they give to `IISControl.Setup` advances the game time and runs scripted steps, such as an End Turn press.
- `tests/test_ui.lua` loads `UI.lua` and checks the combat log text at the start and end of an interrupt, and the banner text of a request.
- `tests/test_moving_target.lua` loads `MovingTarget.lua` and calls the `CalcValue` of its to-hit modifier with fake units and an active interrupt.

`tests/test_engine.lua` also loads `Aim.lua`. Its aim limit tests call the wrapped `Unit:GetBaseAimLevelRange` during an IOS or IIS interrupt through the provoke-list wrapper, also over a fake GBO 4 wrap.

The tests do not cover the rest of `UI.lua` or anything that needs the game.

## Testing in the game

`tools/deploy.sh` copies `mod/` to the game's Mods folder. `tools/log.sh -f` follows the game log. Both scripts have the paths of a Steam Proton install on Linux. Change the paths for your system.

For a quick combat test, open the Mod Editor from the main menu. Its Cheats menu has "Place test mercs" and "Spawn enemy". The in-game Esc menu then has Cheats, "Start Combat Now".

## Log

All mod lines in the game log start with `[IIS]`. `tools/log.sh` also shows `[LUA ERROR]` lines with their stack, and mod load errors.

| Line | Meaning |
|---|---|
| `loaded`, `control loaded`, `IOS loaded`, `UI loaded` | The game ran the code files. Each hook status must say `ours`. `IOS loaded` gives the IOS option. |
| `mods loaded` | The title, id and version of each loaded mod. |
| `check #N ... TRIGGER` | A check found winners, with their points (JA2 Classic) or count and reaction time (IIS). |
| `trigger in an AI planning check` | The AI ran the same check to group its units. Nothing happens. |
| `IIS register`, `IIS commit` | A seen enemy action or move added AP to the mercs' counters. |
| `enemy attack exec begin`, `enemy attack exec end` | An enemy firearm attack started or ended. A `begin` without an `end` means that the enemy's command stopped inside the attack. |
| `after-attack check` | The check after an enemy attack, with its result or the reason that it did not run. |
| `INT #N BEGIN`, `INT #N END` | The interrupt started or ended. `END` gives the reason and the AP of each interrupter. An IOS interrupt has the label `IOS overwatch`, and each overwatcher line gives its pool and attack cost. |
| `INT #N overwatcher` | The pool and the attack count of an overwatcher after an IOS interrupt, or the reason that its Overwatch ended. |
| `INT #N ... refused by the action limit` | The interrupter's action limit refused an action, for example a move by an overwatcher with "IOS actions = Shot only". The action did not start and cost no AP. |
| `IOS: overwatcher ... cannot pay for an attack` | The pool of a merc on Overwatch is below the cost of one attack, so vanilla gets its entry. |
| `aim range hook: ours` | `Aim.lua` wrapped `Unit:GetBaseAimLevelRange` on `ModsReloaded`. `REPLACED` means that another mod replaced the wrap. |
| `INT #N aim limit failed` | The aim limit failed with a Lua error. The shot gets the aim range of the game. |
| `INT #- <type> handler failed` | A provoke-list handler failed. Vanilla gets the entries of that group. |
| `INT #N collective` | A collective interrupt roll, or the reason that a teammate did not roll. |
| `INT #N run action`, `action ended` | An interrupter action started or ended. |
| `INT #N waiting` | The state of a waiting interrupt. It is written when the state changes, and every 30 seconds. |
| `INT #N STUCK?` | A merc stayed busy for more than 10 seconds. |
| `INT #N ... failed` | A part of the interrupt failed with a Lua error. The interrupt continues without that part. |
| `stops at`, `re-plans from its tile` | "Stop" mode: the enemy stays on its tile, gets back AP and plans its attacks again. |
| `TurnEnded` | The check counts of the turn, the skip reasons and the IIS counters by session id (`a<-enemy=5`). |
