# Overwatch research for IOS

Facts about vanilla JA3 Overwatch, GBO 4 and JA2 1.13 for issue #17. Researched on 2026-11-08. Vanilla paths are relative to `_reference/game/Lua/Lua/`, and `Data/` is `_reference/game/Data/`.

## AP cost, number of attacks, duration
- Entering Overwatch spends all remaining AP. The merc needs at least the AP for one attack. `Data/CombatAction.lua:2777-2786`, `Tactical/UnitOverwatch.lua:244-247`.
- Number of attacks: `1 + floor(remaining AP / cost of the default attack)`, then `OnCalcOverwatchAttacks`. `Tactical/UnitOverwatch.lua:295-315`.
  - OverwatchExpert gives +1.
  - The ExtraOverwatchShots weapon component gives +1.
  - No stat changes the number.
- Overwatch ends at the start of the owner's next turn (`expiration_turn = turn + 1`). `Tactical/Unit.lua:2671-2678`.
- `g_Combat.current_turn` counts rounds. It goes up before the player team's turn starts (`Tactical/Combat.lua:497-503, 736-737`). Thus Overwatch that a merc enters in an interrupt during the enemy turn also ends at the merc's next turn start.
- Overwatch also ends:
  - at 0 attacks, if it is not permanent;
  - when the weapon jams;
  - when the weapon is out of ammo;
  - from `InterruptPreparedAttack`: Panic, Berserk, knockdown, Distracting Shot.
- With a set-up MG, Overwatch is permanent. The number of attacks is recalculated each turn. `Tactical/UnitOverwatch.lua:1702-1725`.

## Cone and triggers
- Cone angle comes from the weapon's `OverwatchAngle`.
- Cone length is between 2 tiles and 75% of weapon range. Shotguns and MGs use full range. It is limited to sight range. `Tactical/Weapon.lua:3205-3213, 3249-3255`.
- Only `"move"` and `"attack interrupt"` cause a trigger. An attack interrupt happens before and after `PrepareToAttack`. `Tactical/UnitOverwatch.lua:1310-1318`.
- These do not cause a trigger:
  - a mover with LightStep;
  - Distracting Shot;
  - a HardBlow melee attack;
  - a hidden mover.
- `CombatGoto` checks the full path and stops at the first step that triggers. When the mover reaches that step, the list runs and the rest of the path is checked again. `Tactical/Unit.lua:3350-3375, 3455-3492`.
- Each overwatcher fires at most once per mover command (`passed_interrupts`). A new command from the same mover can trigger it again. `Tactical/UnitOverwatch.lua:1203`, `Tactical/Unit.lua:2946`.
- Only the earliest step that triggers is kept. All overwatchers that trigger on that step fire, in session_id order. `Tactical/UnitOverwatch.lua:1003-1016`, `Tactical/Unit.lua:9601`.

## The shot
- Mode: the first visible `AvailableAttacks` entry of the weapon. This is usually burst for automatic weapons, and single shot for bolt-action rifles. The firing mode that the player chose is not used. `Tactical/Weapon.lua:3188-3199`.
- Aim: the minimum aim level of the weapon, normally 0. `Tactical/Unit.lua:8305`.
- Body part: always Torso. If an ally blocks the Torso, the spot changes. `Tactical/UnitOverwatch.lua:932-947, 1449-1458`.
- To-hit modifier `OpportunityAttack`: -20 at Dexterity 0 to +10 at Dexterity 100. The `OpportunityAttackBonusCth` component adds +10. `Data/ChanceToHitModifier.lua:506-539`.
- An interrupt attack cannot crit without OpportunisticKiller. `Tactical/Unit.lua:7294`.
- There is no penalty for a moving target. `EvasiveMovement` is turned off. `Data/ChanceToHitModifier.lua:249`.
- The attack command is `OpportunityAttack`, which runs `FirearmAttack` at 0 AP with `opportunity_attack_type = "Overwatch"`. `Tactical/UnitOverwatch.lua:1441-1471`.

## Other reactions
- Pin Down fires at the start of the target's turn, from `BeginTurn`. It is not in the provoke list. It uses the stored aim and body part. `Tactical/Unit.lua:2772`.
- Melee Training uses the provoke list, with entry `"melee"`.
- Hotblood and HaveABlast retaliation attacks fire from `AttackReaction`, outside the provoke list.
- Killzone gives 2 shots per trigger, for Overwatch, Pin Down and retaliation.

## AI
- Soldier, Control (SpamOverwatch) and TheMajor archetypes choose `AIConeAttack` with `"Overwatch"`. There is also a fallback Overwatch action when the AI has nothing else to do.
- Enemy Overwatch against mercs uses the same functions.

## Intercept point
- Entry shape: `{"overwatch", attacker, attack_args, target_dummy, interrupt_pos}`.
- `ProvokeOpportunityAttack_Overwatch` (`Tactical/UnitOverwatch.lua:1417`) does the following:
  - sets `triggered_by`;
  - removes Hidden from the mover;
  - calls `InterruptBegin`;
  - fires the attack;
  - calls `FinishOpportunityAttack_Overwatch`, which uses one attack and ends Overwatch at 0.
- The merc has 0 AP in Overwatch. The merc is in `PreparedAttackIdle`. A new command can drop the prepared attack.

