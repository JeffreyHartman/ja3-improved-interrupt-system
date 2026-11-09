return {
	PlaceObj('ModItemOptionChoice', {
		'name', "InterruptSystem",
		'DisplayName', "<color AmmoHPColor>Interrupt System (Experimental)</color>",
		'Help', "IIS (the JA2 1.13 default): each merc counts the AP that a seen enemy spends. When the count reaches the merc's reaction time, the merc interrupts. JA2 Classic: when an enemy comes into view, the merc and the enemy compare level and Agility. The higher score wins, a tie goes to the enemy, and an enemy that cannot see the merc always loses. Off: no IIS or JA2 Classic interrupts. The mod stays loaded, because saves turn it back on.",
		'DefaultValue', "IIS",
		'ChoiceList', {
			"IIS",
			"JA2 Classic",
			"Off",
		},
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "Collective",
		'DisplayName', "<color AmmoHPColor>Collective interrupts (IIS)</color>",
		'Help', "When a merc wins an interrupt, teammates within 5 tiles can join it. The chance comes from Leadership, levels, Agility and Wisdom.",
		'DefaultValue', true,
	}),
	PlaceObj('ModItemOptionChoice', {
		'name', "AfterInterrupt",
		'DisplayName', "<color AmmoHPColor>Interrupted enemy</color>",
		'Help', "Stop (JA2 1.13): the enemy stays on the tile where it was interrupted, gets back the AP for the rest of its path and attacks from there. Continue: the enemy walks on to its destination.",
		'DefaultValue', "Stop",
		'ChoiceList', {
			"Stop",
			"Continue",
		},
	}),
	PlaceObj('ModItemOptionNumber', {
		'name', "ReactionTime",
		'DisplayName', "<color AmmoHPColor>IIS reaction time</color>",
		'Help', "BASIC_REACTION_TIME_LENGTH of JA2 1.13. Lower values give more interrupts. Agility, AP left, wounds and fatigue change it for each merc. Default 25.",
		'DefaultValue', 25,
		'MinValue', 5,
		'MaxValue', 60,
		'StepSize', 5,
	}),
	PlaceObj('ModItemOptionNumber', {
		'name', "BasicPercent",
		'DisplayName', "<color AmmoHPColor>IIS AP registered (%)</color>",
		'Help', "BASIC_PERCENTAGE_APS_REGISTERED of JA2 1.13: the percent of a seen enemy's AP that a merc counts, plus 4% per merc level, minus up to 25% for distance. Higher values give more interrupts. Default 60.",
		'DefaultValue', 60,
		'MinValue', 30,
		'MaxValue', 100,
		'StepSize', 10,
	}),
	PlaceObj('ModItemOptionChoice', {
		'name', "MovingTargetPenalty",
		'DisplayName', "<color AmmoTracerColor>Moving target penalty</color>",
		'Help', "A to-hit penalty for a merc's shot in an interrupt at the enemy whose action the interrupt paused. The penalty is the full value when the enemy moved 10 tiles or more across the line of fire in its current move, less for a shorter move or a move toward or away from the merc, and 0 when the enemy did not move. A reflex sight removes it. 0: no penalty. Under GBO 4 with aimed CTH, the penalty makes the aim cone wider, as other to-hit modifiers do.",
		'DefaultValue', "0",
		'ChoiceList', {
			"0",
			"10",
			"15",
			"25",
			"35",
		},
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "IOS",
		'DisplayName', "<color AmmoMatchColor>Improved Overwatch System (IOS)</color>",
		'Help', "On: when an enemy moves or attacks in the Overwatch cone of a merc, the enemy stops and the merc acts in an interrupt in place of the automatic Overwatch shot. The merc pays from the AP of its Overwatch attacks, and the AP that it does not spend stays for the next trigger. End Turn with no action costs nothing. The enemy then continues its action. Enemy Overwatch does not change. Under GBO 4, the pool uses the GBO 4 attack costs and Overwatch attack count.",
		'DefaultValue', false,
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "VerboseLog",
		'DisplayName', "<color AmmoTracerColor>Verbose log</color>",
		'Help', "Also write one log line for each merc in each interrupt check.",
		'DefaultValue', false,
	}),
	PlaceObj('ModItemCode', {
		'name', "Rules",
		'CodeFileName', "Code/Rules.lua",
	}),
	PlaceObj('ModItemCode', {
		'name', "IIS",
		'CodeFileName', "Code/IIS.lua",
	}),
	PlaceObj('ModItemCode', {
		'name', "Control",
		'CodeFileName', "Code/Control.lua",
	}),
	PlaceObj('ModItemCode', {
		'name', "IOS",
		'CodeFileName', "Code/IOS.lua",
	}),
	PlaceObj('ModItemCode', {
		'name', "UI",
		'CodeFileName', "Code/UI.lua",
	}),
	PlaceObj('ModItemCode', {
		'name', "MovingTarget",
		'CodeFileName', "Code/MovingTarget.lua",
	}),
}
