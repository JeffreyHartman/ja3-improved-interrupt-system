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
-- The tests check lines of every level. A test that gives no LogLevel gets Debug.
CurrentModOptions = { LogLevel = "Debug" }
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

-- Runs each started thread as a coroutine. A thread that yields stays suspended for good, as a hung
-- game thread does.
local function RunThreads()
	local list = threads_started
	threads_started = {}
	for _, th in ipairs(list) do
		local ok, err = coroutine.resume(coroutine.create(th[1]), table.unpack(th, 2, th.n))
		if not ok then
			error(err, 0)
		end
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
local function vanilla_aim_range(self) return self.min_aim or 0, self.max_aim or 3 end
-- Like vanilla, it returns a copy of `args` with the attacker and the weapon of the action.
local function vanilla_prepare_attack_args(unit, action_id, args)
	local attack_args = {}
	for k, v in pairs(args or {}) do
		attack_args[k] = v
	end
	attack_args.action_id, attack_args.obj = action_id, unit
	attack_args.weapon = attack_args.weapon or unit.weapon
	return attack_args
end
-- Like vanilla, the fake list function attacks for each "overwatch" entry and adds every entry to
-- the mover's passed_interrupts. It calls vanilla_result.on_attack(entry) at each attack.
Unit = {
	CheckProvokeOpportunityAttacks = function()
		return vanilla_result.interrupts, vanilla_result.idx
	end,
	ProvokeOpportunityAttacksFromList = function(mover, list)
		vanilla_provoked[#vanilla_provoked + 1] = list
		for _, data in ipairs(list) do
			if data[1] == "overwatch" then
				vanilla_attacks[#vanilla_attacks + 1] = data[2]
				if vanilla_result.on_attack then
					vanilla_result.on_attack(data)
				end
			end
			mover.passed_interrupts = mover.passed_interrupts or {}
			table.insert(mover.passed_interrupts, data)
		end
	end,
	CanBeControlled = function() return "vanilla" end,
	OnDie = function(self) self.on_die_called = true end,
	IsIdleOrRunningBehavior = function() return "vanilla" end,
	GetBaseAimLevelRange = vanilla_aim_range,
	PrepareAttackArgs = vanilla_prepare_attack_args,
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
dofile("mod/Code/Aim.lua")
-- A mod whose code loads after this mod's code wraps this function.
local prepare_attack_args_after_load = Unit.PrepareAttackArgs
-- The game sends ModsReloaded after it runs the code files.
OnMsg.ModsReloaded()

local Q = IIS
local E = Q.E
local Mem = IISMemory

------------------------------------------------------------------------------------------------
-- Fake units and engine reads

local player_team = { side = "player1", control = "UI" }
local enemy_team = { side = "enemy1", control = "AI" }

-- The player and its allies are one camp, as in JA3. Neutral units are hostile to every camp here,
-- so that only the mod's own neutral check keeps them out.
local camps = { player1 = "player", ally = "player", enemy1 = "enemy", enemy2 = "enemy", neutral = "neutral" }

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
	function u:IsOnEnemySide(other) return camps[self.team.side] ~= camps[other.team.side] end
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
	world = { players = {}, ai_units = {}, ai_runs = {}, player_turn = false, los = {}, sees = {}, mover_sees = {}, cone = {}, rand = 99 }
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
	Q.Config.enemy_interrupts = true
	Q.ResetTurnStats()
	CombatActions_RunningState = {}
	ran_actions = {}
	vanilla_started = {}
	threads_started = {}
	g_AIExecutionController = {}
end

E.PlayerUnits = function() return world.players end
E.CanControlTeam = function(u) return u.team.control == "UI" end
E.AIUnits = function() return world.ai_units end
E.IsAITurnEnemy = function(u) return u.team.control ~= "UI" and not world.player_turn end
E.IsPlayerTurnMerc = function(u) return u.team.control == "UI" and world.player_turn end
local real_RunAI, real_StopAI = E.RunAI, E.StopAI
-- Records each AI run and plays world.ai_script(units) in place of the vanilla AI.
E.RunAI = function(units, camera_obj)
	world.ai_runs[#world.ai_runs + 1] = { units = units, camera_obj = camera_obj, active = IISControl.Active() }
	if world.ai_script then
		world.ai_script(units)
	end
end
E.MaxAPRaw = function(u) return u.max_ap end
E.StepRaw = function(stance) return stance == "Crouch" and 1500 or 1000 end
E.WalkRaw = function() return 1000 end
local real_attack_cost_raw = E.AttackCostRaw
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
-- world.team_sees[team][unit] is true when the team has seen the unit.
E.TeamSees = function(team, u) return world.team_sees and world.team_sees[team] and world.team_sees[team][u] or false end
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

-- A watcher with a counter and seen marks for a mover, as a save holds them.
local function SavedMemory()
	ResetWorld()
	local a, mover = FakeUnit({ id = "a" }), FakeUnit({ id = "enemy", team = enemy_team })
	Mem.Register(a, mover, 20)
	Mem.Sees(a, mover)
	return a, mover
end

t.case("CombatStart from a load keeps the counters and seen marks of the save", function()
	local a, mover = SavedMemory()
	OnMsg.CombatStart({ units = {} }, {})
	t.eq(Mem.Counter(a, mover), 20)
	t.eq(Mem.SeenThisTurn(a, mover), true)
	t.eq(Mem.SeenBefore(a, mover), true)
end)

t.case("CombatStart of a new combat clears the counters and seen marks", function()
	local a, mover = SavedMemory()
	OnMsg.CombatStart(nil, {})
	t.eq(Mem.Counter(a, mover), 0)
	t.eq(Mem.SeenThisTurn(a, mover), false)
	t.eq(Mem.SeenBefore(a, mover), false)
end)

-- A move plan of 3 steps along x in which watcher `a` registers 6 AP for each step.
local function PlannedMove(a, mover)
	local steps = { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 2, y = 0 } }
	Mem.PlanMove(mover, { steps = steps, first = 1, rows = { { unit = a, cum = { 6, 12, 18 } } } })
	return steps
end

t.case("A load drops the move plans", function()
	local a, mover = SavedMemory()
	local steps = PlannedMove(a, mover)
	Q.attack_targets[mover] = { a }
	OnMsg.PreLoadSessionData({})
	t.eq(next(Q.attack_targets), nil)
	t.eq(Mem.MoveDone(mover, steps[3]), nil)
	t.eq(Mem.Counter(a, mover), 20)
end)

t.case("The mod has no LoadGame handler, because JA3 does not send it", function()
	t.eq(msg_handlers.LoadGame, nil)
end)

------------------------------------------------------------------------------------------------
-- Mod options

-- Gives the options to the mod as the game does when it loads them or when the player applies them.
local function ApplyModOptions(options)
	if rawget(options, "LogLevel") == nil then
		options.LogLevel = "Debug"
	end
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

t.case("Options: the log line of the options gives IOS full aim under GBO 4", function()
	log_lines = {}
	ApplyModOptions({ IOSFullAim = true })
	t.eq(LogHas("mod options applied: .* ios_full_aim=true"), true)
	ApplyModOptions({})
	t.eq(Q.Config.ios_full_aim, false)
end)

local function WriteEachLevel()
	log_lines = {}
	Q.Error("an error line")
	Q.Info("an info line")
	Q.Debug("a debug line")
	Q.Always("an identity line")
end

t.case("Log level Error: only error lines and identity lines, each with its level tag", function()
	ApplyModOptions({ LogLevel = "Error" })
	WriteEachLevel()
	t.eq(table.concat(log_lines, "|"), "[IIS] [ERROR] an error line|[IIS] [INFO] an identity line")
	ApplyModOptions({})
end)

t.case("Log level Info: error, info and identity lines, no debug lines", function()
	ApplyModOptions({ LogLevel = "Info" })
	WriteEachLevel()
	t.eq(table.concat(log_lines, "|"),
		"[IIS] [ERROR] an error line|[IIS] [INFO] an info line|[IIS] [INFO] an identity line")
	ApplyModOptions({})
end)

t.case("Log level Debug: all lines", function()
	ApplyModOptions({ LogLevel = "Debug" })
	WriteEachLevel()
	t.eq(table.concat(log_lines, "|"),
		"[IIS] [ERROR] an error line|[IIS] [INFO] an info line|[IIS] [DEBUG] a debug line|[IIS] [INFO] an identity line")
end)

t.case("Log level: with no stored value or an unknown value, the level is Error", function()
	CurrentModOptions = {}
	OnMsg.ApplyModOptions(CurrentModId)
	t.eq(Q.Config.log_level, "Error")
	CurrentModOptions = { LogLevel = "Verbose" }
	OnMsg.ApplyModOptions(CurrentModId)
	t.eq(Q.Config.log_level, "Error")
	ApplyModOptions({})
end)

t.case("Log level: the config line gives the level, and the mod writes it at level Error", function()
	log_lines = {}
	ApplyModOptions({ LogLevel = "Error" })
	t.eq(LogHas("^%[IIS%] %[INFO%] mod options applied: .* log_level=Error "), true)
	t.eq(LogHas("verbose="), false)
	ApplyModOptions({})
end)

t.case("Log level: a line that the level filters out is not formatted", function()
	ApplyModOptions({ LogLevel = "Error" })
	log_lines = {}
	local called = false
	Q.Debug("%s", setmetatable({}, { __tostring = function() called = true return "x" end }))
	t.eq(called, false)
	t.eq(#log_lines, 0)
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
	t.eq(names.VerboseLog, nil)
	t.eq(table.concat(names.LogLevel.ChoiceList, ","), "Error,Info,Debug")
	t.eq(names.LogLevel.DefaultValue, "Error")
	t.eq(names.LogLevel.DisplayName:match("<color (%w+)>"), group_colors["both systems"])
	t.eq(table.concat(names.IOSActions.ChoiceList, ","), "Shot only,Any action")
	t.eq(names.IOSActions.DefaultValue, "Shot only")
	t.eq(names.IOSActions.DisplayName:match("<color (%w+)>"), group_colors.IOS)
	t.eq(names.IOSActions.Help:find("GBO 4") ~= nil, true)
end)

t.case("The options list: the help text of each option says what changes under GBO 4", function()
	for _, item in ipairs(LoadModFile("mod/items.lua")) do
		if item.class:find("^ModItemOption") then
			t.eq(item.Help:find("GBO 4", 1, true) ~= nil, true, item.name)
		end
	end
end)

t.case("The README options table has a row for each option", function()
	local file = io.open("README.md")
	local readme = file:read("a")
	file:close()
	for _, item in ipairs(LoadModFile("mod/items.lua")) do
		if item.class:find("^ModItemOption") then
			local name = item.DisplayName:match("^<color %w+>(.*)</color>$")
			t.eq(readme:find("\n| " .. name .. " |", 1, true) ~= nil, true, name)
		end
	end
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
	t.eq(Q.MoverSkipReason(FakeUnit({ id = "merc" }), "move"), "mover is not on the player team that has the turn")
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

t.case("WinSkipReason: a merc on Overwatch that has AP wins no IIS or JA2 Classic interrupt", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 10000 })
	local saved = rawget(_G, "g_Overwatch")
	g_Overwatch = { [a] = { num_attacks = 2, triggered_by = {} } }
	local iis, classic = Q.WinSkipReason(a, "IIS"), Q.WinSkipReason(a, "JA2 Classic")
	g_Overwatch = saved
	t.eq(iis, "on Overwatch")
	t.eq(classic, "on Overwatch")
	t.eq(Q.WinSkipReason(a, "IIS"), nil)
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

t.case("AttackCostRaw: a lookup error writes one log line with the error and the unit, and returns -1", function()
	ResetWorld()
	g_Combat.current_turn = 3
	local u = FakeUnit({ id = "err" })
	function u:GetDefaultAttackAction() error("no weapon table") end
	local before = #log_lines
	t.eq(real_attack_cost_raw(u), -1)
	t.eq(#log_lines, before + 1)
	t.eq(log_lines[#log_lines]:find("no weapon table", 1, true) ~= nil, true)
	t.eq(log_lines[#log_lines]:find("err#err", 1, true) ~= nil, true)
end)

t.case("AttackCostRaw: a unit logs its lookup error once per combat turn", function()
	ResetWorld()
	g_Combat.current_turn = 4
	local u = FakeUnit({ id = "again" })
	function u:GetDefaultAttackAction() error("broken") end
	local before = #log_lines
	real_attack_cost_raw(u)
	t.eq(real_attack_cost_raw(u), -1)
	t.eq(#log_lines, before + 1)
	g_Combat.current_turn = 5
	real_attack_cost_raw(u)
	t.eq(#log_lines, before + 2)
end)

t.case("AttackCostRaw: a lookup error outside combat and in a new combat writes a log line", function()
	ResetWorld()
	local u = FakeUnit({ id = "nocombat" })
	function u:GetDefaultAttackAction() error("broken") end
	local saved = g_Combat
	g_Combat = nil
	local before = #log_lines
	real_attack_cost_raw(u)
	local outside = #log_lines - before
	g_Combat = { current_turn = 2 }
	real_attack_cost_raw(u)
	g_Combat = { current_turn = 2 }
	real_attack_cost_raw(u)
	g_Combat = saved
	t.eq(outside, 1)
	t.eq(#log_lines, before + 3)
end)

t.case("AttackCostRaw: a unit with no default attack action returns -1 and logs nothing", function()
	ResetWorld()
	local u = FakeUnit({ id = "unarmed" })
	function u:GetDefaultAttackAction() return nil end
	local before = #log_lines
	t.eq(real_attack_cost_raw(u), -1)
	t.eq(#log_lines, before)
end)

t.case("WinSkipReason: an unknown attack cost is not an AP shortage", function()
	ResetWorld()
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 10000, attack_cost = -1 }), "IIS"), "attack cost unknown")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 10000, attack_cost = -1 }), "JA2 Classic"), "attack cost unknown")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 3000, attack_cost = 4000 }), "IIS"), "AP below attack cost")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 4000, attack_cost = 4000 }), "IIS"), nil)
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

