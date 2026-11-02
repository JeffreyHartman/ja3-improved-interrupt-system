# Improved Interrupt System

A Jagged Alliance 3 mod that lets units act during the turn of another team, with the interrupt rules of JA2 1.13. In prose, the product is "the mod".

## Language

### Interrupt systems

**IIS**:
The 1.13 rule set where each watcher builds a counter and interrupts when the counter reaches its reaction time. It is one of the two systems that the mod offers.
_Avoid_: IIS as a name for the mod

**Classic**:
The 1.13 rule set where a watcher and the mover compare points when the watcher first sees the mover.

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

**Interrupter**:
A unit that acts in an interrupt: a winner or a joiner.
_Avoid_: merc (as a role)

**Merc**:
A player unit. The word says nothing about the unit's role in an interrupt.

### IIS counting

**Registered AP**:
The part of a mover's AP that a watcher adds to its counter.

**Counter**:
The registered AP that a watcher holds for one mover.
_Avoid_: count

**Reaction time**:
The value that a watcher's counter must reach for the watcher to win.

### Action points

**Raw AP**:
The AP value that JA3 stores for a unit or a cost. It stays the same with GBO 4, which changes only the AP that the game shows.

**Vanilla AP**:
The AP that vanilla JA3 shows. One vanilla AP is 1000 raw AP.

**Free Move AP**:
AP that a unit gets at turn start and can spend only on moves. The unit loses the rest when it attacks or ends its turn.

**1.13 AP**:
An AP amount on the JA2 1.13 scale, converted from JA3 AP at the same rate for every unit.
_Avoid_: points, scale-100 AP
