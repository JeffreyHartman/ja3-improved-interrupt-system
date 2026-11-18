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
| `mod/Code/Aim.lua` | The wrap of `Unit:GetBaseAimLevelRange` that applies the free aim levels and the aim limit of the active interrupt. |

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
| `on_end(ap_left, started)` | A function. At the end, `IISControl` calls it with the raw AP that each granted interrupter had left, and the list of the action IDs that each interrupter started. A queued action that did not start is not in the list. |
| `banner` | A text. The banner shows "`banner`: interrupter names" in place of "INTERRUPT!". |
| `aim_limit` | A percent. The maximum aim level of each interrupter is this percent of the maximum that the game gives, rounded up, and never below the minimum. The `"iis"` and `"iis_enemy"` handlers give the "Interrupt aim limit" option, and the `"overwatch"` handler gives the "IOS aim limit" option, both read when the interrupt starts. |
| `free_aim` | A function `free_aim(unit, action, target)` that returns a number of aim levels. The minimum aim level of each interrupter is at least this number, and never above the maximum that the game gives. The levels up to the minimum cost no AP, because `Unit:GetAttackAPCost` charges only for the levels above the minimum. The `"overwatch"` handler gives the higher of the "IOS free aim levels" option, read when the interrupt starts, and the Killzone value. |
| `action_limits[unit]` | A function `limit(action_id, target)`. The `StartCombatAction` override calls it before it takes the AP. When the limit does not return true, or fails, the action does not start and costs no AP. |

The handler for `"iis"` entries is `IIS.InterruptRequest`, the 1.13 trigger adapter in `IIS.lua`. It refuses an entry from an older version, drops the winners that can no longer act, rolls the collective joiners and commits the counters in the Watcher memory. It sends Stop when the "Interrupted enemy" option is "Stop" and the trigger is a move. A merc on Overwatch (`E.Overwatch`) never wins and never joins, also when it has AP.

### Enemy interrupts

When the mover is a merc in the player turn and the "Enemy interrupts" option is on, `IIS.Watchers` gives the AI units (`E.AIUnits`), and the checks use the same rules as for a merc watcher. `IIS.ObserverSkipReason` refuses neutral units (`E.IsNeutral`) and units that are not hostile to the merc, such as militia and AI allies. A win adds an `"iis_enemy"` entry. `IIS.InterruptRequest` handles it too, and its request has `enemy = true` and no collective joiners.

For a request with `enemy = true`, `IISControl` does not wait in the merc's command thread (ADR 0003). It makes the Enemy interrupt the active interrupt, and it stops the merc if the merc moves (the command of a merc that attacks ends by itself). Then it starts a game-time thread that calls `IISControl.RunEnemyAI`. That function calls `E.RunAI(units, camera_obj)`, which runs `AIExecutionController:Execute` for the interrupters that can act, and then ends the interrupt with the reason `ai_done`. A second thread (`IISControl.WatchEnemyAI`) ends the interrupt with the reason `ai_timeout` after `enemy_ai_timeout_ms` (45 s of game time) and calls `E.StopAI`. The tests replace `E.RunAI` with a fake, and they call the real `E.RunAI` and `E.StopAI` with a fake AI controller. `Interrupt:IsEnemy()` is true for an Enemy interrupt. The overrides that give the engine to merc interrupters apply only to a Player interrupt. During an Enemy interrupt, no player unit can be controlled or start an action, and End Turn does nothing. `OnMsg.CanSaveGameQuery` blocks saves, and a load ends the interrupt with the reason `load`, so the AI does not run.

The interrupt shows the banner "Enemy Interrupt" (`UI.BeginEnemy`, `UI.EndEnemy`). At the end, `EndInterrupt` selects the interrupted merc again when it is valid, alive and not down. The AI run can change the selection.

In JA2 Classic, an enemy gets its point for a team that saw the merc (`E.TeamSees`). A merc's attack causes the after-attack check in IIS and in JA2 Classic. The interrupt after an attack does not stop the merc, because the request sets `stop` only for a move. In IIS, a merc's actions register AP only when the "Enemy interrupts" option is on. Collective joiners of an enemy winner must be on its team, and the interrupter list can hold more than one unit. The moving-target penalty applies to an enemy interrupter's shot too.