-- Sends DoneMap as the engine does when `loading` says that a save is being loaded.
local function LoadMap(loading)
	local orig = E.LoadingSave
	E.LoadingSave = function() return loading end
	OnMsg.DoneMap()
	E.LoadingSave = orig
end

t.case("A load during an interrupt ends the interrupt and closes its UI", function()
	ResetWorld()
	log_lines = {}
	local ui_ended
	Q.UI = { End = function(it) ui_ended = it end }
	local it = ActiveState({ FakeUnit({ id = "a" }) }, FakeUnit({ id = "enemy", team = enemy_team }))
	LoadMap(true)
	t.eq(IISControl.Active(), false)
	t.eq(ui_ended, it)
	t.eq(LogHas("INT #1 END %(load%)"), true)
end)

t.case("A map change without a load during an interrupt ends it as a map change", function()
	ResetWorld()
	log_lines = {}
	ActiveState({ FakeUnit({ id = "a" }) }, FakeUnit({ id = "enemy", team = enemy_team }))
	LoadMap(false)
	t.eq(IISControl.Active(), false)
	t.eq(LogHas("INT #1 END %(map_change%)"), true)
end)

t.case("A map change with no interrupt active logs no interrupt end", function()
	ResetWorld()
	log_lines = {}
	OnMsg.DoneMap()
	t.eq(LogHas("END"), false)
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

t.case("A Stop interrupt that a load ends does not stop the mover", function()
	local mover, a = WalkingMover(10)
	local pops = 0
	function mover:PopDestructor() pops = pops + 1 end
	-- The map change runs in the thread of the load, not in the mover's command thread.
	FakeControl({ { at = 200, run = function()
		mover.in_cmd = false
		LoadMap(true)
	end } })
	local dummy = { pos = { x = 3, y = 0 }, valid = false }
	IISControl.Handle("test", function()
		return { interrupters = { a }, dummy = dummy, stop = true, label = "Test move" }
	end)
	Unit.ProvokeOpportunityAttacksFromList(mover, { { "test", a, nil, dummy } })
	IISControl.Handle("test", nil)
	t.eq(IISControl.Active(), false)
	t.eq(LogHas("END %(load%)"), true)
	t.eq(mover.combat_path[1], "dest")
	t.eq(IISControl.IsStopped(mover), false)
	t.eq(pops, 0)
end)

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
E.CrosshairTarget = function(u) return world.crosshair and world.crosshair[u] end

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

t.case("IOS: after a load, the pool comes from the saved Overwatch args, also the part below one attack cost", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 3, cost = 3000 }
	ow.combat_behavior = "OverwatchAction"
	ow.combat_behavior_params = { "Attack", 0, { num_attacks = 3 } }
	g_Combat.current_turn = 1
	SetIOS(true)
	OverwatchTrigger(mover, ow, dummies, { { at = 100, run = Shoot(ow, mover, 4000) }, { at = 300, run = PressEndTurn } })
	-- A load builds the Overwatch state again from the saved args, without the IOS fields.
	local args = ow.combat_behavior_params[3]
	g_Overwatch[ow] = { num_attacks = args.num_attacks, triggered_by = {} }
	local during
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() during = ow.ActionPoints end },
		{ at = 300, run = PressEndTurn },
	})
	g_Combat.current_turn = nil
	t.eq(args.num_attacks, 1)
	t.eq(during, 5000)
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

t.case("IOS Any action: a queued move that never started does not end Overwatch", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 2, cost = 4000 }
	SetIOS(true, "Any action")
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function()
			CombatActions_RunningState[ow] = "start"
			StartCombatAction("Move", ow, 1000, { goto_pos = { x = 9, y = 9 } })
		end },
		{ at = 200, run = function() CombatActions_RunningState[ow] = nil end },
		{ at = 300, run = PressEndTurn },
		{ at = 400, run = PressEndTurn },
	})
	t.eq(LogHas("dropped queued action Move of ow#ow"), true)
	t.eq(#ran_actions, 0)
	t.eq(g_Overwatch[ow] ~= nil, true)
	t.eq(g_Overwatch[ow].num_attacks, 2)
end)

