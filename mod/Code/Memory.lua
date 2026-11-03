-- IISMemory holds the Watcher memory of each unit in combat and the move plan of each mover
-- (GLOSSARY.md). The file makes no engine calls, so tools/test.sh runs it with a plain Lua interpreter.

IISMemory = {}
local M = IISMemory

local key, same_tile, store
local plans = {}

--- Sets the functions that the module calls.
-- `key(unit)` returns the unit's session id, `same_tile(a, b)` compares two positions, and
-- `store()` returns the table that the game saves.
function M.Setup(o)
	key, same_tile, store = o.key, o.same_tile, o.store
	plans = {}
end

local function Store()
	local s = store()
	s.counters = s.counters or {}
	-- Saves from 0.7.2 and earlier hold the seen marks under these names.
	s.seen_turn = s.seen_turn or {}
	s.seen_ever = s.seen_ever or {}
	return s
end

local function Get(tbl, a, b)
	local row = tbl[key(a)]
	return row and row[key(b)]
end

local function Set(tbl, a, b, value)
	local ka, kb = key(a), key(b)
	if ka == nil or kb == nil then return end
	local row = tbl[ka]
	if not row then
		if value == nil then return end
		row = {}
		tbl[ka] = row
	end
	row[kb] = value
end

--- The registered 1.13 AP that watcher `w` holds for mover `m`.
function M.Counter(w, m)
	return Get(Store().counters, w, m) or 0
end

--- Adds `ap` registered 1.13 AP to the counter of `watcher` for `mover` and returns the new counter.
function M.Register(watcher, mover, ap)
	local c = math.min(255, math.max(0, M.Counter(watcher, mover) + ap)) -- UINT8 in 1.13
	Set(Store().counters, watcher, mover, c ~= 0 and c or nil)
	return c
end

--- Marks that `unit` saw `other`: Seen this turn and Seen before.
function M.Sees(unit, other)
	local s = Store()
	Set(s.seen_turn, unit, other, true)
	Set(s.seen_ever, unit, other, true)
end

--- True if `w` saw `m` after the start of its own last turn.
function M.SeenThisTurn(w, m)
	return Get(Store().seen_turn, w, m) or false
end

--- True if `w` saw `m` at some time in the current combat.
function M.SeenBefore(w, m)
	return Get(Store().seen_ever, w, m) or false
end

------------------------------------------------------------------------------------------------
-- Move plans. A plan is { steps = {pos...}, first = n, rows = {{ unit, cum }} }, where
-- row.cum[i] is the AP that row.unit registers on steps first..i. The game does not save plans.

-- The last step of the plan on the tile `here`.
local function Reached(plan, here)
	for i = #plan.steps, plan.first, -1 do
		if same_tile(plan.steps[i], here) then
			return i
		end
	end
end

-- Adds the AP of the steps after entry.done through the step on `here` to the counters.
local function Commit(mover, entry, here)
	local upto = Reached(entry.plan, here)
	if not upto then
		return { off_path = true, done = entry.done }
	end
	if upto <= entry.done then return end
	local adds = {}
	for _, row in ipairs(entry.plan.rows) do
		local delta = (row.cum[upto] or 0) - (row.cum[entry.done] or 0)
		if delta > 0 then
			adds[#adds + 1] = { unit = row.unit, delta = delta, counter = M.Register(row.unit, mover, delta) }
		end
	end
	entry.done = upto
	return { through = upto, adds = adds }
end

local function CommitThrough(mover, here)
	local entry = plans[key(mover)]
	if entry and here then
		return Commit(mover, entry, here)
	end
end

--- Commits the mover's old plan through the tile `here`, then stores `plan` in its place.
-- `plan` can be nil: then the mover has no plan after the call. Returns the commit result:
-- `{ through = step, adds = {{ unit, delta, counter }} }`, `{ off_path = true, done = n }`
-- when `here` is not on the old plan, or nil when there was nothing to commit.
function M.PlanMove(mover, plan, here)
	local result = CommitThrough(mover, here)
	plans[key(mover)] = plan and { plan = plan, done = plan.first - 1 } or nil
	return result
end

--- Commits the mover's plan through the tile `here` and drops the plan. Returns the commit result.
function M.MoveDone(mover, here)
	local result = CommitThrough(mover, here)
	plans[key(mover)] = nil
	return result
end

--- Records an interrupt against `mover`: commits its plan through `here`, then resets the
-- interrupters' counters for the mover, then marks that they saw it. `here` is nil after an
-- attack. Returns the commit result.
function M.Fired(mover, interrupters, here)
	local result = CommitThrough(mover, here)
	local counters = Store().counters
	for _, u in ipairs(interrupters) do
		Set(counters, u, mover, nil)
		M.Sees(u, mover)
	end
	return result
end

------------------------------------------------------------------------------------------------
-- Turns and the combat

--- Starts the turn of the team of `units`: their counters and Seen this turn marks decay, like
-- ubInterruptCounter and SEEN_THIS_TURN in 1.13 (TeamTurns.cpp:576).
function M.TurnStart(units)
	local s = Store()
	for _, u in ipairs(units or {}) do
		local k = key(u)
		if k ~= nil then
			s.counters[k] = nil
			s.seen_turn[k] = nil
		end
	end
end

--- Forgets everything. The game calls it at the start and the end of a combat.
function M.Clear()
	local s = Store()
	s.counters, s.seen_turn, s.seen_ever = {}, {}, {}
	plans = {}
end

--- Drops the plans after a load. The counters and the seen marks are in the save.
function M.Loaded()
	plans = {}
end

--- Every non-zero counter as `{ watcher = key, mover = key, counter = n }`, sorted by key.
function M.Counters()
	local list = {}
	for wk, row in pairs(Store().counters) do
		for mk, c in pairs(row) do
			list[#list + 1] = { watcher = wk, mover = mk, counter = c }
		end
	end
	table.sort(list, function(x, y)
		if x.watcher ~= y.watcher then
			return tostring(x.watcher) < tostring(y.watcher)
		end
		return tostring(x.mover) < tostring(y.mover)
	end)
	return list
end
