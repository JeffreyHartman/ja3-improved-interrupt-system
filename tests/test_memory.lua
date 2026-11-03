-- Tests for IISMemory (mod/Code/Memory.lua) with a plain store table and plain units.

local t = Test
local M = IISMemory

local store

local function Fresh(initial)
	store = initial or {}
	M.Setup{
		key = function(u) return u.id end,
		same_tile = function(a, b) return a.x == b.x and a.y == b.y end,
		store = function() return store end,
	}
end

local function Unit(id)
	return { id = id }
end

t.case("Memory: Register adds to the counter and returns it", function()
	Fresh()
	local a, e = Unit("a"), Unit("e")
	t.eq(M.Counter(a, e), 0)
	t.eq(M.Register(a, e, 6), 6)
	t.eq(M.Register(a, e, 4), 10)
	t.eq(M.Counter(a, e), 10)
	t.eq(M.Counter(e, a), 0)
end)

t.case("Memory: counters cap at 255 like the UINT8 in 1.13", function()
	Fresh()
	local a, e = Unit("a"), Unit("e")
	M.Register(a, e, 250)
	t.eq(M.Register(a, e, 20), 255)
	t.eq(M.Counter(a, e), 255)
end)

-- A straight path of six tiles. The mover stands on step 1, so the plan starts at step 2.
local function Steps()
	local steps = {}
	for i = 1, 6 do
		steps[i] = { x = i, y = 0 }
	end
	return steps
end

-- Each watcher registers `per_step` AP on each step from 2 to 6.
local function Plan(steps, watchers, per_step)
	local rows = {}
	for i, w in ipairs(watchers) do
		local cum = {}
		for s = 2, 6 do
			cum[s] = (s - 1) * per_step
		end
		rows[i] = { unit = w, cum = cum }
	end
	return { steps = steps, first = 2, rows = rows }
end

t.case("Memory: a plan adds each step once", function()
	Fresh()
	local a, e = Unit("a"), Unit("e")
	local steps = Steps()
	M.Register(a, e, 10)
	M.PlanMove(e, Plan(steps, { a }, 6), steps[1])
	local r = M.Fired(e, {}, steps[4])
	t.eq(r.through, 4)
	t.eq(r.adds[1].unit, a)
	t.eq(r.adds[1].delta, 18)
	t.eq(r.adds[1].counter, 28)
	t.eq(M.Counter(a, e), 28)
	t.eq(M.Fired(e, {}, steps[3]), nil)
	t.eq(M.Counter(a, e), 28)
	t.eq(M.MoveDone(e, steps[6]).through, 6)
	t.eq(M.Counter(a, e), 40)
	t.eq(M.MoveDone(e, steps[6]), nil, "the plan is gone")
end)

t.case("Memory: a move that ends off the planned path commits nothing", function()
	Fresh()
	local a, e = Unit("a"), Unit("e")
	local steps = Steps()
	M.PlanMove(e, Plan(steps, { a }, 6), steps[1])
	local r = M.MoveDone(e, { x = 9, y = 9 })
	t.eq(r.off_path, true)
	t.eq(r.done, 1)
	t.eq(M.Counter(a, e), 0)
end)

-- Issue #4: a vanilla interrupt stops the mover on step 2, and the next check plans the rest of
-- the path from there.
t.case("Memory: a new plan commits the old plan through the mover's tile", function()
	Fresh()
	local a, e = Unit("a"), Unit("e")
	local steps = Steps()
	M.Register(a, e, 10)
	M.PlanMove(e, Plan(steps, { a }, 6), steps[1])
	local rest = { table.unpack(steps, 2) }
	local next_plan = { steps = rest, first = 2, rows = { { unit = a, cum = { [2] = 6, [3] = 12, [4] = 18, [5] = 24 } } } }
	local r = M.PlanMove(e, next_plan, steps[2])
	t.eq(r.through, 2)
	t.eq(M.Counter(a, e), 16)
	M.MoveDone(e, steps[6])
	t.eq(M.Counter(a, e), 40) -- 10 + 5 steps of 6
end)