t.case("IOS Any action: a stance change ends Overwatch after the interrupt", function()
	local mover, _, dummies = WalkingMover(10)
	local ow = Overwatcher{ attacks = 3, cost = 4000 }
	SetIOS(true, "Any action")
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() StartCombatAction("StanceCrouch", ow, 1000, {}) end },
		{ at = 300, run = PressEndTurn },
	})
	t.eq(#ran_actions, 1)
	t.eq(ran_actions[1][1], "StanceCrouch")
	t.eq(g_Overwatch[ow], nil)
	t.eq(LogHas("overwatcher ow#ow started StanceCrouch, Overwatch ends"), true)
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

-- Like GBO 4 (FEATURE_StepOutGate.lua), a wrap that calls the function that was in place when its
-- code loaded. It records the args that it gets from that function in `seen`.
local function GBOAttackArgsWrap(loaded, seen)
	return function(self, action_id, args)
		local attack_args = loaded(self, action_id, args)
		seen[#seen + 1] = attack_args.opportunity_attack or false
		return attack_args
	end
end

-- Returns the preview args of an overwatcher's shot and what a GBO 4 wrap saw. `gbo_first` puts the
-- GBO 4 code before this mod's code in the load order.
local function PreviewOverGBOWrap(gbo_first)
	local seen = {}
	local loaded = gbo_first and vanilla_prepare_attack_args or prepare_attack_args_after_load
	Unit.PrepareAttackArgs = GBOAttackArgsWrap(loaded, seen)
	OnMsg.ModsReloaded()
	local mover, _, dummies = WalkingMover(10)
	local ow = Armed(Overwatcher{})
	SetIOS(true)
	local args
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() args = PreviewArgs(ow, mover) end },
		{ at = 300, run = PressEndTurn },
	})
	Unit.PrepareAttackArgs = vanilla_prepare_attack_args
	OnMsg.ModsReloaded()
	return args, seen
end

t.case("IOS: in either load order with GBO 4, the preview is an Overwatch opportunity attack, and GBO 4 sees the args of the game", function()
	for _, gbo_first in ipairs{ true, false } do
		local args, seen = PreviewOverGBOWrap(gbo_first)
		t.eq(args.opportunity_attack, true, tostring(gbo_first))
		t.eq(args.opportunity_attack_type, "Overwatch", tostring(gbo_first))
		t.eq(#seen, 1, tostring(gbo_first))
		t.eq(seen[1], false, tostring(gbo_first))
	end
end)

t.case("IOS: the attack args hook is in place after a second ModsReloaded", function()
	log_lines = {}
	OnMsg.ModsReloaded()
	OnMsg.ModsReloaded()
	t.eq(LogHas("attack args hook: ours"), true)
	t.eq(LogHas("attack args hook: REPLACED"), false)
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

------------------------------------------------------------------------------------------------
-- "IOS full aim under GBO 4"

-- Like the GBO 4 Aim modifier in old CTH mode (Code/CTH_aim.lua), an opportunity attack gets
-- half of the aim bonus. Each aim level gives 10.
local function FakeGBO4OldCTH()
	aim_cth = function() end
	Presets = { ChanceToHitModifier = { Default = { Aim = {
		CalcValue = function(self, attacker, target, body_part_def, action, weapon1, weapon2, lof, aim,
			opportunity_attack)
			local bonus = aim * 10
			if opportunity_attack then
				bonus = bonus // 2
			end
			return aim > 0, bonus
		end,
	} } } }
	OnMsg.DataLoaded()
end

-- Like Unit:CalcChanceToHit, the to-hit of `unit` is the value of the Aim modifier for the attack args.
local function AimedArmed(unit)
	Armed(unit)
	function unit:CalcChanceToHit(target, action, args)
		self.cth_args[#self.cth_args + 1] = args
		local _, value = Presets.ChanceToHitModifier.Default.Aim:CalcValue(self, target, nil, action, args.weapon,
			nil, false, args.aim or 0, args.opportunity_attack)
		return value
	end
	return unit
end

-- Returns the to-hit of the crosshair preview of a shot of `unit` at `target` with `aim` aim levels.
local function PreviewAim(unit, target, aim)
	return (CombatActions.Attack:GetActionResults(unit, { target = target, aim = aim })).chance_to_hit
end

local function SetIOSFullAim(full_aim)
	ApplyModOptions({ IOS = true, IOSFullAim = full_aim })
end

t.case("IOS full aim under GBO 4: with the option on, an IOS shot gets the full aim bonus of GBO 4 old CTH", function()
	FakeGBO4OldCTH()
	local mover, _, dummies = WalkingMover(10)
	local ow = AimedArmed(Overwatcher{})
	SetIOSFullAim(true)
	local cth
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() cth = PreviewAim(ow, mover, 3) end },
		{ at = 300, run = PressEndTurn },
	})
	SetIOS(false)
	t.eq(cth, 30)
end)

t.case("IOS full aim under GBO 4: with the option off, an IOS shot gets half of the aim bonus, as in GBO 4 old CTH", function()
	FakeGBO4OldCTH()
	local mover, _, dummies = WalkingMover(10)
	local ow = AimedArmed(Overwatcher{})
	SetIOSFullAim(false)
	local cth
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() cth = PreviewAim(ow, mover, 3) end },
		{ at = 300, run = PressEndTurn },
	})
	SetIOS(false)
	t.eq(cth, 15)
end)

t.case("IOS full aim under GBO 4: with the option on, a vanilla Overwatch shot outside an IOS interrupt gets half of the aim bonus", function()
	FakeGBO4OldCTH()
	local mover = WalkingMover(10)
	local ow = Overwatcher{}
	SetIOSFullAim(true)
	local _, value = Presets.ChanceToHitModifier.Default.Aim:CalcValue(ow, mover, nil, CombatActions.Attack, rifle,
		nil, false, 3, true)
	SetIOS(false)
	t.eq(value, 15)
end)

t.case("IOS full aim under GBO 4: with the option on, the to-hit preview and the attack of an IOS shot are still Overwatch opportunity attacks", function()
	FakeGBO4OldCTH()
	local mover, _, dummies = WalkingMover(10)
	local ow = AimedArmed(Overwatcher{ attacks = 2, cost = 4000 })
	SetIOSFullAim(true)
	local preview
	local fired = WithFiringAttacks(function()
		OverwatchTrigger(mover, ow, dummies, {
			{ at = 100, run = function()
				PreviewAim(ow, mover, 3)
				preview = ow.cth_args[#ow.cth_args]
				Shoot(ow, mover, 4000)()
			end },
			{ at = 300, run = PressEndTurn },
		})
	end)
	SetIOS(false)
	t.eq(preview.opportunity_attack, true)
	t.eq(preview.opportunity_attack_type, "Overwatch")
	t.eq(#fired, 1)
	t.eq(fired[1].opportunity_attack, true)
	t.eq(fired[1].opportunity_attack_type, "Overwatch")
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

------------------------------------------------------------------------------------------------
-- Aim limits through the wrapped Unit:GetBaseAimLevelRange

local aim_action = { id = "SingleShot", IsAimableAttack = true }

local function AimRange(u)
	return Unit.GetBaseAimLevelRange(u, aim_action)
end

-- Runs an IOS interrupt for `ow` with the options `options` and returns the aim range of `ow` in it.
local function OverwatcherAimRange(ow, options)
	local mover, _, dummies = WalkingMover(10)
	options.IOS = true
	ApplyModOptions(options)
	local min, max
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() min, max = AimRange(ow) end },
		{ at = 300, run = PressEndTurn },
	})
	ApplyModOptions({})
	return min, max
end

t.case("Aim limit: the IOS and Interrupt aim limit options have the values 25% to 100% and the color of their group", function()
	local names = {}
	for _, item in ipairs(LoadModFile("mod/items.lua")) do
		names[item.name] = item
	end
	for name, group in pairs({ IOSAimLimit = "IOS", InterruptAimLimit = "Interrupt System" }) do
		t.eq(table.concat(names[name].ChoiceList, ","), "25%,50%,75%,100%", name)
		t.eq(names[name].DefaultValue, "100%", name)
		t.eq(names[name].DisplayName:match("<color (%w+)>"), group_colors[group], name)
	end
	t.eq(names.IOSAimLimit.DisplayName:find("IOS aim limit", 1, true) ~= nil, true)
	t.eq(names.InterruptAimLimit.DisplayName:find("Interrupt aim limit", 1, true) ~= nil, true)
end)

t.case("Aim limit: a 3-level weapon at 50% gives an overwatcher a maximum of 2 levels", function()
	local ow = Overwatcher{}
	ow.max_aim = 3
	local min, max = OverwatcherAimRange(ow, { IOSAimLimit = "50%", IOSFreeAim = "0" })
	t.eq(min, 0)
	t.eq(max, 2)
end)

t.case("Aim limit: a 10-level weapon at 25% gives an overwatcher a maximum of 3 levels", function()
	local ow = Overwatcher{}
	ow.max_aim = 10
	local _, max = OverwatcherAimRange(ow, { IOSAimLimit = "25%" })
	t.eq(max, 3)
end)

t.case("Aim limit: an overwatcher gets the IOS aim limit, and an IIS winner gets the Interrupt aim limit", function()
	local options = { IOSAimLimit = "50%", InterruptAimLimit = "25%" }
	local ow = Overwatcher{}
	ow.max_aim = 10
	local _, ow_max = OverwatcherAimRange(ow, options)
	t.eq(ow_max, 5)

	local mover, a, dummies = WalkingMover(10)
	a.max_aim = 10
	local winner_max
	FakeControl{
		{ at = 100, run = function() winner_max = select(2, AimRange(a)) end },
		{ at = 300, run = PressEndTurn },
	}
	ApplyModOptions(options)
	Unit.ProvokeOpportunityAttacksFromList(mover, Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", dummies))
	ApplyModOptions({})
	game_time = 0
	t.eq(winner_max, 3)
end)

t.case("Aim limit: no limit when no interrupt is active, or for a unit that is not an interrupter", function()
	local ow = Overwatcher{}
	ow.max_aim = 10
	local other = FakeUnit({ id = "b" })
	other.max_aim = 10
	local mover, _, dummies = WalkingMover(10)
	mover.max_aim = 10
	ApplyModOptions({ IOS = true, IOSAimLimit = "25%", InterruptAimLimit = "25%" })
	local other_max, mover_max
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function()
			other_max = select(2, AimRange(other))
			mover_max = select(2, AimRange(mover))
		end },
		{ at = 300, run = PressEndTurn },
	})
	local _, after_max = AimRange(ow)
	ApplyModOptions({})
	t.eq(other_max, 10)
	t.eq(mover_max, 10)
	t.eq(after_max, 10)