## GBO 4 changes to Overwatch (paths relative to `_reference/mods/gbo4/`)
- Load order: no priority. Our hooks must install on `ModsReloaded` and wrap what is there.
- Full redefinitions:
  - `ProvokeOpportunityAttack_Overwatch` (`Code/PERKS_Interrupt.lua:149`): 1 attack per trigger, Killzone aim from `Rat_KillzoneAim`.
  - `_Pindown` (:109), `Retaliate` (:229).
  - `GetOverwatchAttacksAndAim` (`Code/SOURCE_shooting_stance_overwatch_function_n_attacks.lua:2`): `1 + (AP - stance cost - first shot) / (shot cost + bolt cycling)`. Aim is 1 with Shooting Stance. It can return only `0`.
  - `IsOverwatchAction` adds `R_PrepareWeapon`.
  - `BeginTurn` (`Code/SOURCE_APScale_vanilla.lua:190`): a unit with Overwatch that is still active at its turn start gets 0 AP.
  - `GetAttackAPCost` (1 vanilla AP = 10 GBO AP), `CalcChanceToHit`, `ExecFirearmAttacks`.
- Wraps: `CanAttack`, `EnumUIActions`, `GetBaseAimLevelRange`.
- On `DataLoaded`: `CombatActions.Overwatch.GetAPCost` (includes the Shooting Stance cost), the UI of the Overwatch action, `ChanceToHitModifier.OpportunityAttack.CalcValue` (Reflex-based, -10..+20, `R_OWMul`).
- Aim modifier, old CTH mode only (`Code/CTH_aim.lua`): an opportunity attack gets half the aim bonus (:232). With Shooting Stance, an opportunity attack gets at least 1 aim level (:127).
- In aCTH, the default mode, each aim level makes the cone smaller with no halving. The `opportunity_attack` flag turns off Settled and changes the set-up MG rules (`Code/FUNCTIONS_aperture.lua:617-757`).
- Perks:
  - Opportunistic Killer: +1 Overwatch attack, no interrupt crits.
  - Killzone: aim ladder {3,2,1} for each new target per turn, and crits only when the type is "Overwatch".
  - Beaten Zone: the MG version of the ladder.
  - Sharpshooter and Settled: turned off for opportunity attacks.
- Shooting Stance: on `CombatActionEnd`, a unit in `g_Overwatch` turns back to its Overwatch angle. Overwatch is cancelled when `num_attacks < 1`.
- Only mod option: `OWBonusPct`.
- SmartOverwatch shim: overwrites `GetOverwatchAttacksAndAim` on `EnterSector`, `CombatStart`, `ZuluGameLoaded` and `ModsReloaded`. Never wrap that function.

## Hook strategy
- Wrap `ProvokeOpportunityAttack_Overwatch`. Call the original for every case that IOS does not handle. Do not copy its body.
- Install on `ModsReloaded`, check function identity, and detect GBO by feature (`rawget(_G, "Rat_KillzoneAim")`).
- Pool = `num_attacks` x the per-shot cost from live `GetAPCost` calls. Never hardcode costs.
- Keep `num_attacks` correct, because RatoAI `FUNCTION_DangerScan.lua:288` reads it.
- Tag the shot as `opportunity_attack = true` and `opportunity_attack_type = "Overwatch"`, in the CTH preview too. Without the tag, GBO 4 gives Settled, and in old CTH the full aim bonus.

## Other mods
- No conflicts in ratoai, rtg2, gcmilitia, legion, lynx, revmags or rew.

## Aim levels
- Vanilla max aim = `weapon.MaxAimActions` (3 for firearms) + `OnCalcMaxAimActions`. `Tactical/Unit.lua:8305-8325`.
  - Long-range scopes (LROptics, LROpticsAdvanced, PSG, Dragunov) give +1.
  - Sharpshooter gives +2 on the first attack each turn.
  - Stats do not change the number of levels.
- AP: 1 AP for each level above the minimum. Levels up to the minimum are free. `Unit.lua:7318-7339`.
- To-hit for each level: `AimAccuracy` (2 by default, 3-8 for most guns) + 10% of (Dex - 40). Camouflage on the target halves it.
- Min aim above 0:
  - UVDot sights give min 1.
  - ScopeCOGQuick gives min 3 on the first shot, but not on Overwatch.
  - An Overwatch shot gets the minimum aim.
- GBO 4:
  - The max is 10.
  - Scopes add +1 to +3.
  - Sharpshooter gives Settled stacks in place of +2 aims.
  - The Shooting Stance status gives +1 min aim (a free level), not +1 max (`CharacterEffect/shooting_stance.lua:115-122`). Entering the stance costs 3 AP (`APStance`). Moving, prone, reloading or swapping weapons removes it.

## Moving target
- Vanilla `EvasiveMovement` (`Data/ChanceToHitModifier.lua:246-295`) is turned off.
  - Its design: -25 x (1 - |cos(shot dir, move dir)|) x min(dist, 10 tiles)/10. It applies only below -5. A reflex sight exempts the shot.
  - It used `last_turn_movement`: the target's net move in its last own turn.
- JA2 1.13 old CTH (`Weapons.cpp:7004-7013`):
  - penalty = min(tiles moved x 1.5, 30), where a run counts 2 for each tile.
  - Dauntless gives 1/3 of it.
  - The count resets at the target's turn start.
- JA2 1.13 NCTH (`LOS.cpp:9126-9349`):
  - It moves the aim point sideways, by net distance from turn start x sin(angle).
  - The shooter's skill (MRK, WIS, DEX, EXP) sets how many tiles give the maximum penalty. After that, the penalty goes down.
- GBO 4 has no moving-target penalty. It already penalizes interrupt shots: snapshot spread and the Reflexes Overwatch modifier. A new penalty adds to these.