t.case("Memory: an interrupt commits the plan, then resets the interrupters' counters", function()
	Fresh()
	local a, b, e = Unit("a"), Unit("b"), Unit("e")
	local steps = Steps()
	M.Register(a, e, 10)
	M.PlanMove(e, Plan(steps, { a, b }, 6), steps[1])
	local r = M.Fired(e, { a }, steps[3])
	t.eq(r.adds[1].counter, 22, "the commit result shows a's counter before the reset")
	t.eq(M.Counter(a, e), 0)
	t.eq(M.Counter(b, e), 12)
	t.eq(M.SeenThisTurn(a, e), true)
	t.eq(M.SeenBefore(a, e), true)
	t.eq(M.SeenThisTurn(b, e), false)
end)

t.case("Memory: an interrupt after an attack resets the counters and commits nothing", function()
	Fresh()
	local a, e = Unit("a"), Unit("e")
	local steps = Steps()
	M.Register(a, e, 30)
	M.PlanMove(e, Plan(steps, { a }, 6), steps[1])
	t.eq(M.Fired(e, { a }, nil), nil)
	t.eq(M.Counter(a, e), 0)
	t.eq(M.MoveDone(e, steps[6]).adds[1].counter, 30)
end)

t.case("Memory: a team's counters and Seen this turn marks decay at the start of its own turn", function()
	Fresh()
	local a, e = Unit("a"), Unit("e")
	M.Sees(a, e)
	M.Sees(e, a)
	M.Register(a, e, 5)
	M.Register(e, a, 7)
	M.TurnStart({ a })
	t.eq(M.Counter(a, e), 0)
	t.eq(M.SeenThisTurn(a, e), false)
	t.eq(M.SeenBefore(a, e), true)
	t.eq(M.Counter(e, a), 7, "the other team keeps its counters")
	t.eq(M.SeenThisTurn(e, a), true)
	M.TurnStart({ e })
	t.eq(M.Counter(e, a), 0)
	t.eq(M.SeenThisTurn(e, a), false)
	t.eq(M.SeenBefore(e, a), true)
end)

t.case("Memory: a load keeps the counters and the seen marks and drops the plans", function()
	Fresh()
	local a, e = Unit("a"), Unit("e")
	local steps = Steps()
	M.Register(a, e, 10)
	M.Sees(a, e)
	M.PlanMove(e, Plan(steps, { a }, 6), steps[1])
	M.Loaded()
	t.eq(M.Counter(a, e), 10)
	t.eq(M.SeenThisTurn(a, e), true)
	t.eq(M.SeenBefore(a, e), true)
	t.eq(M.MoveDone(e, steps[6]), nil)
	t.eq(M.Counter(a, e), 10)
end)

t.case("Memory: a save from 0.7.2 keeps its seen marks and starts with empty counters", function()
	Fresh({ seen_turn = { a = { e = true } }, seen_ever = { a = { e = true } } })
	local a, e = Unit("a"), Unit("e")
	t.eq(M.SeenThisTurn(a, e), true)
	t.eq(M.Counter(a, e), 0)
	M.Register(a, e, 4)
	t.eq(store.counters.a.e, 4, "the counters are saved under session ids")
end)

t.case("Memory: Clear forgets the counters, the marks and the plans", function()
	Fresh()
	local a, e = Unit("a"), Unit("e")
	local steps = Steps()
	M.Register(a, e, 10)
	M.Sees(a, e)
	M.PlanMove(e, Plan(steps, { a }, 6), steps[1])
	M.Clear()
	t.eq(M.Counter(a, e), 0)
	t.eq(M.SeenThisTurn(a, e), false)
	t.eq(M.SeenBefore(a, e), false)
	t.eq(M.MoveDone(e, steps[6]), nil)
end)

t.case("Memory: Counters lists every non-zero counter by key", function()
	Fresh()
	local a, b, e = Unit("a"), Unit("b"), Unit("e")
	M.Register(b, e, 3)
	M.Register(a, e, 5)
	M.Register(a, b, 0)
	local list = M.Counters()
	t.eq(#list, 2)
	t.eq(list[1].watcher, "a")
	t.eq(list[1].mover, "e")
	t.eq(list[1].counter, 5)
	t.eq(list[2].watcher, "b")
end)