end)

t.case("Aim limit: the maximum never goes below the minimum", function()
	local ow = Overwatcher{}
	ow.min_aim, ow.max_aim = 2, 3
	local min, max = OverwatcherAimRange(ow, { IOSAimLimit = "25%" })
	t.eq(min, 2)
	t.eq(max, 2)
end)

-- Like GBO 4, a wrap that calls the function that was in place when its code loaded and changes
-- the range it returns.
local function GBOAimWrap(loaded)
	return function(self, action, target)
		local min, max = loaded(self, action, target)
		return math.max(min, 1), max + 7
	end
end

-- GBO 4 replaces the function when its code loads, so in either load order its wrap of vanilla is
-- in place when the game sends ModsReloaded.
t.case("Aim limit: the limit applies over a GBO 4 wrap of the aim range function in either load order", function()
	Unit.GetBaseAimLevelRange = GBOAimWrap(vanilla_aim_range)
	OnMsg.ModsReloaded()
	local ow = Overwatcher{}
	local min, max = OverwatcherAimRange(ow, { IOSAimLimit = "25%" })
	local after_min, after_max = AimRange(ow)
	Unit.GetBaseAimLevelRange = vanilla_aim_range
	OnMsg.ModsReloaded()
	t.eq(min, 1)
	t.eq(max, 3)
	t.eq(after_min, 1)
	t.eq(after_max, 10)
end)

t.case("Aim limit: a second ModsReloaded does not apply the limit twice", function()
	OnMsg.ModsReloaded()
	OnMsg.ModsReloaded()
	local ow = Overwatcher{}
	ow.max_aim = 10
	local _, max = OverwatcherAimRange(ow, { IOSAimLimit = "25%" })
	t.eq(max, 3)
end)

t.case("Aim limit: an error in the limit is logged, and the range of the wrapped function goes through", function()
	Unit.GetBaseAimLevelRange = function() return 0, "three" end
	OnMsg.ModsReloaded()
	local ow = Overwatcher{}
	local min, max = OverwatcherAimRange(ow, { IOSAimLimit = "25%" })
	local logged = LogHas("aim range failed")
	Unit.GetBaseAimLevelRange = vanilla_aim_range
	OnMsg.ModsReloaded()
	t.eq(min, 0)
	t.eq(max, "three")
	t.eq(logged, true)
end)

------------------------------------------------------------------------------------------------
-- IOS free aim levels through the wrapped Unit:GetBaseAimLevelRange

t.case("Free aim: the IOS free aim levels option has the values 0 to 2, the default 1 and the IOS color", function()
	local item
	for _, i in ipairs(LoadModFile("mod/items.lua")) do
		if i.name == "IOSFreeAim" then item = i end
	end
	t.eq(table.concat(item.ChoiceList, ","), "0,1,2")
	t.eq(item.DefaultValue, "1")
	t.eq(item.DisplayName:match("<color (%w+)>"), group_colors.IOS)
	t.eq(item.DisplayName:find("IOS free aim levels", 1, true) ~= nil, true)
	t.eq(item.Help:find("GBO 4", 1, true) ~= nil, true)
	t.eq(ApplyModOptions({}) and Q.Config.ios_free_aim, 1)
	t.eq(ApplyModOptions({ IOSFreeAim = "2" }) and Q.Config.ios_free_aim, 2)
	ApplyModOptions({})
end)

t.case("Free aim: with the value 1 and no GBO 4, the minimum aim of an overwatcher's shot is 1", function()
	local ow = Overwatcher{}
	local min, max = OverwatcherAimRange(ow, { IOSFreeAim = "1" })
	t.eq(min, 1)
	t.eq(max, 3)
end)

-- Like GBO 4, a wrap that gives a unit in the Shooting Stance a minimum of 1 aim level.
local function GBOStanceWrap(loaded)
	return function(self, action, target)
		local min, max = loaded(self, action, target)
		if self.Mobile_aimed then min = math.max(min, 1) end
		return min, max + 7
	end
end

-- Runs OverwatcherAimRange for an overwatcher in the GBO 4 Shooting Stance.
local function StanceAimRange(options)
	Unit.GetBaseAimLevelRange = GBOStanceWrap(vanilla_aim_range)
	OnMsg.ModsReloaded()
	local ow = Overwatcher{}
	ow.Mobile_aimed = true
	local min, max = OverwatcherAimRange(ow, options)
	Unit.GetBaseAimLevelRange = vanilla_aim_range
	OnMsg.ModsReloaded()
	return min, max
end

t.case("Free aim: the value is a total, so the value 1 gives no extra level in the GBO 4 Shooting Stance", function()
	local min, max = StanceAimRange({ IOSFreeAim = "1" })
	t.eq(min, 1)
	t.eq(max, 10)
end)

t.case("Free aim: with the value 2 in the GBO 4 Shooting Stance, the minimum aim is 2", function()
	local min = StanceAimRange({ IOSFreeAim = "2" })
	t.eq(min, 2)
end)

t.case("Free aim: the minimum never goes above the maximum aim levels of the weapon", function()
	local ow = Overwatcher{}
	ow.max_aim = 1
	local min, max = OverwatcherAimRange(ow, { IOSFreeAim = "2" })
	t.eq(min, 1)
	t.eq(max, 1)
end)

t.case("Free aim: no free levels for an IIS winner, a unit that is not an interrupter, or outside an interrupt", function()
	local ow = Overwatcher{}
	local other = FakeUnit({ id = "b" })
	local mover, _, dummies = WalkingMover(10)
	ApplyModOptions({ IOS = true, IOSFreeAim = "2" })
	local other_min, mover_min
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function()
			other_min = AimRange(other)
			mover_min = AimRange(mover)
		end },
		{ at = 300, run = PressEndTurn },
	})
	local after_min = AimRange(ow)

	local iis_mover, a, iis_dummies = WalkingMover(10)
	local winner_min
	FakeControl{
		{ at = 100, run = function() winner_min = AimRange(a) end },
		{ at = 300, run = PressEndTurn },
	}
	Unit.ProvokeOpportunityAttacksFromList(iis_mover, Unit.CheckProvokeOpportunityAttacks(iis_mover, nil, "move", iis_dummies))
	ApplyModOptions({})
	game_time = 0
	t.eq(other_min, 0)
	t.eq(mover_min, 0)
	t.eq(after_min, 0)
	t.eq(winner_min, 0)
end)

-- Like GBO 4 Rat_KillzoneAim, it gives `aim`, or the ladder value of `target` capped at the maximum
-- aim of the attacker, when the target is a unit. `ladder[target]` is the value of each target.
local function FakeKillzoneAim(ladder, targets)
	return function(attacker, target, aim, action)
		targets[#targets + 1] = target
		if not IsKindOf(target, "Unit") then return aim end
		local _, max = Unit.GetBaseAimLevelRange(attacker, action, target)
		return math.max(aim, math.min(ladder[target] or 0, max))
	end
end

-- Runs OverwatcherAimRange with a fake GBO 4 Killzone ladder that gives the mover `value`.
-- Returns the aim range and the targets that the ladder got.
local function KillzoneAimRange(ow, value, options)
	local targets = {}
	local mover, _, dummies = WalkingMover(10)
	Rat_KillzoneAim = FakeKillzoneAim({ [mover] = value }, targets)
	options.IOS = true
	ApplyModOptions(options)
	local min, max
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() min, max = AimRange(ow) end },
		{ at = 300, run = PressEndTurn },
	})
	ApplyModOptions({})
	Rat_KillzoneAim = nil
	return min, max, targets, mover
end

t.case("Free aim: Killzone with a GBO 4 ladder value of 3 gives a minimum of 3", function()
	local ow = Overwatcher{}
	ow.max_aim = 10
	local min, max, targets, mover = KillzoneAimRange(ow, 3, { IOSFreeAim = "1" })
	t.eq(min, 3)
	t.eq(max, 10)
	t.eq(targets[1], mover)
end)

t.case("Free aim: an error in the GBO 4 Killzone ladder is logged, and the next shot still gets the ladder value", function()
	local ow = Overwatcher{}
	ow.max_aim = 10
	local mover, _, dummies = WalkingMover(10)
	local calls = 0
	Rat_KillzoneAim = function()
		calls = calls + 1
		if calls == 1 then error("ladder broken") end
		return 3
	end
	ApplyModOptions({ IOS = true, IOSFreeAim = "1" })
	local first_min, second_min
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function()
			first_min = AimRange(ow)
			second_min = AimRange(ow)
		end },
		{ at = 300, run = PressEndTurn },
	})
	ApplyModOptions({})
	Rat_KillzoneAim = nil
	t.eq(first_min, 0)
	t.eq(LogHas("aim range failed: .*ladder broken"), true)
	t.eq(second_min, 3)
end)

