# Improved Interrupt System

A Jagged Alliance 3 mod for player-controlled interrupts with the rules of JA2 1.13. During the enemy turn, your mercs can interrupt by the 1.13 Improved Interrupt System (IIS) or by the classic duel. Then you give orders to the mercs that interrupted.

This version is a proof of concept. A rewrite comes after it.

## Status

Version 0.7 has all parts of the proof of concept. It passed an in-game test on 2026-11-01 with three mercs against one enemy, with GBO 4 and Rato's AI Overhaul loaded. In that test, the interrupts after an enemy attack did not occur. Version 0.7.1 adds log lines to find the cause.

During the enemy turn, mercs win interrupts by the 1.13 rules. The enemy stops, and only the mercs that won can take orders. Press End Turn (Enter) to end the interrupt. Then the enemy turn continues.

To turn the mod off, set the "Interrupts enabled" mod option to off. Do not disable the mod in the Mod Manager. A save that used the mod turns it on again when you load it.

## Mod options

| Option | Default | Effect |
|---|---|---|
| Interrupts enabled | on | Off: no interrupts. |
| Interrupt system | IIS | IIS: each merc counts the AP that a seen enemy spends, and interrupts when the count reaches its reaction time. Classic: a duel of level and Agility when an enemy comes into view. |
| Collective interrupts (IIS) | on | Teammates within 5 tiles of a winner can join the interrupt by chance. |
| Interrupted enemy | Stop | Stop: the enemy stays on its tile, gets back the AP for the rest of its path, and attacks from there. Continue: it walks on to its destination. |
| End interrupt at 0 AP | on | The interrupt ends 1.5 seconds after the last action when no interrupter has AP for one step. Off: only End Turn ends it, as in 1.13. |
| Need AP for an attack | on | A merc wins only if it has the AP for its default attack (1.13 rule). |
| IIS reaction time | 25 | `BASIC_REACTION_TIME_LENGTH`. Lower values give more interrupts. |
| IIS AP registered (%) | 60 | `BASIC_PERCENTAGE_APS_REGISTERED`. Higher values give more interrupts. |
| Verbose log | off | Writes one line for each merc in each check. |

## The rules

`mod/Code/Rules.lua` holds the 1.13 formulas. Each function names the 1.13 source line that it follows.

**IIS (1.13 default):**

- When an enemy that a merc sees spends AP, the merc counts 60% + 4% per merc level of that AP, minus up to 25% for distance. A 1.13 turn is 100 AP, so the mod converts JA3 AP to a share of the enemy's maximum AP.
- A move counts on each step where the merc has line of sight. Other actions count when they start.
- The reaction time is 25, changed by Agility, AP left, wounds, fatigue, gas, bandaging and suppression.
- The merc interrupts at the first step, or after an attack, where its count reaches its reaction time. Its count then goes back to 0.
- The counts go back to 0 at the start of each player turn.

**Classic:**

- When an enemy comes into view of a merc that did not see it this turn, both get points: `(20 × level + Agility + 15) / 30`, with the 1.13 modifiers.
- The merc wins if it has more points. A tie goes to the enemy. An enemy that cannot see the merc always loses.
- A merc that an enemy shoots without being seen also gets a duel.

**Both systems:** all mercs that win at the same step get control together. The merc with the largest margin is selected first.

## How it works

| File | What it does |
|---|---|
| `Code/Rules.lua` | The 1.13 formulas. It makes no engine calls. |
| `Code/IIS.lua` | Settings, log, trigger checks, IIS counts and what each unit saw. `IIS.E` holds every engine read, so the tests can replace it. |
| `Code/Control.lua` | Runs an interrupt and gives control to the interrupters. |
| `Code/UI.lua` | Banner, portrait marks, End Turn label, camera and sounds. |

The trigger is a `"iis"` entry that the wrapper of `Unit:CheckProvokeOpportunityAttacks` adds to the vanilla interrupt list. The game then calls `Unit:ProvokeOpportunityAttacksFromList` in the enemy's command thread, and the AI turn waits until the interrupt ends.

Overrides in `Control.lua`. Each one changes behavior only while an interrupt is active:

| Override | Why |
|---|---|
| `IsNetPlayerTurn` | Returns true. The UI and the action start code ask it whose turn it is. |
| `Unit:CanBeControlled` | True for the interrupters. False, with the reason `iis_not_interrupter`, for the other player units. |
| `CombatActionCannotBeStarted` | Counts only the interrupters' running actions. The frozen enemy's action never ends during the interrupt. |
| `StartCombatAction` | Runs the interrupters' actions in a small queue with the vanilla start rule, applied to the interrupters only. |
| `Unit:IsIdleOrRunningBehavior` | Returns true for the frozen enemy. `Unit:FirearmAttack` waits until its target is idle. |
| `WaitOtherCombatActionsEnd` | An interrupter waits only for the other interrupters. |
| `IModeCombatMovement:OnMouseButtonDown` | Sets `g_CurrentTeam` to the player team during the click handler. |
| `NetSyncEvents.EndTurn`, `NetSyncLocalEffects.EndTurn` | End the interrupt instead of the turn. |
| `HUDMercClass.SetupStyle` (in `UI.lua`) | Marks the portraits. |
| `OnMsg.CanSaveGameQuery` | Blocks saves during an interrupt. |