An enemy that is on Overwatch and triggers on the same step as an enemy interrupt fires first, and the log says "same step as vanilla X, vanilla runs first". A merc that the Overwatch downs gets no interrupt.

When `AIExecutionController:Execute` fails, `E.RunAI` calls `E.StopAI`, and the interrupt ends with the reason `ai_error`. `E.StopAI` removes the AI controller, turns the camera back to the merc and gives control back to the player. At the time-out, the mod also sends each interrupter that still runs a command to `Idle` ("sending X to Idle"). In IIS, the move of an interrupter registers the AP of each step with the mercs that see it, but its check starts no interrupt. Vanilla gives 0 AP at the turn start to a unit whose Overwatch has not expired, and an Overwatch from the player turn expires one combat turn later. Thus at the end of an Enemy interrupt, the Overwatch of each interrupter expires at its next turn start ("Overwatch ends at its next turn start"), and the AP that it spent does not come out of its next turn.

The handler for `"overwatch"` entries is `IOS.InterruptRequest` in `IOS.lua`. `IOS.Install` registers it when the IOS option is on, on `ModsReloaded` and when the options change. When the option is off, no handler is registered, and vanilla gets each `"overwatch"` entry unchanged. The handler:

- takes each entry of a merc (a unit of a UI-controlled team) on Overwatch whose pool can pay for one default attack. An entry of an enemy overwatcher goes to vanilla unchanged;
- does the bookkeeping of `Unit:ProvokeOpportunityAttack_Overwatch` without calling it: it adds the mover to the overwatcher's `triggered_by`, removes Hidden from the mover and writes the vanilla combat log line;
- sends a request with each overwatcher's pool as its AP grant, `stop = false` and the banner "Overwatch". The "Interrupted enemy" option does not apply;
- gives each overwatcher an action limit from the "IOS actions" option. With "Shot only", the limit allows a reload and an attack on an enemy unit. The overwatcher must see that unit (`E.SeesNow`). The unit must also be in the Overwatch cone of the overwatcher (`E.InOverwatchCone`). `E.InOverwatchCone` calls the vanilla `target:IsThreatened({ overwatcher }, "overwatch")`, as the vanilla AI does. With "Any action", the limit allows every action. An attack is an action of the `WeaponAttacks` or `FiringModeMetaAction` group with a ranged or melee `ActionType`. The attacks that move the attacker (`MobileShot`, `RunAndGun`, `Charge`, `HyenaCharge`) are not attacks for this rule;
- in `on_end`, ends Overwatch with `Unit:InterruptPreparedAttack` when the overwatcher started an action that is not an attack or a reload, such as a move or a stance change. A queued action that did not start does not end Overwatch. The rest of the pool is lost. Otherwise it stores the AP that each overwatcher has left as its new pool, and sets `num_attacks` to the pool divided by the cost of one default attack, rounded down. The Overwatch marker and RatoAI read `num_attacks`. When the pool cannot pay for one attack, it ends Overwatch with `Unit:InterruptPreparedAttack`. A permanent Overwatch (a set-up machine gun) stays at 0 attacks, as in vanilla.

`IOS.IsOverwatcher(unit)` is true while an IOS interrupt is active and `unit` is one of its overwatchers. `IOS.lua` wraps `Unit:PrepareAttackArgs` on `ModsReloaded`. The wrap sets `opportunity_attack = true` and `opportunity_attack_type = "Overwatch"` in the attack args of an overwatcher's firearm attack. The crosshair's to-hit preview and `Unit:FirearmAttack` both get their attack args from `Unit:PrepareAttackArgs`, through `CombatAction:GetActionResults`. Thus the Overwatch to-hit modifier, the vanilla crit rule and the Overwatch perks apply to the shot, and under GBO 4 Settled does not. A shot by an IIS or JA2 Classic interrupter does not get the flag. GBO 4 wraps `Unit:PrepareAttackArgs` when its code loads. Thus, in either load order, the chain is the wrap of this mod, then GBO 4, then vanilla, and the GBO 4 wrap does not see the flag. The wrap checks its identity, so a second `ModsReloaded` does not wrap it again.