t.case("Free aim: under GBO 4, the option value applies when it is higher than the Killzone ladder value", function()
	local ow = Overwatcher{}
	ow.max_aim = 10
	t.eq(KillzoneAimRange(ow, 1, { IOSFreeAim = "2" }), 2)
end)

-- Like Unit:GetAttackAPCost, it asks for the aim range with the weapon as the target.
local function CostAimMin(u)
	return (Unit.GetBaseAimLevelRange(u, aim_action, { kinds = { Firearm = true } }))
end

t.case("Free aim: under GBO 4, the Killzone ladder gets the target of the shot when it is a unit", function()
	local ow = Overwatcher{}
	ow.max_aim = 10
	local other = FakeUnit({ id = "b", team = enemy_team })
	local mover, _, dummies = WalkingMover(10)
	local targets = {}
	Rat_KillzoneAim = FakeKillzoneAim({ [mover] = 3, [other] = 2 }, targets)
	ApplyModOptions({ IOS = true, IOSFreeAim = "0" })
	local other_min
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function() other_min = Unit.GetBaseAimLevelRange(ow, aim_action, other) end },
		{ at = 300, run = PressEndTurn },
	})
	ApplyModOptions({})
	Rat_KillzoneAim = nil
	t.eq(other_min, 2)
end)

t.case("Free aim: under GBO 4, the AP cost of a shot at the crosshair target gets the Killzone value of that target", function()
	local ow = Overwatcher{}
	ow.max_aim = 10
	local other = FakeUnit({ id = "b", team = enemy_team })
	local mover, _, dummies = WalkingMover(10)
	Rat_KillzoneAim = FakeKillzoneAim({ [mover] = 3, [other] = 2 }, {})
	ApplyModOptions({ IOS = true, IOSFreeAim = "0" })
	local crosshair_min, no_crosshair_min
	OverwatchTrigger(mover, ow, dummies, {
		{ at = 100, run = function()
			world.crosshair = { [ow] = other }
			crosshair_min = CostAimMin(ow)
			world.crosshair = nil
			no_crosshair_min = CostAimMin(ow)
		end },
		{ at = 300, run = PressEndTurn },
	})
	ApplyModOptions({})
	Rat_KillzoneAim = nil
	t.eq(crosshair_min, 2)
	t.eq(no_crosshair_min, 3)
end)

-- Runs OverwatcherAimRange for an overwatcher with the Killzone perk and no GBO 4.
local function VanillaKillzoneAimRange(options)
	local ow = Overwatcher{}
	local perk = E.Perk
	E.Perk = function(u, id) return u == ow and id == "Killzone" end
	local min, max = OverwatcherAimRange(ow, options)
	E.Perk = perk
	return min, max
end

t.case("Free aim: Killzone without GBO 4 gives 1 level, and the option value when it is higher", function()
	t.eq(VanillaKillzoneAimRange({ IOSFreeAim = "0" }), 1)
	t.eq(VanillaKillzoneAimRange({ IOSFreeAim = "2" }), 2)
end)

t.case("Watchers: a merc is on the player side and an enemy is not, and each watches only the other side", function()
	local alive = function() return false end
	local merc = { team = { control = "UI" }, IsIncapacitated = alive }
	local enemy = { team = { control = "AI" }, IsIncapacitated = alive }
	merc.IsOnEnemySide = function() return true end
	t.eq(Q.IsPlayerSide(merc), true)
	t.eq(Q.IsPlayerSide(enemy), false)
	t.eq(Q.ObserverSkipReason(merc, enemy), nil)
	t.eq(Q.ObserverSkipReason(merc, merc), "same side as mover")
end)

------------------------------------------------------------------------------------------------
-- Enemy interrupts

local militia_team = { side = "ally", control = "AI" }
local neutral_team = { side = "neutral", control = "AI" }

-- A merc in the player turn walking a path of 6 steps in its own CombatGoto command, and an enemy
-- that watches it with reaction time 27 and registers 6 AP per step. With a counter of 10, the
-- enemy wins on step 4. The path costs 6 AP to the end and 3 AP to step 4.
local function WalkingMerc(counter, watcher)
	ResetWorld()
	g_AIExecutionController = false
	world.player_turn = true
	local merc = FakeUnit({ id = "merc", pos = { x = 0, y = 0 }, max_ap = 12000 })
	local o = { id = "e", team = enemy_team, level = 5, agility = 80, ap = 10000, pos = { x = 0, y = 6 } }
	for k, v in pairs(watcher or {}) do
		o[k] = v
	end
	local e = FakeUnit(o)
	world.ai_units = { e }
	world.los[e] = Steps(2, 3, 4, 5, 6)
	E.Dist = function() return 6 end
	if counter then
		Mem.Register(e, merc, counter)
	end
	local dummies = Path(merc, 6)
	merc.in_cmd = true
	merc.command = "CombatGoto"
	merc.command_thread = "cmd"
	merc.combat_path = { "dest", "mid", "start" }
	merc.combat_path_obj = { GetAP = function(_, p) return p == "dest" and 6000 or 3000 end }
	merc.start_move_free_ap = 0
	return merc, e, dummies
end

-- Sends the move check and the provoke list of the merc's path, as CombatGoto does.
local function MercMoves(merc, dummies)
	local list = Unit.CheckProvokeOpportunityAttacks(merc, nil, "move", dummies)
	if list then
		Unit.ProvokeOpportunityAttacksFromList(merc, list)
	end
	return list
end

