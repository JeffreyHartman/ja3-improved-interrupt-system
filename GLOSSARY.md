# Improved Interrupt System

A Jagged Alliance 3 mod that lets units act during the turn of another team. It offers the interrupt rules of JA2 1.13 and the IOS. In prose, the product is "the mod".

## Language

### Interrupt systems

**IIS**:
The 1.13 rule set where each watcher builds a counter and interrupts when the counter reaches its reaction time. It is one of the two 1.13 rule sets that the mod offers.
_Avoid_: IIS as a name for the mod

**JA2 Classic**:
The 1.13 rule set where a watcher and the mover compare points when the watcher first sees the mover.
_Avoid_: Classic (it can mean vanilla JA3)

**IOS**:
Improved Overwatch System. The system where the Overwatch trigger of a merc starts an interrupt in place of the vanilla Overwatch shot. It can be on together with IIS or JA2 Classic.
_Avoid_: Overwatch (as the name of the system)

**Overwatch trigger**:
The moment when a mover moves or attacks in the cone of a unit on Overwatch, and vanilla JA3 fires an Overwatch shot.

### Roles

**Mover**:
The unit that has the turn and spends AP, for any action.
_Avoid_: enemy (as a role)

**Attacker**:
A mover in the check that follows its attack.

**Watcher**:
A unit that can register the AP of a mover.

**Winner**:
A watcher that won a check.

**Joiner**:
A teammate near a winner that enters the interrupt through a collective roll. It did not win a check.
_Avoid_: collective winner

**Overwatcher**:
A unit that acts in an interrupt because of its Overwatch trigger. It did not win a check.

**Interrupter**:
A unit that acts in an interrupt. An interrupter is a winner, a joiner or an overwatcher.
_Avoid_: merc (as a role)

**Merc**:
A player unit. The word says nothing about the unit's role in an interrupt.

### Interrupt

**Interrupt**:
A pause in a mover's action in which the interrupters act. The mover's action continues when the interrupt ends.
_Avoid_: interrupt turn

**End request**:
The first End Turn press in an interrupt. The interrupt ends when no interrupter is busy.
_Avoid_: end_requested, player end

**Forced end**:
A second End Turn press while an interrupter is busy. The busy interrupters stop their actions, and the interrupt ends at once.
_Avoid_: force_end

**Auto end**:
The end of an interrupt when no interrupter has the AP for one step and no interrupter acted for a short time.
_Avoid_: out of AP end

### IIS counting

**Registered AP**:
The part of a mover's AP that a watcher adds to its counter.

**Counter**:
The registered AP that a watcher holds for one mover.
_Avoid_: count

**Move plan**:
The registered AP that each watcher gets on each step of a mover's path, from one move check. The counters get a step's AP when the mover reaches that step.

**Reaction time**:
The value that a watcher's counter must reach for the watcher to win.

### Memory

**Watcher memory**:
What a unit remembers about each enemy unit during a combat: its counter, and whether it saw that unit this turn or before. Every unit in combat has one, on both sides.

**Seen this turn**:
A unit saw an enemy unit after the start of its own last turn. JA2 Classic does not let a watcher duel a mover that it saw this turn.
_Avoid_: seen_turn

**Seen before**:
A unit saw an enemy unit at some time in the current combat. In JA2 Classic, it gives a point in a duel.
_Avoid_: seen ever, saw before

### Action points

**Raw AP**:
The AP value that JA3 stores for a unit or a cost. It stays the same with GBO 4, which changes only the AP that the game shows.

**Vanilla AP**:
The AP that vanilla JA3 shows. One vanilla AP is 1000 raw AP.

**Free Move AP**:
AP that a unit gets at turn start and can spend only on moves. The unit loses the rest when it attacks, ends its turn or enters an interrupt as an interrupter. The interrupt checks do not count it.

**1.13 AP**:
An AP amount on the JA2 1.13 scale, converted from JA3 AP at the same rate for every unit.
_Avoid_: points, scale-100 AP
