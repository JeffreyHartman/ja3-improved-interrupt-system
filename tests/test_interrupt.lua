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
	t.eq(it:EndReason(), "auto_end")
end)

t.case("Interrupt: an action step restarts the Auto end delay", function()
	local it = Fresh()
	it:ActionStarted()
	clock = 1000
	it:Activity()
	clock = 2499
	t.eq(it:EndReason(), nil)
	clock = 2500
	t.eq(it:EndReason(), "auto_end")
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
	t.eq(it:EndReason(), "end_request")
end)

t.case("Interrupt: an End request waits for the busy interrupter", function()
	local it, _, w = Fresh()
	w[1].busy = true
	t.eq(it:Busy(), true)
	t.eq(it:EndTurnPressed(), "requested")
	t.eq(it:EndReason(), nil)
	w[1].busy = false
	t.eq(it:EndReason(), "end_request")
end)

t.case("Interrupt: a second press while busy is a Forced end, and later presses do nothing", function()
	local it, _, w = Fresh()
	w[1].busy = true
	t.eq(it:EndTurnPressed(), "requested")
	t.eq(it:EndTurnPressed(), "forced")
	t.eq(it:EndReason(), "forced_end")
	t.eq(it:EndTurnPressed(), nil)
end)

t.case("Interrupt: a second press with nobody busy does nothing", function()
	local it = Fresh()
	t.eq(it:EndTurnPressed(), "requested")
	t.eq(it:EndTurnPressed(), nil)
	t.eq(it:EndReason(), "end_request")
end)

t.case("Interrupt: the interrupt ends when the last interrupter goes down", function()
	local it, _, w = Fresh{ winners = { Unit("a", { ap = 5000 }) }, joiners = { Unit("b", { ap = 5000 }) } }
	w[1].down = true
	t.eq(it:EndReason(), nil)
	it:Interrupters()[2].down = true
	t.eq(it:EndReason(), "interrupters_down")
end)

t.case("Interrupt: the interrupt ends when the mover is dead", function()
	local it, mover = Fresh{ winners = { Unit("a", { ap = 5000 }) } }
	mover.down = true
	t.eq(it:EndReason(), nil)
	mover.dead = true
	t.eq(it:EndReason(), "mover_dead")
end)

t.case("Interrupt: the interrupt ends when combat ends", function()
	local it = Fresh{ winners = { Unit("a", { ap = 5000 }) } }
	combat = false
	t.eq(it:EndReason(), "combat_ended")
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
	t.eq(it:EndReason(), "auto_end")
end)

t.case("Interrupt: ActionStarted counts the actions for the log", function()
	local it = Fresh()
	t.eq(it:Actions(), 0)
	t.eq(it:ActionStarted(), 1)
	t.eq(it:ActionStarted(), 2)
	t.eq(it:Actions(), 2)
end)

t.case("Interrupt: HasEndRequest is true after the first End Turn press", function()
	local it = Fresh()
	t.eq(it:HasEndRequest(), false)
	it:EndTurnPressed()
	t.eq(it:HasEndRequest(), true)
end)

local function Entry(id, unit, o)
	o = o or {}
	return { action_id = id, unit = unit, ap = o.ap or 1000, simultaneous = o.simultaneous or false, packed = id }
end

t.case("Interrupt: a queued action counts as busy", function()
	local it, _, w = Fresh()
	t.eq(it:Busy(), false)
	it:Enqueue(Entry("Attack", w[1]))
	t.eq(it:Busy(), true)
end)

t.case("Interrupt: a down interrupter is not busy", function()
	local it, _, w = Fresh{ winners = { Unit("a"), Unit("b") } }
	w[1].busy, w[1].down = true, true
	t.eq(it:Busy(), false)
end)

local function Ids(list)
	local ids = {}
	for i, e in ipairs(list) do
		ids[i] = e.action_id
	end
	return table.concat(ids, " ")
end

local function Yes() return true end

t.case("Interrupt: TakeNext takes the actions that can start in queue order", function()
	local it, _, w = Fresh{ winners = { Unit("a"), Unit("b") } }
	it:Enqueue(Entry("Attack", w[1]))
	it:Enqueue(Entry("Move", w[2]))
	t.eq(it:TakeNext(Yes).action_id, "Attack")
	t.eq(it:QueueLength(), 1)
	t.eq(it:TakeNext(Yes).action_id, "Move")
	t.eq(it:TakeNext(Yes), nil)
	t.eq(it:QueueLength(), 0)
end)