t.case("Enemy interrupt: an enemy wins an IIS move check, the merc stops with the AP of the rest of its path, and the AI run gets the winner", function()
	local merc, e, dummies = WalkingMerc(10)
	FakeControl()
	local n = IISControl.InterruptCount() + 1
	MercMoves(merc, dummies)
	t.eq(LogHas("check #%d+ IIS TRIGGER mover=merc#merc at step 4/6"), true)
	t.eq(#merc.combat_path, 1)
	t.eq(merc.combat_path[1], dummies[4].pos)
	t.eq(merc.ActionPoints, 13000)
	t.eq(#world.ai_runs, 0)
	RunThreads()
	t.eq(#world.ai_runs, 1)
	t.eq(#world.ai_runs[1].units, 1)
	t.eq(world.ai_runs[1].units[1], e)
	t.eq(world.ai_runs[1].camera_obj, merc)
	t.eq(LogHas("INT #" .. n .. " BEGIN IIS enemy move: mover=merc#merc"), true)
	t.eq(LogHas("INT #" .. n .. "   interrupter 1: e#e"), true)
	t.eq(LogHas("INT #" .. n .. " END %(ai_done%)"), true)
	t.eq(Mem.Counter(e, merc), 0)
end)

t.case("Enemy interrupt: player orders and End Turn do nothing from the stop until the AI run returns, then player control comes back", function()
	local merc, e, dummies = WalkingMerc(10)
	local other = FakeUnit({ id = "other" })
	FakeControl()
	MercMoves(merc, dummies)
	t.eq(Unit.CanBeControlled(merc), false)
	t.eq(Unit.CanBeControlled(other), false)
	t.eq(NetSyncEvents.EndTurn(netUniqueId), nil)
	StartCombatAction("Move", merc, 1000)
	t.eq(#vanilla_started, 0)
	t.eq(merc.ActionPoints, 13000)
	t.eq(IISControl.Active() ~= false, true)
	world.ai_script = function(units)
		StartCombatAction("Attack", units[1], 4000)
		t.eq(Unit.CanBeControlled(merc), false)
	end
	RunThreads()
	t.eq(#vanilla_started, 1)
	t.eq(vanilla_started[1][2], e)
	t.eq(IISControl.Active(), false)
	t.eq(Unit.CanBeControlled(merc), "vanilla")
	t.eq(NetSyncEvents.EndTurn(netUniqueId), "vanilla")
end)

t.case("Enemy interrupt: the notification shows at the start and hides at the end, and the merc is selected after it", function()
	local merc, e, dummies = WalkingMerc(10)
	FakeControl()
	local shown = {}
	FakeSelection(merc)
	Q.UI = {
		BeginEnemy = function() shown[#shown + 1] = "begin" end,
		EndEnemy = function() shown[#shown + 1] = "end" end,
	}
	world.ai_script = function()
		shown[#shown + 1] = "ai"
		SelectedObj = e
	end
	MercMoves(merc, dummies)
	t.eq(table.concat(shown, ","), "begin")
	RunThreads()
	t.eq(table.concat(shown, ","), "begin,ai,end")
	t.eq(SelectedObj, merc)
	t.eq(IISControl.Active(), false)
end)

t.case("Enemy interrupt: a merc that went down is not selected after the interrupt", function()
	local merc, e, dummies = WalkingMerc(10)
	FakeControl()
	FakeSelection(merc)
	Q.UI = { BeginEnemy = function() end, EndEnemy = function() end }
	world.ai_script = function()
		merc.down = true
		SelectedObj = e
	end
	MercMoves(merc, dummies)
	RunThreads()
	t.eq(SelectedObj, e)
end)

-- True when the merc walks its whole path and no AI run starts.
local function NoEnemyInterrupt(merc, dummies)
	FakeControl()
	local list = MercMoves(merc, dummies)
	RunThreads()
	return list == nil and #merc.combat_path == 3 and #world.ai_runs == 0 and IISControl.Active() == false
end

t.case("Enemy interrupt: an enemy with too little AP, on Overwatch or with a blocking status does not win", function()
	local merc, _, dummies = WalkingMerc(10, { ap = 3000, attack_cost = 4000 })
	t.eq(NoEnemyInterrupt(merc, dummies), true)
	local merc2, e2, dummies2 = WalkingMerc(10)
	local saved = rawget(_G, "g_Overwatch")
	g_Overwatch = { [e2] = { num_attacks = 2, triggered_by = {} } }
	local on_overwatch = NoEnemyInterrupt(merc2, dummies2)
	g_Overwatch = saved
	t.eq(on_overwatch, true)
	local merc3, _, dummies3 = WalkingMerc(10, { statuses = { Panicked = true } })
	t.eq(NoEnemyInterrupt(merc3, dummies3), true)
end)

t.case("Enemy interrupt: militia, AI allies and neutral units do not win", function()
	local ai_ally_team = { side = "player1", control = "AI" }
	for _, team in ipairs({ militia_team, ai_ally_team, neutral_team }) do
		local merc, _, dummies = WalkingMerc(10, { team = team })
		t.eq(NoEnemyInterrupt(merc, dummies), true, team.side)
	end
	t.eq(Q.turn_stats.watcher_skips.neutral, 1)
end)

t.case("Enemy interrupt: with the Enemy interrupts option off, or with Interrupt System = Off, no enemy interrupt starts", function()
	local merc, _, dummies = WalkingMerc(10)
	ApplyModOptions({ EnemyInterrupts = false })
	local option_off = NoEnemyInterrupt(merc, dummies)
	local skips = Q.turn_stats.mover_skips["enemy interrupts off"]
	merc, _, dummies = WalkingMerc(10)
	ApplyModOptions({ InterruptSystem = "Off" })
	local system_off = NoEnemyInterrupt(merc, dummies)
	ApplyModOptions({})
	t.eq(option_off, true)
	t.eq(skips, 1)
	t.eq(system_off, true)
	t.eq(Q.Config.enemy_interrupts, true)
	t.eq(LoadModFile("mod/metadata.lua").default_options.EnemyInterrupts, true)
end)

t.case("Enemy interrupt: no check of either side runs while it is active", function()
	local merc, e, dummies = WalkingMerc(10)
	local watcher = FakeUnit({ id = "a", pos = { x = 0, y = 6 } })
	world.players = { watcher, merc }
	world.los[watcher] = Steps(2, 3, 4, 5, 6)
	FakeControl()
	MercMoves(merc, dummies)
	local merc2 = FakeUnit({ id = "merc2" })
	Mem.Register(e, merc2, 100)
	Mem.Register(watcher, e, 100)
	local lists = {}
	world.ai_script = function()
		g_AIExecutionController = {}
		lists.ai = Q.AddTrigger(e, "move", Path(e, 6))
		lists.merc = Q.AddTrigger(merc2, "move", Path(merc2, 6))
		g_AIExecutionController = false
	end
	RunThreads()
	t.eq(#world.ai_runs, 1)
	t.eq(lists.ai, nil)
	t.eq(lists.merc, nil)
	t.eq(Q.turn_stats.mover_skips["interrupt active"], 2)
end)

-- WalkingMerc with an enemy overwatcher whose vanilla Overwatch entry is on step 4, the step of
-- the enemy interrupt. `on_shot(merc)` runs at the Overwatch shot.
local function OverwatchOnTheStep(on_shot)
	local merc, e, dummies = WalkingMerc(10)
	local o = FakeUnit({ id = "o", team = enemy_team, pos = { x = 6, y = 0 } })
	vanilla_result.interrupts, vanilla_result.idx = { { "overwatch", o, {}, dummies[4] } }, 4
	local shot = {}
	vanilla_result.on_attack = function()
		shot.active, shot.path_nodes = IISControl.Active(), #merc.combat_path
		if on_shot then on_shot(merc) end
	end
	FakeControl()
	local list = MercMoves(merc, dummies)
	return merc, e, dummies, list, shot, o
end

t.case("Enemy interrupt: a vanilla Overwatch entry on the same step fires before the enemy interrupt starts", function()
	local merc, e, dummies, list, shot, o = OverwatchOnTheStep()
	t.eq(#list, 2)
	t.eq(vanilla_attacks[1], o)
	t.eq(shot.active, false)
	t.eq(shot.path_nodes, 3)
	t.eq(#merc.combat_path, 1)
	t.eq(merc.combat_path[1], dummies[4].pos)
	RunThreads()
	t.eq(#world.ai_runs, 1)
	t.eq(world.ai_runs[1].units[1], e)
	t.eq(IISControl.Active(), false)
end)

t.case("Enemy interrupt: a merc that the Overwatch shot downs gets no enemy interrupt", function()
	local merc = OverwatchOnTheStep(function(m) m.down = true end)
	RunThreads()
	t.eq(#world.ai_runs, 0)
	t.eq(IISControl.Active(), false)
	t.eq(#merc.combat_path, 3)
	t.eq(LogHas("interrupt skipped: mover merc#merc cannot act"), true)
end)

t.case("Enemy interrupt: a hung AI run ends at the time-out with a stuck dump, and player control comes back", function()
	local merc, _, dummies = WalkingMerc(10)
	FakeControl()
	local stopped = {}
	local orig_stop = E.StopAI
	E.StopAI = function() stopped[#stopped + 1] = IISControl.Active() end
	world.ai_script = function() coroutine.yield() end
	MercMoves(merc, dummies)
	RunThreads()
	E.StopAI = orig_stop
	t.eq(#world.ai_runs, 1)
	t.eq(game_time, Q.Config.enemy_ai_timeout_ms)
	t.eq(LogHas("INT #%d+ STUCK%? the AI run did not return in %d+ms"), true)
	t.eq(LogHas("INT #%d+ END %(ai_timeout%)"), true)
	t.eq(#stopped, 1)
	t.eq(IISControl.Active(), false)
	t.eq(Unit.CanBeControlled(merc), "vanilla")
	t.eq(NetSyncEvents.EndTurn(netUniqueId), "vanilla")
	game_time = 0
end)

t.case("Enemy interrupt: an AI run that fails calls E.StopAI and ends the interrupt with the reason ai_error", function()
	local merc, _, dummies = WalkingMerc(10)
	FakeControl()
	local stopped = 0
	local orig_stop = E.StopAI
	E.StopAI = function() stopped = stopped + 1 end
	world.ai_script = function() error("AI broke") end
	MercMoves(merc, dummies)
	local ok = pcall(RunThreads)
	E.StopAI = orig_stop
	t.eq(ok, true)
	t.eq(stopped, 1)
	t.eq(LogHas("INT #%d+ AI run failed: .*AI broke"), true)
	t.eq(LogHas("INT #%d+ END %(ai_error%)"), true)
	t.eq(IISControl.Active(), false)
	t.eq(Unit.CanBeControlled(merc), "vanilla")
end)

-- Runs `fn` with fakes of the engine reads of the Enemy interrupt diagnostics: visibility, camera and Shooting
-- Stance. `o.camera` is the list of look-at distances that E.Camera returns, one per call.
local function WithDiagnosticReads(o, fn)
	local saved = { E.Visibility, E.Camera, E.CarriedAP }
	E.Visibility = function(unit) return table.unpack(o.visibility[unit.session_id] or { false, false, false }) end
	Q.UI = { BeginEnemy = function() end, EndEnemy = function() end }
	local camera_calls = 0
	E.Camera = function()
		camera_calls = camera_calls + 1
		return "look" .. camera_calls, (o.camera or {})[camera_calls]
	end
	E.CarriedAP = function(unit) return (o.carried or {})[unit.session_id] end
	local ok, err = pcall(fn)
	E.Visibility, E.Camera, E.CarriedAP = table.unpack(saved)
	if not ok then
		error(err, 0)
	end
end

t.case("Enemy interrupt diagnostics: BEGIN gives the visibility of each interrupter in both directions", function()
	local merc, e, dummies = WalkingMerc(10)
	FakeControl()
	local n = IISControl.InterruptCount() + 1
	WithDiagnosticReads({ visibility = { e = { true, false, false } } }, function()
		MercMoves(merc, dummies)
		RunThreads()
	end)
	t.eq(LogHas("^%[IIS%] %[INFO%] INT #" .. n .. "   visibility e#e: sees mover=true, mover sees it=false, player team sees it=false$"), true)
end)

t.case("Enemy interrupt diagnostics: a unit that dies or goes down in an interrupt writes one line, and vanilla OnDie still runs", function()
	local merc, e, dummies = WalkingMerc(10)
	FakeControl()
	local n = IISControl.InterruptCount() + 1
	local other = FakeUnit({ id = "other" })
	function merc:ShouldGetDowned() return false end
	function other:ShouldGetDowned() return true end
	world.ai_script = function(units)
		Unit.OnDie(merc, units[1], {})
		Unit.OnDie(other, units[1], {})
	end
	MercMoves(merc, dummies)
	RunThreads()
	t.eq(LogHas("^%[IIS%] %[INFO%] INT #" .. n .. " unit died: merc#merc, attacker e#e$"), true)
	t.eq(LogHas("^%[IIS%] %[INFO%] INT #" .. n .. " unit downed: other#other, attacker e#e$"), true)
	t.eq(merc.on_die_called, true)
	log_lines = {}
	Unit.OnDie(e, merc, {})
	t.eq(LogHas("unit died"), false)
end)

t.case("Enemy interrupt diagnostics: the camera look-at and its distance to the mover at BEGIN, END and 2 s after END", function()
	local merc, _, dummies = WalkingMerc(10)
	FakeControl()
	local n = IISControl.InterruptCount() + 1
	local end_time
	WithDiagnosticReads({ visibility = {}, camera = { 287, 10322, 290 } }, function()
		MercMoves(merc, dummies)
		RunThreads()
		end_time = game_time
		RunThreads()
	end)
	t.eq(game_time, end_time + 2000)
	t.eq(LogHas("^%[IIS%] %[INFO%] INT #" .. n .. " camera at BEGIN: look%-at=look1, distance to mover=287$"), true)
	t.eq(LogHas("^%[IIS%] %[INFO%] INT #" .. n .. " camera at END: look%-at=look2, distance to mover=10322$"), true)
	t.eq(LogHas("^%[IIS%] %[INFO%] INT #" .. n .. " camera 2s after END: look%-at=look3, distance to mover=290$"), true)
end)

t.case("Enemy interrupt diagnostics: BEGIN and END give the Shooting Stance and the carried AP of each interrupter", function()
	local merc, e, dummies = WalkingMerc(10)
	FakeControl()
	local n = IISControl.InterruptCount() + 1
	WithDiagnosticReads({ visibility = {}, carried = { e = 6000 } }, function()
		MercMoves(merc, dummies)
		RunThreads()
	end)
	t.eq(LogHas("^%[IIS%] %[INFO%] INT #" .. n .. "   e#e at BEGIN: shooting_stance=yes AP_Carried=6000 raw$"), true)
	t.eq(LogHas("^%[IIS%] %[INFO%] INT #" .. n .. "   e#e at END: shooting_stance=yes AP_Carried=6000 raw$"), true)
	for _, case in ipairs({ { carried = {}, line = "e#e at END: shooting_stance=no$" },
		{ carried = { e = "unset" }, line = "e#e at END: shooting_stance=yes AP_Carried=unset$" } }) do
		local merc2, _, dummies2 = WalkingMerc(10)
		FakeControl()
		WithDiagnosticReads({ visibility = {}, carried = case.carried }, function()
			MercMoves(merc2, dummies2)
			RunThreads()
		end)
		t.eq(LogHas(case.line), true, case.line)
	end
end)

t.case("Enemy interrupt diagnostics: at log level Error, none of them are in the log", function()
	local merc, _, dummies = WalkingMerc(10)
	FakeControl()
	ApplyModOptions({ LogLevel = "Error" })
	function merc:ShouldGetDowned() return false end
	world.ai_script = function(units) Unit.OnDie(merc, units[1], {}) end
	local ok, err = pcall(WithDiagnosticReads, { visibility = {}, camera = { 1, 2, 3 }, carried = { e = 6000 } }, function()
		MercMoves(merc, dummies)
		RunThreads()
		RunThreads()
	end)
	ApplyModOptions({})
	t.eq(ok, true, tostring(err))
	for _, pattern in ipairs({ "visibility", "unit died", "camera", "shooting_stance" }) do
		t.eq(LogHas(pattern), false, pattern)
	end
	t.eq(LogHas("mod options applied: .* log_level=Error "), true)
end)

-- A fake AI controller class for the real E.RunAI and E.StopAI. `execute(controller)` plays
-- AIExecutionController:Execute, and DoneObject plays AIExecutionController:Done (CombatCamera.lua:601).
local function FakeAIController(execute)
	local saved = { CreateAIExecutionController, DoneObject, AdjustCombatCamera, g_AIExecutionController }
	local fake = { done = {}, camera = {} }
	function CreateAIExecutionController(o)
		local c = { label = o.label, restore_camera_obj = false }
		function c:Execute(units) return execute(self, units) end
		g_AIExecutionController = c
		fake.controller = c
		return c
	end
	function DoneObject(c)
		fake.done[#fake.done + 1] = c
		if c.restore_camera_obj then
			fake.camera[#fake.camera + 1] = c.restore_camera_obj
		end
		g_AIExecutionController = false
	end
	function AdjustCombatCamera(state, _, target)
		if state == "reset" then
			fake.camera[#fake.camera + 1] = target
		end
	end
	function fake.restore()
		CreateAIExecutionController, DoneObject, AdjustCombatCamera, g_AIExecutionController = table.unpack(saved, 1, 4)
	end
	return fake
end

t.case("Enemy interrupt: when Execute fails, E.RunAI removes the AI controller, turns the camera to the merc and gives back player control", function()
	local merc = FakeUnit({ id = "merc" })
	g_Combat.is_player_control = true
	local fake = FakeAIController(function()
		g_Combat.is_player_control = false
		error("Execute broke")
	end)
	local ok, err = pcall(real_RunAI, {}, merc)
	fake.restore()
	t.eq(ok, false)
	t.eq(tostring(err):find("Execute broke") ~= nil, true)
	t.eq(#fake.done, 1)
	t.eq(fake.done[1], fake.controller)
	t.eq(fake.camera[1], merc)
	t.eq(g_Combat.is_player_control, true)
end)

t.case("Enemy interrupt: E.StopAI turns the camera to the merc, with or without an AI controller", function()
	local merc = FakeUnit({ id = "merc" })
	local fake = FakeAIController(function() end)
	CreateAIExecutionController{ label = "hung" }
	real_StopAI(nil, merc)
	t.eq(#fake.done, 1)
	t.eq(fake.camera[1], merc)
	real_StopAI(nil, merc)
	fake.restore()
	t.eq(#fake.done, 1)
	t.eq(fake.camera[2], merc)
end)

t.case("Enemy interrupt: at the time-out the AI interrupters stop their commands and E.StopAI gets the merc for the camera", function()
	local merc, e, dummies = WalkingMerc(10)
	FakeControl()
	local stop_args
	local orig_stop = E.StopAI
	E.StopAI = function(thread, camera_obj) stop_args = { camera_obj = camera_obj } end
	world.ai_script = function()
		e.command = "CombatGoto"
		coroutine.yield()
	end
	MercMoves(merc, dummies)
	RunThreads()
	E.StopAI = orig_stop
	game_time = 0
	t.eq(stop_args.camera_obj, merc)
	t.eq(e.command, "Idle")
	t.eq(LogHas("INT #%d+ sending e#e to Idle %(was CombatGoto%)"), true)
end)

t.case("Enemy interrupt: CanSaveGameQuery blocks saves until the AI run returns", function()
	local merc, _, dummies = WalkingMerc(10)
	FakeControl()
	MercMoves(merc, dummies)
	local during, after = {}, {}
	OnMsg.CanSaveGameQuery(during)
	RunThreads()
	OnMsg.CanSaveGameQuery(after)
	t.eq(during.iis_interrupt, true)
	t.eq(after.iis_interrupt, nil)
end)

t.case("Enemy interrupt: a load before the AI run starts ends the interrupt, and the AI does not run", function()
	local merc, _, dummies = WalkingMerc(10)
	FakeControl()
	MercMoves(merc, dummies)
	LoadMap(true)
	t.eq(IISControl.Active(), false)
	t.eq(LogHas("INT #%d+ END %(load%)"), true)
	RunThreads()
	t.eq(#world.ai_runs, 0)
	t.eq(IISControl.Active(), false)
	t.eq(game_time, 0)
end)

-- A merc that is on its way along a path and an AI watcher that never saw it. The watcher and the
-- merc both have 6 JA2 Classic points at 6 tiles.
local function ClassicSetup(watcher)
	local merc, e, dummies = WalkingMerc(nil, watcher)
	Q.Config.system = "JA2 Classic"
	-- A path of 5 steps or more is a run, which costs the mover 2 points.
	return merc, e, { dummies[1], dummies[2], dummies[3], dummies[4] }
end

t.case("Enemy interrupt, JA2 Classic: an enemy wins the duel on first sight only with the team knowledge point", function()
	local merc, e, dummies = ClassicSetup()
	local idx = Q.FindClassicMoveTrigger(merc, dummies, 1)
	t.eq(idx, nil) -- 6 vs 6, a tie goes to the mover
	world.team_sees = { [enemy_team] = { [merc] = true } }
	local winners
	idx, winners = Q.FindClassicMoveTrigger(merc, dummies, 1)
	t.eq(idx, 2)
	t.eq(winners[1].unit, e)
	t.eq(winners[1].how, "points") -- 7 vs 6
end)

t.case("Enemy interrupt, JA2 Classic: an enemy that saw the merc this turn does not duel it", function()
	local merc, e, dummies = ClassicSetup({ level = 9, agility = 95 })
	Mem.Sees(e, merc)
	t.eq(Q.FindClassicMoveTrigger(merc, dummies, 1), nil)
	t.eq(Q.turn_stats.watcher_skips["saw mover this turn"], 1)
end)

t.case("Enemy interrupt, JA2 Classic: the merc's own points get no enemy bonus from its team", function()
	local merc, e, dummies = ClassicSetup()
	world.team_sees = { [player_team] = { [e] = true } }
	t.eq(Q.FindClassicMoveTrigger(merc, dummies, 1), nil)
end)

-- A merc that attacked the enemy `e` and was not seen by it, and the attack check of the merc.
local function MercAttacks(system, watcher)
	local merc, e, dummies = WalkingMerc(100, watcher)
	Q.Config.system = system
	merc.command = "Idle"
	merc.in_cmd = false
	OnMsg.RunCombatAction("Attack", merc, 4000)
	OnMsg.Attack({ id = "Attack" }, {}, {}, false, merc, e)
	FakeControl()
	return merc, e, Unit.CheckProvokeOpportunityAttacks(merc, nil, "attack reaction", { merc })
end

t.case("Enemy interrupt: an enemy wins the check after a merc's attack in IIS", function()
	local merc, e, list = MercAttacks("IIS")
	t.eq(list ~= nil and list[1][1], "iis_enemy")
	t.eq(list[1][2], e)
	t.eq(list[1][3].kind, "attack")
end)

t.case("Enemy interrupt: an enemy that was not attacked and does not see the merc wins no IIS check after its attack", function()
	local merc, e = WalkingMerc(100)
	merc.command = "Idle"
	FakeControl()
	t.eq(Unit.CheckProvokeOpportunityAttacks(merc, nil, "attack reaction", { merc }), nil)
end)

t.case("Enemy interrupt: an enemy wins the check after a merc's attack in JA2 Classic", function()
	local merc, e, list = MercAttacks("JA2 Classic", { level = 8 })
	t.eq(list ~= nil and list[1][1], "iis_enemy")
	t.eq(list[1][2], e)
	t.eq(list[1][3].system, "JA2 Classic")
end)

t.case("Enemy interrupt: a merc action that an enemy sees adds to the counter of that enemy in IIS", function()
	local merc, e = WalkingMerc(nil)
	local hidden = FakeUnit({ id = "hidden", team = enemy_team })
	world.ai_units = { e, hidden }
	world.sees[e] = { [merc] = true }
	OnMsg.RunCombatAction("Attack", merc, 4000)
	t.eq(Mem.Counter(e, merc), 24)
	t.eq(Mem.Counter(hidden, merc), 0)
	OnMsg.RunCombatAction("Move", merc, 4000)
	t.eq(Mem.Counter(e, merc), 24)
	Q.Config.enemy_interrupts = false
	OnMsg.RunCombatAction("Attack", merc, 4000)
	t.eq(Mem.Counter(e, merc), 24)
end)

t.case("Enemy interrupt: an enemy interrupter's action adds to the counters of the mercs, and no player interrupt starts", function()
	local merc, e, dummies = WalkingMerc(10)
	world.players = { merc }
	world.sees[merc] = { [e] = true }
	FakeControl()
	local n = IISControl.InterruptCount()
	MercMoves(merc, dummies)
	world.ai_script = function()
		g_AIExecutionController = {}
		OnMsg.RunCombatAction("Attack", e, 4000)
		g_AIExecutionController = false
		world.during = IISControl.Active()
	end
	RunThreads()
	t.eq(Mem.Counter(merc, e) > 0, true)
	t.eq(world.during ~= false, true)
	t.eq(IISControl.InterruptCount(), n + 1)
end)

t.case("Enemy interrupt: an AI interrupter's move adds the AP of each seen step to the counters of the mercs, and starts no check", function()
	local merc, e, dummies = WalkingMerc(10)
	world.players = { merc }
	FakeControl()
	local n = IISControl.InterruptCount()
	MercMoves(merc, dummies)
	local result = {}
	world.ai_script = function()
		g_AIExecutionController = {}
		local path = Path(e, 6)
		world.los[merc] = Steps(2, 3, 4, 5, 6)
		e.in_cmd = true
		result.list = Unit.CheckProvokeOpportunityAttacks(e, nil, "move", path)
		e.pos = path[6].pos
		OnMsg.UnitMovementDone(e)
		e.in_cmd = false
		g_AIExecutionController = false
	end
	RunThreads()
	t.eq(result.list, nil)
	-- 6 registered AP on each of the 5 seen steps, as for the enemy watcher of WalkingMerc.
	t.eq(Mem.Counter(merc, e), 30)
	t.eq(IISControl.InterruptCount(), n + 1)
	t.eq(LogHas("TRIGGER mover=e#e"), false)
end)

-- Plays the AP rule of vanilla Unit:BeginTurn (Unit.lua:2671, 2692): an Overwatch that has not
-- expired stays, and then the unit starts its turn with 0 AP.
local function VanillaBeginTurn(u)
	local ow = g_Overwatch[u]
	if ow and not (ow.permanent or ow.expiration_turn > g_Combat.current_turn) then
		g_Overwatch[u] = nil
		ow = nil
	end
	u.ActionPoints = ow and not ow.permanent and 0 or u.max_ap
end

t.case("Enemy interrupt: an interrupter that spends all its AP and goes on Overwatch in it starts its next turn with full AP", function()
	local merc, e, dummies = WalkingMerc(10)
	FakeControl()
	MercMoves(merc, dummies)
	-- Vanilla Overwatch expires in the round after the one it starts in (UnitOverwatch.lua:210),
	-- and the enemy turn comes later in the same round as the player turn.
	local saved_turn = g_Combat.current_turn
	g_Combat.current_turn = 3
	world.ai_script = function()
		e:ConsumeAP(e.ActionPoints)
		g_Overwatch[e] = { expiration_turn = g_Combat.current_turn + 1, triggered_by = {} }
	end
	RunThreads()
	VanillaBeginTurn(e)
	g_Combat.current_turn = saved_turn
	t.eq(e.ActionPoints, e.max_ap)
	t.eq(g_Overwatch[e], nil)
end)

t.case("Enemy interrupt: with collective on, an enemy teammate near the winner joins and the AI run gets both", function()
	local merc, e, dummies = WalkingMerc(10)
	local mate = FakeUnit({ id = "mate", team = enemy_team, ap = 10000, pos = { x = 0, y = 7 } })
	world.ai_units = { e, mate }
	world.rand = 0
	FakeControl()
	local n = IISControl.InterruptCount() + 1
	MercMoves(merc, dummies)
	RunThreads()
	t.eq(#world.ai_runs, 1)
	t.eq(#world.ai_runs[1].units, 2)
	t.eq(world.ai_runs[1].units[1], e)
	t.eq(world.ai_runs[1].units[2], mate)
	t.eq(LogHas("INT #" .. n .. " collective: e#e %-> mate#mate chance=%d+ roll=0 JOINS"), true)
	t.eq(LogHas("INT #" .. n .. "   interrupter 2: mate#mate ap=10 %(collective%)"), true)
end)

t.case("Enemy interrupt: with collective off, only the winner plays", function()
	local merc, e, dummies = WalkingMerc(10)
	local mate = FakeUnit({ id = "mate", team = enemy_team, ap = 10000, pos = { x = 0, y = 7 } })
	world.ai_units = { e, mate }
	world.rand = 0
	Q.Config.collective = false
	FakeControl()
	MercMoves(merc, dummies)
	RunThreads()
	Q.Config.collective = true
	t.eq(#world.ai_runs, 1)
	t.eq(#world.ai_runs[1].units, 1)
	t.eq(world.ai_runs[1].units[1], e)
end)

t.case("Enemy interrupt: a joiner must pass the merc joiner checks and be on the winner's team", function()
	local merc, e, dummies = WalkingMerc(10)
	local far = FakeUnit({ id = "far", team = enemy_team, ap = 10000, pos = { x = 0, y = 30 } })
	local tired = FakeUnit({ id = "tired", team = enemy_team, ap = 0, pos = { x = 0, y = 7 } })
	local other = FakeUnit({ id = "other", team = { side = "enemy2", control = "AI" }, ap = 10000, pos = { x = 0, y = 7 } })
	world.ai_units = { e, far, tired, other }
	world.rand = 0
	FakeControl()
	MercMoves(merc, dummies)
	RunThreads()
	t.eq(#world.ai_runs, 1)
	t.eq(#world.ai_runs[1].units, 1)
	t.eq(LogHas("collective: e#e %-> far#far skipped: %d+ tiles away"), true)
	t.eq(LogHas("collective: e#e %-> tired#tired skipped: AP below minimum"), true)
	t.eq(LogHas("collective: e#e %-> other#other skipped: other team"), true)
end)

t.case("Enemy interrupt: the aim range of the AI interrupter is limited by the Interrupt aim limit", function()
	local merc, e, dummies = WalkingMerc(10)
	e.max_aim = 10
	ApplyModOptions({ InterruptAimLimit = "50%" })
	FakeControl()
	local min, max
	world.ai_script = function()
		min, max = AimRange(e)
	end
	MercMoves(merc, dummies)
	RunThreads()
	ApplyModOptions({})
	t.eq(#world.ai_runs, 1)
	t.eq(min, 0)
	t.eq(max, 5)
	t.eq(select(2, AimRange(e)), 10)
end)

t.case("Enemy interrupt: the aim limit does not apply to an enemy that is not an interrupter, nor to the merc", function()
	local merc, _, dummies = WalkingMerc(10)
	merc.max_aim = 10
	local other = FakeUnit({ id = "other", team = enemy_team })
	other.max_aim = 10
	ApplyModOptions({ InterruptAimLimit = "25%" })
	FakeControl()
	local other_max, merc_max
	world.ai_script = function()
		other_max = select(2, AimRange(other))
		merc_max = select(2, AimRange(merc))
	end
	MercMoves(merc, dummies)
	RunThreads()
	ApplyModOptions({})
	t.eq(other_max, 10)
	t.eq(merc_max, 10)
end)

t.case("Enemy interrupt: an enemy on vanilla Overwatch outside an enemy interrupt keeps its full aim range", function()
	WalkingMerc(10)
	local ow = Overwatcher{}
	ow.max_aim = 10
	ApplyModOptions({ InterruptAimLimit = "25%", IOSAimLimit = "25%" })
	t.eq(IISControl.Active() and true or false, false)
	local min, max = AimRange(ow)
	ApplyModOptions({})
	t.eq(min, 0)
	t.eq(max, 10)
end)
