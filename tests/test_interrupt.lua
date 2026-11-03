-- Tests for IISInterrupt (mod/Code/Interrupt.lua) with a fake clock and plain units.

local t = Test
local I = IISInterrupt

local clock, combat

local cfg = { auto_end = true, auto_end_delay_ms = 1500, stuck_ms = 10000 }

local function Unit(id, o)
	o = o or {}
	return { id = id, ap = o.ap or 0, busy = false, down = false, dead = false }
end

local function Fresh(o)
	o = o or {}
	clock, combat = 0, true
	I.Setup{
		now = function() return clock end,
		in_combat = function() return combat end,
		alive = function(u) return not u.dead end,
		can_act = function(u) return not u.down end,
		busy = function(u) return u.busy end,
		ap_raw = function(u) return u.ap end,
		walk_ap = function() return 1000 end,
	}
	local mover = Unit("mover")
	local winners = o.winners or { Unit("a") }
	local it = I.Begin{ n = 1, mover = mover, winners = winners, joiners = o.joiners or {}, system = "IIS",
		kind = "move", cfg = cfg }
	return it, mover, winners
end

t.case("Interrupt: Auto end waits for the delay after the last action", function()
	local it = Fresh()
	clock = 1000
	it:ActionStarted()
	clock = 2499
	t.eq(it:EndReason(), nil)
	clock = 2500
	t.eq(it:EndReason(), "interrupters are out of AP (auto end)")
end)

t.case("Interrupt: an action step restarts the Auto end delay", function()
	local it = Fresh()
	it:ActionStarted()
	clock = 1000
	it:Activity()
	clock = 2499
	t.eq(it:EndReason(), nil)
	clock = 2500
	t.eq(it:EndReason(), "interrupters are out of AP (auto end)")
end)

t.case("Interrupt: no Auto end before the first action", function()
	local it = Fresh()
	clock = 60000
	t.eq(it:EndReason(), nil)
end)

t.case("Interrupt: no Auto end while an interrupter has the AP for one step", function()
	local it = Fresh{ winners = { Unit("a", { ap = 1000 }) } }
	it:ActionStarted()
	clock = 60000
	t.eq(it:EndReason(), nil)
end)

t.case("Interrupt: an End request with nobody busy ends the interrupt", function()
	local it = Fresh{ winners = { Unit("a", { ap = 5000 }) } }
	t.eq(it:EndReason(), nil)
	t.eq(it:EndTurnPressed(), "requested")
	t.eq(it:EndReason(), "player ended the interrupt")
end)

t.case("Interrupt: an End request waits for the busy interrupter", function()
	local it, _, w = Fresh()
	w[1].busy = true
	t.eq(it:Busy(), true)
	t.eq(it:EndTurnPressed(), "requested")
	t.eq(it:EndReason(), nil)
	w[1].busy = false
	t.eq(it:EndReason(), "player ended the interrupt")
end)

t.case("Interrupt: a second press while busy is a Forced end, and later presses do nothing", function()
	local it, _, w = Fresh()
	w[1].busy = true
	t.eq(it:EndTurnPressed(), "requested")
	t.eq(it:EndTurnPressed(), "forced")
	t.eq(it:EndReason(), "forced: End Turn pressed again while a merc was busy")
	t.eq(it:EndTurnPressed(), nil)
end)

t.case("Interrupt: a second press with nobody busy does nothing", function()
	local it = Fresh()
	t.eq(it:EndTurnPressed(), "requested")
	t.eq(it:EndTurnPressed(), nil)
	t.eq(it:EndReason(), "player ended the interrupt")
end)

t.case("Interrupt: the interrupt ends when the last interrupter goes down", function()
	local it, _, w = Fresh{ winners = { Unit("a", { ap = 5000 }) }, joiners = { Unit("b", { ap = 5000 }) } }
	w[1].down = true
	t.eq(it:EndReason(), nil)
	it:Interrupters()[2].down = true
	t.eq(it:EndReason(), "all interrupters are down")
end)

t.case("Interrupt: the interrupt ends when the mover is dead", function()
	local it, mover = Fresh{ winners = { Unit("a", { ap = 5000 }) } }
	mover.down = true
	t.eq(it:EndReason(), nil)
	mover.dead = true
	t.eq(it:EndReason(), "enemy dead")
end)

t.case("Interrupt: the interrupt ends when combat ends", function()
	local it = Fresh{ winners = { Unit("a", { ap = 5000 }) } }
	combat = false
	t.eq(it:EndReason(), "combat ended")
end)

-- Ticks 100 ms at a time and returns the busy times at which a stuck dump was due.
local function TickFor(it, ms)
	local due = {}
	for _ = 1, ms // 100 do
		clock = clock + 100
		if it:Tick(100) then
			due[#due + 1] = it:BusyMs()
		end
	end
	return due
end

t.case("Interrupt: the stuck timer is due at the stuck time and then every 10 seconds while busy", function()
	local it, _, w = Fresh()
	w[1].busy = true
	local due = TickFor(it, 30000)
	t.eq(#due, 3)
	t.eq(due[1], 10000)
	t.eq(due[2], 20000)
	t.eq(due[3], 30000)
end)

t.case("Interrupt: the stuck timer starts again after the interrupters are idle", function()
	local it, _, w = Fresh()
	w[1].busy = true
	TickFor(it, 9000)
	w[1].busy = false
	t.eq(#TickFor(it, 100), 0)
	t.eq(it:BusyMs(), 0)
	w[1].busy = true
	local due = TickFor(it, 10000)
	t.eq(#due, 1)
	t.eq(due[1], 10000)
end)

t.case("Interrupt: a busy tick restarts the Auto end delay", function()
	local it, _, w = Fresh()
	it:ActionStarted()
	w[1].busy = true
	TickFor(it, 5000)
	w[1].busy = false
	t.eq(it:EndReason(), nil)
	clock = clock + 1500
	t.eq(it:EndReason(), "interrupters are out of AP (auto end)")
end)

t.case("Interrupt: ActionStarted counts the actions for the log", function()
	local it = Fresh()
	t.eq(it:Actions(), 0)
	t.eq(it:ActionStarted(), 1)
	t.eq(it:ActionStarted(), 2)
	t.eq(it:Actions(), 2)
end)

t.case("Interrupt: EndRequested is true after the first End Turn press", function()
	local it = Fresh()
	t.eq(it:EndRequested(), false)
	it:EndTurnPressed()
	t.eq(it:EndRequested(), true)
end)

t.case("Interrupt: a queued action counts as busy", function()
	local queue = {}
	Fresh()
	local it = I.Begin{ n = 1, mover = Unit("mover"), winners = { Unit("a") }, joiners = {}, system = "IIS",
		kind = "move", cfg = cfg, queue = queue }
	t.eq(it:Busy(), false)
	queue[1] = "Attack"
	t.eq(it:Busy(), true)
end)

t.case("Interrupt: a down interrupter is not busy", function()
	local it, _, w = Fresh{ winners = { Unit("a"), Unit("b") } }
	w[1].busy, w[1].down = true, true
	t.eq(it:Busy(), false)
end)