Under GBO 4 in old CTH mode, the `CalcValue` of the `Aim` to-hit modifier halves the aim bonus of an opportunity attack. GBO 4 sets that `CalcValue` in its function `aim_cth` on `DataLoaded`. When `aim_cth` exists, `IOS.lua` wraps that `CalcValue` on `DataLoaded`, on `ModsReloaded` and when the options change. When the "IOS full aim under GBO 4" option is on and the attacker is an overwatcher, the wrapper calls the original with `opportunity_attack = false`. The attack args keep the flag, so the other to-hit modifiers and the Overwatch perks still see an opportunity attack. In aCTH mode, the GBO 4 `Aim` modifier does not apply, so the option has no effect.

The pool is in the Overwatch state, `g_Overwatch[unit]`. `g_Overwatch` is a MapVar, and the game does not save it. After a load, the game builds `g_Overwatch[unit]` again from the saved Overwatch command arguments (`combat_behavior_params[3]`), without the IOS fields. Thus `IOS.StorePool` writes the IOS fields to both tables, and `IOS.Pool` reads the saved arguments when the state has no pool. `ios_pool` is the raw AP, and `ios_count` and `ios_turn` are the attack count and the combat turn when IOS stored it. When the game changed the attack count or the turn since then, or when neither table has a pool (an old save), the pool is `num_attacks` multiplied by the cost of one default attack. Thus a set-up machine gun gets its pool from the attack count that the game calculates again at each turn start. The handler gets each cost from `E.AttackCostRaw`, a live game call.

`Aim.lua` wraps `Unit:GetBaseAimLevelRange` on `ModsReloaded`, and `IISControl.Request()` gives it the request of the active interrupt. The wrap calls the function that was in place and changes its result only while an interrupt is active, for an interrupter, when the request has an `aim_limit` or a `free_aim`. It raises the minimum first, then it lowers the maximum. GBO 4 replaces the function when its code loads, and its version calls the vanilla one. Thus, in either load order, the chain is the wrap of this mod, then GBO 4, then vanilla. The wrap checks its identity, so a second `ModsReloaded` does not wrap it again.

The Killzone value of an overwatcher is the result of the GBO 4 function `Rat_KillzoneAim` with the aim 0, when that global exists. The mod finds GBO 4 by this function, so the load order does not matter. Without GBO 4, the value is 1 for a merc with the Killzone perk and 0 for other mercs. `Rat_KillzoneAim` calls `Unit:GetBaseAimLevelRange`, and that call gets no Killzone value, so the wrap does not call itself without end. `Unit:GetAttackAPCost` gives the weapon as the target, so for a target that is not a unit, the Killzone value uses the target of the open crosshair of the overwatcher (`E.CrosshairTarget`). The crosshair computes the AP cost of the shot, so the cost matches the free levels that it shows. Without a crosshair, for example in the AP cost of an action button before the player aims, the target is the mover. Thus that cost can differ from the cost in the crosshair for a shot at another unit. The GBO 4 Shooting Stance is already in the minimum that the game gives, so it counts toward the free aim levels.

When the interrupt starts, `IISControl` takes engine state from the game, and it gives the state back when the interrupt ends. The takeover list in `Control.lua` holds each take together with its give-back: the mover destructor, the visibility override, the camera locks, the AI camera fields and the player control. The start runs the list from the top, and the end runs it from the bottom. An error in one give-back is logged, and the other give-backs still run. The selection and the interface mode are taken but not given back. The counters for the `END` log line are in a separate table.

After the handlers, the wrapper gives the full list to vanilla. Vanilla ignores the `"iis"` and `"iis_handled"` entry types, so it fires no attack for them. It still adds each entry to the mover's `passed_interrupts`, so the unit of a taken entry cannot trigger again in the same mover command. An entry that no handler took, and an entry type with no handler, go to vanilla unchanged.

These overrides change behavior only while an interrupt is active:

