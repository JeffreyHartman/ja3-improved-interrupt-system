# IOS is a separate option next to the Interrupt System

IOS has its own on/off option, and it is not a third value of the "Interrupt System" option (IIS, JA2 Classic, Off). Thus a player can use IOS together with IIS or JA2 Classic. The two systems give a merc a real choice each turn: keep AP for a chance to win an interrupt in all directions, or spend all AP on Overwatch for a certain interrupt in the cone.

## Considered Options

- **A third value of "Interrupt System":** only one system is active at a time, and each system has its own balance. It removes the case where two systems pause the same step. We did not choose it, because the choice between saved AP and Overwatch exists only when both systems are on.

## Consequences

- A merc on Overwatch has 0 AP, and a winner needs the AP for its default attack. Thus one merc never gets an IOS interrupt and an IIS or JA2 Classic interrupt from the same mover action.
- Two different mercs can get an interrupt on the same step: one overwatcher and one winner. The overwatchers get the first interrupt, because they prepared for it. The IIS or JA2 Classic interrupt starts after it ends, if the mover can still act.
- The handlers for IOS and for the 1.13 rule sets stay separate. Each must work when the other is off.
