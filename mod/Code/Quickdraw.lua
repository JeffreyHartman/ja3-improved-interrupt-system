-- Quickdraw: player-controlled interrupts in the style of JA2 1.13.
-- This file holds the settings, the log, the trigger checks and the IIS counters.
-- Rules.lua has the 1.13 formulas, Control.lua runs an interrupt and UI.lua shows it.
--
-- A trigger is an entry { "quickdraw", top_merc, info, dummy } that the wrapper of
-- Unit:CheckProvokeOpportunityAttacks adds to the vanilla interrupt list. The game then calls
-- Unit:ProvokeOpportunityAttacksFromList in the enemy's command thread, and the AI turn waits.

Quickdraw = Quickdraw or {}
Quickdraw.version = "0.7"
local R = QuickdrawRules

Quickdraw.Config = {
	enabled = true,
	system = "IIS",              -- "IIS" (the 1.13 default) or "Classic"
	collective = true,           -- IIS collective interrupts, ALLOW_COLLECTIVE_INTERRUPTS
	after_interrupt = "stop",    -- "stop": the enemy stays on its tile and gets back the AP of the rest of its path; "continue": it walks on
	auto_end = true,             -- end the interrupt when no interrupter has AP for one step
	auto_end_delay_ms = 1500,    -- game time after the last action before auto_end ends the interrupt
	require_attack_ap = true,    -- a winner needs AP for its default attack (TeamTurns.cpp:877)
	reaction_time = 25,          -- BASIC_REACTION_TIME_LENGTH
	basic_pct = 60,              -- BASIC_PERCENTAGE_APS_REGISTERED
	log_checks = false,          -- also log each watcher of each check
	heartbeat_ms = 5000,         -- log interval while an interrupt waits for the player
	stuck_ms = 10000,            -- dump the merc's thread stack when one action runs longer than this
}

-- The game loads mod options before this code runs.
local function ApplyOptions()
	local o = rawget(_G, "CurrentModOptions") or {}
	local cfg = Quickdraw.Config
	cfg.enabled = o.Enabled ~= false
	cfg.system = o.System == "Classic" and "Classic" or "IIS"
	cfg.collective = o.Collective ~= false
	cfg.after_interrupt = o.AfterInterrupt == "Continue" and "continue" or "stop"
	cfg.auto_end = o.AutoEnd ~= false
	cfg.require_attack_ap = o.RequireAttackAP ~= false
	cfg.reaction_time = tonumber(o.ReactionTime) or 25
	cfg.basic_pct = tonumber(o.BasicPercent) or 60
	cfg.log_checks = o.VerboseLog == true
end
ApplyOptions()

-- Rules settings for the current options.
function Quickdraw.RulesConfig()
	local cfg = Quickdraw.Config
	local rc = {}
	for k, v in pairs(R.Defaults) do
		rc[k] = v
	end
	rc.reaction_time = cfg.reaction_time
	rc.basic_pct_registered = cfg.basic_pct
	return rc
end

------------------------------------------------------------------------------------------------
-- Log

-- The game buffers its log file during play, so each line flushes it.
local function Log(fmt, ...)
	local ok, line = pcall(string.format, fmt, ...)
	print("[Quickdraw] " .. (ok and line or ("log format error: " .. tostring(line) .. " in " .. tostring(fmt))))
	local flush = rawget(_G, "FlushLogFile")
	if flush then
		flush()
	end
end
Quickdraw.Log = Log

local function Verbose(fmt, ...)
	if Quickdraw.Config.log_checks then
		Log(fmt, ...)
	end
end
Quickdraw.Verbose = Verbose

local function Name(unit)
	if not unit then return "nil" end
	return string.format("%s#%s", tostring(unit.session_id or unit.unitdatadef_id or unit.class), tostring(unit.handle))
end

-- Raw AP as displayed AP with one decimal. JA3's "/" truncates, so "10.5" would print as "10".
local function FormatAP(raw)
	raw = raw or 0
	local scale = const.Scale.AP
	local sign = raw < 0 and "-" or ""
	raw = math.abs(raw)
	local whole = R.idiv(raw, scale)
	local tenth = R.idiv((raw - whole * scale) * 10, scale)
	return tenth == 0 and (sign .. whole) or string.format("%s%d.%d", sign, whole, tenth)
end
Quickdraw.FormatAP = FormatAP

local function AP(unit)
	return FormatAP(unit.ActionPoints)
end

local function Pos(obj)
	return IsValid(obj) and tostring(obj:GetVisualPos()) or "?"
end
Quickdraw.Name, Quickdraw.AP, Quickdraw.Pos = Name, AP, Pos

local function NameList(units)
	local parts = {}
	for i, u in ipairs(units or {}) do
		parts[i] = Name(u)
	end
	return #parts > 0 and table.concat(parts, ", ") or "(none)"
end
Quickdraw.NameList = NameList

local function Count(tbl, key)
	tbl[key] = (tbl[key] or 0) + 1
end