| Override | Why |
|---|---|
| `IsNetPlayerTurn` | Returns true. The UI and the action start code ask it whose turn it is. |
| `Unit:CanBeControlled` | True for the interrupters. False, with the reason `iis_not_interrupter`, for the other player units. During an Enemy interrupt it is false for every player unit, with the reason `iis_enemy_interrupt`. |
| `CombatActionCannotBeStarted` | Counts only the interrupters' running actions. The frozen enemy's action never ends during the interrupt. |
| `StartCombatAction` | Runs the interrupters' actions in a queue with the vanilla start rule. It refuses an action that the interrupter's action limit refuses. During an Enemy interrupt it refuses every action of a player unit and logs `refused: enemy interrupt`. |
| `Unit:IsIdleOrRunningBehavior` | Returns true for the frozen enemy, because `Unit:FirearmAttack` waits until its target is idle. |
| `WaitOtherCombatActionsEnd` | An interrupter waits only for the other interrupters. |
| `IModeCombatMovement:OnMouseButtonDown` | Sets `g_CurrentTeam` to the player team during the click handler. |
| `NetSyncEvents.EndTurn`, `NetSyncLocalEffects.EndTurn` | End a Player interrupt instead of the turn. During an Enemy interrupt they do nothing and log `End Turn ignored: enemy interrupt`. |
| `HUDMercClass.SetupStyle` (in `UI.lua`) | Marks the portraits. |
| `OnMsg.CanSaveGameQuery` | Blocks saves during an interrupt. |
| `Unit:OnDie` | Logs `unit died` or `unit downed`, then calls vanilla. Behavior does not change. |

A load during an interrupt ends the interrupt with the reason `load`. `CanLoadGame` does not ask the mod, so `OnMsg.DoneMap` ends the interrupt before the map closes. It runs outside the mover's command thread, so the mover destructor stays on the old mover. A map change without a load gives the reason `map_change`. The end skips the Stop of the mover.

## Options

`mod/items.lua` has the options, and `mod/metadata.lua` has their defaults in `default_options`. `IIS.lua` reads the options into `IIS.Config` when it loads and on `ApplyModOptions`.

Each option has the color tag of its group in its display name:

| Group | Color tag |
|---|---|
| Interrupt System | `<color AmmoHPColor>` |
| IOS | `<color AmmoMatchColor>` |
| Both systems | `<color AmmoTracerColor>` |

The tags are text styles of the game. GBO 4 and RatoAI use the same text styles for their option groups.

The game does not remove a stored option value when the mod removes the option. Thus the values of version 0.7.4 and earlier stay in the storage:

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

`tests/test_engine.lua` also loads `Aim.lua`. Its aim limit and free aim tests call the wrapped `Unit:GetBaseAimLevelRange` during an IOS or IIS interrupt through the provoke-list wrapper, also over a fake GBO 4 wrap, Shooting Stance and Killzone ladder.

The tests do not cover the rest of `UI.lua` or anything that needs the game.

## Testing in the game

`tools/deploy.sh` copies `mod/` to the game's Mods folder. It has the paths of a Steam Proton install on Linux. Change the paths for your system.

