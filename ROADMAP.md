# Roadmap

The mod will have two modes:

- **JA2 1.13 interrupts (Experimental):** the current system. It changes the game balance a lot.
- **Improved Overwatch:** a new mode. See [Improved Overwatch](#improved-overwatch).

The mod can need a new name when it has two modes. This is not decided.

## Before the first Workshop release

Release as a beta when all of these are done.

- [ ] Finish the in-game play test (#14). The play test did not show `forced_end`, `auto_end`, `interrupters_down` or the queue with two interrupters yet.
- [ ] Check in game that an interrupter loses its Free Move AP.
- [ ] Save and load after a combat with interrupts. The IIS counters are in the save, so each update must load older saves.
- [ ] Play several full combats in a campaign, not only in the mod editor.
- [ ] Decide how often interrupts must happen, and set the defaults (#2).
- [ ] Add enemy interrupts. See [Enemy interrupts](#enemy-interrupts).
- [ ] Decide what Overwatch does in the JA2 1.13 mode. See [Overwatch in the JA2 1.13 mode](#overwatch-in-the-ja2-113-mode).
- [ ] Remove the "End Interrupt at 0 AP" and "Need AP for an attack" options, and always use both rules.
- [ ] Check the GBO 4 Shooting Stance carry-over. GBO 4 saves the carried AP at the end of the turn, so AP that a merc spends in a later interrupt can carry over too.
- [ ] Change the status line in the README to beta.
- [ ] Bump the version.

## Improved Overwatch

Issue #17. When a merc's Overwatch triggers, the game pauses and the player takes control of that merc. The player can aim, choose another target, or not shoot. Then the enemy turn continues.

The AI already uses Overwatch, so this mode needs no enemy interrupts. It can use the code that pauses the enemy turn and gives control to the player (`Control.lua`, `Interrupt.lua`). The open questions are in #17.

## Enemy interrupts

An enemy interrupts a merc that moves or acts during the player's turn. Without this feature, only the player's side can interrupt, and the game is easier than vanilla.

Open questions:

- The merc's command must stop, the AI must act, and then control must go back to the player.
- The player's turn has no AI turn loop. The mod must start the AI for the interrupter only.
- Which player actions register AP with the enemies: moves only, or attacks too.
- How the camera follows the enemy interrupter.

Counter-interrupts (#16) need the same parts: the other team acts during an interrupt, and then control comes back. Build enemy interrupts so that #16 can use them.

## Overwatch in the JA2 1.13 mode

The mod does not change Overwatch now. A unit on Overwatch can also get an interrupt, so one unit can get two reactions to the same move.

Options:

1. Keep both. This is the least work. Overwatch costs AP before it triggers, and an interrupt is free, so they are different choices.
2. Turn Overwatch off. The AI uses Overwatch a lot, so this changes the AI in ways that are hard to predict.
3. Give a unit on Overwatch a reaction bonus against movement in its cone, in place of the Overwatch shots. This is the most work. It is close to the 1.13 watched-location bonus.

Recommendation: keep both until enemy interrupts work, and then decide in play. Enemy interrupts and enemy Overwatch together can be too strong. If one option is clearly better, make it a mod option.

## Later

- Counter-interrupts (#16)
- Militia interrupts
- Interrupts from noise
- The 1.13 watched-location bonus
- Co-op (not decided)