local function CountsToString(tbl)
	local keys = {}
	for k in pairs(tbl) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	local parts = {}
	for i, k in ipairs(keys) do
		parts[i] = string.format("%s=%d", k, tbl[k])
	end
	return #parts > 0 and table.concat(parts, ", ") or "(none)"
end
Quickdraw.CountsToString = CountsToString

------------------------------------------------------------------------------------------------
-- Engine reads. Each function is one place that touches the JA3 API; tests/test_engine.lua
-- replaces this table with fakes.

local E = {}
Quickdraw.E = E

function E.PlayerUnits()
	return GetAllPlayerUnitsOnMap() or {}
end

function E.CanControlTeam(unit)
	return unit.team and unit.team.control == "UI"
end

function E.IsAITurnEnemy(unit)
	local team = unit.team
	return team and team.control ~= "UI" and team.side ~= "neutral" and g_Teams[g_CurrentTeam] == team
end

function E.APRaw(unit)
	return unit.ActionPoints or 0
end

function E.MaxAPRaw(unit)
	return unit:GetMaxActionPoints()
end

function E.StepRaw(stance)
	local costs = const["Action Point Costs"]
	local mod = stance == "Crouch" and costs.CrouchModifier or stance == "Prone" and costs.ProneModifier or 0
	return MulDivRound(costs.Walk, 100 + mod, 100)
end

function E.WalkRaw()
	return const["Action Point Costs"].Walk
end

function E.AttackCostRaw(unit)
	local ok, cost = pcall(function()
		local action = unit:GetDefaultAttackAction()
		return action and action:GetAPCost(unit) or -1
	end)
	return ok and cost or -1
end

function E.Status(unit, id)
	return unit:HasStatusEffect(id) and true or false
end

function E.Perk(unit, id)
	return HasPerk(unit, id) and true or false
end

function E.SeesNow(observer, other)
	return HasVisibilityTo(observer, other) and true or false
end

function E.VisibleEnemyCount(unit)
	local n = 0
	for _, other in ipairs(g_Visibility and g_Visibility[unit] or empty_table) do
		if IsKindOf(other, "Unit") and not other:IsDead() and unit:IsOnEnemySide(other) and HasVisibilityTo(unit, other) then
			n = n + 1
		end
	end
	return n
end

function E.DistTiles(unit, pos)
	return R.idiv(unit:GetDist(pos), const.SlabSizeX)
end

function E.Dist(unit, pos)
	return unit:GetDist(pos)
end

function E.MaxSightTiles()
	return const.Combat.AwareSightRange
end

-- Sight radius of observer toward other at step_pos, and whether the night penalty applies.
function E.Sight(observer, other, step_pos)
	local sight, _, dark = observer:GetSightRadius(other, nil, step_pos)
	return sight, dark and true or false
end

function E.WatcherSeesStep(w, mover, dummy)
	local pos = dummy.pos
	if not IsCloser(w, pos, GetMaxSightRadius() + 1) then
		return false
	end
	local sight = w:GetSightRadius(mover, nil, pos)
	local target = stance_pos_pack(pos, StancesList[dummy.stance or mover.stance])
	local los = CheckLOS(target, w, sight)
	return los and los ~= 0 or false
end

function E.MoverSeesWatcher(mover, dummy, w)
	local pos = dummy and dummy.pos or mover:GetPos()
	local sight = mover:GetSightRadius(w)
	if not IsCloser(w, pos, sight + 1) then
		return false
	end
	local los = CheckLOS(w, pos, sight, dummy and dummy.stance or mover.stance)
	return los and los ~= 0 or false
end

function E.TeamSees(team, unit)
	return team and HasVisibilityTo(team, unit) and true or false
end

function E.IsCurrentPos(mover, pos)
	return pos and mover:GetPos():Equal2D(pos)
end

function E.Key(unit)
	return unit.session_id or unit.handle
end

function E.InCommandThread(unit)
	return CurrentThread() == unit.command_thread
end

function E.Rand(max)
	return InteractionRand(max, "Quickdraw")
end

------------------------------------------------------------------------------------------------
-- What each unit saw. seen_turn decays at the start of the watcher's own turn, like SEEN_THIS_TURN
-- in 1.13 (TeamTurns.cpp:576). seen_ever is gbSeenOpponents. Keys are session ids.

GameVar("gv_Quickdraw", function() return { seen_turn = {}, seen_ever = {} } end)

-- The mod environment refuses new globals after loading, so a missing GameVar falls back to a
-- table that is not saved.
local fallback_memory = { seen_turn = {}, seen_ever = {} }

local function Memory()
	local mem = rawget(_G, "gv_Quickdraw")
	if type(mem) ~= "table" then
		mem = fallback_memory
	end
	mem.seen_turn = mem.seen_turn or {}
	mem.seen_ever = mem.seen_ever or {}
	return mem
end
Quickdraw.Memory = Memory

local function Mark(tbl, a, b)
	local ka, kb = E.Key(a), E.Key(b)
	if not ka or not kb then return end
	local row = tbl[ka]
	if not row then
		row = {}
		tbl[ka] = row
	end
	row[kb] = true
end
Quickdraw.Mark = Mark

