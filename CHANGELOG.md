# Changelog

This file lists the changes in each version of the mod. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

A version is `version_major.version_minor` and a patch number. The game shows the build number, which is `version` in `mod/metadata.lua`. When you bump `version`, add a section here.

## 0.8.0 (build 12), not released

### Added

- The "Improved Overwatch System (IOS)" option, off by default. When the Overwatch trigger of a merc happens, the merc acts in an interrupt in place of the vanilla Overwatch shot. Its AP in the interrupt is its Overwatch attacks multiplied by the cost of its default attack. The AP that it does not spend stays for the next trigger, and a pass costs nothing. The enemy always continues its action (#29).
- The "IOS actions" option. With "Shot only", the default, an overwatcher can only shoot at an enemy in its Overwatch cone that it can see, or reload. With "Any action", it can do any action that its pool pays for. A move, a stance change or an action that is not an attack or a reload ends Overwatch after the interrupt (#31).
- The shot of a merc in an IOS interrupt is an Overwatch attack for the game rules, in the to-hit preview and in the attack. The Overwatch to-hit modifier, the vanilla crit rule and the Overwatch perks apply to it (#32).
- The "IOS aim limit" and "Interrupt aim limit" options: 25%, 50%, 75% or 100% of the weapon's aim levels, rounded up, in an IOS interrupt or in an IIS or JA2 Classic interrupt. The default 100% gives all aim levels (#33).
- The "IOS free aim levels" option: 0, 1 or 2, default 1. It is the minimum aim level of a merc's shot in an IOS interrupt, and the levels up to it cost no AP. Under GBO 4, the Shooting Stance level counts toward it. Killzone gives 1 free level, or the GBO 4 Killzone ladder value under GBO 4, when that is higher than the option (#34).
- An "IOS full aim under GBO 4" option, off by default. Under GBO 4 in old CTH mode, an IOS shot then gets the full aim bonus in place of half. The shot stays an Overwatch attack (#36).
- A "Moving target penalty" option. It gives a to-hit penalty for a merc's shot in an interrupt at the enemy that the interrupt paused, by the design of the vanilla Evasive Movement modifier. The default 0 gives no penalty (#35).

### Changed

- The "Interrupt System (Experimental)" option has the values IIS, JA2 Classic and Off. It replaces the "JA2 1.13 interrupts (Experimental)" and "Interrupt system" options. "Classic" is now "JA2 Classic". Old settings become the new settings (#28).
- The "End interrupt at 0 AP" and "Need AP for an attack" options are removed. Their rules are always on (#28).
- Each option has the color of its group in the options list (#28).
- The mod description names IIS, JA2 Classic and IOS (#28).
- An error in a provoke-list handler is logged, and the enemy action continues with the vanilla interrupts.
- A merc on Overwatch never wins an IIS or JA2 Classic interrupt (#17).
- No interrupt starts on an enemy that is dead or downed (#30).
- When the game cannot give a unit's attack cost, the log gives the error. Each unit writes this line once per combat turn. The skip reason is then `attack cost unknown`, not `AP below attack cost` (#38).

## 0.7.4 (build 11), not released

### Changed

- The code that runs an interrupt is in a new module, `IISControl`. Each entry type of the provoke list has a handler, and the 1.13 checks are the first handler. This prepares Improved Overwatch (#17). The game does not change (#19, #26).
- The "Interrupted enemy" option is read when the interrupt begins. A change to the option during an interrupt has an effect only on the next interrupt.

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
