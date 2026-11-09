-- Tests for the game-side logic in mod/Code/IIS.lua, Control.lua and IOS.lua. They load the
-- real files with fake engine globals, then replace IIS.E (the engine reads) with fakes. They
-- use the real IISMemory and IISInterrupt modules.
-- They do not cover UI.lua or anything that needs a running game.

local t = Test
local R = IISRules

------------------------------------------------------------------------------------------------
-- Fake engine globals, just enough to load the two files.

local log_lines = {}
function print(line)
	log_lines[#log_lines + 1] = line
end

local function LogHas(pattern)
	for _, line in ipairs(log_lines) do
		if line:find(pattern) then
			return true
		end
	end
	return false
end

function table.find(tbl, a, b)
	for i, v in ipairs(tbl or {}) do
		if b == nil then
			if v == a then return i end
		elseif type(v) == "table" and v[a] == b then
			return i
		end
	end
end

function table.iclear(tbl)
	for i = #tbl, 1, -1 do
		tbl[i] = nil
	end
end

function pack_params(...)
	return table.pack(...)
end

function unpack_params(p, i, j)
	return table.unpack(p, i or 1, j or p.n)
end

empty_table = {}
const = {
	Scale = { AP = 1000 },
	["Action Point Costs"] = { Walk = 1000, CrouchModifier = 50, ProneModifier = 100 },
	SlabSizeX = 1200,
	Combat = { AwareSightRange = 24 },
}
CurrentModOptions = {}
CurrentModId = "ImprovedInterruptSystem"

function GameVar(name, default)
	_G[name] = type(default) == "function" and default() or default
end

function IsValid(obj)
	return type(obj) == "table" and obj.valid ~= false
end

function IsKindOf(obj, class)
	return type(obj) == "table" and obj.kinds and obj.kinds[class] or false
end

function MulDivRound(a, b, c)
	return math.floor(a * b / c + 0.5)
end

function Max(a, b)
	return a > b and a or b
end

local game_time = 0
function GameTime()
	return game_time
end

local threads_started = {}
function CreateGameTimeThread(f, ...)
	threads_started[#threads_started + 1] = table.pack(f, ...)
end

local function RunThreads()
	local list = threads_started
	threads_started = {}
	for _, th in ipairs(list) do
		th[1](table.unpack(th, 2, th.n))
	end
end

function CreateRealTimeThread(f, ...)
	CreateGameTimeThread(f, ...)
end

function point_pack(p)
	return p
end

function GetPackedPosAndStance(unit)
	return string.format("packed %d,%d", unit.pos.x, unit.pos.y)
end

function GetPassSlab(p)
	return p
end

function ObjModified() end
function IsValidThread() return false end
function IsSetpiecePlaying() return false end

CombatActions_RunningState = {}
CombatActions_Waiting = {}
CombatActions = {
	Move = { SimultaneousPlay = true, group = "Default" },
	Attack = { ActionType = "Ranged Attack", group = "FiringModeMetaAction" },
	Reload = { group = "Hidden" },
}

function HasCombatActionInProgress(unit)
	return CombatActions_RunningState[unit] and true or false
end

local ran_actions = {}
function RunCombatAction(action_id, unit, ap)
	ran_actions[#ran_actions + 1] = { action_id, unit, ap }
end

g_Combat = { SetActiveUnit = function() end }
g_AIExecutionController = {}
g_StartingCombat = false
g_Teams = {}
g_CurrentTeam = 2
netUniqueId = 1

local vanilla_result = {}
local vanilla_provoked = {}
local vanilla_attacks = {}
-- Like vanilla, the fake list function attacks for each "overwatch" entry and adds every entry to
-- the mover's passed_interrupts.
Unit = {
	CheckProvokeOpportunityAttacks = function()
		return vanilla_result.interrupts, vanilla_result.idx
	end,
	ProvokeOpportunityAttacksFromList = function(mover, list)
		vanilla_provoked[#vanilla_provoked + 1] = list
		for _, data in ipairs(list) do
			if data[1] == "overwatch" then
				vanilla_attacks[#vanilla_attacks + 1] = data[2]
			end
			mover.passed_interrupts = mover.passed_interrupts or {}
			table.insert(mover.passed_interrupts, data)
		end
	end,
	CanBeControlled = function() return "vanilla" end,
	IsIdleOrRunningBehavior = function() return "vanilla" end,
	-- Like vanilla, it returns a copy of `args` with the attacker and the weapon of the action.
	PrepareAttackArgs = function(unit, action_id, args)
		local attack_args = {}
		for k, v in pairs(args or {}) do
			attack_args[k] = v
		end
		attack_args.action_id, attack_args.obj = action_id, unit
		attack_args.weapon = attack_args.weapon or unit.weapon
		return attack_args
	end,
}
function IsNetPlayerTurn() return "vanilla" end
function CombatActionCannotBeStarted() return "vanilla" end
function NetStartCombatAction() return "vanilla" end
local vanilla_started = {}
function StartCombatAction(...)
	vanilla_started[#vanilla_started + 1] = table.pack(...)
end
function WaitOtherCombatActionsEnd() return "vanilla" end
IModeCombatMovement = { OnMouseButtonDown = function() return "vanilla" end }
NetSyncEvents = { EndTurn = function() return "vanilla" end }
NetSyncLocalEffects = { EndTurn = function() return "vanilla" end }
-- Like the game, OnMsg keeps every handler that a file defines and runs them in the order of definition.
local msg_handlers = {}
OnMsg = setmetatable({}, {
	__newindex = function(_, name, fn)
		msg_handlers[name] = msg_handlers[name] or {}
		table.insert(msg_handlers[name], fn)
	end,
	__index = function(_, name)
		return function(...)
			for _, fn in ipairs(msg_handlers[name] or {}) do
				fn(...)
			end
		end
	end,
})

dofile("mod/Code/IIS.lua")
dofile("mod/Code/Control.lua")
dofile("mod/Code/IOS.lua")
-- The game sends ModsReloaded after it runs the code files.
OnMsg.ModsReloaded()

local Q = IIS
local E = Q.E
local Mem = IISMemory

------------------------------------------------------------------------------------------------
-- Fake units and engine reads

local player_team = { side = "player1", control = "UI" }
local enemy_team = { side = "enemy1", control = "AI" }

local function FakeUnit(o)
	local u = {
		kinds = { Unit = true },
		session_id = o.id,
		handle = o.id,
		team = o.team or player_team,
		ActionPoints = (o.ap or 10000) + (o.free_move_ap or 0),
		free_move_ap = o.free_move_ap or 0,
		max_ap = o.max_ap or 12000,
		level = o.level or 5,
		agility = o.agility or 80,
		HitPoints = 100,
		MaxHitPoints = 100,
		stance = o.stance or "Standing",
		statuses = o.statuses or {},
		pos = o.pos or { x = 0, y = 0 },
		attack_cost = o.attack_cost or 4000,
		command = o.command or "Idle",
		command_thread = o.thread,
	}
	function u:GetLevel() return self.level end
	function u:GetProperty(k)
		if k == "Agility" then return self.agility end
		return 50
	end
	function u:IsIncapacitated() return self.down or false end
	function u:IsDead() return self.dead or false end
	function u:IsOnEnemySide(other) return self.team.side ~= other.team.side end
	function u:HasNightVision() return false end
	function u:GetPos() return self.pos end
	function u:GetVisualPos() return self.pos end
	function u:GainAP(n) self.ActionPoints = self.ActionPoints + n end
	function u:ConsumeAP(n) self.ActionPoints = self.ActionPoints - (n or 0) end
	function u:RemoveStatusEffect(id)
		if id == "FreeMove" and self.statuses.FreeMove then
			self:ConsumeAP(self.free_move_ap)
			self.free_move_ap = 0
		end
		self.statuses[id] = nil
	end
	function u:IsIdleCommand() return self.command == "Idle" end
	function u:SetCommand(cmd) self.command = cmd end
	return u
end

local function Dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.floor(math.sqrt(dx * dx + dy * dy))
end

local world = {}

local function EndActive()
	local it = IISControl.Active()
	if it then
		Q.UI = { End = function() end }
		IISControl.EndInterrupt(it, "test")
	end
end

local function ResetWorld()
	world = { players = {}, los = {}, sees = {}, mover_sees = {}, cone = {}, rand = 99 }
	Q.attack_targets = {}
	EndActive()
	gv_IIS = {}
	Mem.Setup{
		key = function(u) return E.Key(u) end,
		same_tile = function(a, b) return E.SameTile(a, b) end,
		store = function() return gv_IIS end,
	}
	vanilla_result = {}
	vanilla_provoked = {}
	vanilla_attacks = {}
	Q.Config.system = "IIS"
	Q.Config.collective = true
	Q.ResetTurnStats()
	CombatActions_RunningState = {}
	ran_actions = {}
	vanilla_started = {}
	threads_started = {}
	g_AIExecutionController = {}
end

E.PlayerUnits = function() return world.players end
E.CanControlTeam = function(u) return u.team.control == "UI" end
E.IsAITurnEnemy = function(u) return u.team.control ~= "UI" end
E.MaxAPRaw = function(u) return u.max_ap end
E.StepRaw = function(stance) return stance == "Crouch" and 1500 or 1000 end
E.WalkRaw = function() return 1000 end
E.AttackCostRaw = function(u) return u.attack_cost end
E.Status = function(u, id) return u.statuses[id] or false end
E.Perk = function() return false end
E.SeesNow = function(a, b) return world.sees[a] and world.sees[a][b] or false end
E.VisibleEnemyCount = function() return 1 end
E.DistTiles = function(u, pos) return Dist(u.pos, pos) end
E.Dist = function(u, pos) return Dist(u.pos, pos) end
E.MaxSightTiles = function() return 24 end
E.Sight = function() return 24, false end
E.WatcherSeesStep = function(w, mover, dummy)
	local row = world.los[w]
	return row and dummy.i and row[dummy.i] or false
end
E.MoverSeesWatcher = function(mover, dummy, w) return world.mover_sees[w] ~= false end
E.TeamSees = function() return false end
E.IsCurrentPos = function(mover, pos) return pos == mover.pos end
E.SameTile = function(a, b) return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y end
E.Key = function(u) return u.session_id end
E.InCommandThread = function(u) return u.in_cmd or false end
E.Rand = function() return world.rand end

-- A straight path of n dummies along x, starting on the mover's tile.
local function Path(mover, n, stance)
	local dummies = { { pos = mover.pos, stance = stance or mover.stance, i = 1 } }
	for i = 2, n do
		dummies[i] = { pos = { x = mover.pos.x + i - 1, y = mover.pos.y }, stance = stance or mover.stance, i = i }
	end
	return dummies
end

local function Steps(...)
	local row = {}
	for _, i in ipairs({ ... }) do
		row[i] = true
	end
	return row
end

-- Starts an interrupt with IISControl.Activate, as the provoke-list wrapper does, without the engine calls around it.
local function ActiveState(interrupters, mover)
	local it = IISInterrupt.Begin{ n = 1, mover = mover, interrupters = interrupters, cfg = Q.Config }
	IISControl.Activate(it)
	return it
end

------------------------------------------------------------------------------------------------
-- Game messages

t.case("The OnMsg fake runs every handler for a message in the order of definition", function()
	local calls = {}
	function OnMsg.IISTestMessage(x) calls[#calls + 1] = "first " .. x end
	function OnMsg.IISTestMessage(x) calls[#calls + 1] = "second " .. x end
	OnMsg.IISTestMessage("a")
	t.eq(#calls, 2)
	t.eq(calls[1], "first a")
	t.eq(calls[2], "second a")
end)

------------------------------------------------------------------------------------------------
-- Mod options

-- Gives the options to the mod as the game does when it loads them or when the player applies them.
local function ApplyModOptions(options)
	CurrentModOptions = options
	OnMsg.ApplyModOptions(CurrentModId)
	return options
end

t.case("Options from an older version: Enabled = off gives Interrupt System = Off", function()
	local o = ApplyModOptions({ Enabled = false, System = "IIS" })
	t.eq(Q.Config.system, "Off")
	t.eq(o.InterruptSystem, "Off")
	ApplyModOptions({})
end)

t.case("Options from an older version: Classic gives JA2 Classic, and the log names JA2 Classic", function()
	log_lines = {}
	local o = ApplyModOptions({ Enabled = true, System = "Classic" })
	t.eq(Q.Config.system, "JA2 Classic")
	t.eq(o.InterruptSystem, "JA2 Classic")
	t.eq(LogHas("mod options applied: system=JA2 Classic "), true)
	ApplyModOptions({})
end)

t.case("Options: a stored Interrupt System value wins over the old values that stay in the storage", function()
	t.eq(ApplyModOptions({ InterruptSystem = "IIS", Enabled = false, System = "Classic" }).InterruptSystem, "IIS")
	t.eq(Q.Config.system, "IIS")
	ApplyModOptions({ InterruptSystem = "JA2 Classic", System = "IIS" })
	t.eq(Q.Config.system, "JA2 Classic")
	ApplyModOptions({ InterruptSystem = "Off", Enabled = true })
	t.eq(Q.Config.system, "Off")
	ApplyModOptions({})
end)

t.case("Options: with no stored value, the Interrupt System is IIS", function()
	t.eq(ApplyModOptions({}).InterruptSystem, "IIS")
	t.eq(Q.Config.system, "IIS")
end)

local function LoadModFile(path)
	local saved = rawget(_G, "PlaceObj")
	function PlaceObj(class, props)
		local obj = { class = class }
		for i = 1, #props, 2 do
			obj[props[i]] = props[i + 1]
		end
		return obj
	end
	local result = dofile(path)
	PlaceObj = saved
	return result
end

local group_colors = {
	["Interrupt System"] = "AmmoHPColor",
	IOS = "AmmoMatchColor",
	["both systems"] = "AmmoTracerColor",
}

t.case("The options list: no removed option, and each option has the color tag of one group", function()
	local names = {}
	for _, item in ipairs(LoadModFile("mod/items.lua")) do
		if item.class:find("^ModItemOption") then
			names[item.name] = item
			local color = item.DisplayName:match("^<color (%w+)>.*</color>$")
			local in_group = false
			for _, c in pairs(group_colors) do
				in_group = in_group or c == color
			end
			t.eq(in_group, true, item.name .. " color " .. tostring(color))
		end
	end
	t.eq(names.Enabled, nil)
	t.eq(names.System, nil)
	t.eq(names.AutoEnd, nil)
	t.eq(names.RequireAttackAP, nil)
	t.eq(table.concat(names.InterruptSystem.ChoiceList, ","), "IIS,JA2 Classic,Off")
	t.eq(names.InterruptSystem.DefaultValue, "IIS")
	t.eq(names.InterruptSystem.DisplayName:match("<color (%w+)>"), group_colors["Interrupt System"])
	t.eq(names.VerboseLog.DisplayName:match("<color (%w+)>"), group_colors["both systems"])
	t.eq(table.concat(names.IOSActions.ChoiceList, ","), "Shot only,Any action")
	t.eq(names.IOSActions.DefaultValue, "Shot only")
	t.eq(names.IOSActions.DisplayName:match("<color (%w+)>"), group_colors.IOS)
	t.eq(names.IOSActions.Help:find("GBO 4") ~= nil, true)
end)

t.case("Options: IOS actions gives the action limit of an overwatcher, and Shot only is the default", function()
	t.eq(ApplyModOptions({ IOSActions = "Any action" }) and Q.Config.ios_actions, "any")
	t.eq(ApplyModOptions({ IOSActions = "Shot only" }) and Q.Config.ios_actions, "shot")
	t.eq(ApplyModOptions({}) and Q.Config.ios_actions, "shot")
end)

t.case("metadata.lua gives a default for each option except InterruptSystem", function()
	local defaults = LoadModFile("mod/metadata.lua").default_options
	t.eq(defaults.InterruptSystem, nil)
	local options = {}
	for _, item in ipairs(LoadModFile("mod/items.lua")) do
		if item.class:find("^ModItemOption") and item.name ~= "InterruptSystem" then
			options[item.name] = true
			t.eq(defaults[item.name], item.DefaultValue, item.name)
		end
	end
	for name in pairs(defaults) do
		t.eq(options[name], true, name)
	end
end)

t.case("Options from an older version: Need AP for an attack = off still refuses a winner without the attack AP", function()
	ResetWorld()
	ApplyModOptions({ RequireAttackAP = false })
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 3000, attack_cost = 4000 }), "IIS"), "AP below attack cost")
	ApplyModOptions({})
end)

------------------------------------------------------------------------------------------------
-- Mover and watcher filters

t.case("MoverSkipReason accepts an AI enemy's move during the AI turn", function()
	ResetWorld()
	local mover = FakeUnit({ id = "enemy", team = enemy_team })
	t.eq(Q.MoverSkipReason(mover, "move"), nil)
	t.eq(Q.MoverSkipReason(mover, "attack reaction"), nil)
end)

t.case("MoverSkipReason refuses previews, other triggers, player units and the reposition phase", function()
	ResetWorld()
	local mover = FakeUnit({ id = "enemy", team = enemy_team })
	t.eq(Q.MoverSkipReason(mover, "attack interrupt"), "trigger attack interrupt")
	t.eq(Q.MoverSkipReason(mover, "move", nil, "any"), "preview")
	t.eq(Q.MoverSkipReason(mover, "move", true), "visible_only")
	t.eq(Q.MoverSkipReason(FakeUnit({ id = "merc" }), "move"), "mover is not on the AI team that has the turn")
	g_AIExecutionController = { reposition = true }
	t.eq(Q.MoverSkipReason(mover, "move"), "reposition phase")
	g_AIExecutionController = false
	t.eq(Q.MoverSkipReason(mover, "move"), "no AI turn")
end)

t.case("WinSkipReason: the AP minimum does not depend on the watcher's max AP", function()
	ResetWorld()
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 1500, max_ap = 6000, attack_cost = 1000 }), "JA2 Classic"), "AP below minimum")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 500, max_ap = 24000, attack_cost = 500 }), "IIS"), nil)
end)