To read the game log, use `scripts/log.sh` of the [ja3-play](https://github.com/JeffreyHartman/ja3-play) skill with the IIS tag: `log.sh -x 'collective=' '\[IIS\]|\[PROBE\]'`. Add `-f` to follow the log. It reads the log of the debug build and of the retail build. `-x 'collective='` drops the option dump that the mod writes after each load.

An agent drives the debug build with the `ja3-play` skill. To play fights with its auto-player, run `tools/autoplay-iis.lua` with the skill's `lua.py` once after each launch, then the skill's `lua/autoplay.lua`. The hook file lets the auto-player act in IIS interrupts and adds the IIS win check to its enemy AP line. `tools/wait-interrupt.sh` ends each player turn until an IIS interrupt starts. Its `-q` option quick saves at the start of each player turn, for a load test during an interrupt.

For a quick combat test, open the Mod Editor from the main menu. Its Cheats menu has "Place test mercs" and "Spawn enemy". The in-game Esc menu then has Cheats, "Start Combat Now".

## Log

All mod lines in the game log start with `[IIS]` and the level of the line: `[IIS] [ERROR]`, `[IIS] [INFO]` or `[IIS] [DEBUG]`. The `log.sh` of the skill also shows `[LUA ERROR]` lines with their stack, and mod load errors.

The "Log level" option sets which lines the mod writes. Each level also writes the lines of the levels before it:

| Level | Lines |
|---|---|
| `Error` (default) | A part of the mod failed: `... failed`, `STUCK?`, `handler failed`, `log format error`. |
| `Info` | The checks and interrupts: `TRIGGER`, `INT #N BEGIN`/`END`, skip reasons, `stops at`, `TurnStart`, `AP/max AP at turn start`, `TurnEnded` and `IIS counters at turn end`. |
| `Debug` | All lines: `IIS register`/`commit`, the line for each watcher of a check, the skip counts and action counts of a turn, `waiting`, `run action`, AI camera tracking, the UI lines. |

The identity lines show at every level with the tag `[INFO]`: `loaded`, `control loaded`, `IOS loaded`, `UI loaded`, `ModsReloaded`, `mods loaded`, the hook status lines and the options line (`log_level=`). Each written line flushes the log file. `Info` gives the facts of a playtest, and `Debug` adds the detail for a bug. Calls are `IIS.Error`, `IIS.Info`, `IIS.Debug` and `IIS.Always`.

The log shows AP in the scale that the game shows (`IIS.FormatAP` divides raw AP by `const.Scale.AP`). GBO 4 changes that scale and keeps raw AP, so with GBO 4 the log AP values are 10 times the vanilla values. For example, `110->1.8` is 11 vanilla AP at the start and 0.18 at the end, and `165/121` is 16.5 of a maximum of 12.1. Divide by 10 before you compare a GBO 4 log with a vanilla log or with an attack cost in vanilla AP.

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
| `attack args hook: ours` | `IOS.lua` wrapped `Unit:PrepareAttackArgs` on `ModsReloaded`. `REPLACED` means that another mod replaced the wrap. |
| `aim range hook: ours` | `Aim.lua` wrapped `Unit:GetBaseAimLevelRange` on `ModsReloaded`. `REPLACED` means that another mod replaced the wrap. |
| `INT #N aim range failed` | The free aim levels or the aim limit failed with a Lua error. The shot gets the aim range of the game. |
| `attack cost lookup failed for` | The game call for the default attack cost of a unit failed with a Lua error. Each unit writes this line once per combat turn. The unit cannot win an IIS or JA2 Classic interrupt (`attack cost unknown`). |
| `INT #- <type> handler failed` | A provoke-list handler failed. Vanilla gets the entries of that group. |
| `INT #N UI enemy banner` | The "Enemy Interrupt" banner showed or did not show. |
| `INT #N AI runs for` | The AI starts for the interrupters of an Enemy interrupt. |
| `INT #N   visibility` | At the start of an Enemy interrupt, for each interrupter: whether it sees the mover, whether the mover sees it, and whether the player team sees it. |
| `INT #N camera at BEGIN`, `at END`, `2s after END` | The look-at point of the camera and its distance to the mover, in game units, during an Enemy interrupt. |
| `INT #N   ... at BEGIN: shooting_stance=`, `at END:` | At the start and the end of an Enemy interrupt, whether each interrupter has the GBO 4 Shooting Stance, and the raw AP that the stance carries to its next turn (`AP_Carried`, `unset` before the stance first sets it). GBO 4 sets it at the end of the enemy turn and adds it at the next turn start, before `TurnStart`. |
| `INT #N unit died`, `unit downed` | A hit during an interrupt killed a unit or put it down, with the attacker. The line comes when the hit lands, before the dying animation. |
| `INT #N ... refused: enemy interrupt` | A player unit tried an action during an Enemy interrupt. The action did not start. |
| `INT #N End Turn ignored: enemy interrupt` | The player pressed End Turn during an Enemy interrupt. Nothing happened. |
| `same step as vanilla ..., vanilla runs first` | An enemy on Overwatch triggered on the same step as an enemy interrupt. The Overwatch fires first. |
| `INT #N collective` | A collective interrupt roll, or the reason that a teammate did not roll. |
| `INT #N run action`, `action ended` | An interrupter action started or ended. |
| `INT #N waiting` | The state of a waiting interrupt. It is written when the state changes, and every 30 seconds. |
| `INT #N STUCK?` | A merc stayed busy for more than 10 seconds. |
| `INT #N ... failed` | A part of the interrupt failed with a Lua error. The interrupt continues without that part. |
| `stops at`, `re-plans from its tile` | "Stop" mode: the enemy stays on its tile, gets back AP and plans its attacks again. |
| `TurnEnded` | The check counts of the turn and the IIS counters by session id (`a<-enemy=5`). At `Debug`, also the skip reasons and the action counts. |