local function Saw(tbl, a, b)
	local row = tbl[E.Key(a)]
	return row and row[E.Key(b)] or false
end
Quickdraw.Saw = Saw

function Quickdraw.RecordVisibility()
	local mem = Memory()
	for _, u in ipairs(g_Units or empty_table) do
		if IsValid(u) and not u:IsDead() and u.team then
			local player = E.CanControlTeam(u)
			for _, other in ipairs(g_Visibility and g_Visibility[u] or empty_table) do
				if IsKindOf(other, "Unit") and u:IsOnEnemySide(other) and HasVisibilityTo(u, other) then
					Mark(mem.seen_ever, u, other)
					if player then
						Mark(mem.seen_turn, u, other)
					end
				end
			end
		end
	end
end

function OnMsg.CombatComputedVisibility()
	local ok, err = pcall(Quickdraw.RecordVisibility)
	if not ok then
		Log("RecordVisibility failed: %s", tostring(err))
	end
end

------------------------------------------------------------------------------------------------
-- IIS counters: counters[watcher][mover] holds the registered AP (ubInterruptCounter).
-- A watcher's counters reset at the start of its own turn and when its interrupt fires.

Quickdraw.counters = Quickdraw.counters or {}
Quickdraw.plans = Quickdraw.plans or {}

local function Counter(w, m)
	local row = Quickdraw.counters[w]
	return row and row[m] or 0
end
Quickdraw.Counter = Counter

local function AddCounter(w, m, n)
	if n == 0 then return end
	local row = Quickdraw.counters[w]
	if not row then
		row = {}
		Quickdraw.counters[w] = row
	end
	row[m] = math.min(255, math.max(0, (row[m] or 0) + n)) -- UINT8 in 1.13
end
Quickdraw.AddCounter = AddCounter

local function ResetCounter(w, m)
	local row = Quickdraw.counters[w]
	if row then
		row[m] = nil
	end
end
Quickdraw.ResetCounter = ResetCounter

function Quickdraw.ResetCountersOf(units)
	for _, u in ipairs(units or {}) do
		Quickdraw.counters[u] = nil
	end
end

------------------------------------------------------------------------------------------------
-- Soldier tables for Rules.lua

local function Shock(u)
	return E.Status(u, "Suppressed") and 1 or 0
end

function Quickdraw.ClassicSoldier(u, opts)
	return {
		level = u:GetLevel(),
		agility = u:GetProperty("Agility"),
		shock = Shock(u),
		visible_enemies = E.VisibleEnemyCount(u),
		stance = opts.stance or u.stance,
		running = opts.running,
		bandaging = E.Status(u, "BandageInCombat") or E.Status(u, "BeingBandaged"),
		night_ops = E.Perk(u, "NightOps"),
		saw_before = opts.saw_before,
		team_knows = opts.team_knows,
		is_player = opts.is_player,
		is_enemy = not opts.is_player,
	}
end

function Quickdraw.IISWatcher(u)
	local life, life_max = u.HitPoints or 100, u.MaxHitPoints or 100
	local breath = 100
	if E.Status(u, "Exhausted") then
		breath = 0
	elseif E.Status(u, "Tired") then
		breath = 50
	end
	return {
		agility = u:GetProperty("Agility"),
		ap = E.APRaw(u),
		max_ap = E.MaxAPRaw(u),
		life = life,
		life_max = life_max,
		bleeding = E.Status(u, "Bleeding") and (life_max - life) or 0,
		level = u:GetLevel(),
		breath = breath,
		gassed = E.Status(u, "Choking"),
		getting_aid = E.Status(u, "BeingBandaged"),
		shock = Shock(u),
	}
end

-- Percent of the mover's AP that w registers when it sees the mover at pos (Points.cpp:972).
function Quickdraw.RegisteredPercent(w, mover, pos)
	local sight, dark = E.Sight(w, mover, pos)
	return R.IISRegisteredPercent(
		{ level = w:GetLevel(), night_ops = w:HasNightVision() },
		{ distance = E.Dist(w, pos), sight = sight, dark = dark, mover_stealthy = E.Perk(mover, "Stealthy") },
		Quickdraw.RulesConfig())
end

------------------------------------------------------------------------------------------------
-- Who can interrupt

-- Statuses that take a merc out of player control.
local blocking_status = { "Unconscious", "Downed", "Panicked", "Berserk", "Blinded" }

-- A watcher whose AP the mover's actions can register (IIS) or who can duel (classic).
function Quickdraw.ObserverSkipReason(w, mover)
	if not IsValid(w) or w:IsIncapacitated() then return "incapacitated" end
	if not E.CanControlTeam(w) then return "not player controlled" end
	if not w:IsOnEnemySide(mover) then return "not enemies" end
end

