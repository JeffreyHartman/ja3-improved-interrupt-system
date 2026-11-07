# Improved Interrupt System

A Jagged Alliance 3 mod that adds the interrupt system of JA2 1.13. During the enemy turn, your mercs can interrupt the enemy. The enemy stops, and you give orders to the mercs that interrupted.

> **Status:** early proof of concept. Expect bugs.

## Features

- **IIS (1.13 default):** each merc registers part of the AP that a seen enemy spends. When the merc's counter reaches its reaction time, the merc interrupts.
- **Classic:** when an enemy comes into view, the merc and the enemy compare level and Agility. The higher score wins.
- **Collective interrupts:** teammates near a winner can join the interrupt.
- **Clear UI:** an INTERRUPT! banner shows at the top of the screen, and the other mercs' portraits are locked. End Turn ends the interrupt.
- **Stop or continue:** the interrupted enemy stops on its tile and attacks from there, or it continues its move.

The formulas follow the JA2 1.13 source code. `mod/Code/Rules.lua` names the 1.13 source line for each formula.

## Installation

The mod is not on the Steam Workshop yet.

1. Copy the `mod` folder to `%AppData%\Jagged Alliance 3\Mods\` and rename it to `ImprovedInterruptSystem`.
2. Start the game. In the Mod Manager, enable "Improved Interrupt System".

## Usage

Play as usual. When a merc interrupts, you control only the mercs that interrupted. Press End Turn (Enter) to end the interrupt, and the enemy turn continues.

A merc loses its Free Move AP when it enters an interrupt. The interrupt checks count only the AP that can pay for an attack.

If a merc hangs during an action, press End Turn two times.

To turn the mod off, set the "Interrupts enabled" option to off. Do not disable the mod in the Mod Manager, because a save that used the mod turns it on again.

## Options

| Option | Default | Effect |
|---|---|---|
| Interrupts enabled | on | Turns the mod on or off. |
| Interrupt system | IIS | IIS or Classic. |
| Collective interrupts (IIS) | on | Teammates within 5 tiles of a winner can join. |
| Interrupted enemy | Stop | Stop: the enemy stays on its tile. Continue: it walks on. |
| End interrupt at 0 AP | on | Ends the interrupt when no interrupter has the AP for one step. |
| Need AP for an attack | on | A merc must have the AP for an attack to interrupt (1.13 rule). |
| IIS reaction time | 25 | Lower values give more interrupts. |
| IIS AP registered (%) | 60 | Higher values give more interrupts. |
| Verbose log | off | Writes more detail to the game log. |

## Compatibility

Made for vanilla JA3 and for Rato's Gameplay Balance and Overhaul 4. Co-op is not supported.

## Not supported yet

- Enemy interrupts during your turn
- Militia interrupts
- Counter-interrupts
- Interrupts from noise
- The 1.13 watched-location bonus

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the code layout, the tests and the log.

## Credits

The interrupt rules come from the [JA2 1.13](https://github.com/1dot13/source) project.

## License

[MIT](LICENSE)
