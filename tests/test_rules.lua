-- Tests for IISRules (mod/Code/Rules.lua). The worked examples come from
-- interrupts/JA2_113_INTERRUPTS.md, sections 1.7 and 2.6.

local R = IISRules
local t = Test

t.case("idiv truncates toward zero like C", function()
	t.eq(R.idiv(7, 2), 3)
	t.eq(R.idiv(-7, 2), -3)
	t.eq(R.idiv(200, 30), 6)
	t.eq(R.idiv(0, 5), 0)
end)

t.case("To113AP converts 12 vanilla AP to 100 1.13 AP and rounds half up", function()
	t.eq(R.To113AP(12000), 100)
	t.eq(R.To113AP(1000), 8)    -- a walk step, 8 AP in 1.13
	t.eq(R.To113AP(10000), 83)  -- the shot from the issue #1 log
	t.eq(R.To113AP(1500), 13)   -- 12.5 rounds up
	t.eq(R.To113AP(0), 0)
end)

t.case("MinAP: 16 1.13 AP for Classic, 4 for IIS, and one step as the Classic floor", function()
	t.eq(R.MinAP("Classic", 1000), 1920)
	t.eq(R.MinAP("Classic", 3000), 3000)
	t.eq(R.MinAP("IIS", 1000), 480)
	t.eq(R.MinAP("IIS", 3000), 480)
end)

-- Section 1.7: watcher level 5, agility 85, 15 tiles away, passive.
local function watcher_115()
	return { level = 5, agility = 85, stance = "Standing", is_player = true }
end

t.case("ClassicPoints: 1.13 worked example, passive watcher", function()
	local pts = R.ClassicPoints(watcher_115(), { passive = true, distance = 15 })
	t.eq(pts, 5)
end)

t.case("ClassicPoints: 1.13 worked example, active mover", function()
	local m = { level = 3, agility = 70, stance = "Standing", is_enemy = true }
	t.eq(R.ClassicPoints(m, { passive = false, distance = 15, other_saw_me = true }), 4)
	m.saw_before = true
	t.eq(R.ClassicPoints(m, { passive = false, distance = 15, other_saw_me = true }), 5)
end)

t.case("ClassicPoints: modifiers", function()
	local base = R.ClassicPoints(watcher_115(), { passive = true, distance = 0 })
	t.eq(base, 6)
	local w = watcher_115()
	w.visible_enemies = 5 -- -(5-1)/2 = -2
	t.eq(R.ClassicPoints(w, { passive = true, distance = 0 }), 4)
	w = watcher_115()
	w.shock = 1
	w.bandaging = true
	t.eq(R.ClassicPoints(w, { passive = true, distance = 0 }), 3)
	w = watcher_115()
	w.night_ops = true
	t.eq(R.ClassicPoints(w, { passive = true, distance = 0, dark = true }), 8)
	t.eq(R.ClassicPoints(w, { passive = true, distance = 0, dark = false }), 6)
	w = watcher_115()
	w.saw_before = true
	t.eq(R.ClassicPoints(w, { passive = true, distance = 0 }), 7)
end)

t.case("ClassicPoints: active mover stance bonuses at long range", function()
	local m = { level = 3, agility = 70, stance = "Crouch", is_enemy = true }
	t.eq(R.ClassicPoints(m, { distance = 13, max_visible = 24 }), 5)  -- 13 > 12
	t.eq(R.ClassicPoints(m, { distance = 12, max_visible = 24 }), 4)
	m.stance = "Prone"
	t.eq(R.ClassicPoints(m, { distance = 13, max_visible = 24 }), 5)  -- 13 / 12 = 1
	t.eq(R.ClassicPoints(m, { distance = 13, max_visible = 24, other_saw_me = true }), 4)
	m.stance = "Standing"
	m.running = true
	t.eq(R.ClassicPoints(m, { distance = 13, max_visible = 24 }), 2)
end)

t.case("ClassicPoints caps at 99", function()
	t.eq(R.ClassicPoints({ level = 200, agility = 100 }, { passive = true }), 99)
end)

t.case("ClassicDuel: higher score wins, a tie goes to the mover", function()
	local won, margin, how = R.ClassicDuel(5, 4, true, true)
	t.eq(won, true); t.eq(margin, 1); t.eq(how, "points")
	won, margin = R.ClassicDuel(5, 5, true, true)
	t.eq(won, false); t.eq(margin, 0)
end)