t.case("WinSkipReason: Free Move AP does not pay for the attack or the AP minimum", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 3000, free_move_ap = 29000, attack_cost = 4000, statuses = { FreeMove = true } })
	t.eq(Q.WinSkipReason(a, "IIS"), "AP below attack cost")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "b", ap = 0, free_move_ap = 29000 }), "IIS"), "AP below minimum")
end)

t.case("IISWatcher: the AP of the reaction time leaves out Free Move AP", function()
	ResetWorld()
	t.eq(Q.IISWatcher(FakeUnit({ id = "a", ap = 6000, free_move_ap = 3000 })).ap, 6000)
end)

t.case("RemoveFreeMove: the interrupter loses its Free Move AP and the FreeMove status", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 4000, free_move_ap = 29000, statuses = { FreeMove = true } })
	t.eq(IISControl.RemoveFreeMove(a), 29000)
	t.eq(a.ActionPoints, 4000)
	t.eq(a.free_move_ap, 0)
	t.eq(a.statuses.FreeMove, nil)
end)

t.case("RemoveFreeMove: Free Move AP without the status is also removed", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 4000, free_move_ap = 2000 })
	t.eq(IISControl.RemoveFreeMove(a), 2000)
	t.eq(a.ActionPoints, 4000)
	t.eq(a.free_move_ap, 0)
end)

t.case("RemoveFreeMove: a unit with no Free Move AP keeps its AP", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 4000 })
	t.eq(IISControl.RemoveFreeMove(a), 0)
	t.eq(a.ActionPoints, 4000)
end)

t.case("WinSkipReason: AP minimum, attack cost and blocking statuses", function()
	ResetWorld()
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 10000 }), "IIS"), nil)
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 1500, attack_cost = 1000 }), "JA2 Classic"), "AP below minimum")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 3000, attack_cost = 4000 }), "IIS"), "AP below attack cost")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", statuses = { Panicked = true } }), "IIS"), "Panicked")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", statuses = { Suppressed = true } }), "JA2 Classic"), "under fire")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", statuses = { Suppressed = true } }), "IIS"), nil)
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", statuses = { Choking = true } }), "JA2 Classic"), "gassed")
end)

------------------------------------------------------------------------------------------------
-- JA2 Classic move trigger

