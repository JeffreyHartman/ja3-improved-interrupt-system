# Roadmap

The mod will have two systems, and a player can turn on one or both. See ADR 0002.

- **Interrupt System (Experimental):** IIS, JA2 Classic or Off. The current system.
- **Improved Overwatch System (IOS):** on or off. See [Improved Overwatch System](#improved-overwatch-system).

The mod keeps its name, "Improved Interrupt System". The mod description must name both systems.

## Before the first Workshop release

Release as a beta when all of these are done.

- [ ] Save and load after a combat with interrupts. The IIS counters are in the save, so each update must load older saves.
- [ ] Play several full combats in a campaign, not only in the mod editor.
- [ ] Decide how often interrupts must happen, and set the defaults (#2).
- [ ] Add enemy interrupts. See [Enemy interrupts](#enemy-interrupts).
- [ ] Decide if enemy Overwatch must change when enemy interrupts work. See [Overwatch and the Interrupt System](#overwatch-and-the-interrupt-system).
- [ ] Remove the "End Interrupt at 0 AP" and "Need AP for an attack" options, and always use both rules.
- [ ] Check the GBO 4 Shooting Stance carry-over. GBO 4 saves the carried AP at the end of the turn, so AP that a merc spends in a later interrupt can carry over too.
- [ ] Change the status line in the README to beta.
- [ ] Bump the version.

## Improved Overwatch System

Issue #17. When a merc's Overwatch triggers, the game pauses and the player takes control of that merc. The player can aim, choose another target, or not shoot. Then the enemy turn continues.

The AI already uses Overwatch, so IOS needs no enemy interrupts. It can use the code that pauses the enemy turn and gives control to the player (`Control.lua`, `Interrupt.lua`). The open questions are in #17.

Later:

- An option that gives enemy Overwatch shots an aim bonus. In version 1, enemy Overwatch stays vanilla.
- Player control for other reactions: Pin Down, Melee Training, and the Hotblood and HaveABlast retaliation attacks. In version 1, they stay vanilla.
- New perks for IOS, or changes to vanilla Overwatch perks so that they fit IOS.
- Possible gap: the moving-target penalty applies only to shots that a merc fires in an interrupt. Vanilla Overwatch shots and enemy Overwatch shots do not get it.
- Help topics in the A.I.M. Help Center for IIS, JA2 Classic and IOS, as GBO 4 does (`PopupNotification` and `TutorialHint` presets). Each topic about IOS must explain what changes under GBO 4.

## Enemy interrupts

An enemy interrupts a merc that moves or acts during the player's turn. Without this feature, only the player's side can interrupt, and the game is easier than vanilla.

Open questions:

- The merc's command must stop, the AI must act, and then control must go back to the player.
- The player's turn has no AI turn loop. The mod must start the AI for the interrupter only.
- Which player actions register AP with the enemies: moves only, or attacks too.
- How the camera follows the enemy interrupter.

Counter-interrupts (#16) need the same parts: the other team acts during an interrupt, and then control comes back. Build enemy interrupts so that #16 can use them.

## Overwatch and the Interrupt System

When IOS is off, Overwatch stays vanilla. When IOS is on, a merc's Overwatch trigger starts an IOS interrupt. See ADR 0002.

A merc on Overwatch has 0 AP, so it cannot win an IIS or JA2 Classic interrupt. Thus one merc never gets two reactions to the same mover action.

Open question: enemy interrupts and enemy Overwatch together can be too strong. Decide in play when enemy interrupts work. If one option is clearly better, make it a mod option.

## Later

- Counter-interrupts (#16)
- Militia interrupts
- Interrupts from noise
- The 1.13 watched-location bonus
- Co-op (not decided)