-- A watcher that can win an interrupt now.
function Quickdraw.WinSkipReason(w, system)
	for _, id in ipairs(blocking_status) do
		if E.Status(w, id) then return id end
	end
	local ap = E.APRaw(w)
	local min = R.MinAP(system, E.MaxAPRaw(w), E.WalkRaw(), Quickdraw.RulesConfig())
	if ap < min then return "AP below minimum" end
	if Quickdraw.Config.require_attack_ap then
		local cost = E.AttackCostRaw(w)
		if cost < 0 or ap < cost then return "AP below attack cost" end
	end
	if system == "Classic" then
		if E.Status(w, "Choking") then return "gassed" end
		if E.Status(w, "Suppressed") then return "under fire" end
	end
end

function Quickdraw.MoverSkipReason(mover, trigger_type, visible_only, return_result)
	local cfg = Quickdraw.Config
	if not cfg.enabled then return "disabled" end
	if trigger_type ~= "move" and trigger_type ~= "attack reaction" then return "trigger " .. tostring(trigger_type) end
	-- "any" and "all" come from path previews and trap scans, not from a real action.
	if return_result then return "preview" end
	if visible_only then return "visible_only" end
	if not g_Combat or g_StartingCombat then return "not in combat" end
	if not g_AIExecutionController then return "no AI turn" end
	if g_AIExecutionController.reposition or mover.command == "Reposition" then return "reposition phase" end
	if IsSetpiecePlaying() then return "setpiece" end
	if Quickdraw.active then return "interrupt active" end
	if not E.IsAITurnEnemy(mover) then return "mover is not on the AI team that has the turn" end
	if mover.opportunity_attack then return "mover is in an opportunity attack" end
end

------------------------------------------------------------------------------------------------
-- Trigger checks

Quickdraw.check_count = Quickdraw.check_count or 0

function Quickdraw.ResetTurnStats()
	Quickdraw.turn_stats = { calls = 0, mover_skips = {}, watcher_skips = {}, checked = 0, triggers = 0, enemy_actions = {}, registered = 0 }
end
Quickdraw.ResetTurnStats()

-- The first dummy is the mover's own tile at the start of a move. Later checks of the same move
-- start at the next step.
local function FirstStep(mover, dummies)
	return E.IsCurrentPos(mover, dummies[1] and dummies[1].pos) and 2 or 1
end

local function IsRunning(mover, dummies, first)
	return mover.stance == "Standing" and #dummies - first + 1 >= 5
end