t.case("JA2 Classic: the earliest winning step wins, a loser before it does not block", function()
	ResetWorld()
	Q.Config.system = "JA2 Classic"
	local mover = FakeUnit({ id = "enemy", team = enemy_team, level = 1, agility = 30, pos = { x = 0, y = 0 } })
	local a = FakeUnit({ id = "a", level = 5, agility = 85, pos = { x = 2, y = 3 } })
	local b = FakeUnit({ id = "b", level = 3, agility = 70, pos = { x = 2, y = -3 } })
	local weak = FakeUnit({ id = "weak", level = 1, agility = 30, pos = { x = 1, y = 2 } })
	local saw = FakeUnit({ id = "saw", pos = { x = 1, y = -2 } })
	world.players = { weak, b, a, saw }
	world.los[a] = Steps(3, 4)
	world.los[b] = Steps(3)
	world.los[weak] = Steps(2, 3)
	world.los[saw] = Steps(2)
	Mem.Sees(saw, mover)
	local dummies = Path(mover, 4)
	local idx, winners = Q.FindClassicMoveTrigger(mover, dummies, 1)
	t.eq(idx, 3)
	t.eq(#winners, 2)
	t.eq(winners[1].unit, a) -- 6 vs 2, margin 4
	t.eq(winners[2].unit, b) -- 4 vs 2, margin 2
	t.eq(Q.turn_stats.watcher_skips["saw mover this turn"], 1)
end)

t.case("JA2 Classic: a watcher with LOS to the mover's tile is skipped", function()
	ResetWorld()
	Q.Config.system = "JA2 Classic"
	local mover = FakeUnit({ id = "enemy", team = enemy_team, level = 1, agility = 30 })
	local a = FakeUnit({ id = "a", pos = { x = 2, y = 2 } })
	world.players = { a }
	world.los[a] = Steps(3)
	local orig = E.WatcherSeesStep
	E.WatcherSeesStep = function(w, m, dummy)
		if dummy.i == nil then return true end -- the start target has no index
		return orig(w, m, dummy)
	end
	local idx = Q.FindClassicMoveTrigger(mover, Path(mover, 4), 1)
	E.WatcherSeesStep = orig
	t.eq(idx, nil)
	t.eq(Q.turn_stats.watcher_skips["has LOS at the mover's tile"], 1)
end)

t.case("JA2 Classic: an unseen watcher wins even with a lower score", function()
	ResetWorld()
	Q.Config.system = "JA2 Classic"
	local mover = FakeUnit({ id = "enemy", team = enemy_team, level = 9, agility = 95 })
	local a = FakeUnit({ id = "a", level = 1, agility = 30, pos = { x = 3, y = 1 } })
	world.players = { a }
	world.los[a] = Steps(2)
	world.mover_sees[a] = false
	local idx, winners = Q.FindClassicMoveTrigger(mover, Path(mover, 3), 1)
	t.eq(idx, 2)
	t.eq(winners[1].how, "automatic")
end)

t.case("JA2 Classic: a watcher under fire does not duel", function()
	ResetWorld()
	Q.Config.system = "JA2 Classic"
	local mover = FakeUnit({ id = "enemy", team = enemy_team, level = 1, agility = 30 })
	local a = FakeUnit({ id = "a", level = 9, agility = 95, pos = { x = 3, y = 1 }, statuses = { Suppressed = true } })
	world.players = { a }
	world.los[a] = Steps(2)
	t.eq(Q.FindClassicMoveTrigger(mover, Path(mover, 3), 1), nil)
	t.eq(Q.turn_stats.watcher_skips["under fire"], 1)
end)

------------------------------------------------------------------------------------------------
-- IIS move trigger and counters

-- Watcher a: level 5, agility 80, 10 of 12 AP -> reaction time 27. It stands 6 tiles from the
-- path, so it registers 74% of 8 AP per step = 6.
local function IISSetup(counter)
	ResetWorld()
	local mover = FakeUnit({ id = "enemy", team = enemy_team, pos = { x = 0, y = 0 }, max_ap = 12000 })
	local a = FakeUnit({ id = "a", level = 5, agility = 80, ap = 10000, max_ap = 12000, pos = { x = 0, y = 6 } })
	world.players = { a }
	world.los[a] = Steps(2, 3, 4, 5, 6)
	E.Dist = function() return 6 end
	if counter then
		Mem.Register(a, mover, counter)
	end
	return mover, a
end

t.case("IIS: the reaction time and the AP per step match the hand calculation", function()
	local mover, a = IISSetup()
	t.eq(R.IISReactionTime(Q.IISWatcher(a), Q.RulesConfig()), 27)
	t.eq(Q.RegisteredPercent(a, mover, { x = 0, y = 0 }), 74)
end)

t.case("IIS: the counter reaches the reaction time on the fifth step", function()
	local mover, a = IISSetup()
	local idx, winners, rows, plan = Q.FindIISMoveTrigger(mover, Path(mover, 6), 1)
	t.eq(idx, 6) -- 6, 12, 18, 24, 30
	t.eq(winners[1].unit, a)
	t.eq(winners[1].margin, 3)
	t.eq(plan.first, 2)
	t.eq(rows[1].cum[6], 30)
end)

t.case("IIS: a step registers the same AP for a mover with more max AP", function()
	local mover, a = IISSetup()
	mover.max_ap = 24000
	local idx, _, rows = Q.FindIISMoveTrigger(mover, Path(mover, 6), 1)
	t.eq(idx, 6)
	t.eq(rows[1].cum[6], 30) -- 6 per step
end)

t.case("IIS: AP registered before the move bring the interrupt forward", function()
	local mover = IISSetup(10)
	local idx = Q.FindIISMoveTrigger(mover, Path(mover, 6), 1)
	t.eq(idx, 4) -- 16, 22, 28
end)

t.case("IIS: a watcher that cannot win still registers AP", function()
	local mover, a = IISSetup()
	a.statuses.Panicked = true
	local idx, winners, rows = Q.FindIISMoveTrigger(mover, Path(mover, 6), 1)
	t.eq(idx, nil)
	t.eq(#winners, 0)
	t.eq(rows[1].cum[6], 30)
	t.eq(rows[1].win_skip, "Panicked")
end)

t.case("IIS: a later check of the same move starts on its first dummy", function()
	local mover, a = IISSetup()
	local dummies = Path(mover, 6)
	table.remove(dummies, 1) -- an interrupt removed the mover's tile from the list
	local idx, _, _, plan = Q.FindIISMoveTrigger(mover, dummies, 1)
	t.eq(plan.first, 1)
	t.eq(idx, 5) -- the five dummies are steps 2..6 of the old list
end)

t.case("RegisterAction adds the AP of a seen action", function()
	local mover, a = IISSetup()
	world.sees[a] = { [mover] = true }
	Q.RegisterAction(mover, "Attack", 4000)
	-- 4000 raw = 33 1.13 AP, 74% of it = 24
	t.eq(Mem.Counter(a, mover), 24)
	local hidden = FakeUnit({ id = "hidden", team = enemy_team })
	Q.RegisterAction(hidden, "Attack", 4000)
	t.eq(Mem.Counter(a, hidden), 0)
end)

t.case("RegisterAction adds the same AP for a mover with more max AP", function()
	local mover, a = IISSetup()
	mover.max_ap = 24000
	world.sees[a] = { [mover] = true }
	Q.RegisterAction(mover, "Attack", 4000)
	t.eq(Mem.Counter(a, mover), 24)
end)

------------------------------------------------------------------------------------------------
-- The check wrapper

t.case("AddTrigger: a vanilla interrupt at an earlier step goes first", function()
	local mover = IISSetup(10)
	local vanilla = { { "overwatch" } }
	local list, idx = Q.AddTrigger(mover, "move", Path(mover, 6), nil, nil, vanilla, 2)
	t.eq(list, vanilla)
	t.eq(idx, 2)
	t.eq(#list, 1)
end)

t.case("AddTrigger: on the same step ours runs first", function()
	local mover = IISSetup(10)
	local vanilla = { { "overwatch" } }
	local list, idx = Q.AddTrigger(mover, "move", Path(mover, 6), nil, nil, vanilla, 4)
	t.eq(idx, 4)
	t.eq(list[1][1], "iis")
	t.eq(list[2][1], "overwatch")
	t.eq(list[1][3].step, 4)
end)

t.case("AddTrigger: a later vanilla interrupt is dropped until the next check", function()
	local mover, a = IISSetup(10)
	local dummies = Path(mover, 6)
	local list, idx = Q.AddTrigger(mover, "move", dummies, nil, nil, { { "overwatch" } }, 6)
	t.eq(idx, 4)
	t.eq(#list, 1)
	t.eq(list[1][1], "iis")
	t.eq(list[1][2], a)
	t.eq(list[1][4], dummies[4])
	t.eq(list[1][3].kind, "move")
end)

t.case("AddTrigger stores the plan only for the check in the mover's own thread", function()
	local mover, a = IISSetup(10)
	local dummies = Path(mover, 6)
	Q.AddTrigger(mover, "move", dummies)
	mover.pos = dummies[6].pos
	OnMsg.UnitMovementDone(mover)
	t.eq(Mem.Counter(a, mover), 10)
	mover.pos = dummies[1].pos
	mover.in_cmd = true
	Q.AddTrigger(mover, "move", dummies)
	mover.pos = dummies[6].pos
	OnMsg.UnitMovementDone(mover)
	t.eq(Mem.Counter(a, mover), 40)
end)

-- Issue #4. The counter starts at 10 and each seen step adds 6. A vanilla overwatch stops the
-- mover on step 2, before the IIS trigger at step 4. CombatGoto then checks the rest of the path.
t.case("IIS: a vanilla interrupt at an earlier step keeps the AP of the walked steps", function()
	local mover, a = IISSetup(10)
	mover.in_cmd = true
	local dummies = Path(mover, 6)
	local list = Q.AddTrigger(mover, "move", dummies, nil, nil, { { "overwatch" } }, 2)
	t.eq(list[1][1], "overwatch")
	mover.pos = dummies[2].pos
	local rest = { table.unpack(dummies, 2) }
	local _, idx = Q.AddTrigger(mover, "move", rest)
	t.eq(idx, 3, "trigger index in the rest of the path") -- step 4: 16, 22, 28
	mover.pos = dummies[6].pos
	OnMsg.UnitMovementDone(mover)
	t.eq(Mem.Counter(a, mover), 40) -- 10 + 5 steps of 6
end)

-- A mover that StopMover stopped on a CombatGoto path in its command thread "cmd".
local function StoppedMover(mover)
	mover.in_cmd = true
	mover.command = "CombatGoto"
	mover.command_thread = "cmd"
	mover.combat_path = { "dest", "start" }
	IISControl.StopMover(ActiveState({ FakeUnit({ id = "b" }) }, mover), { pos = mover.pos })
	EndActive()
	return mover
end

t.case("The check wrapper returns nothing for a stopped mover", function()
	local mover = StoppedMover(IISSetup(10))
	vanilla_result = { interrupts = { { "overwatch" } }, idx = 2 }
	t.eq(Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", Path(mover, 6)), nil)
	mover.command_thread = "next cmd"
	local list = Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", Path(mover, 6))
	t.eq(list[1][1], "overwatch")
end)

t.case("Interrupt System = Off: the check wrapper adds no iis entry, and the vanilla entries stay", function()
	local mover = IISSetup(10)
	ApplyModOptions({ InterruptSystem = "Off" })
	vanilla_result = { interrupts = { { "overwatch" } }, idx = 2 }
	local list = Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", Path(mover, 6))
	t.eq(#list, 1)
	t.eq(list[1][1], "overwatch")
	t.eq(Q.turn_stats.mover_skips["interrupt system off"], 1)
	ApplyModOptions({})
	vanilla_result = {}
	t.eq(Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", Path(mover, 6))[1][1], "iis")
end)

------------------------------------------------------------------------------------------------
-- Attack trigger

t.case("IIS after an attack: a full counter wins if the merc sees or was attacked", function()
	local mover, a = IISSetup()
	local b = FakeUnit({ id = "b", level = 5, agility = 80, ap = 10000, pos = { x = 1, y = 1 } })
	local c = FakeUnit({ id = "c", level = 5, agility = 80, ap = 10000, pos = { x = 2, y = 1 } })
	world.players = { a, b, c }
	Mem.Register(a, mover, 30)
	Mem.Register(b, mover, 30)
	Mem.Register(c, mover, 5)
	world.sees[a] = { [mover] = true }
	world.sees[c] = { [mover] = true }
	Q.attack_targets[mover] = { [b] = true }
	local winners = Q.FindAttackTrigger(mover, 1)
	t.eq(#winners, 2)
	local list, idx = Q.AddTrigger(mover, "attack reaction", { mover })
	t.eq(idx, 1)
	t.eq(list[1][3].kind, "attack")
	t.eq(#list[1][3].mercs, 2)
end)

t.case("After an attack: the log names the skip reason, or each watcher when nobody wins", function()
	local mover, a = IISSetup()
	world.sees[a] = { [mover] = true }
	ActiveState({ FakeUnit({ id = "b" }) }, FakeUnit({ id = "other", team = enemy_team }))
	Q.AddTrigger(mover, "attack reaction", { mover })
	t.eq(LogHas("after%-attack check by enemy.* skipped: interrupt active"), true)
	EndActive()
	local list = Q.AddTrigger(mover, "attack reaction", { mover })
	t.eq(list, nil)
	t.eq(LogHas("after attack by enemy.*: no winner: a.*counter 0, reaction time %d+, sees attacker"), true)
end)

t.case("JA2 Classic after an attack: only an attacked merc that did not see the attacker duels", function()
	ResetWorld()
	Q.Config.system = "JA2 Classic"
	local mover = FakeUnit({ id = "enemy", team = enemy_team, level = 1, agility = 30, pos = { x = 0, y = 0 } })
	local target = FakeUnit({ id = "target", level = 6, agility = 90, pos = { x = 4, y = 0 } })
	local seer = FakeUnit({ id = "seer", level = 6, agility = 90, pos = { x = 5, y = 0 } })
	local bystander = FakeUnit({ id = "bystander", level = 6, agility = 90, pos = { x = 6, y = 0 } })
	world.players = { target, seer, bystander }
	world.sees[seer] = { [mover] = true }
	Q.attack_targets[mover] = { [target] = true, [seer] = true }
	local winners = Q.FindAttackTrigger(mover, 1)
	t.eq(#winners, 1)
	t.eq(winners[1].unit, target)
end)

------------------------------------------------------------------------------------------------
-- Control overrides

t.case("CanBeControlled: interrupters yes, other player units no, enemies vanilla", function()
	ResetWorld()
	local a, b = FakeUnit({ id = "a" }), FakeUnit({ id = "b" })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	ActiveState({ a }, enemy)
	t.eq(Unit.CanBeControlled(a), true)
	local ok, reason = Unit.CanBeControlled(b)
	t.eq(ok, false)
	t.eq(reason, "iis_not_interrupter")
	t.eq(Unit.CanBeControlled(enemy), "vanilla")
	a.down = true
	t.eq(Unit.CanBeControlled(a), false)
	EndActive()
	t.eq(Unit.CanBeControlled(b), "vanilla")
end)

t.case("CanBeControlled: a collective joiner is an interrupter", function()
	ResetWorld()
	local a, b = FakeUnit({ id = "a" }), FakeUnit({ id = "b" })
	ActiveState({ a, b }, FakeUnit({ id = "enemy", team = enemy_team }))
	t.eq(Unit.CanBeControlled(b), true)
	b.down = true
	t.eq(Unit.CanBeControlled(b), false)
end)

local function FakeSelection(unit)
	SelectedObj = unit
	SelectObj = function(o) SelectedObj = o end
	Q.UI = { Refresh = function() end }
end

t.case("Tick selects the next interrupter that can act when the selected one goes down", function()
	ResetWorld()
	local a, b, c = FakeUnit({ id = "a" }), FakeUnit({ id = "b" }), FakeUnit({ id = "c" })
	local it = ActiveState({ a, b, c }, FakeUnit({ id = "enemy", team = enemy_team }))
	FakeSelection(a)
	Q.Tick(it, 100)
	t.eq(SelectedObj, a)
	a.down, b.down = true, true
	Q.Tick(it, 200)
	t.eq(SelectedObj, c)
	t.eq(LogHas("INT #1 a#a is down, selecting c#c"), true)
end)

t.case("SelectionChange selects an interrupter in place of another player unit", function()
	ResetWorld()
	local a, b, other = FakeUnit({ id = "a" }), FakeUnit({ id = "b" }), FakeUnit({ id = "other" })
	ActiveState({ a, b }, FakeUnit({ id = "enemy", team = enemy_team }))
	FakeSelection(b)
	OnMsg.SelectionChange()
	RunThreads()
	t.eq(SelectedObj, b)
	FakeSelection(other)
	OnMsg.SelectionChange()
	RunThreads()
	t.eq(SelectedObj, a)
	t.eq(LogHas("other#other is not an interrupter, selecting a#a"), true)
end)

t.case("CombatActionCannotBeStarted ignores the frozen enemy and counts the interrupters", function()
	ResetWorld()
	local a, b = FakeUnit({ id = "a" }), FakeUnit({ id = "b" })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	ActiveState({ a, b }, enemy)
	CombatActions_RunningState[enemy] = "start"
	t.eq(CombatActionCannotBeStarted("Attack", a), false)
	CombatActions_RunningState[b] = "PostAction"
	t.eq(CombatActionCannotBeStarted("Attack", a), false)
	CombatActions_RunningState[b] = "start"
	t.eq(CombatActionCannotBeStarted("Attack", a), true)
	t.eq(CombatActionCannotBeStarted("Attack", enemy), "vanilla")
end)

t.case("StartCombatAction runs an interrupter's action at once and pays its AP", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 10000 })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	ActiveState({ a }, enemy)
	CombatActions_RunningState[enemy] = "start"
	StartCombatAction("Attack", a, 4000)
	t.eq(#ran_actions, 1)
	t.eq(ran_actions[1][1], "Attack")
	t.eq(a.ActionPoints, 6000)
	t.eq(#vanilla_started, 0)
end)

t.case("StartCombatAction queues behind another interrupter and starts after it", function()
	ResetWorld()
	local a, b = FakeUnit({ id = "a" }), FakeUnit({ id = "b" })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	local it = ActiveState({ a, b }, enemy)
	CombatActions_RunningState[a] = "start"
	StartCombatAction("Move", b, 2000)
	t.eq(#ran_actions, 0)
	t.eq(it:QueueLength(), 1)
	t.eq(LogHas("queued Move: 1 waiting"), true)
	CombatActions_RunningState[a] = "PostAction"
	OnMsg.CombatPostAction(a)
	RunThreads()
	t.eq(#ran_actions, 1) -- Move plays alongside a PostAction
	t.eq(it:QueueLength(), 0)
end)

t.case("CombatActionEnd traces an enemy action and steps an interrupter action", function()
	ResetWorld()
	local a = FakeUnit({ id = "a" })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	ActiveState({ a }, enemy)
	Q.UI = { Refresh = function() end }
	VisibilityUpdate = function() end
	OnMsg.CombatActionEnd(enemy)
	OnMsg.CombatActionEnd(a)
	VisibilityUpdate = nil
	t.eq(LogHas("enemy action ended: enemy#enemy"), true)
	t.eq(LogHas("INT #1 merc a#a action ended"), true)
end)

t.case("StartCombatAction drops the queued action of a unit that died", function()
	ResetWorld()
	local a, b = FakeUnit({ id = "a" }), FakeUnit({ id = "b" })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	local it = ActiveState({ a, b }, enemy)
	CombatActions_RunningState[a] = "start"
	StartCombatAction("Attack", b, 2000)
	b.dead = true
	CombatActions_RunningState[a] = "PostAction"
	OnMsg.CombatPostAction(a)
	RunThreads()
	t.eq(#ran_actions, 0)
	t.eq(it:QueueLength(), 0)
	t.eq(LogHas("INT #1 dropped queued Attack: the unit is gone"), true)
end)

t.case("EndInterrupt refunds the AP of queued actions that never started", function()
	ResetWorld()
	local a, b = FakeUnit({ id = "a" }), FakeUnit({ id = "b", ap = 10000 })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	local it = ActiveState({ a, b }, enemy)
	CombatActions_RunningState[a] = "start"
	StartCombatAction("Attack", b, 3000)
	t.eq(b.ActionPoints, 7000)
	Q.UI = { End = function() end }
	IISControl.EndInterrupt(it, "test")
	t.eq(b.ActionPoints, 10000)
	t.eq(it:QueueLength(), 0)
	t.eq(LogHas("INT #1 dropped queued action Attack of " .. Q.Name(b) .. ", refunded 3000 raw AP"), true)
end)

t.case("StartCombatAction keeps vanilla behavior for other units", function()
	ResetWorld()
	local a = FakeUnit({ id = "a" })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	ActiveState({ a }, enemy)
	StartCombatAction("Move", enemy, 1000)
	t.eq(#vanilla_started, 1)
	t.eq(#ran_actions, 0)
end)

t.case("IsIdleOrRunningBehavior is true for the frozen enemy only", function()
	ResetWorld()
	local a = FakeUnit({ id = "a" })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	ActiveState({ a }, enemy)
	t.eq(Unit.IsIdleOrRunningBehavior(enemy), true)
	t.eq(Unit.IsIdleOrRunningBehavior(a), "vanilla")
end)

t.case("End Turn: first press asks to end, a second press while busy forces it", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", command = "FirearmAttack" })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	local it = ActiveState({ a }, enemy)
	local refreshed = 0
	Q.UI = { Refresh = function() refreshed = refreshed + 1 end }
	NetSyncEvents.EndTurn(netUniqueId)
	t.eq(LogHas("end requested %(End Turn%)%. busy=true"), true)
	t.eq(refreshed, 1)
	t.eq(it:EndReason(), nil)
	t.eq(a.command, "FirearmAttack")
	NetSyncEvents.EndTurn(netUniqueId)
	t.eq(LogHas("STUCK%? End Turn pressed again while a merc is busy"), true)
	t.eq(a.command, "Idle")
	t.eq(it:EndReason(), "forced_end")
	EndActive()
	t.eq(NetSyncEvents.EndTurn(netUniqueId), "vanilla")
end)

t.case("Activate returns the takeover state with the dummy and the counters with the start AP of each interrupter", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 7000 })
	local it = IISInterrupt.Begin{ n = 1, mover = FakeUnit({ id = "enemy", team = enemy_team }), interrupters = { a },
		cfg = Q.Config }
	local dummy = { pos = { x = 1, y = 0 } }
	local taken, counters = IISControl.Activate(it, dummy)
	t.eq(IISControl.Active(), it)
	t.eq(taken.dummy, dummy)
	t.eq(counters.start_ap[a], 7000)
end)

t.case("DumpStuck logs the command stack of each busy interrupter that is not down", function()
	ResetWorld()
	local a = FakeUnit({ id = "stuck_a", command = "FirearmAttack" })
	local b = FakeUnit({ id = "stuck_b", command = "FirearmAttack" })
	local c = FakeUnit({ id = "stuck_c" })
	b.down = true
	local it = ActiveState({ a, b, c }, FakeUnit({ id = "enemy", team = enemy_team }))
	Q.DumpStuck(it, "test")
	t.eq(LogHas("merc stuck_a#stuck_a cmd=FirearmAttack"), true)
	t.eq(LogHas("merc stuck_b#stuck_b"), false)
	t.eq(LogHas("merc stuck_c#stuck_c"), false)
end)

t.case("An error in the end check ends the interrupt with end_check_error", function()
	ResetWorld()
	local a = FakeUnit({ id = "a" })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	function enemy:IsDead() error("boom") end
	local it = ActiveState({ a }, enemy)
	local ui_ended = false
	Q.UI = { End = function() ui_ended = true end }
	local reason = Q.CheckEnd(it)
	t.eq(reason, "end_check_error")
	t.eq(LogHas("EndReason failed: .*boom"), true)
	IISControl.EndInterrupt(it, reason)
	t.eq(LogHas("INT #1 END %(end_check_error%)"), true)
	t.eq(ui_ended, true)
	t.eq(IISControl.Active(), false)
end)

t.case("The END log line shows the Forced counts and the AP of each interrupter at the start and at the end", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 10000 })
	local b = FakeUnit({ id = "b", ap = 8500 })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	game_time = 1000
	local it = ActiveState({ a, b }, enemy)
	Unit.CanBeControlled(a)
	Unit.CanBeControlled(b)
	IsNetPlayerTurn()
	StartCombatAction("Attack", a, 4000)
	Q.UI = { End = function() end }
	game_time = 3500
	IISControl.EndInterrupt(it, "end_request")
	game_time = 0
	t.eq(LogHas("INT #1 END %(end_request%): 2500ms game time, actions=1, ap: a#a 10%->6, b#b 8%.5%->8%.5, "
		.. "forced: CanBeControlled=2 IsNetPlayerTurn=1$"), true)
end)

t.case("StopMover keeps the enemy on its tile and refunds the AP of the rest of the path", function()
	ResetWorld()
	local here = { x = 3, y = 0 }
	local enemy = FakeUnit({ id = "enemy", team = enemy_team, ap = 2000, command = "CombatGoto", thread = "cmd" })
	enemy.in_cmd = true
	enemy.combat_path = { "dest", "mid", here }
	enemy.combat_path_obj = { GetAP = function(_, p) return p == "dest" and 6000 or 3000 end }
	enemy.start_move_free_ap = 0
	local it = ActiveState({ FakeUnit({ id = "a" }) }, enemy)
	IISControl.StopMover(it, { pos = here })
	t.eq(#enemy.combat_path, 1)
	t.eq(enemy.combat_path[1], here)
	t.eq(enemy.ActionPoints, 5000)
	t.eq(IISControl.IsStopped(enemy), true)
	t.eq(LogHas("stops at"), true)
end)

t.case("StopMover snaps a stop between two tiles to the pass slab and refunds from that tile", function()
	ResetWorld()
	local between, tile = { x = 3.4, y = 0 }, { x = 3, y = 0 }
	local saved = GetPassSlab
	GetPassSlab = function(p) return p == between and tile or nil end
	local enemy = FakeUnit({ id = "enemy", team = enemy_team, ap = 2000, command = "CombatGoto", thread = "cmd" })
	enemy.in_cmd = true
	enemy.combat_path = { "dest", "mid", "start" }
	enemy.combat_path_obj = { GetAP = function(_, p)
		if p == "dest" then return 6000 end
		if p == tile then return 3000 end
	end }
	enemy.start_move_free_ap = 0
	local it = ActiveState({ FakeUnit({ id = "a" }) }, enemy)
	IISControl.StopMover(it, { pos = between })
	GetPassSlab = saved
	t.eq(#enemy.combat_path, 1)
	t.eq(enemy.combat_path[1], tile)
	t.eq(enemy.ActionPoints, 5000)
end)

t.case("StopMover leaves an enemy alone when it is not in CombatGoto", function()
	ResetWorld()
	local enemy = FakeUnit({ id = "enemy", team = enemy_team, command = "FirearmAttack" })
	enemy.in_cmd = true
	enemy.combat_path = { "dest" }
	local it = ActiveState({ FakeUnit({ id = "a" }) }, enemy)
	IISControl.StopMover(it, { pos = { x = 1, y = 0 } })
	t.eq(enemy.combat_path[1], "dest")
	t.eq(IISControl.IsStopped(enemy), false)
end)

t.case("One move-done message commits the move plan and re-plans a stopped mover", function()
	local mover, a = IISSetup(10)
	mover.in_cmd = true
	mover.command_thread = "cmd"
	local dummies = Path(mover, 6)
	Q.AddTrigger(mover, "move", dummies)
	StoppedMover(mover)
	mover.ai_context = { ai_destination = "far" }
	mover.pos = dummies[4].pos
	OnMsg.UnitMovementDone(mover)
	t.eq(Mem.Counter(a, mover), 28) -- 10 + 3 steps of 6
	t.eq(mover.ai_context.ai_destination, "packed 3,0")
	t.eq(IISControl.IsStopped(mover), false)
	t.eq(LogHas("IIS commit"), true)
	t.eq(LogHas("enemy enemy#enemy re%-plans from its tile"), true)
end)

t.case("CanSaveGameQuery blocks saves during an interrupt", function()
	ResetWorld()
	local query = {}
	OnMsg.CanSaveGameQuery(query)
	t.eq(query.iis_interrupt, nil)
	ActiveState({ FakeUnit({ id = "a" }) }, FakeUnit({ id = "enemy", team = enemy_team }))
	OnMsg.CanSaveGameQuery(query)
	t.eq(query.iis_interrupt, true)
end)

------------------------------------------------------------------------------------------------
-- A full interrupt through the provoke-list wrapper

g_Combat.SetPlayerControl = function(self, v) self.is_player_control = v end
s_CameraMoveLockReasons = {}
function VisibilityUpdate() end
function UnlockCameraMovement() end
function LockCameraMovement() end
function HasVisibilityTo() return true end
function GetInGameInterfaceMode() return "IModeCombatMovement" end
function SetInGameInterfaceMode() end

-- Each step of `script` is { at = game time in ms, run = function }. The fake sleep advances the
-- game time and runs each step whose time has come. The captured log starts empty.
local function FakeControl(script)
	game_time = 0
	log_lines = {}
	local pending = { table.unpack(script or {}) }
	IISControl.Setup{
		sleep = function(ms)
			game_time = game_time + ms
			if game_time > 60000 then
				error("the interrupt did not end in 60 s of game time")
			end
			while pending[1] and pending[1].at <= game_time do
				table.remove(pending, 1).run()
			end
		end,
		can_yield = function() return true end,
	}
	SelectObj = function(o) SelectedObj = o end
	Q.UI = { Begin = function() end, End = function() end, Refresh = function() end }
end

local function PressEndTurn()
	NetSyncEvents.EndTurn(netUniqueId)
end

-- The IISSetup mover, walking a path of 6 steps in its own CombatGoto command. Watcher a wins on
-- step 4. The path costs 6 AP to the end and 3 AP to step 4.
local function WalkingMover(counter)
	local mover, a = IISSetup(counter)
	local dummies = Path(mover, 6)
	mover.in_cmd = true
	mover.command = "CombatGoto"
	mover.command_thread = "cmd"
	mover.combat_path = { "dest", "mid", "start" }
	mover.combat_path_obj = { GetAP = function(_, p) return p == "dest" and 6000 or 3000 end }
	mover.start_move_free_ap = 0
	local destructors = {}
	function mover:InterruptBegin() end
	function mover:SetAnimSpeedModifier() end
	function mover:PushDestructor(f) destructors[#destructors + 1] = f end
	function mover:PopDestructor() table.remove(destructors) end
	function mover:Destructors() return destructors end
	return mover, a, dummies
end

t.case("A move trigger: End Turn ends the interrupt with end_request and the mover stops", function()
	local mover, a, dummies = WalkingMover(10)
	FakeControl{ { at = 300, run = PressEndTurn } }
	Q.Config.after_interrupt = "stop"
	local n = IISControl.InterruptCount() + 1
	local list = Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", dummies)
	t.eq(list[1][1], "iis")
	Unit.ProvokeOpportunityAttacksFromList(mover, list)
	t.eq(LogHas("INT #" .. n .. " BEGIN IIS move: mover=enemy#enemy"), true)
	t.eq(LogHas("INT #" .. n .. "   interrupter 1: a#a"), true)
	t.eq(LogHas("INT #" .. n .. " end requested %(End Turn%)%. busy=false"), true)
	t.eq(LogHas("INT #" .. n .. " END %(end_request%): 300ms game time"), true)
	t.eq(IISControl.Active(), false)
	t.eq(#mover.combat_path, 1)
	t.eq(mover.combat_path[1], dummies[4].pos)
	t.eq(mover.ActionPoints, 13000)
	t.eq(LogHas("INT #" .. n .. " enemy enemy#enemy stops at"), true)
	t.eq(vanilla_provoked[1], list)
	game_time = 0
end)

t.case("While another interrupt is active, a new iis entry starts no interrupt and rolls no collective", function()
	local mover, a, dummies = WalkingMover(10)
	local mate = FakeUnit({ id = "mate", pos = { x = 1, y = 6 } })
	world.players = { a, mate }
	FakeControl()
	local count = IISControl.InterruptCount()
	local list = Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", dummies)
	t.eq(list[1][1], "iis")
	local other = ActiveState({ FakeUnit({ id = "b" }) }, FakeUnit({ id = "other", team = enemy_team }))
	local rolls = 0
	local orig_rand = E.Rand
	E.Rand = function() rolls = rolls + 1 return 0 end
	Unit.ProvokeOpportunityAttacksFromList(mover, list)
	E.Rand = orig_rand
	t.eq(LogHas("interrupt skipped: INT #1 is still active"), true)
	t.eq(IISControl.Active(), other)
	t.eq(IISControl.InterruptCount(), count)
	t.eq(rolls, 0)
	t.eq(LogHas("collective"), false)
	t.eq(#mover.combat_path, 3)
	t.eq(vanilla_provoked[1], list)
end)

t.case("A vanilla overwatch entry goes to vanilla unchanged", function()
	local mover, a, dummies = WalkingMover(10)
	FakeControl()
	local count = IISControl.InterruptCount()
	local entry = { "overwatch", a, "attack args", dummies[2] }
	local list = { entry }
	Unit.ProvokeOpportunityAttacksFromList(mover, list)
	t.eq(#vanilla_provoked, 1)
	t.eq(vanilla_provoked[1], list)
	t.eq(#list, 1)
	t.eq(list[1], entry)
	t.eq(entry[1], "overwatch")
	t.eq(entry[2], a)
	t.eq(entry[3], "attack args")
	t.eq(entry[4], dummies[2])
	t.eq(IISControl.InterruptCount(), count)
	t.eq(IISControl.Active(), false)
	t.eq(#log_lines, 0)
end)

t.case("A move trigger with a collective joiner: the joiner rolls, joins and is marked in its log line", function()
	local mover, a, dummies = WalkingMover(10)
	local mate = FakeUnit({ id = "mate", pos = { x = 1, y = 6 } })
	world.players = { a, mate }
	world.rand = 0
	FakeControl{ { at = 300, run = PressEndTurn } }
	local n = IISControl.InterruptCount() + 1
	local list = Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", dummies)
	Unit.ProvokeOpportunityAttacksFromList(mover, list)
	t.eq(LogHas("INT #" .. n .. " collective: a#a %-> mate#mate chance=%d+ roll=0 JOINS"), true)
	t.eq(LogHas("INT #" .. n .. "   interrupter 1: a#a ap=10$"), true)
	t.eq(LogHas("INT #" .. n .. "   interrupter 2: mate#mate ap=10 %(collective%)$"), true)
	t.eq(IISControl.InterruptCount(), n)
	game_time = 0
end)

t.case("An iis entry from an older version starts no interrupt", function()
	local mover, a, dummies = WalkingMover(10)
	FakeControl()
	local count = IISControl.InterruptCount()
	Unit.ProvokeOpportunityAttacksFromList(mover, { { "iis", a, nil, dummies[4] } })
	t.eq(LogHas("interrupt skipped: bad entry from an older version"), true)
	t.eq(IISControl.InterruptCount(), count)
	t.eq(IISControl.Active(), false)
end)

t.case("IIS.lua registers the handler for iis entries on ModsReloaded", function()
	IISControl.Handle("iis", nil)
	OnMsg.ModsReloaded()
	local mover, a, dummies = WalkingMover(10)
	FakeControl{ { at = 300, run = PressEndTurn } }
	local n = IISControl.InterruptCount() + 1
	local list = Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", dummies)
	Unit.ProvokeOpportunityAttacksFromList(mover, list)
	t.eq(LogHas("INT #" .. n .. " BEGIN IIS move: mover=enemy#enemy"), true)
	game_time = 0
end)

t.case("The hook status reports the provoke-list wrapper as ours", function()
	t.eq(Q.HookStatus():find("provoke_hook=ours", 1, true) ~= nil, true)
end)

t.case("A handler that returns nothing starts no interrupt, and the interrupt number does not change", function()
	local mover, a, dummies = WalkingMover(10)
	FakeControl()
	local count = IISControl.InterruptCount()
	local calls = {}
	IISControl.Handle("test", function(m, entry, n)
		calls[#calls + 1] = { m, entry, n }
	end)
	local entry = { "test", a, nil, dummies[4] }
	local list = { entry }
	Unit.ProvokeOpportunityAttacksFromList(mover, list)
	IISControl.Handle("test", nil)
	t.eq(#calls, 1)
	t.eq(calls[1][1], mover)
	t.eq(calls[1][2], entry)
	t.eq(calls[1][3], count + 1)
	t.eq(IISControl.InterruptCount(), count)
	t.eq(IISControl.Active(), false)
	t.eq(LogHas("BEGIN"), false)
	t.eq(vanilla_provoked[1], list)
end)

t.case("A handler that sends stop = false starts an interrupt, and the mover does not stop", function()
	local mover, a, dummies = WalkingMover(10)
	FakeControl{ { at = 300, run = PressEndTurn } }
	Q.Config.after_interrupt = "stop"
	local n = IISControl.InterruptCount() + 1
	IISControl.Handle("test", function(_, entry)
		return { interrupters = { entry[2] }, dummy = entry[4], stop = false, label = "Test move",
			notes = { [entry[2]] = " (test)" } }
	end)
	local list = { { "test", a, nil, dummies[4] } }
	Unit.ProvokeOpportunityAttacksFromList(mover, list)
	IISControl.Handle("test", nil)
	t.eq(LogHas("INT #" .. n .. " BEGIN Test move: mover=enemy#enemy"), true)
	t.eq(LogHas("INT #" .. n .. "   interrupter 1: a#a ap=10 %(test%)$"), true)
	t.eq(LogHas("INT #" .. n .. " END %(end_request%): 300ms game time"), true)
	t.eq(IISControl.InterruptCount(), n)
	t.eq(IISControl.IsStopped(mover), false)
	t.eq(#mover.combat_path, 3)
	t.eq(mover.ActionPoints, 10000)
	t.eq(LogHas("stops at"), false)
	t.eq(vanilla_provoked[1], list)
	game_time = 0
end)

-- Starts an interrupt through a "test" handler that catches the WalkingMover on a step that is not
-- a valid object, as CombatGoto's path dummies are in the game.
local function TestInterrupt(mover, a, script)
	FakeControl(script)
	local dummy = { pos = { x = 3, y = 0 }, valid = false }
	IISControl.Handle("test", function()
		return { interrupters = { a }, dummy = dummy, stop = false, label = "Test move" }
	end)
	Unit.ProvokeOpportunityAttacksFromList(mover, { { "test", a, nil, dummy } })
	IISControl.Handle("test", nil)
	game_time = 0
	return dummy
end

t.case("After an interrupt, the visibility override, the camera locks and the player control have their old values", function()
	local mover, a = WalkingMover(10)
	local hidden_end = { pos = { x = 5, y = 0 }, valid = false }
	mover.visibility_override = hidden_end
	s_CameraMoveLockReasons = { cinematic = true }
	g_Combat.is_player_control = false
	local saved_lock, saved_unlock = LockCameraMovement, UnlockCameraMovement
	function LockCameraMovement(reason) s_CameraMoveLockReasons[reason] = true end
	function UnlockCameraMovement() s_CameraMoveLockReasons = {} end
	local during = {}
	local dummy = TestInterrupt(mover, a, {
		{ at = 100, run = function()
			during.override = mover.visibility_override
			during.locked = next(s_CameraMoveLockReasons) ~= nil
			during.control = g_Combat.is_player_control
		end },
		{ at = 300, run = PressEndTurn },
	})
	LockCameraMovement, UnlockCameraMovement = saved_lock, saved_unlock
	t.eq(during.override, dummy)
	t.eq(during.locked, false)
	t.eq(during.control, true)
	t.eq(mover.visibility_override, hidden_end)
	t.eq(s_CameraMoveLockReasons.cinematic, true)
	t.eq(g_Combat.is_player_control, false)
	s_CameraMoveLockReasons = {}
end)

-- Replaces the engine calls of the takeover with fakes that write each call to the returned list.
-- The AI controller is a proxy, so each write of its tracked_pois field is a call too.
local function RecordTakeover(mover)
	local calls = {}
	local saved = { VisibilityUpdate, LockCameraMovement, UnlockCameraMovement, g_Combat.SetPlayerControl,
		g_AIExecutionController }
	local push, pop = mover.PushDestructor, mover.PopDestructor
	function mover:PushDestructor(f)
		calls[#calls + 1] = "push destructor"
		push(self, f)
	end
	function mover:PopDestructor()
		calls[#calls + 1] = "pop destructor"
		pop(self)
	end
	function VisibilityUpdate() calls[#calls + 1] = "visibility " .. tostring(mover.visibility_override.pos.x) end
	function LockCameraMovement(reason) calls[#calls + 1] = "lock " .. reason end
	function UnlockCameraMovement() calls[#calls + 1] = "unlock" end
	g_Combat.SetPlayerControl = function(self, v)
		self.is_player_control = v
		calls[#calls + 1] = "player control " .. tostring(v)
	end
	local fields = { tracked_pois = "pois" }
	g_AIExecutionController = setmetatable({}, {
		__index = fields,
		__newindex = function(_, k, v)
			if k == "tracked_pois" then calls[#calls + 1] = "ai camera " .. tostring(v) end
			fields[k] = v
		end,
	})
	local function restore()
		VisibilityUpdate, LockCameraMovement, UnlockCameraMovement, g_Combat.SetPlayerControl,
			g_AIExecutionController = table.unpack(saved, 1, 5)
	end
	return calls, restore
end

t.case("The end gives back the engine state in the reverse order of the takes", function()
	local mover, a = WalkingMover(10)
	mover.visibility_override = { pos = { x = 5, y = 0 }, valid = false }
	s_CameraMoveLockReasons = { cinematic = true }
	g_Combat.is_player_control = false
	local calls, restore = RecordTakeover(mover)
	TestInterrupt(mover, a, { { at = 300, run = PressEndTurn } })
	restore()
	s_CameraMoveLockReasons = {}
	t.eq(table.concat(calls, ", "), table.concat({
		"push destructor", "visibility 3", "unlock", "ai camera false", "player control true",
		"player control false", "ai camera pois", "lock cinematic", "visibility 5", "pop destructor",
	}, ", "))
	t.eq(#mover:Destructors(), 0)
end)

t.case("An error in one give-back is logged, and the other give-backs still run", function()
	local mover, a = WalkingMover(10)
	mover.visibility_override = { pos = { x = 5, y = 0 }, valid = false }
	s_CameraMoveLockReasons = { cinematic = true }
	g_Combat.is_player_control = false
	local calls, restore = RecordTakeover(mover)
	function LockCameraMovement() error("lock boom") end
	TestInterrupt(mover, a, { { at = 300, run = PressEndTurn } })
	restore()
	s_CameraMoveLockReasons = {}
	t.eq(LogHas("INT #%d+ restore camera failed: .*lock boom"), true)
	t.eq(table.concat(calls, ", "), table.concat({
		"push destructor", "visibility 3", "unlock", "ai camera false", "player control true",
		"player control false", "ai camera pois", "visibility 5", "pop destructor",
	}, ", "))
	t.eq(LogHas("END %(end_request%)"), true)
end)

t.case("When the mover's command ends in an interrupt, its destructor ends the interrupt and gives back the state", function()
	local mover, a = WalkingMover(10)
	g_Combat.is_player_control = false
	local pops = 0
	function mover:PopDestructor() pops = pops + 1 end
	TestInterrupt(mover, a, { { at = 200, run = function()
		table.remove(mover:Destructors())()
	end } })
	t.eq(LogHas("END %(mover_command_ended%)"), true)
	t.eq(IISControl.Active(), false)
	t.eq(g_Combat.is_player_control, false)
	t.eq(pops, 0)
end)

------------------------------------------------------------------------------------------------
-- The provoke-list wrapper with more than one entry type

-- Registers `fakes` (entry type -> handler) while `f` runs, then puts back the real "iis" handler
-- and removes the others.
local function WithHandlers(fakes, f)
	for entry_type, handler in pairs(fakes) do
		IISControl.Handle(entry_type, handler)
	end
	local ok, err = pcall(f)
	for entry_type in pairs(fakes) do
		IISControl.Handle(entry_type, nil)
	end
	IISControl.Handle("iis", Q.InterruptRequest)
	game_time = 0
	if not ok then error(err, 0) end
end

t.case("The overwatch handler runs before the iis handler when the iis entry is first in the list", function()
	local mover, a, dummies = WalkingMover(10)
	local b = FakeUnit({ id = "b" })
	FakeControl()
	local order = {}
	WithHandlers({
		iis = function() order[#order + 1] = "iis" end,
		overwatch = function() order[#order + 1] = "overwatch" end,
	}, function()
		Unit.ProvokeOpportunityAttacksFromList(mover, {
			{ "iis", a, {}, dummies[4] },
			{ "overwatch", b, "attack args", dummies[4] },
		})
	end)
	t.eq(table.concat(order, ", "), "overwatch, iis")
end)

t.case("Two overwatch entries on one step reach the handler in one call", function()
	local mover, a, dummies = WalkingMover(10)
	local b = FakeUnit({ id = "b" })
	FakeControl()
	local calls = {}
	local first = { "overwatch", a, "args a", dummies[4] }
	local second = { "overwatch", b, "args b", dummies[4] }
	WithHandlers({
		overwatch = function(m, entry, n, entries) calls[#calls + 1] = { m, entry, n, entries } end,
	}, function()
		Unit.ProvokeOpportunityAttacksFromList(mover, { first, { "iis", a, {}, dummies[4] }, second })
	end)
	t.eq(#calls, 1)
	t.eq(calls[1][1], mover)
	t.eq(calls[1][2], first)
	t.eq(#calls[1][4], 2)
	t.eq(calls[1][4][1], first)
	t.eq(calls[1][4][2], second)
end)

-- An overwatch handler that takes the entries of the player units and leaves the others.
local function TakePlayers(_, _, _, entries)
	local mine = {}
	for _, e in ipairs(entries) do
		if e[2].team == player_team then
			mine[#mine + 1] = e[2]
		end
	end
	if #mine == 0 then return end
	return { interrupters = mine, dummy = entries[1][4], stop = false, label = "Test overwatch" }
end

t.case("Vanilla fires no attack for a handled overwatch entry, and still adds its attacker to the passed interrupts", function()
	local mover, a, dummies = WalkingMover(10)
	local foe = FakeUnit({ id = "foe", team = enemy_team })
	FakeControl{ { at = 300, run = PressEndTurn } }
	local n = IISControl.InterruptCount() + 1
	WithHandlers({ overwatch = TakePlayers }, function()
		Unit.ProvokeOpportunityAttacksFromList(mover, {
			{ "overwatch", a, "args a", dummies[4] },
			{ "overwatch", foe, "args foe", dummies[4] },
		})
	end)
	t.eq(LogHas("INT #" .. n .. " BEGIN Test overwatch"), true)
	t.eq(#vanilla_attacks, 1)
	t.eq(vanilla_attacks[1], foe)
	t.eq(table.find(mover.passed_interrupts, 2, a) ~= nil, true)
	t.eq(table.find(mover.passed_interrupts, 2, foe) ~= nil, true)
end)

t.case("An entry type with no handler goes to vanilla unchanged next to a handled entry", function()
	local mover, a, dummies = WalkingMover(10)
	local b = FakeUnit({ id = "b" })
	FakeControl{ { at = 300, run = PressEndTurn } }
	local melee = { "melee", b, "melee args", dummies[4] }
	local list = { melee, { "overwatch", a, "args a", dummies[4] } }
	WithHandlers({ overwatch = TakePlayers }, function()
		Unit.ProvokeOpportunityAttacksFromList(mover, list)
	end)
	t.eq(vanilla_provoked[1], list)
	t.eq(list[1], melee)
	t.eq(melee[1], "melee")
	t.eq(melee[2], b)
	t.eq(melee[3], "melee args")
	t.eq(melee[4], dummies[4])
end)

t.case("An AP grant sets the interrupter's AP during the interrupt, and the handler gets the AP that is left", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = FakeUnit({ id = "ow", ap = 0 })
	local during, left
	FakeControl{
		{ at = 100, run = function()
			during = ow.ActionPoints
			ow:ConsumeAP(3000)
		end },
		{ at = 300, run = PressEndTurn },
	}
	WithHandlers({
		overwatch = function(_, entry)
			return { interrupters = { ow }, dummy = entry[4], stop = false, label = "Test overwatch",
				ap_grants = { [ow] = 8000 }, on_end = function(ap_left) left = ap_left end }
		end,
	}, function()
		Unit.ProvokeOpportunityAttacksFromList(mover, { { "overwatch", ow, "args", dummies[4] } })
	end)
	t.eq(during, 8000)
	t.eq(left and left[ow], 5000)
	t.eq(ow.ActionPoints, 0)
end)

t.case("An action limit stops an action that the check refuses, and allows an action that the check accepts", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = FakeUnit({ id = "ow", ap = 8000 })
	local other = FakeUnit({ id = "other", team = enemy_team })
	local asked = {}
	local function shot_at_mover(action_id, target)
		asked[#asked + 1] = action_id
		return action_id == "Attack" and target == mover
	end
	FakeControl{
		{ at = 100, run = function()
			StartCombatAction("Move", ow, 1000, { goto_pos = { x = 9, y = 9 } })
			StartCombatAction("Attack", ow, 2000, { target = other })
			StartCombatAction("Attack", ow, 2000, { target = mover })
		end },
		{ at = 300, run = PressEndTurn },
	}
	WithHandlers({
		overwatch = function(_, entry)
			return { interrupters = { ow }, dummy = entry[4], stop = false, label = "Test overwatch",
				action_limits = { [ow] = shot_at_mover } }
		end,
	}, function()
		Unit.ProvokeOpportunityAttacksFromList(mover, { { "overwatch", ow, "args", dummies[4] } })
	end)
	t.eq(table.concat(asked, ", "), "Move, Attack, Attack")
	t.eq(#ran_actions, 1)
	t.eq(ran_actions[1][1], "Attack")
	t.eq(ow.ActionPoints, 6000)
	t.eq(#vanilla_started, 0)
end)

------------------------------------------------------------------------------------------------
-- IOS through the provoke-list wrapper

g_Overwatch = {}
local reveal_logs = {}
E.LogOverwatchReveal = function(mover) reveal_logs[#reveal_logs + 1] = mover end

E.InOverwatchCone = function(u, target) return world.cone[u] and world.cone[u][target] or false end

local function SetIOS(on, actions)
	ApplyModOptions({ IOS = on, IOSActions = actions })
end

-- Sets what `ow` sees and has in its Overwatch cone. A nil value keeps the current one.
local function Watch(ow, target, sees, in_cone)
	world.sees[ow] = world.sees[ow] or {}
	world.cone[ow] = world.cone[ow] or {}
	if sees ~= nil then world.sees[ow][target] = sees end
	if in_cone ~= nil then world.cone[ow][target] = in_cone end
end

-- A merc on Overwatch with 0 AP and `attacks` Overwatch attacks. Its default attack costs `cost`
-- raw AP. Like vanilla, GainAP does nothing while it is on Overwatch that is not permanent.
local function Overwatcher(o)
	local u = FakeUnit({ id = o.id or "ow", ap = 0, attack_cost = o.cost or 4000, team = o.team })
	g_Overwatch[u] = { num_attacks = o.attacks or 2, triggered_by = {}, permanent = o.permanent }
	function u:InterruptPreparedAttack() g_Overwatch[self] = nil end
	function u:UpdateOverwatchVisual() end
	local gain = u.GainAP
	function u:GainAP(n)
		if g_Overwatch[self] and not g_Overwatch[self].permanent then return end
		gain(self, n)
	end
	return u
end

-- Unless a test says otherwise, `ow` sees the mover and has it in its cone, as vanilla requires for
-- a trigger.
local function WatchMover(ow, mover)
	for _, rows in ipairs{ world.sees, world.cone } do
		rows[ow] = rows[ow] or {}
		if rows[ow][mover] == nil then rows[ow][mover] = true end
	end
end

-- Gives the WalkingMover's provoke list an "overwatch" entry of `ow` on step 4, and returns the list.
local function OverwatchTrigger(mover, ow, dummies, script)
	WatchMover(ow, mover)
	FakeControl(script)
	local list = { { "overwatch", ow, { target = mover }, dummies[4] } }
	Unit.ProvokeOpportunityAttacksFromList(mover, list)
	game_time = 0
	return list
end

local function Shoot(ow, mover, cost)
	return function() StartCombatAction("Attack", ow, cost, { target = mover }) end
end

t.case("IOS: an overwatch entry of a merc starts an IOS interrupt with the merc as overwatcher, and vanilla fires no shot", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{}
	SetIOS(true)
	local n = IISControl.InterruptCount() + 1
	local list = OverwatchTrigger(mover, ow, dummies, { { at = 300, run = PressEndTurn } })
	t.eq(LogHas("INT #" .. n .. " BEGIN IOS overwatch: mover=enemy#enemy"), true)
	t.eq(LogHas("INT #" .. n .. "   interrupter 1: ow#ow"), true)
	t.eq(#vanilla_attacks, 0)
	t.eq(list[1][1], IISControl.HANDLED)
	t.eq(table.find(mover.passed_interrupts, 2, ow) ~= nil, true)
end)

t.case("IOS: the overwatcher's AP in the interrupt is the attack count multiplied by the default attack cost", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 3, cost = 2500 }
	SetIOS(true)
	local during
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() during = ow.ActionPoints end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(during, 7500)
	t.eq(ow.ActionPoints, 0)
end)

t.case("IOS: the handler adds the mover to triggered_by, removes its Hidden status and writes the combat log line", function()
	local mover, _, dummies = WalkingMover(10)
	mover.statuses.Hidden = true
	local ow = Overwatcher{}
	SetIOS(true)
	reveal_logs = {}
	OverwatchTrigger(mover, ow, dummies, { { at = 300, run = PressEndTurn } })
	t.eq(g_Overwatch[ow].triggered_by[mover.handle], true)
	t.eq(mover.statuses.Hidden, nil)
	t.eq(#reveal_logs, 1)
	t.eq(reveal_logs[1], mover)
end)

t.case("IOS: after a shot and End Turn, the AP that is left is the pool of the next trigger, and the attack count is the pool divided by the attack cost", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 3, cost = 3000 }
	SetIOS(true)
	OverwatchTrigger(mover, ow, dummies, { { at = 100, run = Shoot(ow, mover, 4000) }, { at = 300, run = PressEndTurn } })
	t.eq(ow.ActionPoints, 0)
	t.eq(g_Overwatch[ow].num_attacks, 1)
	local during
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() during = ow.ActionPoints end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(during, 5000)
end)

t.case("IOS: Overwatch ends when the pool cannot pay for one attack", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 2, cost = 3000 }
	SetIOS(true)
	OverwatchTrigger(mover, ow, dummies, { { at = 100, run = Shoot(ow, mover, 4000) }, { at = 300, run = PressEndTurn } })
	t.eq(g_Overwatch[ow], nil)
	t.eq(ow.ActionPoints, 0)
end)

t.case("IOS: a set-up machine gun stays on Overwatch with 0 attacks when its pool cannot pay for one attack", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 1, cost = 3000, permanent = true }
	SetIOS(true)
	OverwatchTrigger(mover, ow, dummies, { { at = 100, run = Shoot(ow, mover, 3000) }, { at = 300, run = PressEndTurn } })
	t.eq(g_Overwatch[ow] ~= nil, true)
	t.eq(g_Overwatch[ow].num_attacks, 0)
end)

t.case("IOS: a pass costs nothing, and Overwatch stays with all its attacks", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 2, cost = 4000 }
	SetIOS(true)
	OverwatchTrigger(mover, ow, dummies, { { at = 300, run = PressEndTurn } })
	t.eq(g_Overwatch[ow].num_attacks, 2)
	t.eq(ow.ActionPoints, 0)
	local during
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() during = ow.ActionPoints end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(during, 8000)
end)

t.case("IOS: the mover continues after the interrupt with \"Interrupted enemy = Stop\"", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{}
	SetIOS(true)
	Q.Config.after_interrupt = "stop"
	OverwatchTrigger(mover, ow, dummies, { { at = 300, run = PressEndTurn } })
	t.eq(IISControl.IsStopped(mover), false)
	t.eq(#mover.combat_path, 3)
	t.eq(LogHas("stops at"), false)
end)

t.case("IOS: with IOS off, vanilla gets the overwatch entry of a merc unchanged", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{}
	SetIOS(false)
	local count = IISControl.InterruptCount()
	local list = OverwatchTrigger(mover, ow, dummies)
	t.eq(list[1][1], "overwatch")
	t.eq(list[1][2], ow)
	t.eq(#vanilla_attacks, 1)
	t.eq(vanilla_attacks[1], ow)
	t.eq(IISControl.InterruptCount(), count)
end)

t.case("IOS: vanilla gets the overwatch entry of an enemy overwatcher unchanged", function()
	local mover, _, dummies = WalkingMover(10)
	local foe = Overwatcher{ id = "foe", team = enemy_team }
	SetIOS(true)
	local count = IISControl.InterruptCount()
	local list = OverwatchTrigger(mover, foe, dummies)
	t.eq(list[1][1], "overwatch")
	t.eq(#vanilla_attacks, 1)
	t.eq(vanilla_attacks[1], foe)
	t.eq(IISControl.InterruptCount(), count)
end)

t.case("IOS: an Overwatch state without a pool, as from an old save, gets a pool from its attack count", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 1, cost = 5000 }
	g_Overwatch[ow] = { num_attacks = 4, triggered_by = {}, expiration_turn = 2 }
	SetIOS(true)
	local during
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() during = ow.ActionPoints end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(during, 20000)
end)

t.case("IOS: after the game counts the attacks of a set-up machine gun again at its turn start, the pool comes from the new count", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 2, cost = 3000, permanent = true }
	g_Combat.current_turn = 1
	SetIOS(true)
	OverwatchTrigger(mover, ow, dummies, { { at = 100, run = Shoot(ow, mover, 4000) }, { at = 300, run = PressEndTurn } })
	t.eq(g_Overwatch[ow].num_attacks, 0)
	g_Combat.current_turn = 2
	g_Overwatch[ow].num_attacks = 3
	local during
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() during = ow.ActionPoints end },
		{ at = 300, run = PressEndTurn },
	})
	g_Combat.current_turn = nil
	t.eq(during, 9000)
end)

t.case("IOS: the AP of a queued action that never started goes back to the pool", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 2, cost = 4000 }
	SetIOS(true)
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function()
			CombatActions_RunningState[ow] = "start"
			StartCombatAction("Attack", ow, 4000, { target = mover })
		end },
		{ at = 200, run = function() CombatActions_RunningState[ow] = nil end },
		{ at = 300, run = PressEndTurn },
		{ at = 400, run = PressEndTurn },
	})
	t.eq(LogHas("dropped queued action Attack of ow#ow, refunded 4000 raw AP"), true)
	t.eq(g_Overwatch[ow].num_attacks, 2)
	t.eq(ow.ActionPoints, 0)
end)

t.case("IOS Shot only: the overwatcher cannot start a move", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 2, cost = 4000 }
	SetIOS(true, "Shot only")
	local left
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function()
			StartCombatAction("Move", ow, 1000, { goto_pos = { x = 9, y = 9 } })
			left = ow.ActionPoints
		end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(#ran_actions, 0)
	t.eq(left, 8000)
	t.eq(g_Overwatch[ow].num_attacks, 2)
end)

t.case("IOS Shot only: the overwatcher cannot attack an enemy outside its cone or an enemy that it cannot see", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 2, cost = 4000 }
	local outside = FakeUnit({ id = "outside", team = enemy_team })
	SetIOS(true, "Shot only")
	Watch(ow, mover, false, true)
	Watch(ow, outside, true, false)
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = Shoot(ow, mover, 4000) },
		{ at = 150, run = Shoot(ow, outside, 4000) },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(#ran_actions, 0)
	t.eq(g_Overwatch[ow].num_attacks, 2)
end)

t.case("IOS Shot only: the overwatcher can attack an enemy in its cone, and Overwatch stays", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 3, cost = 4000 }
	local other = FakeUnit({ id = "other", team = enemy_team })
	SetIOS(true, "Shot only")
	Watch(ow, other, true, true)
	OverwatchTrigger(mover, ow, dummies, { { at = 100, run = Shoot(ow, other, 4000) }, { at = 300, run = PressEndTurn } })
	t.eq(#ran_actions, 1)
	t.eq(ran_actions[1][1], "Attack")
	t.eq(g_Overwatch[ow] ~= nil, true)
	t.eq(g_Overwatch[ow].num_attacks, 2)
end)

t.case("IOS Shot only: a reload is allowed, and Overwatch stays", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 3, cost = 4000 }
	SetIOS(true, "Shot only")
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() StartCombatAction("Reload", ow, 2000, {}) end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(#ran_actions, 1)
	t.eq(ran_actions[1][1], "Reload")
	t.eq(g_Overwatch[ow] ~= nil, true)
	t.eq(g_Overwatch[ow].num_attacks, 2)
end)

t.case("IOS Any action: a move ends Overwatch after the interrupt", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 3, cost = 4000 }
	SetIOS(true, "Any action")
	local during
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function()
			StartCombatAction("Move", ow, 1000, { goto_pos = { x = 9, y = 9 } })
			during = g_Overwatch[ow] ~= nil
		end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(#ran_actions, 1)
	t.eq(ran_actions[1][1], "Move")
	t.eq(during, true)
	t.eq(g_Overwatch[ow], nil)
	t.eq(ow.ActionPoints, 0)
end)

t.case("IOS Any action: an attack keeps Overwatch while the pool can pay for one attack", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 3, cost = 4000 }
	local outside = FakeUnit({ id = "outside", team = enemy_team })
	SetIOS(true, "Any action")
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = Shoot(ow, mover, 4000) },
		{ at = 150, run = Shoot(ow, outside, 4000) },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(#ran_actions, 2)
	t.eq(g_Overwatch[ow] ~= nil, true)
	t.eq(g_Overwatch[ow].num_attacks, 1)
	OverwatchTrigger(mover, ow, dummies, { { at = 100, run = Shoot(ow, mover, 4000) }, { at = 300, run = PressEndTurn } })
	t.eq(g_Overwatch[ow], nil)
end)

------------------------------------------------------------------------------------------------
-- The attack args of a shot in an interrupt

local rifle = { kinds = { Firearm = true } }

-- Like vanilla, Firearm:GetAttackResults gives the attack args to Unit:CalcChanceToHit.
function rifle:GetAttackResults(action, attack_args)
	return { chance_to_hit = attack_args.obj:CalcChanceToHit(attack_args.target, action, attack_args) }
end

-- Like vanilla, CombatAction:GetActionResults makes the attack args with Unit:PrepareAttackArgs.
-- The crosshair calls it for the to-hit preview, and Unit:FirearmAttack calls it for the attack.
function CombatActions.Attack:GetActionResults(unit, args)
	local attack_args = unit:PrepareAttackArgs("Attack", args)
	return attack_args.weapon:GetAttackResults(self, attack_args), attack_args
end

-- Gives `unit` the weapon `weapon`, and records the args of each to-hit calculation in `unit.cth_args`.
local function Armed(unit, weapon)
	unit.weapon = weapon or rifle
	unit.cth_args = {}
	function unit:PrepareAttackArgs(...)
		return Unit.PrepareAttackArgs(self, ...)
	end
	function unit:CalcChanceToHit(_, _, args)
		self.cth_args[#self.cth_args + 1] = args
		return 50
	end
	return unit
end

-- Returns the args of the to-hit calculation of the crosshair preview of a shot of `unit` at `target`.
local function PreviewArgs(unit, target)
	CombatActions.Attack:GetActionResults(unit, { target = target })
	return unit.cth_args[#unit.cth_args]
end

t.case("IOS: the to-hit preview of an overwatcher's shot is an Overwatch opportunity attack", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Armed(Overwatcher{})
	SetIOS(true)
	local args
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() args = PreviewArgs(ow, mover) end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(args.opportunity_attack, true)
	t.eq(args.opportunity_attack_type, "Overwatch")
	local after = PreviewArgs(ow, mover)
	t.eq(after.opportunity_attack, nil)
	t.eq(after.opportunity_attack_type, nil)
end)

-- Runs `f` with a RunCombatAction that, like Unit:FirearmAttack, gets the attack args from
-- CombatAction:GetActionResults. Returns the attack args of each action that ran.
local function WithFiringAttacks(f)
	local fired = {}
	local saved = RunCombatAction
	function RunCombatAction(action_id, unit, ap, args)
		saved(action_id, unit, ap, args)
		local _, attack_args = CombatActions[action_id]:GetActionResults(unit, args)
		fired[#fired + 1] = attack_args
	end
	local ok, err = pcall(f)
	RunCombatAction = saved
	if not ok then error(err, 0) end
	return fired
end

t.case("IOS: the attack args of an overwatcher's shot make it an Overwatch opportunity attack", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Armed(Overwatcher{ attacks = 2, cost = 4000 })
	SetIOS(true)
	local fired = WithFiringAttacks(function()
		OverwatchTrigger(mover, ow, dummies, { { at = 100, run = Shoot(ow, mover, 4000) }, { at = 300, run = PressEndTurn } })
	end)
	t.eq(#fired, 1)
	t.eq(fired[1].opportunity_attack, true)
	t.eq(fired[1].opportunity_attack_type, "Overwatch")
	t.eq(ow.cth_args[1].opportunity_attack, true)
	t.eq(ow.cth_args[1].opportunity_attack_type, "Overwatch")
end)

t.case("IOS: the to-hit preview of an overwatcher's attack with a weapon that is not a firearm is not an opportunity attack", function()
	local mover, _, dummies = WalkingMover(10)
	local knife = { kinds = { MeleeWeapon = true }, GetAttackResults = rifle.GetAttackResults }
	local ow = Armed(Overwatcher{}, knife)
	SetIOS(true)
	local args
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() args = PreviewArgs(ow, mover) end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(args.opportunity_attack, nil)
	t.eq(args.opportunity_attack_type, nil)
end)

t.case("IIS: the to-hit preview and the attack args of a winner's shot are not an opportunity attack", function()
	local mover, a, dummies = WalkingMover(10)
	Armed(a)
	SetIOS(true)
	local preview
	FakeControl{
		{ at = 100, run = function()
			preview = PreviewArgs(a, mover)
			StartCombatAction("Attack", a, 4000, { target = mover })
		end },
		{ at = 300, run = PressEndTurn },
	}
	local fired = WithFiringAttacks(function()
		local list = Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", dummies)
		Unit.ProvokeOpportunityAttacksFromList(mover, list)
	end)
	game_time = 0
	t.eq(preview.opportunity_attack, nil)
	t.eq(preview.opportunity_attack_type, nil)
	t.eq(#fired, 1)
	t.eq(fired[1].opportunity_attack, nil)
	t.eq(fired[1].opportunity_attack_type, nil)
end)

t.case("IOS: an error in the handler is logged, and the enemy action continues with the vanilla shot", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{}
	SetIOS(true)
	local orig = E.LogOverwatchReveal
	E.LogOverwatchReveal = function() error("reveal boom") end
	local count = IISControl.InterruptCount()
	local ok = pcall(OverwatchTrigger, mover, ow, dummies)
	E.LogOverwatchReveal = orig
	t.eq(ok, true)
	t.eq(LogHas("overwatch handler failed: .*reveal boom"), true)
	t.eq(IISControl.InterruptCount(), count)
	t.eq(#vanilla_provoked, 1)
	t.eq(#vanilla_attacks, 1)
	SetIOS(false)
end)

-- Gives the WalkingMover's provoke list an "overwatch" entry on step 4 for each overwatcher in
-- `ows`, then `extra` entries, and returns the list.
local function OverwatchTriggers(mover, ows, dummies, script, extra)
	FakeControl(script)
	local list = {}
	for _, ow in ipairs(ows) do
		WatchMover(ow, mover)
		list[#list + 1] = { "overwatch", ow, { target = mover }, dummies[4] }
	end
	for _, e in ipairs(extra or {}) do
		list[#list + 1] = e
	end
	Unit.ProvokeOpportunityAttacksFromList(mover, list)
	game_time = 0
	return list
end

t.case("IOS: two overwatchers on one step share one IOS interrupt, and each has its own pool", function()
	local mover, _, dummies = WalkingMover(10)
	local ow1 = Overwatcher{ id = "ow1", attacks = 2, cost = 4000 }
	local ow2 = Overwatcher{ id = "ow2", attacks = 3, cost = 2500 }
	SetIOS(true)
	local n = IISControl.InterruptCount() + 1
	local during = {}
	local list = OverwatchTriggers(mover, { ow1, ow2 }, dummies, {
		{ at = 100, run = function() during[ow1], during[ow2] = ow1.ActionPoints, ow2.ActionPoints end },
		{ at = 300, run = PressEndTurn },
	})
	SetIOS(false)
	t.eq(IISControl.InterruptCount(), n)
	t.eq(LogHas("INT #" .. n .. "   interrupter 1: ow1#ow1"), true)
	t.eq(LogHas("INT #" .. n .. "   interrupter 2: ow2#ow2"), true)
	t.eq(during[ow1], 8000)
	t.eq(during[ow2], 7500)
	t.eq(list[1][1], IISControl.HANDLED)
	t.eq(list[2][1], IISControl.HANDLED)
	t.eq(#vanilla_attacks, 0)
end)

-- An "iis" entry on step 4 with `a` as the IIS winner of a move trigger.
local function IISEntry(a, dummies)
	return { "iis", a, { mercs = { a }, system = "IIS", kind = "move", check = 1 }, dummies[4] }
end

t.case("IOS: an overwatcher and an IIS winner on one step give an IOS interrupt, then an IIS interrupt", function()
	local mover, a, dummies = WalkingMover(10)
	local ow = Overwatcher{}
	SetIOS(true)
	local n = IISControl.InterruptCount() + 1
	local actors = {}
	local list = OverwatchTriggers(mover, { ow }, dummies, {
		{ at = 100, run = function() actors[#actors + 1] = IISControl.Active():Interrupters() end },
		{ at = 300, run = PressEndTurn },
		{ at = 500, run = function() actors[#actors + 1] = IISControl.Active():Interrupters() end },
		{ at = 700, run = PressEndTurn },
	}, { IISEntry(a, dummies) })
	SetIOS(false)
	t.eq(IISControl.InterruptCount(), n + 1)
	t.eq(LogHas("INT #" .. n .. " BEGIN IOS overwatch"), true)
	t.eq(LogHas("INT #" .. n + 1 .. " BEGIN IIS move"), true)
	t.eq(#actors, 2)
	t.eq(actors[1][1], ow)
	t.eq(#actors[1], 1)
	t.eq(actors[2][1], a)
	t.eq(#actors[2], 1)
	t.eq(list[1][1], IISControl.HANDLED)
	t.eq(list[2][1], IISControl.HANDLED)
end)

t.case("IOS: when the mover dies in the IOS interrupt, no IIS interrupt starts", function()
	local mover, a, dummies = WalkingMover(10)
	local ow = Overwatcher{}
	SetIOS(true)
	local n = IISControl.InterruptCount() + 1
	OverwatchTriggers(mover, { ow }, dummies, {
		{ at = 100, run = function() mover.dead = true end },
		{ at = 300, run = PressEndTurn },
		{ at = 700, run = PressEndTurn },
	}, { IISEntry(a, dummies) })
	SetIOS(false)
	t.eq(IISControl.InterruptCount(), n)
	t.eq(LogHas("BEGIN IIS"), false)
	t.eq(IISControl.Active(), false)
end)

t.case("IOS: when the mover is downed in the IOS interrupt, no IIS interrupt starts", function()
	local mover, a, dummies = WalkingMover(10)
	local ow = Overwatcher{}
	SetIOS(true)
	local n = IISControl.InterruptCount() + 1
	OverwatchTriggers(mover, { ow }, dummies, {
		{ at = 100, run = function() mover.down = true end },
		{ at = 300, run = PressEndTurn },
		{ at = 700, run = PressEndTurn },
	}, { IISEntry(a, dummies) })
	SetIOS(false)
	t.eq(IISControl.InterruptCount(), n)
	t.eq(LogHas("BEGIN IIS"), false)
	t.eq(LogHas("interrupt skipped: mover enemy#enemy cannot act"), true)
end)

t.case("IOS: an overwatcher that does not shoot because another overwatcher killed the mover keeps its full pool", function()
	local mover, _, dummies = WalkingMover(10)
	local ow1 = Overwatcher{ id = "ow1", attacks = 2, cost = 4000 }
	local ow2 = Overwatcher{ id = "ow2", attacks = 3, cost = 2500 }
	SetIOS(true)
	OverwatchTriggers(mover, { ow1, ow2 }, dummies, {
		{ at = 100, run = function()
			Shoot(ow1, mover, 4000)()
			mover.dead = true
		end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(LogHas("END %(mover_dead%)"), true)
	t.eq(g_Overwatch[ow1].num_attacks, 1)
	t.eq(g_Overwatch[ow2].num_attacks, 3)
	local next_mover, _, next_dummies = WalkingMover(10)
	local during
	OverwatchTriggers(next_mover, { ow2 }, next_dummies, {
		{ at = 100, run = function() during = ow2.ActionPoints end },
		{ at = 300, run = PressEndTurn },
	})
	SetIOS(false)
	t.eq(during, 7500)
end)
