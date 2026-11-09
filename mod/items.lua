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
		'name', "UI",
		'CodeFileName', "Code/UI.lua",
	}),
}