t.case("Interrupt: a blocked action that cannot play alongside others stops the scan", function()
	local it, _, w = Fresh{ winners = { Unit("a"), Unit("b") } }
	it:Enqueue(Entry("Attack", w[1]))
	it:Enqueue(Entry("Move", w[2], { simultaneous = true }))
	local asked = {}
	local function OnlyMove(e)
		asked[#asked + 1] = e.action_id
		return e.action_id == "Move"
	end
	t.eq(it:TakeNext(OnlyMove), nil)
	t.eq(table.concat(asked, " "), "Attack")
	t.eq(it:QueueLength(), 2)
end)

t.case("Interrupt: a blocked simultaneous action lets the scan continue", function()
	local it, _, w = Fresh{ winners = { Unit("a"), Unit("b") } }
	it:Enqueue(Entry("Move", w[1], { simultaneous = true }))
	it:Enqueue(Entry("Attack", w[2]))
	local e = it:TakeNext(function(x) return x.action_id == "Attack" end)
	t.eq(e.action_id, "Attack")
	t.eq(it:QueueLength(), 1)
	t.eq(it:TakeNext(Yes).action_id, "Move")
end)

t.case("Interrupt: TakeNext drops the action of a dead unit and reports it to on_drop", function()
	local it, _, w = Fresh{ winners = { Unit("a"), Unit("b") } }
	it:Enqueue(Entry("Attack", w[1]))
	it:Enqueue(Entry("Move", w[2]))
	w[1].dead = true
	local dropped = {}
	local e = it:TakeNext(Yes, function(x) dropped[#dropped + 1] = x end)
	t.eq(e.action_id, "Move")
	t.eq(Ids(dropped), "Attack")
	t.eq(it:QueueLength(), 0)
end)

t.case("Interrupt: Drain returns the actions that did not start and empties the queue", function()
	local it, _, w = Fresh{ winners = { Unit("a"), Unit("b") } }
	it:Enqueue(Entry("Attack", w[1]))
	it:Enqueue(Entry("Move", w[2]))
	it:Enqueue(Entry("Reload", w[1]))
	it:TakeNext(Yes)
	t.eq(Ids(it:Drain()), "Move Reload")
	t.eq(it:QueueLength(), 0)
	t.eq(#it:Drain(), 0)
end)

t.case("Interrupt: Enqueue restarts the Auto end delay", function()
	local it, _, w = Fresh()
	it:ActionStarted()
	clock = 1000
	it:Enqueue(Entry("Attack", w[1]))
	it:TakeNext(Yes)
	clock = 2499
	t.eq(it:EndReason(), nil)
	clock = 2500
	t.eq(it:EndReason(), "auto_end")
end)

t.case("Interrupt: IsInterrupter is true for the winners and the joiners only", function()
	local a, b = Unit("a"), Unit("b")
	local it, mover = Fresh{ winners = { a }, joiners = { b } }
	t.eq(it:IsInterrupter(a), true)
	t.eq(it:IsInterrupter(b), true)
	t.eq(it:IsInterrupter(mover), false)
	t.eq(it:IsInterrupter(Unit("c")), false)
	t.eq(it:IsInterrupter(nil), false)
end)

t.case("Interrupt: CanAct is true for an interrupter that is not down", function()
	local a, b = Unit("a"), Unit("b")
	local it, mover = Fresh{ winners = { a }, joiners = { b } }
	t.eq(it:CanAct(a), true)
	t.eq(it:CanAct(b), true)
	b.down = true
	t.eq(it:CanAct(b), false)
	t.eq(it:CanAct(mover), false)
	t.eq(it:CanAct(nil), false)
end)

t.case("Interrupt: Top is the first winner, even when it is down", function()
	local a, b, c = Unit("a"), Unit("b"), Unit("c")
	local it = Fresh{ winners = { a, b }, joiners = { c } }
	t.eq(it:Top(), a)
	a.down = true
	t.eq(it:Top(), a)
end)

t.case("Interrupt: Number, Mover, System and Kind return the values from Begin", function()
	local it, mover = Fresh()
	t.eq(it:Number(), 1)
	t.eq(it:Mover(), mover)
	t.eq(it:System(), "IIS")
	t.eq(it:Kind(), "move")
end)
