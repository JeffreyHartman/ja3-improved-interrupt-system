-- JA2 1.13 interrupt rules as pure functions. Each function names the 1.13 code it follows
-- (paths relative to _reference/ja2_113/source at commit 81ecd82). The file makes no engine
-- calls, so tools/test.sh runs it with a plain Lua interpreter.
--
-- Soldier tables hold plain values that IIS.lua reads from JA3 units. AP costs that go into
-- the IIS formulas are 1.13 AP (To113AP).

IISRules = {}
local R = IISRules

R.Defaults = {
	min_aps_to_interrupt = 16, -- APBPConstants.ini MIN_APS_TO_INTERRUPT (classic)
	iis_min_ap = 4,            -- hard-coded in ResolvePendingInterrupt, Soldier Control.cpp:24849
	basic_pct_registered = 60, -- Ja2_Options.INI BASIC_PERCENTAGE_APS_REGISTERED
	pct_per_level = 4,         -- PERCENTAGE_APS_REGISTERED_PER_EXP_LEVEL
	reaction_time = 25,        -- BASIC_REACTION_TIME_LENGTH
	bonus_in_dark = 2,         -- Skills_Settings.INI INTERRUPTS_BONUS_IN_DARK (Night Ops)
	dark_pct_penalty = 10,     -- 1.13 subtracts the light level (7 to 12); JA3 has no light levels
	stealthy_reduction = 20,   -- REDUCED_CHANCE_TO_BE_INTERRUPTED (Stealthy)
	collective_radius = 5,     -- tiles, Soldier Control.cpp:24993
	gassed_pct = 50,           -- Weapons.h AIM_PENALTY_GASSED
	getting_aid_pct = 20,      -- Weapons.h AIM_PENALTY_GETTINGAID
}

-- 12 vanilla AP. GBO 4 changes const.Scale.AP but not raw AP (ADR 0001).
local raw_ap_for_100_113_ap = 12000

-- C integer division truncates toward zero. JA3's Lua also truncates with "/" on integers;
-- a plain Lua 5.4 returns a float, so the result goes through floor or ceil.
local function idiv(a, b)
	local q = a / b
	if q >= 0 then
		return math.floor(q)
	end
	return math.ceil(q)
end
R.idiv = idiv

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- Converts JA3 raw AP to 1.13 AP at the same rate for every unit (ADR 0001).
function R.To113AP(raw)
	return idiv(raw * 100 + idiv(raw_ap_for_100_113_ap, 2), raw_ap_for_100_113_ap)
end

-- Smallest raw AP a watcher needs to get an interrupt. Classic: MIN_APS_TO_INTERRUPT, and at
-- least one step or stance change (TeamTurns.cpp:1613, :1741). IIS: 4 1.13 AP (Soldier Control.cpp:24849).
function R.MinAP(system, step_raw, cfg)
	cfg = cfg or R.Defaults
	local ap113 = system == "Classic" and cfg.min_aps_to_interrupt or cfg.iis_min_ap
	local min = idiv(raw_ap_for_100_113_ap * ap113 + 99, 100)
	if system == "Classic" and step_raw and step_raw > min then
		min = step_raw
	end
	return min
end

