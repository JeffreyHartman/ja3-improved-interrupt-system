return {
	PlaceObj('ModItemOptionToggle', {
		'name', "Enabled",
		'DisplayName', "Interrupts enabled",
		'Help', "Off: no interrupts. The mod stays loaded because saves turn it back on.",
		'DefaultValue', true,
	}),
	PlaceObj('ModItemOptionChoice', {
		'name', "System",
		'DisplayName', "Interrupt system",
		'Help', "IIS (the JA2 1.13 default): each merc counts the AP that a seen enemy spends. When the count reaches the merc's reaction time, the merc interrupts. Classic: when an enemy comes into view, the merc and the enemy compare level and Agility. The higher score wins, a tie goes to the enemy, and an enemy that cannot see the merc always loses.",
		'DefaultValue', "IIS",
		'ChoiceList', {
			"IIS",
			"Classic",
		},
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "Collective",
		'DisplayName', "Collective interrupts (IIS)",
		'Help', "When a merc wins an interrupt, teammates within 5 tiles can join it. The chance comes from Leadership, levels, Agility and Wisdom.",
		'DefaultValue', true,
	}),
	PlaceObj('ModItemOptionChoice', {
		'name', "AfterInterrupt",
		'DisplayName', "Interrupted enemy",
		'Help', "Stop (JA2 1.13): the enemy stays on the tile where it was interrupted, gets back the AP for the rest of its path and attacks from there. Continue: the enemy walks on to its destination.",
		'DefaultValue', "Stop",
		'ChoiceList', {
			"Stop",
			"Continue",
		},
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "AutoEnd",
		'DisplayName', "End interrupt at 0 AP",
		'Help', "On: the interrupt ends by itself when no interrupter has AP for one step. Off: only End Turn ends it, as in JA2 1.13.",
		'DefaultValue', true,
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "RequireAttackAP",
		'DisplayName', "Need AP for an attack",
		'Help', "On (JA2 1.13): a merc gets an interrupt only if it has the AP for its default attack.",
		'DefaultValue', true,
	}),
	PlaceObj('ModItemOptionNumber', {
		'name', "ReactionTime",
		'DisplayName', "IIS reaction time",
		'Help', "BASIC_REACTION_TIME_LENGTH of JA2 1.13. Lower values give more interrupts. Agility, AP left, wounds and fatigue change it for each merc. Default 25.",
		'DefaultValue', 25,
		'MinValue', 5,
		'MaxValue', 60,
		'StepSize', 5,
	}),
	PlaceObj('ModItemOptionNumber', {
		'name', "BasicPercent",
		'DisplayName', "IIS AP registered (%)",
		'Help', "BASIC_PERCENTAGE_APS_REGISTERED of JA2 1.13: the percent of a seen enemy's AP that a merc counts, plus 4% per merc level, minus up to 25% for distance. Higher values give more interrupts. Default 60.",
		'DefaultValue', 60,
		'MinValue', 30,
		'MaxValue', 100,
		'StepSize', 10,
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "VerboseLog",
		'DisplayName', "Verbose log",
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