-- Classic: each watcher that did not see the mover this turn duels at its first step with line of sight.
function Quickdraw.FindClassicMoveTrigger(mover, dummies, n)
	local mem = Memory()
	local stats = Quickdraw.turn_stats
	local first = FirstStep(mover, dummies)
	local running = IsRunning(mover, dummies, first)
	local rows = {}
	local start_target = { pos = mover:GetPos(), stance = mover.stance }
	for _, w in ipairs(E.PlayerUnits()) do
		local skip = Quickdraw.ObserverSkipReason(w, mover) or Quickdraw.WinSkipReason(w, "Classic")
		if not skip and (E.SeesNow(w, mover) or Saw(mem.seen_turn, w, mover)) then
			skip = "saw mover this turn"
		end
		if not skip and E.WatcherSeesStep(w, mover, start_target) then
			skip = "has LOS at the mover's tile"
		end
		if skip then
			Count(stats.watcher_skips, skip)
			Verbose("  check #%d watcher %s skipped: %s", n, Name(w), skip)
		else
			stats.checked = stats.checked + 1
			local row = { unit = w }
			for i = first, #dummies do
				if E.WatcherSeesStep(w, mover, dummies[i]) then
					row.first_los = i
					break
				end
			end
			if row.first_los then
				local dummy = dummies[row.first_los]
				local d = E.DistTiles(w, dummy.pos)
				local _, w_dark = E.Sight(w, mover, dummy.pos)
				local _, m_dark = E.Sight(mover, w)
				local max_visible = E.MaxSightTiles()
				local wp = R.ClassicPoints(
					Quickdraw.ClassicSoldier(w, { is_player = true, saw_before = Saw(mem.seen_ever, w, mover) }),
					{ passive = true, distance = d, max_visible = max_visible, dark = w_dark, other_saw_me = Saw(mem.seen_ever, mover, w) })
				local mp = R.ClassicPoints(
					Quickdraw.ClassicSoldier(mover, { stance = dummy.stance or mover.stance, running = running,
						saw_before = Saw(mem.seen_ever, mover, w), team_knows = E.TeamSees(mover.team, w) }),
					{ passive = false, distance = d, max_visible = max_visible, dark = m_dark, other_saw_me = Saw(mem.seen_ever, w, mover) })
				local m_sees_w = E.MoverSeesWatcher(mover, dummy, w)
				row.won, row.margin, row.how = R.ClassicDuel(wp, mp, true, m_sees_w)
				row.detail = string.format("step %d dist %d: %d vs %d%s -> %s (%s)", row.first_los, d, wp, mp,
					m_sees_w and "" or ", mover does not see it", row.won and "WIN" or "lose", row.how)
			else
				row.detail = "no LOS on the path"
			end
			Verbose("  check #%d watcher %s: %s", n, Name(w), row.detail)
			rows[#rows + 1] = row
		end
	end
	local idx, winners = R.FindClassicTrigger(rows)
	return idx, winners, rows
end

-- IIS: each watcher registers part of the AP of each step on which it sees the mover. It wins at
-- the first step where its counter reaches its reaction time.
function Quickdraw.FindIISMoveTrigger(mover, dummies, n)
	local stats = Quickdraw.turn_stats
	local rc = Quickdraw.RulesConfig()
	local first = FirstStep(mover, dummies)
	local mover_max = E.MaxAPRaw(mover)
	local rows = {}
	for _, w in ipairs(E.PlayerUnits()) do
		local skip = Quickdraw.ObserverSkipReason(w, mover)
		if skip then
			Count(stats.watcher_skips, skip)
			Verbose("  check #%d watcher %s skipped: %s", n, Name(w), skip)
		else
			local win_skip = Quickdraw.WinSkipReason(w, "IIS")
			local row = { unit = w, counter = Counter(w, mover), los = {}, adds = {}, win_skip = win_skip }
			row.rt = win_skip and math.huge or R.IISReactionTime(Quickdraw.IISWatcher(w), rc)
			for i = first, #dummies do
				local dummy = dummies[i]
				if E.WatcherSeesStep(w, mover, dummy) then
					row.los[i] = true
					local pct = Quickdraw.RegisteredPercent(w, mover, dummy.pos)
					local ap100 = R.ToScale100(E.StepRaw(dummy.stance or mover.stance), mover_max)
					row.adds[i] = R.IISRegisteredAP(ap100, pct)
				end
			end
			stats.checked = stats.checked + 1
			rows[#rows + 1] = row
		end
	end
	local idx, winners = R.FindIISTrigger(rows, first, #dummies)
	for _, row in ipairs(rows) do
		local steps = 0
		for _ in pairs(row.los) do
			steps = steps + 1
		end
		row.detail = string.format("counter %d + %d over %d seen steps, reaction time %s%s", row.counter,
			row.cum[#dummies] or 0, steps, row.win_skip and "-" or tostring(row.rt), row.win_skip and (" (cannot win: " .. row.win_skip .. ")") or "")
		Verbose("  check #%d watcher %s: %s", n, Name(row.unit), row.detail)
	end
	-- CombatGoto removes passed steps from its dummy list, so the plan keeps a copy.
	local steps = {}
	for i, d in ipairs(dummies) do
		steps[i] = d
	end
	local plan = { mover = mover, dummies = steps, first = first, rows = rows, done = first - 1 }
	return idx, winners, rows, plan
end

-- Adds the registered AP of steps first..upto of a plan to the counters. A plan commits each
-- step once, so the interrupt and the end of the move can both call it.
function Quickdraw.CommitPlan(plan, upto, why)
	if not plan or upto <= plan.done then return end
	local parts = {}
	for _, row in ipairs(plan.rows) do
		local delta = (row.cum[upto] or 0) - (row.cum[plan.done] or 0)
		if delta > 0 then
			AddCounter(row.unit, plan.mover, delta)
			parts[#parts + 1] = string.format("%s+%d=%d", Name(row.unit), delta, Counter(row.unit, plan.mover))
		end
	end
	plan.done = upto
	if #parts > 0 then
		Log("IIS commit (%s) mover=%s steps through %d: %s", why, Name(plan.mover), upto, table.concat(parts, " "))
	end
end

-- Classic after an attack: a target that did not see the attacker duels it (NoticeUnseenAttacker,
-- opplist.cpp:7386). IIS after an attack: every watcher with a full counter that sees the attacker
-- or was attacked wins (AFTERSHOT_INTERRUPT).
function Quickdraw.FindAttackTrigger(mover, n)
	local system = Quickdraw.Config.system
	local stats = Quickdraw.turn_stats
	local targets = Quickdraw.attack_targets[mover] or {}
	local rows = {}
	local mem = Memory()
	for _, w in ipairs(E.PlayerUnits()) do
		local skip = Quickdraw.ObserverSkipReason(w, mover) or Quickdraw.WinSkipReason(w, system)
		local targeted = targets[w] or false
		if skip then
			Count(stats.watcher_skips, skip)
			Verbose("  check #%d watcher %s skipped: %s", n, Name(w), skip)
		elseif system == "Classic" then
			if not targeted then
				Verbose("  check #%d watcher %s: not attacked", n, Name(w))
			elseif E.SeesNow(w, mover) then
				Verbose("  check #%d watcher %s: saw the attacker", n, Name(w))
			else
				stats.checked = stats.checked + 1
				local d = E.DistTiles(w, mover:GetPos())
				local max_visible = E.MaxSightTiles()
				local wp = R.ClassicPoints(
					Quickdraw.ClassicSoldier(w, { is_player = true, saw_before = Saw(mem.seen_ever, w, mover) }),
					{ passive = true, distance = d, max_visible = max_visible, other_saw_me = true })
				local mp = R.ClassicPoints(
					Quickdraw.ClassicSoldier(mover, { saw_before = true, team_knows = true }),
					{ passive = false, distance = d, max_visible = max_visible, other_saw_me = Saw(mem.seen_ever, w, mover) })
				local won, margin, how = R.ClassicDuel(wp, mp, true, true)
				local row = { unit = w, won = won, margin = margin, how = how,
					detail = string.format("unseen attacker, dist %d: %d vs %d -> %s", d, wp, mp, won and "WIN" or "lose") }
				Verbose("  check #%d watcher %s: %s", n, Name(w), row.detail)
				rows[#rows + 1] = row
			end
		else
			stats.checked = stats.checked + 1
			local row = { unit = w, counter = Counter(w, mover), sees = E.SeesNow(w, mover) or targeted }
			row.rt = R.IISReactionTime(Quickdraw.IISWatcher(w), Quickdraw.RulesConfig())
			row.detail = string.format("counter %d, reaction time %d, %s", row.counter, row.rt,
				row.sees and (targeted and "attacked" or "sees attacker") or "does not see attacker")
			Verbose("  check #%d watcher %s: %s", n, Name(w), row.detail)
			rows[#rows + 1] = row
		end
	end
	local winners
	if system == "Classic" then
		winners = {}
		for _, row in ipairs(rows) do
			if row.won then
				winners[#winners + 1] = row
			end
		end
		R.OrderWinners(winners)
	else
		winners = R.FindIISNow(rows)
	end
	return winners, rows
end

local function WinnerList(winners)
	local parts = {}
	for i, row in ipairs(winners) do
		parts[i] = string.format("%s ap=%s [%s]", Name(row.unit), AP(row.unit), row.detail or "")
	end
	return table.concat(parts, "; ")
end

-- Adds a "quickdraw" entry to the vanilla interrupt list when a trigger is found.
function Quickdraw.AddTrigger(mover, trigger_type, dummies, visible_only, return_result, interrupts, provoke_idx)
	local stats = Quickdraw.turn_stats
	stats.calls = stats.calls + 1
	local skip = Quickdraw.MoverSkipReason(mover, trigger_type, visible_only, return_result)
	if not skip and trigger_type == "move" and #(dummies or {}) < 2 then
		skip = "path shorter than 2 steps"
	end
	if skip then
		Count(stats.mover_skips, skip)
		return interrupts, provoke_idx
	end

	Quickdraw.check_count = Quickdraw.check_count + 1
	local n = Quickdraw.check_count
	local system = Quickdraw.Config.system
	local real = E.InCommandThread(mover)
	Verbose("check #%d %s %s mover=%s cmd=%s steps=%d real=%s vanilla_idx=%s", n, system, trigger_type, Name(mover),
		tostring(mover.command), #(dummies or {}), tostring(real), tostring(provoke_idx))

	local idx, winners, rows, plan
	if trigger_type == "move" then
		if system == "Classic" then
			idx, winners, rows = Quickdraw.FindClassicMoveTrigger(mover, dummies, n)
		else
			idx, winners, rows, plan = Quickdraw.FindIISMoveTrigger(mover, dummies, n)
			if real then
				Quickdraw.plans[mover] = plan
			end
		end
	else
		winners, rows = Quickdraw.FindAttackTrigger(mover, n)
		idx = #winners > 0 and #dummies or nil
	end
	if not idx then
		return interrupts, provoke_idx
	end

	stats.triggers = stats.triggers + 1
	local mercs = {}
	for i, row in ipairs(winners) do
		mercs[i] = row.unit
	end
	local where = trigger_type == "move"
		and string.format("step %d/%d pos=%s", idx, #dummies, tostring(dummies[idx].pos))
		or "after its attack"
	local info = { kind = trigger_type == "move" and "move" or "attack", system = system, mercs = mercs,
		winners = winners, rows = rows, plan = plan, step = idx, check = n, where = where }
	local entry = { "quickdraw", mercs[1], info, dummies[idx] }

	if interrupts and provoke_idx < idx then
		Log("check #%d %s mover=%s: %d winner(s) at %s, but a vanilla interrupt (%s) comes first at step %d. Ours waits for the next check.",
			n, system, Name(mover), #mercs, where, tostring(interrupts[1][1]), provoke_idx)
		return interrupts, provoke_idx
	end
	if real then
		Log("check #%d %s TRIGGER mover=%s at %s: %s", n, system, Name(mover), where, WinnerList(winners))
	else
		-- AIExecutionController:SelectPlayingUnits runs the same check to group its units.
		Log("check #%d %s trigger in an AI planning check, mover=%s at %s: %s", n, system, Name(mover), where, NameList(mercs))
	end
	if interrupts and provoke_idx == idx then
		table.insert(interrupts, 1, entry)
		Log("check #%d   same step as vanilla %s, ours runs first", n, tostring(interrupts[2][1]))
		return interrupts, provoke_idx
	end
	if interrupts then
		Log("check #%d   vanilla interrupt %s at later step %d is dropped for now. The game checks again after ours.", n, tostring(interrupts[1][1]), provoke_idx)
	end
	return { entry }, idx
end

local orig_CheckProvokeOpportunityAttacks = Unit.CheckProvokeOpportunityAttacks
function Unit:CheckProvokeOpportunityAttacks(action, trigger_type, target_dummies_all, visible_only, return_result, ...)
	-- After an interrupt with after_interrupt == "stop", the mover walks no further, so its
	-- remaining path must not get new interrupts (Control.lua, StopMover). The flag holds the
	-- command thread of that move, so it means nothing once the command changes.
	if self.qd_stopped and self.qd_stopped == self.command_thread and trigger_type == "move" and not return_result then
		return
	end
	local interrupts, provoke_idx = orig_CheckProvokeOpportunityAttacks(self, action, trigger_type, target_dummies_all, visible_only, return_result, ...)
	-- This runs in the enemy's command thread. An error here would end the enemy's command.
	local ok, a, b = pcall(Quickdraw.AddTrigger, self, trigger_type, target_dummies_all, visible_only, return_result, interrupts, provoke_idx)
	if not ok then
		Log("check failed for %s: %s", Name(self), tostring(a))
		return interrupts, provoke_idx
	end
	return a, b
end

local orig_ProvokeOpportunityAttacksFromList = Unit.ProvokeOpportunityAttacksFromList
function Unit:ProvokeOpportunityAttacksFromList(list, ...)
	local ours = false
	for _, data in ipairs(list or empty_table) do
		if data[1] == "quickdraw" then
			ours = true
			Quickdraw.RunInterrupt(self, data[3], data[4])
		end
	end
	-- Vanilla ignores the "quickdraw" entry type, adds it to passed_interrupts and ends the interrupt.
	local result = orig_ProvokeOpportunityAttacksFromList(self, list, ...)
	if ours then
		Log("provoke list done: mover=%s interrupted=%s stopped=%s pos=%s ap=%s", Name(self), tostring(self.interrupted),
			tostring(not not self.qd_stopped), Pos(self), AP(self))
	end
	return result
end

------------------------------------------------------------------------------------------------
-- Events

Quickdraw.attack_targets = Quickdraw.attack_targets or {}

-- IIS: a seen enemy's action registers part of its AP with each watcher (Points.cpp:947).
-- Moves register per step in the move check instead.
function Quickdraw.RegisterAction(unit, action_id, ap)
	local mover_max = E.MaxAPRaw(unit)
	local ap100 = R.ToScale100(ap, mover_max)
	local parts = {}
	for _, w in ipairs(E.PlayerUnits()) do
		if not Quickdraw.ObserverSkipReason(w, unit) and E.SeesNow(w, unit) then
			local pct = Quickdraw.RegisteredPercent(w, unit, unit:GetPos())
			local add = R.IISRegisteredAP(ap100, pct)
			AddCounter(w, unit, add)
			parts[#parts + 1] = string.format("%s+%d(%d%%)=%d", Name(w), add, pct, Counter(w, unit))
		end
	end
	if #parts > 0 then
		Quickdraw.turn_stats.registered = Quickdraw.turn_stats.registered + 1
		Log("IIS register %s by %s cost=%d/100: %s", tostring(action_id), Name(unit), ap100, table.concat(parts, " "))
	end
end

local function StatusList(unit)
	local names = {}
	for _, effect in ipairs(unit.StatusEffects or empty_table) do
		names[#names + 1] = tostring(effect.class)
	end
	return #names > 0 and table.concat(names, ",") or "(none)"
end

function OnMsg.RunCombatAction(action_id, unit, ap)
	if not g_Combat or not IsValid(unit) or not unit.team or E.CanControlTeam(unit) then return end
	Quickdraw.attack_targets[unit] = nil
	Count(Quickdraw.turn_stats.enemy_actions, unit)
	local behavior = unit.ai_context and unit.ai_context.behavior
	Log("enemy action %s unit=%s cost=%s ap_left=%s pos=%s behavior=%s status=%s",
		tostring(action_id), Name(unit), FormatAP(ap), AP(unit), Pos(unit),
		tostring(behavior and (behavior.id or behavior.class)), StatusList(unit))
	if Quickdraw.Config.enabled and Quickdraw.Config.system == "IIS" and action_id ~= "Move" and (ap or 0) > 0
		and g_AIExecutionController and E.IsAITurnEnemy(unit) then
		local ok, err = pcall(Quickdraw.RegisterAction, unit, action_id, ap)
		if not ok then
			Log("RegisterAction failed: %s", tostring(err))
		end
	end
end

function OnMsg.Attack(action, results, attack_args, combat_starting, attacker, target)
	if not g_Combat or not IsKindOf(attacker, "Unit") or not attacker.team or E.CanControlTeam(attacker) then return end
	local set = Quickdraw.attack_targets[attacker] or {}
	Quickdraw.attack_targets[attacker] = set
	if IsKindOf(target, "Unit") then
		set[target] = true
	end
	for _, obj in ipairs(results and results.hit_objs or empty_table) do
		if IsKindOf(obj, "Unit") then
			set[obj] = true
		end
	end
end

-- Finds the last step of a plan that the mover reached.
local function ReachedStep(plan, unit)
	local pos = unit:GetPos()
	for i = #plan.dummies, plan.first, -1 do
		local d = plan.dummies[i]
		if d.pos and pos:Equal2D(d.pos) then
			return i
		end
	end
end

function OnMsg.UnitMovementDone(unit)
	local plan = Quickdraw.plans[unit]
	if plan then
		Quickdraw.plans[unit] = nil
		local ok, err = pcall(function()
			local reached = ReachedStep(plan, unit)
			if reached then
				Quickdraw.CommitPlan(plan, reached, "move done")
			else
				Log("IIS plan of %s: the end tile %s is not on the planned path. Steps after %d not counted.", Name(unit), Pos(unit), plan.done)
			end
		end)
		if not ok then
			Log("CommitPlan failed: %s", tostring(err))
		end
	end
	if unit.qd_stopped then
		Quickdraw.OnStoppedMoverDone(unit)
	end
end

function Quickdraw.HookStatus()
	return string.format("check_hook=%s provoke_hook=%s",
		Unit.CheckProvokeOpportunityAttacks == Quickdraw.check_hook and "ours" or "REPLACED",
		Unit.ProvokeOpportunityAttacksFromList == Quickdraw.provoke_hook and "ours" or "REPLACED")
end

local function ResetCombatState(why)
	Quickdraw.counters = {}
	Quickdraw.plans = {}
	Quickdraw.attack_targets = {}
	local mem = Memory()
	mem.seen_turn = {}
	mem.seen_ever = {}
	Log("combat state reset (%s)", why)
end

function OnMsg.CombatStart()
	ResetCombatState("CombatStart")
	Log("CombatStart system=%s %s", Quickdraw.Config.system, Quickdraw.HookStatus())
end

function OnMsg.CombatEnd()
	Log("CombatEnd: checks=%d interrupts=%d", Quickdraw.check_count, Quickdraw.interrupt_count or 0)
	ResetCombatState("CombatEnd")
end

function OnMsg.LoadGame()
	Quickdraw.counters = {}
	Quickdraw.plans = {}
	Log("LoadGame in_combat=%s system=%s %s", tostring(not not g_Combat), Quickdraw.Config.system, Quickdraw.HookStatus())
end

function OnMsg.TurnStart(team_idx)
	Quickdraw.ResetTurnStats()
	local team = g_Teams and g_Teams[team_idx]
	if team and team.control == "UI" then
		-- A soldier's IIS counters and SEEN_THIS_TURN marks decay at the start of its own turn.
		Quickdraw.ResetCountersOf(team.units)
		local mem = Memory()
		for _, u in ipairs(team.units or empty_table) do
			local k = E.Key(u)
			if k then
				mem.seen_turn[k] = nil
			end
		end
	end
	Log("TurnStart team=%s side=%s control=%s system=%s %s", tostring(team_idx), tostring(team and team.side),
		tostring(team and team.control), Quickdraw.Config.system, Quickdraw.HookStatus())
end

function OnMsg.TurnEnded(team_idx)
	local stats = Quickdraw.turn_stats
	Log("TurnEnded team=%s: hook calls=%d, triggers=%d, watchers checked=%d, IIS registrations=%d", tostring(team_idx),
		stats.calls, stats.triggers, stats.checked, stats.registered)
	Log("  mover skips: %s", CountsToString(stats.mover_skips))
	Log("  watcher skips: %s", CountsToString(stats.watcher_skips))
	local team = g_Teams and g_Teams[team_idx]
	if team and team.control ~= "UI" then
		local parts = {}
		for _, u in ipairs(team.units or empty_table) do
			if IsValid(u) and not u:IsDead() then
				parts[#parts + 1] = string.format("%s=%d", Name(u), stats.enemy_actions[u] or 0)
			end
		end
		Log("  actions per living unit: %s", #parts > 0 and table.concat(parts, ", ") or "(none)")
		local rows = {}
		for w, row in pairs(Quickdraw.counters) do
			for m, c in pairs(row) do
				rows[#rows + 1] = string.format("%s<-%s=%d", Name(w), Name(m), c)
			end
		end
		table.sort(rows)
		Log("  IIS counters at turn end: %s", #rows > 0 and table.concat(rows, " ") or "(none)")
	end
end

function OnMsg.ApplyModOptions(mod_id)
	if mod_id ~= rawget(_G, "CurrentModId") then return end
	ApplyOptions()
	Quickdraw.LogConfig("mod options applied")
end

function Quickdraw.LogConfig(why)
	local c = Quickdraw.Config
	Log("%s: enabled=%s system=%s collective=%s after_interrupt=%s auto_end=%s require_attack_ap=%s reaction_time=%s basic_pct=%s verbose=%s",
		why, tostring(c.enabled), c.system, tostring(c.collective), c.after_interrupt, tostring(c.auto_end),
		tostring(c.require_attack_ap), tostring(c.reaction_time), tostring(c.basic_pct), tostring(c.log_checks))
end

Quickdraw.check_hook = Unit.CheckProvokeOpportunityAttacks
Quickdraw.provoke_hook = Unit.ProvokeOpportunityAttacksFromList
Quickdraw.LogConfig("loaded " .. Quickdraw.version)