-- CalcInterruptDuelPts, TeamTurns.cpp:1791. s gets the points; ctx describes the pair.
-- s:   level, agility, shock, visible_enemies, stance ("Standing", "Crouch", "Prone"), running,
--      bandaging, night_ops, saw_before (s saw the other soldier earlier), team_knows (radio),
--      is_player, is_enemy
-- ctx: passive (s's team does not have the turn), distance (tiles), other_saw_me,
--      max_visible (tiles, MaxNormalDistanceVisible), dark, heard_only
function R.ClassicPoints(s, ctx, cfg)
	cfg = cfg or R.Defaults
	local pts = idiv(20 * s.level + s.agility + 15, 30)
	local opp = s.visible_enemies or 0
	if opp > 2 then
		pts = pts - idiv(opp - 1, 2)
	end
	if ctx.heard_only then
		pts = pts - 1
	end
	pts = pts - (s.shock or 0)
	local d = ctx.distance or 0
	local max_visible = ctx.max_visible or 24
	if ctx.passive then
		pts = pts - idiv(d, 10)
	elseif not ctx.other_saw_me then
		-- MaxNormalDistanceVisible is 2 * STRAIGHT (opplist.cpp:1154).
		local straight = math.max(1, idiv(max_visible, 2))
		if s.stance == "Crouch" and d > idiv(max_visible, 2) then
			pts = pts + 1
		elseif s.stance == "Prone" and d > idiv(max_visible, 4) then
			pts = pts + idiv(d, straight)
		end
	end
	if s.running and not s.saw_before then
		pts = pts - 2
	end
	if s.bandaging then
		pts = pts - 2
	end
	if s.night_ops and ctx.dark then
		pts = pts + cfg.bonus_in_dark
	end
	if s.is_player then
		if s.saw_before then
			pts = pts + 1
		end
	elseif s.is_enemy then
		if s.saw_before or s.team_knows then
			pts = pts + 1
		end
	end
	if pts >= 100 then
		pts = 99
	end
	return pts
end

-- InterruptDuel, TeamTurns.cpp:2037. Returns won, margin, how. A tie goes to the mover.
function R.ClassicDuel(w_pts, m_pts, w_sees_m, m_sees_w)
	if w_sees_m and not m_sees_w then
		return true, math.max(w_pts, m_pts) - m_pts, "automatic"
	end
	if w_pts > m_pts then
		return true, w_pts - m_pts, "points"
	end
	return false, w_pts - m_pts, "points"
end

-- Percent of the mover's AP that the watcher registers, Points.cpp:972-1040.
-- w:   level, night_ops
-- ctx: heard_only, distance and sight (same unit), dark, mover_stealthy
function R.IISRegisteredPercent(w, ctx, cfg)
	cfg = cfg or R.Defaults
	local pct = cfg.basic_pct_registered + cfg.pct_per_level * w.level
	if ctx.heard_only then
		pct = pct - 20
	end
	local sight = math.max(ctx.sight or 1, 1)
	pct = pct - math.min(25, idiv(25 * (ctx.distance or 0), sight))
	if ctx.dark and not w.night_ops and not ctx.heard_only then
		pct = pct - cfg.dark_pct_penalty
	end
	if ctx.mover_stealthy then
		pct = pct - cfg.stealthy_reduction
	end
	-- 1.13 keeps pct in a UINT8, so a large reduction wraps around to 100%. This clamps instead.
	return clamp(pct, ctx.heard_only and 10 or 20, 100)
end

-- (UINT8)(sAPCost * pct / 100.0f + 0.5f), Points.cpp:1041. JA3's "/" truncates integers, so
-- this rounds in integers.
function R.IISRegisteredAP(ap113, pct)
	return idiv(ap113 * pct + 50, 100)
end

-- The reaction time of ResolvePendingInterrupt, Soldier Control.cpp:24868-24928.
-- w: agility, ap, max_ap (same unit), life, life_max, bleeding, level, breath (0-100),
--    gassed, getting_aid, shock
-- 1.13 reads breath from the mover, which its own comment calls a watcher penalty.
-- This mod passes the watcher's fatigue, as the comment intends.
function R.IISReactionTime(w, cfg)
	cfg = cfg or R.Defaults
	local rt = cfg.reaction_time * 10
	local ag = w.agility
	if ag >= 80 then
		rt = idiv(rt * (100 - 2 * (ag - 80)), 100)
	elseif ag > 50 then
		rt = idiv(rt * (100 + 2 * (80 - ag)), 100)
	else
		rt = idiv(rt * 8, 5)
	end
	if w.max_ap and w.max_ap > 0 then
		rt = idiv(rt * (100 + (50 - idiv(50 * w.ap, w.max_ap))), 100)
	end
	if w.life and w.life_max and w.life < w.life_max then
		local lost = w.life_max - w.life
		local inj = idiv(200 * (lost + idiv(lost - (w.bleeding or 0), 2)), w.life_max)
		rt = idiv(rt * (100 + idiv(inj * (100 - 3 * w.level), 100)), 100)
	end
	local breath = w.breath or 100
	if breath < 100 then
		rt = idiv(rt * (100 + idiv(100 - breath, 2)), 100)
	end
	if w.gassed then
		rt = idiv(rt * (100 + cfg.gassed_pct), 100)
	end
	if w.getting_aid then
		rt = idiv(rt * (100 + cfg.getting_aid_pct), 100)
	end
	if (w.shock or 0) > 0 then
		rt = idiv(rt * (100 + w.shock * 20), 100)
	end
	return idiv(rt + 5, 10)
end

-- Collective interrupt chance in percent, Soldier Control.cpp:25002.
-- leader: leadership, level. mate: level, agility, wisdom.
function R.CollectiveChance(leader, mate)
	return 10 * idiv(3 * leader.leadership + 20 * leader.level + 20 * mate.level + 2 * mate.agility + mate.wisdom, 100)
end

-- Sorts winners so the largest margin comes first (TeamTurns.cpp:2500-2564 queues them so).
-- Equal margins keep their input order.
function R.OrderWinners(winners)
	for i, w in ipairs(winners) do
		w._order = i
	end
	table.sort(winners, function(a, b)
		if a.margin ~= b.margin then
			return a.margin > b.margin
		end
		return a._order < b._order
	end)
	for _, w in ipairs(winners) do
		w._order = nil
	end
	return winners
end

-- Classic trigger: each watcher duels at its first step with line of sight.
-- watchers[i]: first_los (step index or nil), won, margin
-- Returns the earliest step with a winner, and all winners at that step.
function R.FindClassicTrigger(watchers)
	local best_step, winners
	for _, w in ipairs(watchers) do
		if w.first_los and w.won then
			if not best_step or w.first_los < best_step then
				best_step, winners = w.first_los, {}
			end
			if w.first_los == best_step then
				winners[#winners + 1] = w
			end
		end
	end
	if not best_step then
		return nil, {}
	end
	return best_step, R.OrderWinners(winners)
end

-- IIS trigger along a path. A watcher wins at the first step where it sees the mover and its
-- counter is at least its reaction time. Steps before first_step are not walked.
-- watchers[i]: counter, rt, los[step] (bool), adds[step] (registered AP for that step)
-- Sets w.cum[step] (the counter added through each step) and w.margin on winners.
-- Returns the earliest step with a winner, and all winners at that step.
function R.FindIISTrigger(watchers, first_step, last_step)
	for _, w in ipairs(watchers) do
		local cum, c = {}, 0
		for s = first_step, last_step do
			c = c + (w.adds[s] or 0)
			cum[s] = c
		end
		w.cum = cum
	end
	local best_step, winners
	for _, w in ipairs(watchers) do
		local stop = best_step or last_step
		for s = first_step, stop do
			local total = w.counter + w.cum[s]
			if w.los[s] and total >= w.rt then
				if not best_step or s < best_step then
					best_step, winners = s, {}
				end
				w.margin = total - w.rt
				winners[#winners + 1] = w
				break
			end
		end
	end
	if not best_step then
		return nil, {}
	end
	return best_step, R.OrderWinners(winners)
end

-- IIS check at one moment (after an attack): every watcher at or above its reaction time wins.
-- watchers[i]: counter, rt, sees
function R.FindIISNow(watchers)
	local winners = {}
	for _, w in ipairs(watchers) do
		if w.sees and w.counter >= w.rt then
			w.margin = w.counter - w.rt
			winners[#winners + 1] = w
		end
	end
	return R.OrderWinners(winners)
end

-- The start rule of RunCombatActions (CombatActions.lua:262-281), applied to the interrupters only.
-- states: the running state of each other interrupter that has an action ("start", "PostAction", ...).
function R.CanStartAction(simultaneous, states)
	local any = false
	for _, state in ipairs(states) do
		any = true
		if state ~= "PostAction" then
			return false
		end
	end
	return not any or simultaneous and true or false
end
