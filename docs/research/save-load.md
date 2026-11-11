# Save and load research

Facts about how JA3 saves and loads mod state, and an audit of what this mod stores. Researched on 2026-11-11.

Paths:
- Vanilla paths are relative to `_reference/game/Lua/Lua/`.
- `CommonLua/` is `_reference/game/Lua/CommonLua/`.
- `ModTools/` is the `ModTools` folder of the game install.
- `logs/` is `AppData/Roaming/Jagged Alliance 3/logs/` in the Proton prefix of the game.
- Mod paths are relative to the repository root.

## Summary
- JA3 does not use the engine persist save of the Sol Engine. It writes Lua code text: `Game`, all GameVars, and the map objects of each sector. `_Savegame.lua:151-173`, `GameSession.lua:462-487`.
- The official ModTools docs describe the engine persist save. Most of that text is not true for JA3. See [Official docs and JA3](#official-docs-and-ja3).
- A GameVar is in the save. A MapVar is not. `g_Overwatch` is a MapVar, so the game does not save it.
- The game builds `g_Overwatch[unit]` again after a load, from the Overwatch command arguments of the unit. Mod fields on that entry are lost.
- `OnMsg.LoadGame`, `PreLoadGame` and `PostLoadGame` do not fire in a JA3 load.
- A load into a combat fires `CombatStart`. This mod clears `gv_IIS` on `CombatStart`, so the IIS counters do not survive a load.

## Saved globals mechanism

### GameVar
- Declaration: `GameVar(name, value, meta)` at file scope. `CommonLua/Gameplay.lua:136-151`.
  - It adds the name to `GameVars` and stores the default in `GameVarValues`.
  - It sets `PersistableGlobals[name] = true`.
  - It sets the global to `false` on the first Lua load, or when the global does not exist. A Lua reload keeps the current value.
  - A table default becomes a function that returns a copy. A function default runs at each init.
- `PersistableGlobals[name] = true` lets code create the global after the Lua load. The global table refuses other new globals. `CommonLua/Core/autorun.lua:20-30`.
- The mod environment has the same rule. `CommonLua/Classes/Mod.lua:1340-1345`.
- Init: `InitGameVars` sets each GameVar to its default. `CommonLua/Gameplay.lua:153-161`.
  - `NewGame` calls it. `CommonLua/Gameplay.lua:12-23`.
  - JA3 `ZuluNewGame` calls it. `GameSession.lua:693-725`.
- Reset: `DoneGameVars` sets each GameVar to `false`. `CommonLua/Gameplay.lua:163-167`.
- Save: `GatherSessionData` writes `{ game = Game, gvars = GetPersistableGameVarValues() }` as Lua code with `TupleToLuaCodePStr`. `GameSession.lua:462-487`, `CommonLua/Gameplay.lua:190-198`.
  - Only GameVars with `PersistableGlobals[name]` true go in the save.
  - The save callback writes this text to the `game_session` file. `_Savegame.lua:151-173`.
- Load: `LoadGameSessionData` runs the saved code. Then, for each declared GameVar, it does one of these. `GameSession.lua:548-557`.
  - The save has the var: the global gets the saved value.
  - The save does not have the var (an older save, or a save from before the mod): the global gets the default.
- A var in the save that no code declares now is not read. The loop goes over `GameVars`, not over the save. Thus the next save does not contain it.

### MapVar
- Declaration: `MapVar(name, value, meta)`. `CommonLua/Core/lib.lua:911-927`. It also sets `PersistableGlobals[name] = true`.
- Init: on `NewMap`, each MapVar gets its default. `CommonLua/Core/lib.lua:929-937`.
- Reset: on `PostDoneMap`, each MapVar becomes `false`. `CommonLua/Core/lib.lua:950-955`.
- JA3 does not save MapVars. `GatherSessionData` writes only `Game` and the GameVars. `GameSession.lua:474-476`.
- The MapVar rule in the engine persist path (`PersistSave`, `PersistPostLoad`) does not run in a JA3 save. `CommonLua/Core/persist.lua:96-113`, `CommonLua/Core/lib.lua:939-948`.

### Map objects (sector dynamic data)
- Before a save, `OnMsg.GatherSessionData` calls `GatherSectorDynamicData`. `GameSession.lua:1236-1238`.
- `GatherSectorDynamicData` calls `GetDynamicData(data)` on each saved object. It writes the result as Lua code into `gv_Sectors[id].sector_data`. `GameSession.lua:1067-1168`.
  - Spawned objects and units: class and handle in `spawn`, fields in `dynamic_data`.
  - Then it sends `Msg("SaveDynamicData", sector_data)`. Combat uses it for `g_Combat`. `Tactical/Combat.lua:1750-1756`.
- `gv_Sectors` is a GameVar, so the map data goes in the save with it.
- `ApplyDynamicData` places each spawned object with its saved handle, then calls `SetDynamicData(data)`. `GameSession.lua:932-1055`, `:991`.
- At the end, it sends `Msg("LoadDynamicData", sector_data)`. `GameSession.lua:1052`.

### Unit fields
- `Unit:GetDynamicData` writes a fixed list of fields. `Tactical/Unit.lua:498-640`. `Unit:SetDynamicData` reads the same list. `Tactical/Unit.lua:642-800`.
- A plain field that a mod sets on a unit is not in the list. Thus it is not in the save.
- `behavior_params` and `combat_behavior_params` are saved as a full table copy. `StoreBehaviorParamTbl` changes each `Object` value to its handle and keeps all other keys. `Tactical/Unit.lua:448-479`, `:557-567`.
- Thus an extra key in a behavior params table is in the save, if TableToLuaCode can write its value.
- `UnitData` writes only its properties, through `SavePropsToLuaCode`. A plain mod field on a `UnitData` is not saved. `Mercenary.lua:1024-1032`.
- An `XWindow` sets `__persist = false`. `CommonLua/X/XWindow.lua:4`. This is for the engine persist path only.

### Mod options
- Mod options are not in the save.
- `ApplyModOptions` writes them to `AccountStorage.ModOptions[mod.id]` and calls `SaveAccountStorage`. `Mod.lua:282-299`, `CommonLua/Classes/Mod.lua:654-670`.
- `ModDef:LoadOptions` reads them from `AccountStorage.ModOptions`. `CommonLua/Classes/Mod.lua:602-612`.
- The mod code reads them as `CurrentModOptions`. `CommonLua/Classes/Mod.lua:1405`.
- The file that holds `AccountStorage` is engine code. Its path is unverified.

## Load sequence

This is the order of a load from the menu. Each step names the code that runs it.

1. JA3 `LoadGame` waits for a running save, opens the loading screen and calls the CommonLua `LoadGame`. `_Savegame.lua:34-50`.
2. `Savegame.Load` calls `LoadMetadataCallback`. `CommonLua/Savegame.lua:1063-1086`.
3. `LoadMetadataCallback` reads the metadata and checks the map and the mods. `CommonLua/SavegameMetadata.lua:155-238`.
4. `GameSpecificValidateSaveMetadata` asks the player about missing or outdated mods. `_Savegame.lua:1135-1178`.
5. `GameSpecificLoadCallback` reads the `game_session` file and calls `LoadGameSessionData`. `_Savegame.lua:175-193`.
6. `LoadGameSessionData` sets `loading_savegame` and calls `ChangeMap("")`. `GameSession.lua:518-527`. The old map closes, and MapVars become `false`.
7. `ZuluNewGame` runs. It calls `DoneGame`, `InitGameVars` and sends `Msg("NewGame")`. `GameSession.lua:529`, `:693-725`. Thus `OnMsg.NewGame` also runs on each load.
8. The saved code runs and `FixupSessionData` applies the session fixups. `GameSession.lua:543-547`.
9. Each GameVar gets its saved value or its default. `GameSession.lua:548-557`.
10. `Game` gets the saved game object. `GameSession.lua:559`.
11. `Msg("PreLoadSessionData", data)`. `GameSession.lua:602`. GameVars have their saved values. No map is loaded.
12. `EnterSector` loads the sector map. `GameSession.lua:609`, `Satellite/SatelliteView.lua:1855-1863`.
    - `ChangeMap` sends `NewMap`. MapVars, `g_Overwatch` too, get their defaults.
    - `ApplyDynamicData` places units and calls `SetDynamicData`.
    - `Msg("LoadDynamicData")` makes `g_Combat` and starts `g_Combat:Start(dynamic_data)` in a game time thread. `Tactical/Combat.lua:1736-1748`.
    - `Combat:Start` sends `Msg("CombatStart", dynamic_data, combat)`. On a load, `dynamic_data` is not nil. `Tactical/Combat.lua:313`, `:359`.
    - `Msg("EnterSector", game_start, load_game, lua_revision)`. `Satellite/SatelliteView.lua:1926`.
13. `LoadGameSessionData` waits for the map, then sends `Msg("LoadSessionData")`. `GameSession.lua:623-633`.
14. `LoadMetadataCallback` stores `SavegameMeta` and sends `Msg("GameMetadataLoaded", metadata)`. `CommonLua/SavegameMetadata.lua:233-237`.
15. JA3 `LoadGame` sends `NetSyncEvent("ZuluGameLoaded")`. The handler sends `Msg("ZuluGameLoaded", file_name, lua_revision)` later. `_Savegame.lua:25-27`, `:45`.

Messages that do not fire in a JA3 load:
- `PreLoadGame`, `LoadGame` and `PostLoadGame` fire only in `UnpersistGame`. `CommonLua/Savegame.lua:796-817`.
- No JA3 code calls `UnpersistGame`. The only other mention is a comment. `CommonLua/Savegame.lua:56`.
- The game log agrees. This mod logs `[IIS] LoadGame` in `OnMsg.LoadGame` (`mod/Code/IIS.lua:1009-1012`). That handler is in the mod since version 0.7.
  - `logs/JA3.exe-20261108-15.16.59-67b4a1dd.log` has two loads with IIS 0.7.3 (lines 1070, 2070) and no `[IIS] LoadGame` line.
  - `logs/JA3.exe-20261108-09.50.21-67b4a1dd.log` has one load (line 1073) and no such line.
- In the second load of the first log, `[IIS] combat state reset (CombatStart)` is at line 2059, before `Game loaded on map` at line 2070. `ZuluGameLoaded` comes after it.

When mod code runs:
- Mod code runs when the mods load. That is at game start and when the player changes the mod list. `CommonLua/Classes/Mod.lua:1894-1957`.
- The order is: options load, Lua loads (the mod code runs), items load, `ApplyModOptions` for each mod with options, `ModsReloaded`.
- A save load does not load the mod code again. No step in the load sequence calls `ModsReloadItems`.
- Thus the hooks of the mod are in place before the saved data comes back.

What a mod can do in each hook:

| Hook | State | Use |
|---|---|---|
| `NewGame` | Defaults only. On a load, the saved data is not yet in place. | Reset state for a new game. Do not reset saved state here only for a load. |
| `PreLoadSessionData` | GameVars and `Game` are loaded. No map, no units. | Fix up the data of a GameVar. |
| `CombatStart` | Units are placed, `g_Combat` exists. The second argument is not nil on a load. | Start combat state. Check the argument before you clear saved state. |
| `EnterSector` | The map and units are loaded. `load_game` is true on a load. | Fix up unit or map state after a load. |
| `LoadSessionData` | The full game is loaded. | Fix up after a load. |
| `ZuluGameLoaded` | Sent through a net sync event after the load. | Late fixups. |
| `LoadGame` | Does not fire in JA3. | Do not use. |

## Unknown and extra fields

### g_Overwatch
- `g_Overwatch` is `MapVar("g_Overwatch", setmetatable({}, weak_keys_meta))`. `Tactical/UnitOverwatch.lua:8`.
- It is not a GameVar, so it is not in the save. It is empty after the `NewMap` of a load.
- `Unit:OverwatchAction` stores its arguments as the combat behavior: `SetCombatBehavior("OverwatchAction", {action_id, cost_ap, args})`. `Tactical/UnitOverwatch.lua:174`.
  - `args` is a copy that the function made. `Tactical/UnitOverwatch.lua:115`.
  - The vanilla comment says that `triggered_by` is in `args` "so it gets automatically saved/restored". `Tactical/UnitOverwatch.lua:218`.
- The unit save writes `combat_behavior_params`. On load, `SetDynamicData` sets the `OverwatchAction` behavior again. `Tactical/Unit.lua:564-567`, `:658-666`.
- In combat, `Unit:Idle` starts the combat behavior as a command. `Tactical/Unit.lua:5213-5214`.
- `Unit:OverwatchAction` runs again and makes a new `g_Overwatch[unit]` table. `Tactical/UnitOverwatch.lua:220-238`.
  - The new table has only vanilla fields.
  - `num_attacks` comes from `g_Overwatch[unit]`, which is empty, so it comes from `args.num_attacks`. `Tactical/UnitOverwatch.lua:117`.
- Vanilla keeps `args.num_attacks` correct after each shot. `Tactical/UnitOverwatch.lua:1400-1403`.
- Result: an unknown field on `g_Overwatch[unit]` is not saved. A load drops it.
- An extra key in `args` (`combat_behavior_params[3]`) stays through the save and the copy in `OverwatchAction`. That is not tested in game.

### Fields on other objects
- Unit: only the fields in `Unit:GetDynamicData` are saved. A plain mod field is lost.
- UnitData: only properties are saved.
- GameVar tables: all keys and values are written as Lua code. Keys must be booleans, numbers or strings. `GameSession.lua:1141-1160` has a disabled check for this rule.
- `TableToLuaCode` and `TupleToLuaCodePStr` are engine functions. Their exact rules for functions, threads and objects as values are unverified.

## Mod removed or added

### Save with the mod, loaded without it
- `GetMissingMods` lists each mod of the save that is missing, disabled, too old for the game, or older than the version in the save. `CommonLua/SavegameMetadata.lua:75-92`.
- In single player, the game shows "Cannot load the game. The following mods are missing or outdated" and offers "Load anyway". `_Savegame.lua:1140-1174`.
- In multiplayer, the load stops. `_Savegame.lua:1175-1181`.
- After "Load anyway", the mod goes into `metadata.ignored_mods`. The next load does not ask again for it. `CommonLua/SavegameMetadata.lua:228-232`.
- The saved GameVars of the mod are not read, because no code declares them. The next save drops them.
- The Unit fields and behavior params are vanilla data. A load without the mod reads them as vanilla.

### Save without the mod, loaded with it
- No prompt, unless the mod has sector, map patch or campaign items. This mod has none. `_Savegame.lua:1185-1210`.
- Each GameVar of the mod gets its default. `GameSession.lua:548-557`.
- Saved Overwatch states have no IOS fields.

### Mod turned on during a game
- The Lua reload runs `GameVar`, which sets the global to `false` when it does not exist. `CommonLua/Gameplay.lua:145-147`.
- The global stays `false` until the next new game or load.

## What quickdraw stores

| Item | Written in | Type | Mechanism | Save without it | Risk |
|---|---|---|---|---|---|
| `gv_IIS.counters[watcher][mover]` | `mod/Code/Memory.lua:49-53`, cleared at `:146-162` | number 0..255, keys session id or handle | GameVar `gv_IIS` (`mod/Code/IIS.lua:316`) | Default `{ counters = {}, ... }` from `GameSession.lua:548-557`. `Store()` adds missing subtables (`mod/Code/Memory.lua:18-25`). | Cleared on each load into combat. See below. |
| `gv_IIS.seen_turn[unit][other]` | `mod/Code/Memory.lua:56-60` | boolean | GameVar `gv_IIS` | Same as above. | Same as above. |
| `gv_IIS.seen_ever[unit][other]` | `mod/Code/Memory.lua:56-60` | boolean | GameVar `gv_IIS` | Same as above. | Same as above. JA2 Classic reads it (`mod/Code/IIS.lua:525-530`, `:619-623`). |
| `g_Overwatch[unit].ios_pool`, `ios_count`, `ios_turn` | `mod/Code/IOS.lua:108-113` | numbers | None. `g_Overwatch` is a MapVar and is built again after a load. | `IOS.Pool` uses `num_attacks * cost` when `ios_pool` is nil (`mod/Code/IOS.lua:98-104`). | A load drops the part of the pool below one attack cost. |
| `combat_behavior_params[3].num_attacks` | `mod/Code/IOS.lua:137-141` | number | Unit dynamic data (vanilla field) | Vanilla value. | None. The count after a load is the count that IOS set. |
| `unit.iis_move_start` | `mod/Code/MovingTarget.lua:55-60` | table with a thread and a point | None. Not in `Unit:GetDynamicData`. | Nil. `MoveStart` returns nil, so the penalty is 0. | The move start of a move that was running at save time is lost. |
| `unit.iis_stopped` | `mod/Code/Control.lua:627`, `:634-636` | thread | None. | Nil. | None found. |
| `win.iis_tag`, `iis_glow_size`, `self.iis_mark` | `mod/Code/UI.lua:120-171` | UI values | None. UI objects are not saved. | Nil. | None. |
| Interrupt state (`active`, queues, counters for the log) | `mod/Code/Control.lua:13`, `:65`, `:538` | Lua locals | None. | Starts as `false`. | See the load during an interrupt below. |
| Move plans | `mod/Code/Memory.lua:74-142` | Lua local | None. `Mem.Loaded` is meant to clear them. | Empty after a Lua load. | `Mem.Loaded` never runs. `Mem.Clear` on `CombatStart` clears them. |
| Mod options | `mod/items.lua`, defaults in `mod/metadata.lua` | values per option | `AccountStorage.ModOptions["ImprovedInterruptSystem"]`, not the save | Defaults from the mod items. | None. The options are per account, not per save. |

### gv_IIS on load
- `gv_IIS` gets its saved value at step 9 of the load. `GameSession.lua:548-557`.
- At step 12, a load into combat sends `CombatStart`. `Tactical/Combat.lua:359`.
- `OnMsg.CombatStart` calls `ResetCombatState`, which calls `Mem.Clear()`. `mod/Code/IIS.lua:993-1002`. `Mem.Clear` makes all three tables empty. `mod/Code/Memory.lua:158-162`.
- The mod also clears them on `CombatEnd`. Thus `gv_IIS` is empty outside combat.
- Result: the saved counters and seen marks never come back. An older save and a new save load the same way.
- The effect is small for the counters. A save happens on the player turn, and `Mem.TurnStart` cleared the counters of the player team at that turn start. `mod/Code/Memory.lua:146-155`.
- The seen marks are lost. After a load, `seen_ever` has only what the units see from the first visibility update.
- The statement "The IIS counters are in the save" (`ROADMAP.md:14`) is true for the file, but the mod clears them on load.
- A fix: in `OnMsg.CombatStart(dynamic_data)`, do not call `Mem.Clear` when `dynamic_data` is not nil. Issue #41.

### IOS pool on load
- An older save, or a save from before IOS, has no `ios_*` fields. A new save also has none after a load, because the game builds the entry again.
- `IOS.Pool` treats both cases the same. The pool is `num_attacks` times the live cost of one default attack. `mod/Code/IOS.lua:98-104`.
- `num_attacks` is correct after a load, because IOS also writes it to `combat_behavior_params[3]`. `mod/Code/IOS.lua:137-141`.
- Example: a pool of 7 AP with an attack cost of 4 AP has `num_attacks = 1`. After a load the pool is 4 AP.
- `docs/DEVELOPMENT.md:55` says that the game saves `g_Overwatch[unit]`. This is not correct. The game saves `combat_behavior_params[3]` and builds `g_Overwatch[unit]` from it.
- A fix: also write `ios_pool`, `ios_count` and `ios_turn` to `combat_behavior_params[3]`, and read them from there when `g_Overwatch[unit]` has no pool.

### Load during an interrupt
- `OnMsg.CanSaveGameQuery` blocks a save during an interrupt. `mod/Code/Control.lua:892-896`.
- `CanLoadGame` does not send `CanSaveGameQuery`. `GameSession.lua:841-850`. Thus the player can load a save during an interrupt.
- The interrupt waits in the mover's command thread. `ChangeMap("")` deletes the map threads, so `IISControl.EndInterrupt` does not run. That thread deletion is engine code and is unverified.
- Then `active` in `mod/Code/Control.lua:13` stays set. The overrides in `docs/DEVELOPMENT.md` stay on, and `Start` skips each new interrupt (`mod/Code/Control.lua:437-440`).
- No handler in the mod resets `active` on `NewGame`, `DoneMap` or `CombatStart`. Issue #42.

## Official docs and JA3
- `ModTools/Docs/LuaSavegame.md.html` says that the save serializes all objects, game time threads and `GlobalVar`s. It names `PersistSave`, `PersistLoad` and `LoadGame` as hooks.
- That is the engine persist path (`PersistGame`, `UnpersistGame`). JA3 uses it only for the bug report save. `CommonLua/Savegame.lua:1007-1009`.
- `ModTools/Docs/LuaVars.md.html` says that GameVars and MapVars are "automatically included in savegames".
- In JA3 this is true for GameVars only.
- That doc also says that a var not in the save keeps its initial value, and that the load discards obsolete vars.
- `GameSession.lua:548-557` shows the same rule for GameVars.

## Open questions (need an in-game test)
1. Does `OnMsg.LoadGame` fire on a load in the current game build? Test: load a save and look for `[IIS] LoadGame` in the log. The logs and the Lua say no.
2. After a load in combat, does the unit on Overwatch run `OverwatchAction` again and make a new `g_Overwatch[unit]`? Test: log the entry and its `ios_*` fields before the save and after the load.
3. Does an extra key in `combat_behavior_params[3]` survive the save and the load? Test: put `ios_pool` there, save, load and log it.
4. Does `CombatStart` on a load clear counters and seen marks that the IIS rules need? Test: in JA2 Classic, save in combat, load, and compare the `saw_before` values in the log.
5. What happens when the player loads a save during an interrupt? Test: start an interrupt, load a save from the menu, then check that the next enemy turn can have interrupts.
6. Does quick load during an interrupt act the same as the menu load?
7. Does `ZuluGameLoaded` always come after the first `CombatStart` of a load? The log shows this for one load.
8. Is a save on the enemy turn possible, for example an autosave? If yes, the counters of the player watchers are not zero at save time.
9. Does a save with the mod, loaded with the mod off, give the "missing or outdated" prompt, and does the game then run without errors?
10. Does a save from a newer mod version, loaded with an older one, give the prompt? `GetMissingMods` compares `version`, which is the build number 13 in `mod/metadata.lua`.
