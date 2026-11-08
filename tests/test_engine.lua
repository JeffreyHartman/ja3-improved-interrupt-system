-- Tests for the game-side logic in mod/Code/IIS.lua and mod/Code/Control.lua. They load the
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

function GetPassSlab(p)
	return p
end

function ObjModified() end
function IsValidThread() return false end
function IsSetpiecePlaying() return false end

CombatActions_RunningState = {}
CombatActions_Waiting = {}
CombatActions = { Move = { SimultaneousPlay = true }, Attack = {}, Reload = {} }

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
Unit = {
	CheckProvokeOpportunityAttacks = function()
		return vanilla_result.interrupts, vanilla_result.idx
	end,
	ProvokeOpportunityAttacksFromList = function() end,
	CanBeControlled = function() return "vanilla" end,
	IsIdleOrRunningBehavior = function() return "vanilla" end,
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
OnMsg = {}

dofile("mod/Code/IIS.lua")
dofile("mod/Code/Control.lua")

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
	function u:GainAP(n) self.ActionPoints = self.ActionPoints + n end
	function u:ConsumeAP(n) self.ActionPoints = self.ActionPoints - (n or 0) end
	function u:RemoveStatusEffect(id)
		if id == "FreeMove" and self.statuses.FreeMove then
			self.statuses.FreeMove = nil
			self:ConsumeAP(self.free_move_ap)
			self.free_move_ap = 0
		end
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

local function ResetWorld()
	world = { players = {}, los = {}, sees = {}, mover_sees = {}, rand = 99 }
	Q.attack_targets = {}
	Q.active = false
	gv_IIS = {}
	Mem.Setup{
		key = function(u) return E.Key(u) end,
		same_tile = function(a, b) return E.SameTile(a, b) end,
		store = function() return gv_IIS end,
	}
	vanilla_result = {}
	Q.Config.enabled = true
	Q.Config.system = "IIS"
	Q.Config.require_attack_ap = true
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

-- Starts an interrupt with Q.Activate, as RunInterrupt does, without the engine calls around it.
local function ActiveState(winners, mover, joiners)
	local it = IISInterrupt.Begin{ n = 1, mover = mover, winners = winners, joiners = joiners or {}, system = "IIS",
		kind = "move", cfg = Q.Config }
	Q.Activate(it)
	return it
end

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
	g_AIExecutionController = {}
	Q.Config.enabled = false
	t.eq(Q.MoverSkipReason(mover, "move"), "disabled")
end)

t.case("WinSkipReason: the AP minimum does not depend on the watcher's max AP", function()
	ResetWorld()
	Q.Config.require_attack_ap = false
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 1500, max_ap = 6000 }), "Classic"), "AP below minimum")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 500, max_ap = 24000 }), "IIS"), nil)
end)

t.case("WinSkipReason: Free Move AP does not pay for the attack or the AP minimum", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 3000, free_move_ap = 29000, attack_cost = 4000, statuses = { FreeMove = true } })
	t.eq(Q.WinSkipReason(a, "IIS"), "AP below attack cost")
	Q.Config.require_attack_ap = false
	t.eq(Q.WinSkipReason(FakeUnit({ id = "b", ap = 0, free_move_ap = 29000 }), "IIS"), "AP below minimum")
end)

t.case("IISWatcher: the AP of the reaction time leaves out Free Move AP", function()
	ResetWorld()
	t.eq(Q.IISWatcher(FakeUnit({ id = "a", ap = 6000, free_move_ap = 3000 })).ap, 6000)
end)

t.case("RemoveFreeMove: the interrupter loses its Free Move AP and the FreeMove status", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 4000, free_move_ap = 29000, statuses = { FreeMove = true } })
	t.eq(Q.RemoveFreeMove(a), 29000)
	t.eq(a.ActionPoints, 4000)
	t.eq(a.free_move_ap, 0)
	t.eq(a.statuses.FreeMove, nil)
end)

t.case("RemoveFreeMove: Free Move AP without the status is also removed", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 4000, free_move_ap = 2000 })
	t.eq(Q.RemoveFreeMove(a), 2000)
	t.eq(a.ActionPoints, 4000)
	t.eq(a.free_move_ap, 0)
end)

t.case("RemoveFreeMove: a unit with no Free Move AP keeps its AP", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 4000 })
	t.eq(Q.RemoveFreeMove(a), 0)
	t.eq(a.ActionPoints, 4000)
end)

t.case("WinSkipReason: AP minimum, attack cost and blocking statuses", function()
	ResetWorld()
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 10000 }), "IIS"), nil)
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 1500, attack_cost = 1000 }), "Classic"), "AP below minimum")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 3000, attack_cost = 4000 }), "IIS"), "AP below attack cost")
	Q.Config.require_attack_ap = false
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", ap = 3000, attack_cost = 4000 }), "IIS"), nil)
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", statuses = { Panicked = true } }), "IIS"), "Panicked")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", statuses = { Suppressed = true } }), "Classic"), "under fire")
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", statuses = { Suppressed = true } }), "IIS"), nil)
	t.eq(Q.WinSkipReason(FakeUnit({ id = "a", statuses = { Choking = true } }), "Classic"), "gassed")
end)

------------------------------------------------------------------------------------------------
-- Classic move trigger

