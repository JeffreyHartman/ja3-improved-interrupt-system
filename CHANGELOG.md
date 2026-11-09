# Changelog

This file lists the changes in each version of the mod. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

A version is `version_major.version_minor` and a patch number. The game shows the build number, which is `version` in `mod/metadata.lua`. When you bump `version`, add a section here.

## 0.7.4 (build 11), not released

### Added

- The "Improved Overwatch System (IOS)" option, off by default. When the Overwatch trigger of a merc happens, the merc acts in an interrupt in place of the vanilla Overwatch shot. Its AP in the interrupt is its Overwatch attacks multiplied by the cost of its default attack. The AP that it does not spend stays for the next trigger, and a pass costs nothing. The enemy always continues its action (#29).
- A "Moving target penalty" option. It gives a to-hit penalty for a merc's shot in an interrupt at the enemy that the interrupt paused, by the design of the vanilla Evasive Movement modifier. The default 0 gives no penalty (#35).

### Changed

- The "Interrupt System (Experimental)" option has the values IIS, JA2 Classic and Off. It replaces the "JA2 1.13 interrupts (Experimental)" and "Interrupt system" options. "Classic" is now "JA2 Classic". Old settings become the new settings (#28).
- The "End interrupt at 0 AP" and "Need AP for an attack" options are removed. Their rules are always on (#28).
- Each option has the color of its group in the options list (#28).
- The mod description names IIS, JA2 Classic and IOS (#28).

- The code that runs an interrupt is in a new module, `IISControl`. Each entry type of the provoke list has a handler, and the 1.13 checks are the first handler. This prepares Improved Overwatch (#17). The game does not change (#19, #26).
- The "Interrupted enemy" option is read when the interrupt begins. A change to the option during an interrupt has an effect only on the next interrupt.
- An error in a provoke-list handler is logged, and the enemy action continues with the vanilla interrupts.

### Fixed

- A stopped enemy goes to the center of its tile, so it gets back the AP for the rest of its path (#18).
- The interrupt camera points at the enemy (#18).
- A merc loses its Free Move AP when it enters an interrupt. The interrupt checks count only the AP that can pay for an attack (#15).
- The banner shows only "INTERRUPT!", and the End Turn button keeps its label (#7).

## 0.7.3 (build 10), 2026-11-02

### Added

- Saves keep the IIS counters. Saves from 0.7.2 and earlier load with empty counters (#5, #6).

### Fixed

- When a vanilla interrupt, for example Overwatch, stops an enemy move, the AP of the steps that the enemy walked stays registered for the IIS checks (#4, #6).

## 0.7.2 (build 9), 2026-11-01

### Changed

- The mod name is now "Improved Interrupt System".
- AP converts to 1.13 AP at a fixed rate (#1, #3).

## 0.7.1 (build 8), 2026-11-01

### Added

- Log lines for an interrupt after an attack.

## 0.7.0 (build 7), 2026-10-29

### Added

- The first version: player-controlled interrupts with the JA2 1.13 rules.
