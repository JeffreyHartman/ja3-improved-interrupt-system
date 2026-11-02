# Convert JA3 AP to 1.13 AP at a fixed rate

The IIS formulas convert every JA3 AP cost at one fixed rate for all units: 12 vanilla JA3 AP = 100 1.13 AP. They do not use the mover's own max AP or its AP at turn start, because 1.13 registers the absolute cost of an action (`Points.cpp:1041`) and 100 is the 1.13 AP ceiling, not the size of each turn. At this rate, one walk step costs 8 1.13 AP, the same as the 1.13 walk cost.

## Considered Options

- **The mover's max AP:** an action counts for less when the mover has more max AP. The same 5 AP shot counts as 36 at 14 max AP and as 56 at 9 max AP. 1.13 counts both the same.
- **The mover's AP at turn start:** this value includes Free Move AP, which only moves can spend. The test log shows 183 AP against a max of 113, and the extra 70 AP is Free Move AP. It cannot pay for a shot, and the unit loses the rest when it attacks.

## Consequences

- The rate is in raw AP, not `const.Scale.AP`, because GBO 4 changes that scale and keeps raw AP. 12 vanilla AP is 12000 raw AP in both setups.
- GBO 4 attacks cost more than vanilla attacks, so they register more AP. The formula stays the same in both setups.
- The minimum AP to interrupt uses the fixed 1.13 values: 4 for IIS and 16 for Classic. The rate is a constant, not a mod option, because the reaction time and AP registered options already tune interrupt frequency.
- The reaction time keeps the ratio of the watcher's AP to its own max AP, as 1.13 does (`Soldier Control.cpp:24893`).