t.case("Classic: the earliest winning step wins, a loser before it does not block", function()
	ResetWorld()
	Q.Config.system = "Classic"
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

t.case("Classic: a watcher with LOS to the mover's tile is skipped", function()
	ResetWorld()
	Q.Config.system = "Classic"
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

t.case("Classic: an unseen watcher wins even with a lower score", function()
	ResetWorld()
	Q.Config.system = "Classic"
	local mover = FakeUnit({ id = "enemy", team = enemy_team, level = 9, agility = 95 })
	local a = FakeUnit({ id = "a", level = 1, agility = 30, pos = { x = 3, y = 1 } })
	world.players = { a }
	world.los[a] = Steps(2)
	world.mover_sees[a] = false
	local idx, winners = Q.FindClassicMoveTrigger(mover, Path(mover, 3), 1)
	t.eq(idx, 2)
	t.eq(winners[1].how, "automatic")
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

t.case("The check wrapper returns nothing for a stopped mover", function()
	local mover = IISSetup(10)
	mover.command_thread = "thread"
	mover.iis_stopped = "thread"
	vanilla_result = { interrupts = { { "overwatch" } }, idx = 2 }
	t.eq(Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", Path(mover, 6)), nil)
	mover.iis_stopped = "old thread"
	local list = Unit.CheckProvokeOpportunityAttacks(mover, nil, "move", Path(mover, 6))
	t.eq(list[1][1], "overwatch")
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
	Q.active = false
	local list = Q.AddTrigger(mover, "attack reaction", { mover })
	t.eq(list, nil)
	t.eq(LogHas("after attack by enemy.*: no winner: a.*counter 0, reaction time %d+, sees attacker"), true)
end)

t.case("Classic after an attack: only an attacked merc that did not see the attacker duels", function()
	ResetWorld()
	Q.Config.system = "Classic"
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
	Q.active = false
	t.eq(Unit.CanBeControlled(b), "vanilla")
end)

t.case("CanBeControlled: a collective joiner is an interrupter", function()
	ResetWorld()
	local a, b = FakeUnit({ id = "a" }), FakeUnit({ id = "b" })
	ActiveState({ a }, FakeUnit({ id = "enemy", team = enemy_team }), { b })
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
	local it = ActiveState({ a, b }, FakeUnit({ id = "enemy", team = enemy_team }), { c })
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
	ActiveState({ a }, FakeUnit({ id = "enemy", team = enemy_team }), { b })
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
	Q.EndInterrupt(it, "test")
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
	Q.active = false
	t.eq(NetSyncEvents.EndTurn(netUniqueId), "vanilla")
end)

t.case("Activate returns the new shell with the dummy and the start AP of each interrupter", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 7000 })
	local it = IISInterrupt.Begin{ n = 1, mover = FakeUnit({ id = "enemy", team = enemy_team }), winners = { a },
		joiners = {}, system = "IIS", kind = "move", cfg = Q.Config }
	local dummy = { pos = { x = 1, y = 0 } }
	local sh = Q.Activate(it, dummy)
	t.eq(Q.active, it)
	t.eq(sh.dummy, dummy)
	t.eq(sh.start_ap[a], 7000)
end)

t.case("DumpStuck logs the command stack of each busy interrupter that is not down", function()
	ResetWorld()
	local a = FakeUnit({ id = "stuck_a", command = "FirearmAttack" })
	local b = FakeUnit({ id = "stuck_b", command = "FirearmAttack" })
	local c = FakeUnit({ id = "stuck_c" })
	b.down = true
	local it = ActiveState({ a, b }, FakeUnit({ id = "enemy", team = enemy_team }), { c })
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
	Q.EndInterrupt(it, reason)
	t.eq(LogHas("INT #1 END %(end_check_error%)"), true)
	t.eq(ui_ended, true)
	t.eq(Q.active, false)
end)

t.case("The END log line shows the Forced counts and the AP of each interrupter at the start and at the end", function()
	ResetWorld()
	local a = FakeUnit({ id = "a", ap = 10000 })
	local b = FakeUnit({ id = "b", ap = 8500 })
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	game_time = 1000
	local it = ActiveState({ a }, enemy, { b })
	Unit.CanBeControlled(a)
	Unit.CanBeControlled(b)
	IsNetPlayerTurn()
	StartCombatAction("Attack", a, 4000)
	Q.UI = { End = function() end }
	game_time = 3500
	Q.EndInterrupt(it, "end_request")
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
	Q.StopMover(it, { pos = here })
	t.eq(#enemy.combat_path, 1)
	t.eq(enemy.combat_path[1], here)
	t.eq(enemy.ActionPoints, 5000)
	t.eq(enemy.iis_stopped, "cmd")
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
	Q.StopMover(it, { pos = between })
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
	Q.StopMover(it, { pos = { x = 1, y = 0 } })
	t.eq(enemy.combat_path[1], "dest")
	t.eq(enemy.iis_stopped, nil)
end)

t.case("RunInterrupt skips a new interrupt while another one is active", function()
	ResetWorld()
	CanYield = function() return true end
	local enemy = FakeUnit({ id = "enemy", team = enemy_team })
	local it = ActiveState({ FakeUnit({ id = "a" }) }, enemy)
	Q.RunInterrupt(enemy, { mercs = { FakeUnit({ id = "b" }) } })
	CanYield = nil
	t.eq(LogHas("interrupt skipped: INT #1 is still active"), true)
	t.eq(Q.active, it)
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