t.case("ClassicDuel: an unseen watcher wins automatically with margin 0 or more", function()
	local won, margin, how = R.ClassicDuel(3, 6, true, false)
	t.eq(won, true); t.eq(margin, 0); t.eq(how, "automatic")
	won, margin = R.ClassicDuel(8, 6, true, false)
	t.eq(won, true); t.eq(margin, 2)
end)

-- Section 2.6: level 5, half of the sight range away, 10 AP per step.
t.case("IISRegisteredPercent: 1.13 worked example", function()
	local pct = R.IISRegisteredPercent({ level = 5 }, { distance = 10, sight = 20 })
	t.eq(pct, 68)
	t.eq(R.IISRegisteredAP(10, pct), 7)
end)

t.case("IISRegisteredPercent: penalties and clamps", function()
	t.eq(R.IISRegisteredPercent({ level = 5 }, { distance = 40, sight = 20 }), 55)  -- range penalty caps at 25
	t.eq(R.IISRegisteredPercent({ level = 5 }, { distance = 0, sight = 20, dark = true }), 70)
	t.eq(R.IISRegisteredPercent({ level = 5, night_ops = true }, { distance = 0, sight = 20, dark = true }), 80)
	t.eq(R.IISRegisteredPercent({ level = 5 }, { distance = 0, sight = 20, mover_stealthy = true }), 60)
	t.eq(R.IISRegisteredPercent({ level = 1 }, { distance = 20, sight = 20, mover_stealthy = true, dark = true }), 20)
	t.eq(R.IISRegisteredPercent({ level = 10 }, { distance = 0, sight = 20 }), 100)
	t.eq(R.IISRegisteredPercent({ level = 1 }, { distance = 20, sight = 20, heard_only = true, mover_stealthy = true }), 10)
end)

t.case("IISRegisteredAP rounds half up", function()
	t.eq(R.IISRegisteredAP(8, 68), 5)   -- 5.44
	t.eq(R.IISRegisteredAP(8, 75), 6)   -- 6.0
	t.eq(R.IISRegisteredAP(7, 50), 4)   -- 3.5
end)

local function iis_watcher(over)
	local w = { agility = 85, ap = 100, max_ap = 100, life = 100, life_max = 100, level = 5 }
	for k, v in pairs(over or {}) do
		w[k] = v
	end
	return w
end

t.case("IISReactionTime: 1.13 worked example", function()
	t.eq(R.IISReactionTime(iis_watcher()), 23)
	t.eq(R.IISReactionTime(iis_watcher({ ap = 50 })), 28)
end)

t.case("IISReactionTime: agility bands", function()
	t.eq(R.IISReactionTime(iis_watcher({ agility = 100 })), 15)
	t.eq(R.IISReactionTime(iis_watcher({ agility = 80 })), 25)
	t.eq(R.IISReactionTime(iis_watcher({ agility = 51 })), 40)
	t.eq(R.IISReactionTime(iis_watcher({ agility = 50 })), 40)
	t.eq(R.IISReactionTime(iis_watcher({ agility = 30 })), 40)
end)

t.case("IISReactionTime: AP above the maximum shortens it, no AP lengthens it by half", function()
	t.eq(R.IISReactionTime(iis_watcher({ agility = 80, ap = 0 })), 38)  -- 375 -> 38
	t.eq(R.IISReactionTime(iis_watcher({ agility = 80, ap = 120 })), 23) -- 250 * 90 / 100
end)

t.case("IISReactionTime: injuries, fatigue, gas, aid and shock", function()
	-- 30 HP lost, not bleeding: inj = 200 * (30 + 15) / 100 = 90; *(100 - 15)/100 = 76
	t.eq(R.IISReactionTime(iis_watcher({ agility = 80, life = 70 })), 44) -- 250 * 176 / 100 = 440
	t.eq(R.IISReactionTime(iis_watcher({ agility = 80, breath = 50 })), 31) -- 250 * 125 / 100 = 312
	t.eq(R.IISReactionTime(iis_watcher({ agility = 80, gassed = true })), 38)
	t.eq(R.IISReactionTime(iis_watcher({ agility = 80, getting_aid = true })), 30)
	t.eq(R.IISReactionTime(iis_watcher({ agility = 80, shock = 1 })), 30)
end)

