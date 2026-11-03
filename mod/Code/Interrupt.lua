-- IISInterrupt holds the state of the active interrupt and decides when it ends (GLOSSARY.md). The
-- file makes no engine calls, so tests/run.lua runs it with a plain Lua interpreter.

IISInterrupt = {}
local M = IISInterrupt

local now, in_combat, alive, can_act, busy, ap_raw, walk_ap

--- Sets the engine functions that the module calls.
-- `now()` returns the game time in ms, `in_combat()` is true while combat runs, `alive(u)` is false
-- for a dead or removed unit, `can_act(u)` is false for a down unit, `busy(u)` is true while a unit
-- runs an action or a command, `ap_raw(u)` returns a unit's raw AP and `walk_ap()` the raw AP of one
-- step. The module calls `busy(u)` only for a unit that `can_act(u)` accepts.
function M.Setup(o)
	now, in_combat, alive, can_act, busy = o.now, o.in_combat, o.alive, o.can_act, o.busy
	ap_raw, walk_ap = o.ap_raw, o.walk_ap
end

local Interrupt = {}
Interrupt.__index = Interrupt

--- Starts an interrupt and returns its Interrupt object.
-- `o` has `n`, `mover`, `winners`, `joiners`, `system`, `kind` and `cfg` (IIS.Config).
function M.Begin(o)
	local it = setmetatable({
		n = o.n,
		mover = o.mover,
		system = o.system,
		kind = o.kind,
		cfg = o.cfg,
		interrupters = {},
		is_interrupter = {},
		queue = {},
		actions = 0,
		last_activity = now(),
		end_request = false,
		forced_end = false,
		busy_ms = 0,
	}, Interrupt)
	for _, list in ipairs{ o.winners, o.joiners or {} } do
		for _, u in ipairs(list) do
			it.interrupters[#it.interrupters + 1] = u
			it.is_interrupter[u] = true
		end
	end
	return it
end

--- The interrupt number for the log.
function Interrupt:Number()
	return self.n
end

--- The unit whose action the interrupt pauses.
function Interrupt:Mover()
	return self.mover
end

--- The interrupt system that started the interrupt: "IIS" or "Classic".
function Interrupt:System()
	return self.system
end

--- The trigger kind: "move" or "attack".
function Interrupt:Kind()
	return self.kind
end

--- True when `u` is a winner or a joiner.
function Interrupt:IsInterrupter(u)
	return u ~= nil and self.is_interrupter[u] or false
end

--- True when `u` is an interrupter that is not down.
function Interrupt:CanAct(u)
	return self:IsInterrupter(u) and can_act(u)
end

--- The first winner.
function Interrupt:Top()
	return self.interrupters[1]
end

--- The winners and then the joiners, as a new list.
function Interrupt:Interrupters()
	local list = {}
	for i, u in ipairs(self.interrupters) do
		list[i] = u
	end
	return list
end

--- The interrupters that are not down.
function Interrupt:Living()
	local list = {}
	for _, u in ipairs(self.interrupters) do
		if self:CanAct(u) then
			list[#list + 1] = u
		end
	end
	return list
end

--- Restarts the Auto end delay.
function Interrupt:Activity()
	self.last_activity = now()
end

--- Counts an interrupter action that starts, restarts the Auto end delay and returns the count.
function Interrupt:ActionStarted()
	self.actions = self.actions + 1
	self:Activity()
	return self.actions
end

--- The number of interrupter actions that started.
function Interrupt:Actions()
	return self.actions
end

--- True while an action is queued or an interrupter that is not down is busy.
function Interrupt:Busy()
	if #self.queue > 0 then
		return true
	end
	for _, u in ipairs(self:Living()) do
		if busy(u) then
			return true
		end
	end
	return false
end

--- Adds `ms` to the busy time and returns true when a stuck dump is due.
-- A dump is due at `cfg.stuck_ms` of busy time and then every 10 seconds. A tick while busy
-- restarts the Auto end delay, and a tick while idle sets the busy time to 0.
function Interrupt:Tick(ms)
	if not self:Busy() then
		self.busy_ms, self.next_dump_ms = 0, nil
		return false
	end
	self:Activity()
	self.busy_ms = self.busy_ms + ms
	if self.busy_ms >= (self.next_dump_ms or self.cfg.stuck_ms) then
		self.next_dump_ms = self.busy_ms + 10000
		return true
	end
	return false
end

--- The time in ms that the interrupters have been busy without a pause.
function Interrupt:BusyMs()
	return self.busy_ms
end

--- True when no interrupter that is not down has the AP for one step.
function Interrupt:OutOfAP()
	local walk = walk_ap()
	for _, u in ipairs(self:Living()) do
		if ap_raw(u) >= walk then
			return false
		end
	end
	return true
end

--- Adds an interrupter action to the end of the queue and restarts the Auto end delay.
-- `e` has `action_id`, `unit`, `ap` (the raw AP that the unit already paid), `simultaneous` (true
-- when the action can play alongside others) and `packed` (the arguments for the action).
function Interrupt:Enqueue(e)
	self.queue[#self.queue + 1] = e
	self:Activity()
end

--- Removes and returns the first queued action that can start, or nil.
-- `can_start(e)` is true when the action can start now. The scan stops at a blocked action that
-- is not simultaneous. The action of a dead unit leaves the queue and goes to `on_drop(e)`.
function Interrupt:TakeNext(can_start, on_drop)
	local queue = self.queue
	local i = 1
	while i <= #queue do
		local e = queue[i]
		if not alive(e.unit) then
			table.remove(queue, i)
			on_drop(e)
		elseif can_start(e) then
			table.remove(queue, i)
			return e
		elseif not e.simultaneous then
			return nil
		else
			i = i + 1
		end
	end
end

--- Empties the queue and returns the actions that never started, in queue order.
function Interrupt:Drain()
	local list = self.queue
	self.queue = {}
	return list
end

--- The number of queued actions.
function Interrupt:QueueLength()
	return #self.queue
end

--- Records an End Turn press.
-- Returns "requested" for the End request, "forced" for a Forced end, or nil when the press
-- changes nothing.
function Interrupt:EndTurnPressed()
	if not self.end_request then
		self.end_request = true
		return "requested"
	end
	if not self.forced_end and self:Busy() then
		self.forced_end = true
		return "forced"
	end
end

--- True after the End request.
function Interrupt:HasEndRequest()
	return self.end_request
end

--- The end reason code when the interrupt ends now, or nil while it goes on.
-- The codes are "combat_ended", "mover_dead", "interrupters_down", "forced_end", "end_request"
-- and "auto_end". UI.lua maps each code to the combat log text.
function Interrupt:EndReason()
	local cfg = self.cfg
	if not in_combat() then return "combat_ended" end
	if not alive(self.mover) then return "mover_dead" end
	if #self:Living() == 0 then return "interrupters_down" end
	if self.forced_end then return "forced_end" end
	local is_busy = self:Busy()
	if self.end_request and not is_busy then return "end_request" end
	if cfg.auto_end and self.actions > 0 and not is_busy and self:OutOfAP()
		and now() - self.last_activity >= cfg.auto_end_delay_ms then
		return "auto_end"
	end
end