## Tests

Run `tools/test.sh`. The script checks the syntax of each mod file with `luac5.4`, then runs the tests with `lua5.4`:

- `tests/test_rules.lua` checks the formulas against worked examples from the 1.13 source code.
- `tests/test_engine.lua` loads `IIS.lua` and `Control.lua` with fake engine functions. It checks the trigger checks, the IIS counts, the merge with vanilla interrupts, the control overrides, the action queue and the stop of the enemy.

The tests do not cover `UI.lua` or anything that needs the game.

## In-game test procedure

1. Run `tools/deploy.sh`. The script copies `mod/` to `Mods/ImprovedInterruptSystem` in the game folder.
2. Start the game and enable "Improved Interrupt System" in the Mod Manager.
3. Load a combat save and end the turn.
4. Run `tools/log.sh -f` to follow the log while the game runs.

What you must see during an interrupt:

- A yellow "INTERRUPT!" banner at the top center. The line below it names the interrupters and the frozen enemy.
- A yellow frame and an "INTERRUPT" tag on the interrupters' portraits.
- Gray, faded portraits with a "LOCKED" tag on the other mercs. A click on them does nothing.
- "END INTERRUPT" on the End Turn button. After you press it while a merc is busy, it shows "ENDING...".
- "INTERRUPT!" floating text above each interrupter, and "Interrupted" above the enemy.

If a merc hangs during an action, press End Turn twice. The second press sends the busy mercs to `Idle` and ends the interrupt.

Things to test:

1. Both systems, one at a time.
2. A group of enemies that move at the same time.
3. Two or more interrupters at once.
4. An enemy that dies during the interrupt.
5. "Interrupted enemy" set to Stop: the enemy must stop on its tile and attack from there.
6. An interrupt after an enemy attack.
7. The inventory during an interrupt. It is not tested.

## Log lines

All lines start with `[IIS]`. `tools/log.sh` also shows `[LUA ERROR]` lines with their stack, and mod load errors.

| Line | Meaning |
|---|---|
| `... loaded 0.7.1`, `control loaded`, `UI loaded` | The game ran the code files. Each hook status must say `ours`. |
| `mods loaded` | The title, id and version of each loaded mod. |
| `check #N IIS TRIGGER` or `check #N Classic TRIGGER` | A check found winners. Each winner shows its numbers: points (classic) or count and reaction time (IIS). |
| `trigger in an AI planning check` | The AI ran the same check to group its units. Nothing happens yet. |
| `IIS register` | A seen enemy action added AP to the mercs' counts. The line shows the cost as a share of 100 and the enemy's AP and maximum AP. |
| `AP/max AP at turn start` | The AP and the maximum AP of each AI unit when its turn starts. |
| `enemy attack exec begin`, `enemy attack exec end` | An enemy firearm attack (`Unit:ExecFirearmAttacks`) started or ended. A `begin` without an `end` means that the enemy's command stopped inside the attack. |
| `enemy attack resolved` | The game resolved an enemy attack (`Msg("Attack")`). The line names the target and the units in the attack. |
| `after-attack check by ... skipped` | The check after an attack did not run. The line gives the reason. |
| `check #N ... after attack by ...: no winner` | The check after an attack ran, but no merc won. The line shows the count and the reaction time of each merc. |
| `enemy action ended` | The combat action of an AI unit ended. |
| `IIS commit` | The steps that an enemy walked added AP to the counts. |
| `INT #N BEGIN`, `interrupter K` | The interrupt started, and the list of interrupters. |
| `INT #N collective` | A collective interrupt roll: chance, roll and result. A `skipped` line gives the reason that a teammate did not roll. |
| `INT #N UI shown` | The banner, portraits, button and camera. `end_turn_button=live` means that the button was found. |
| `INT #N run action`, `merc ... action ended` | An interrupter action started or ended. |
| `INT #N waiting +Ns` | The state of the interrupt while it waits. The mod checks the state every 5 seconds. It writes the line when the state changes, and every 30 seconds while the state does not change. |
| `INT #N STUCK?` | A merc stayed busy for more than 10 seconds. The stack follows if the game allows it. |
| `INT #N end requested`, `INT #N END` | End Turn was pressed, and the interrupt ended. `END` shows the reason and the AP of each interrupter. |
| `enemy ... stops at` | "Stop" mode: the enemy stays on its tile and gets back AP. |
| `re-plans from its tile` | The stopped enemy's AI now plans its attacks from where it stands. |
| `INT #N ... failed` | A part of the interrupt failed with a Lua error. The interrupt goes on without that part. |
| `TurnEnded` | The check counts of the turn, why movers and mercs were skipped, and the IIS counts at turn end. |

## Not included

- Enemy interrupts during the player turn. The AI would have to run in the middle of the player turn.
- Militia interrupts. Militia are AI-controlled.
- Counter-interrupts and chains of interrupts.
- 1.13 noise and hearing interrupts.
- The 1.13 watched-location bonus and the Focus trait.
- Co-op. The overrides ignore the net sync rules.