t.case("CollectiveChance is a multiple of 10", function()
	local c = R.CollectiveChance({ leadership = 60, level = 5 }, { level = 4, agility = 80, wisdom = 70 })
	-- (180 + 100 + 80 + 160 + 70) / 100 = 5 -> 50
	t.eq(c, 50)
	t.eq(R.CollectiveChance({ leadership = 100, level = 10 }, { level = 10, agility = 100, wisdom = 100 }), 100)
end)

t.case("OrderWinners puts the largest margin first and keeps ties stable", function()
	local list = R.OrderWinners({ { id = "a", margin = 1 }, { id = "b", margin = 3 }, { id = "c", margin = 1 } })
	t.eq(list[1].id, "b"); t.eq(list[2].id, "a"); t.eq(list[3].id, "c")
end)

t.case("FindClassicTrigger picks the earliest winning step and all winners at it", function()
	local step, winners = R.FindClassicTrigger({
		{ id = "lose_early", first_los = 2, won = false, margin = -1 },
		{ id = "late", first_los = 5, won = true, margin = 4 },
		{ id = "a", first_los = 3, won = true, margin = 1 },
		{ id = "b", first_los = 3, won = true, margin = 2 },
		{ id = "never", won = true, margin = 9 },
	})
	t.eq(step, 3)
	t.eq(#winners, 2)
	t.eq(winners[1].id, "b")
	t.eq(winners[2].id, "a")
end)

t.case("FindClassicTrigger with no winner", function()
	local step, winners = R.FindClassicTrigger({ { first_los = 2, won = false, margin = 0 } })
	t.eq(step, nil)
	t.eq(#winners, 0)
end)

t.case("FindIISTrigger: counters fill only on steps with line of sight", function()
	local a = { id = "a", counter = 0, rt = 12, los = { [2] = true, [3] = true, [4] = true }, adds = { [2] = 5, [3] = 5, [4] = 5 } }
	local b = { id = "b", counter = 10, rt = 23, los = { [4] = true, [5] = true }, adds = { [4] = 7, [5] = 7 } }
	local step, winners = R.FindIISTrigger({ a, b }, 2, 5)
	t.eq(step, 4)
	t.eq(#winners, 1)
	t.eq(winners[1].id, "a")
	t.eq(a.margin, 3)
	t.eq(a.cum[4], 15)
	t.eq(b.cum[5], 14)
end)

t.case("FindIISTrigger: two watchers that cross on the same step both win", function()
	local a = { id = "a", counter = 0, rt = 10, los = { [2] = true, [3] = true }, adds = { [2] = 5, [3] = 5 } }
	local b = { id = "b", counter = 4, rt = 10, los = { [3] = true }, adds = { [3] = 7 } }
	local step, winners = R.FindIISTrigger({ a, b }, 2, 3)
	t.eq(step, 3)
	t.eq(#winners, 2)
	t.eq(winners[1].id, "b") -- margin 1 beats margin 0
end)

t.case("FindIISTrigger: a full counter waits for line of sight", function()
	local a = { id = "a", counter = 30, rt = 20, los = { [4] = true }, adds = {} }
	local step, winners = R.FindIISTrigger({ a }, 2, 6)
	t.eq(step, 4)
	t.eq(winners[1].margin, 10)
end)

t.case("FindIISTrigger: no winner", function()
	local a = { counter = 0, rt = 50, los = { [2] = true }, adds = { [2] = 5 } }
	local step = R.FindIISTrigger({ a }, 2, 2)
	t.eq(step, nil)
end)

t.case("FindIISNow needs sight and a full counter", function()
	local winners = R.FindIISNow({
		{ id = "a", counter = 25, rt = 20, sees = true },
		{ id = "b", counter = 30, rt = 20, sees = false },
		{ id = "c", counter = 10, rt = 20, sees = true },
		{ id = "d", counter = 40, rt = 20, sees = true },
	})
	t.eq(#winners, 2)
	t.eq(winners[1].id, "d")
	t.eq(winners[2].id, "a")
end)

t.case("CanStartAction follows the RunCombatActions rule", function()
	t.eq(R.CanStartAction(false, {}), true)
	t.eq(R.CanStartAction(true, { "PostAction" }), true)
	t.eq(R.CanStartAction(false, { "PostAction" }), false)
	t.eq(R.CanStartAction(true, { "start" }), false)
	t.eq(R.CanStartAction(true, { "PostAction", "wait" }), false)
end)
