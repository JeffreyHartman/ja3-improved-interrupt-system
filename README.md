# Improved Interrupt System

A Jagged Alliance 3 mod that adds the interrupt system of JA2 1.13. During the enemy turn, your mercs can interrupt the enemy. The enemy stops, and you give orders to the mercs that interrupted.

> **Status:** experimental. Interrupts change the game balance a lot, and bugs are possible.

## Features

- **IIS (1.13 default):** each merc registers part of the AP that a seen enemy spends. When the merc's counter reaches its reaction time, the merc interrupts.
- **JA2 Classic:** when an enemy comes into view, the merc and the enemy compare level and Agility. The higher score wins.
- **Collective interrupts:** teammates near a winner can join the interrupt.
- **Clear UI:** an INTERRUPT! banner shows at the top of the screen, and the other mercs' portraits are locked. End Turn ends the interrupt.
- **Stop or continue:** the interrupted enemy stops on its tile and attacks from there, or it continues its move.
- **Improved Overwatch System (IOS):** when an enemy moves or attacks in the Overwatch cone of a merc, the merc acts in an interrupt in place of the automatic Overwatch shot. The merc pays from the AP of its Overwatch attacks, and End Turn with no action costs nothing. IOS is a separate option, and it works with or without the 1.13 interrupts.

The formulas follow the JA2 1.13 source code. `mod/Code/Rules.lua` names the 1.13 source line for each formula.

## Installation

The mod is not on the Steam Workshop yet.

1. Copy the `mod` folder to `%AppData%\Jagged Alliance 3\Mods\` and rename it to `ImprovedInterruptSystem`.
2. Start the game. In the Mod Manager, enable "Improved Interrupt System".

## Usage

Play as usual. When a merc interrupts, you control only the mercs that interrupted. Press End Turn (Enter) to end the interrupt, and the enemy turn continues.

A merc loses its Free Move AP when it enters an interrupt. The interrupt checks count only the AP that can pay for an attack.

If a merc hangs during an action, press End Turn two times.

To turn the interrupts off, set the "Interrupt System (Experimental)" option to Off. Do not disable the mod in the Mod Manager, because a save that used the mod turns it on again.

An interrupt ends by itself when no interrupter has the AP for one step. A merc gets an interrupt only if it has the AP for its default attack (1.13 rule).

## Options

The options list shows each group of options in one color: one color for the Interrupt System, one for IOS, and one for the options of both systems.

| Option | Group | Default | Effect |
|---|---|---|---|
| Interrupt System (Experimental) | Interrupt System | IIS | IIS, JA2 Classic or Off. |
| Collective interrupts (IIS) | Interrupt System | on | Teammates within 5 tiles of a winner can join. |
| Interrupted enemy | Interrupt System | Stop | Stop: the enemy stays on its tile. Continue: it walks on. |
| IIS reaction time | Interrupt System | 25 | Lower values give more interrupts. |
| IIS AP registered (%) | Interrupt System | 60 | Higher values give more interrupts. |
| Interrupt aim limit | Interrupt System | 100% | The part of the weapon's aim levels that a merc can use in an IIS or JA2 Classic interrupt, rounded up. |
| Improved Overwatch System (IOS) | IOS | off | The Overwatch trigger of a merc starts an interrupt in place of the Overwatch shot. |
| IOS actions | IOS | Shot only | Shot only: the merc can shoot at an enemy in its Overwatch cone that it can see, or reload. Any action: the merc can do any action. A move, a stance change or another action that is not an attack or a reload ends Overwatch. |
| IOS aim limit | IOS | 100% | The part of the weapon's aim levels that a merc can use in an IOS interrupt, rounded up. |
| IOS free aim levels | IOS | 1 | The minimum aim level of a merc's shot in an IOS interrupt. These levels cost no AP. Killzone gives at least 1. |
| IOS full aim under GBO 4 | IOS | off | Under GBO 4 in old CTH mode, an IOS shot gets the full aim bonus in place of half. |
| Moving target penalty | Both systems | 0 | A to-hit penalty for a shot in an interrupt at an enemy that moved across the line of fire. |
| Verbose log | Both systems | off | Writes more detail to the game log. |

A setting from version 0.7.3 or earlier becomes a new setting. "JA2 1.13 interrupts (Experimental) = off" becomes "Interrupt System = Off", and "Classic" becomes "JA2 Classic".

## Compatibility

Made for vanilla JA3 and for Rato's Gameplay Balance and Overhaul 4. Co-op is not supported.

## Not supported yet

- Enemy interrupts during your turn
- Militia interrupts
- Counter-interrupts
- Interrupts from noise
- The 1.13 watched-location bonus

See [ROADMAP.md](ROADMAP.md) for the plan.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the code layout, the tests and the log.

## Credits

The interrupt rules come from the [JA2 1.13](https://github.com/1dot13/source) project.

## License

[MIT](LICENSE)
