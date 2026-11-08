-- Improved Interrupt System: runs an interrupt. The frozen enemy's command thread waits in
-- RunInterrupt while the interrupters take orders. End Turn (Enter) ends the interrupt. The
-- overrides at the end of the file change behavior only while IIS.active is set.

local R = IISRules
local E = IIS.E
local Log, Name, AP, Pos, NameList = IIS.Log, IIS.Name, IIS.AP, IIS.Pos, IIS.NameList

IIS.active = false
IIS.interrupt_count = IIS.interrupt_count or 0

IISControl = IISControl or {}

local sleep, can_yield

--- Sets the engine functions that the interrupt calls.
-- `sleep(ms)` waits for `ms` of game time in the mover's command thread, and `can_yield()` is true
-- when the current thread can wait.
function IISControl.Setup(o)
	sleep, can_yield = o.sleep, o.can_yield
end

-- The engine state of the last interrupt that EndInterrupt restores, and the counters for its END
-- log line. IIS.Activate replaces it at the start of each interrupt.
local shell

--- Makes `it` the active interrupt, starts a new shell for it and returns the shell.
-- `dummy` is the step of the mover's path where the interrupt caught it, or nil.
function IIS.Activate(it, dummy)
	shell = { dummy = dummy, start_time = GameTime(), start_ap = {}, forced = {} }
	for _, m in ipairs(it:Interrupters()) do
		shell.start_ap[m] = E.APRaw(m)
	end
	IIS.active = it
	return shell
end

local function Forced(what)
	shell.forced[what] = (shell.forced[what] or 0) + 1
end

-- An error in code that runs in the frozen enemy's command thread ends the enemy's command, so
-- everything that is not the wait itself runs under pcall.
local function SafeCall(it, what, f, ...)
	local ok, err = pcall(f, ...)
	if not ok then
		Log("INT #%s %s failed: %s", it and tostring(it:Number()) or "-", what, tostring(err))
	end
	return ok, err
end
IIS.SafeCall = SafeCall

local function RunningStateSnapshot()
	local parts = {}
	for u, state in pairs(CombatActions_RunningState or empty_table) do
		parts[#parts + 1] = string.format("%s=%s", Name(u), tostring(state))
	end
	table.sort(parts)
	return string.format("running={%s} waiting=%d", table.concat(parts, " "), #(CombatActions_Waiting or empty_table))
end
IIS.RunningStateSnapshot = RunningStateSnapshot

local function CameraLockReasons()
	local reasons = {}
	for reason in pairs(s_CameraMoveLockReasons or empty_table) do
		reasons[#reasons + 1] = reason
	end
	return reasons
end

local function ReasonsToString(reasons)
	local parts = {}
	for i, r in ipairs(reasons) do
		parts[i] = type(r) == "table" and tostring(r.class or r) or tostring(r)
	end
	return #parts > 0 and table.concat(parts, ",") or "(none)"
end

local function UIState(it)
	local mover = it:Mover()
	return string.format("selected=%s igi=%s mover_visible=%s camera_locks=%s",
		Name(SelectedObj), tostring(GetInGameInterfaceMode()),
		tostring(IsValid(mover) and it:Top().team and HasVisibilityTo(it:Top().team, mover)),
		ReasonsToString(CameraLockReasons()))
end
IIS.UIState = UIState

-- The mod environment blocks the debug library in release builds. GBO 4's notes say that the
-- identifier spelled d-b-g must not appear in mod code, so the local has another name.
local function ThreadStackLines(thread, max_frames)
	local trace_lib = rawget(_G, "debug")
	if not trace_lib or not trace_lib.getinfo then return { "(debug library not available in the mod environment)" } end
	if not thread then return { "(no thread)" } end
	local lines = {}
	for level = 0, max_frames or 20 do
		local ok, info = pcall(trace_lib.getinfo, thread, level, "Sln")
		if not ok or not info then break end
		lines[#lines + 1] = string.format("%s(%s) %s", tostring(info.short_src), tostring(info.currentline), tostring(info.name or "?"))
	end
	if #lines == 0 then lines[1] = "(empty stack, status " .. tostring(GetThreadStatus(thread)) .. ")" end
	return lines
end

local function RunsActionOrCommand(m)
	return HasCombatActionInProgress(m) or not m:IsIdleCommand()
end

IISInterrupt.Setup{
	now = function() return GameTime() end,
	in_combat = function() return not not g_Combat end,
	alive = function(u) return IsValid(u) and not u:IsDead() end,
	can_act = function(u) return IsValid(u) and not u:IsIncapacitated() end,
	busy = RunsActionOrCommand,
	ap_raw = function(u) return E.APRaw(u) end,
	walk_ap = function() return E.WalkRaw() end,
}

IISControl.Setup{
	sleep = function(ms) return Sleep(ms) end,
	can_yield = function() return CanYield() end,
}

function IIS.DumpStuck(it, why)
	local n, mover = it:Number(), it:Mover()
	Log("INT #%d STUCK? %s: mover cmd=%s interrupted=%s pain_thread=%s | %s", n, why,
		tostring(mover.command), tostring(mover.interrupted), tostring((IsValidThread(mover.pain_thread))), RunningStateSnapshot())
	for _, m in ipairs(it:Interrupters()) do
		if it:CanAct(m) and RunsActionOrCommand(m) then
			Log("INT #%d   merc %s cmd=%s idle=%s running=%s, command thread stack:", n, Name(m), tostring(m.command),
				tostring((m:IsIdleCommand())), tostring(CombatActions_RunningState[m]))
			for _, line in ipairs(ThreadStackLines(m.command_thread)) do
				Log("INT #%d     %s", n, line)
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- AI camera and visibility while the player has control

-- AIExecutionTrackUnits and AICinematicCombatCamera move the camera every 50 ms from these fields.
local ai_camera_fields = { "tracked_pois", "group_to_follow", "track_group", "cinematic_combat_camera" }

local function FieldToString(v)
	if type(v) == "table" then return "table#" .. #v end
	return tostring(v)
end

local function SuspendAICamera(it, sh)
	local ctrl = g_AIExecutionController
	if not ctrl then return end
	sh.ai_camera_ctrl = ctrl
	sh.ai_camera = {}
	local parts = {}
	for _, f in ipairs(ai_camera_fields) do
		sh.ai_camera[f] = ctrl[f]
		parts[#parts + 1] = string.format("%s=%s", f, FieldToString(ctrl[f]))
		ctrl[f] = false
	end
	Log("INT #%d AI camera tracking suspended: %s", it:Number(), table.concat(parts, " "))
end

local function RestoreAICamera(it, sh)
	local ctrl = sh.ai_camera_ctrl
	if not ctrl then return end
	if ctrl ~= g_AIExecutionController then
		Log("INT #%d AI camera tracking not restored: the AI controller changed", it:Number())
		return
	end
	for _, f in ipairs(ai_camera_fields) do
		ctrl[f] = sh.ai_camera[f]
	end
	Log("INT #%d AI camera tracking restored", it:Number())
end

local function BeginControl(it, sh)
	local mover, dummy = it:Mover(), sh.dummy

	-- CombatGoto points visibility_override at the path end when the enemy was hidden at the start.
	sh.saved_visibility_override = mover.visibility_override
	if type(dummy) == "table" and dummy.pos and not IsValid(dummy) then
		mover.visibility_override = dummy
	end
	VisibilityUpdate(true)

	sh.camera_locks = CameraLockReasons()
	UnlockCameraMovement(nil, "unlock_all")
	SuspendAICamera(it, sh)

	-- Fast forward applies while is_player_control is false (UpdateFastForwardGameSpeed).
	sh.saved_player_control = g_Combat.is_player_control
	g_Combat:SetPlayerControl(true)

	SelectObj(it:Top())
	if GetInGameInterfaceMode() ~= "IModeCombatMovement" then
		SetInGameInterfaceMode("IModeCombatMovement")
	end
end

------------------------------------------------------------------------------------------------
-- Interrupt lifecycle

-- IIS collective interrupts (Soldier Control.cpp:24960): teammates within 5 tiles of an original
-- winner join it by chance.
local function AddCollective(st_mercs, mover, n)
	local rc = IIS.RulesConfig()
	local originals = {}
	for i, m in ipairs(st_mercs) do
		originals[i] = m
	end
	local joined = {}
	for _, leader in ipairs(originals) do
		for _, mate in ipairs(E.PlayerUnits()) do
			local skip = table.find(st_mercs, mate) and "interrupter"
				or IIS.ObserverSkipReason(mate, mover) or IIS.WinSkipReason(mate, "IIS")
			if not skip then
				local dist = E.DistTiles(leader, mate:GetPos())
				if dist > rc.collective_radius then
					skip = string.format("%d tiles away (max %d)", dist, rc.collective_radius)
				end
			end
			if skip then
				if skip ~= "interrupter" then
					Log("INT #%d collective: %s -> %s skipped: %s", n, Name(leader), Name(mate), skip)
				end
			else
				local chance = R.CollectiveChance(
					{ leadership = leader:GetProperty("Leadership"), level = leader:GetLevel() },
					{ level = mate:GetLevel(), agility = mate:GetProperty("Agility"), wisdom = mate:GetProperty("Wisdom") })
				local roll = E.Rand(100)
				local ok = roll < chance
				Log("INT #%d collective: %s -> %s chance=%d roll=%d %s", n, Name(leader), Name(mate), chance, roll, ok and "JOINS" or "no")
				if ok then
					st_mercs[#st_mercs + 1] = mate
					joined[#joined + 1] = mate
				end
			end
		end
	end
	return joined
end

-- Returns the raw Free Move AP that the unit lost. The FreeMove status consumes the AP when it is
-- removed, and the second branch covers Free Move AP without the status.
function IIS.RemoveFreeMove(u)
	local free = u.free_move_ap or 0
	if free <= 0 then return 0 end
	u:RemoveStatusEffect("FreeMove")
	if (u.free_move_ap or 0) > 0 then
		u:ConsumeAP(u.free_move_ap)
		u.free_move_ap = 0
	end
	ObjModified(u)
	return free
end

function IIS.RunInterrupt(mover, info, dummy)
	local cfg = IIS.Config
	if type(info) ~= "table" or not info.mercs then
		Log("interrupt skipped: bad entry from an older version")
		return
	end
	if not can_yield() then
		Log("interrupt skipped: cannot Sleep in this thread (mover=%s)", Name(mover))
		return
	end
	if IIS.active then
		Log("interrupt skipped: INT #%d is still active", IIS.active:Number())
		return
	end
	if not IsValid(mover) or mover:IsDead() then
		Log("interrupt skipped: mover %s is gone", Name(mover))
		return
	end
	local mercs = {}
	for _, m in ipairs(info.mercs) do
		if IsValid(m) and not m:IsIncapacitated() and not IIS.WinSkipReason(m, info.system) then
			mercs[#mercs + 1] = m
		else
			Log("interrupt: winner %s can no longer act, dropped", Name(m))
		end
	end
	if #mercs == 0 then
		Log("interrupt skipped: no winner of check #%d can act", info.check or 0)
		return
	end

	IIS.interrupt_count = IIS.interrupt_count + 1
	local n = IIS.interrupt_count

	local winners = {}
	for i, m in ipairs(mercs) do
		winners[i] = m
	end
	local joined = {}
	if info.system == "IIS" and cfg.collective then
		SafeCall(nil, "collective", function()
			joined = AddCollective(mercs, mover, n)
		end)
	end
	SafeCall(nil, "IIS memory", function()
		local here = info.kind == "move" and dummy and dummy.pos or nil
		IIS.LogCommit(IISMemory.Fired(mover, mercs, here), "interrupt #" .. n, mover)
	end)

	local it = IISInterrupt.Begin{ n = n, mover = mover, winners = winners, joiners = joined, system = info.system,
		kind = info.kind, cfg = cfg }

	local in_cmd = E.InCommandThread(mover)
	Log("INT #%d BEGIN %s %s: mover=%s pos=%s ap=%s %s in_command_thread=%s", n, info.system, info.kind, Name(mover), Pos(mover),
		AP(mover), info.where or "", tostring(in_cmd))
	for i, m in ipairs(it:Interrupters()) do
		local joined_mark = table.find(joined, m) and " (collective)" or ""
		local free = 0
		SafeCall(nil, "RemoveFreeMove", function()
			free = IIS.RemoveFreeMove(m)
		end)
		local free_mark = free > 0 and string.format(" (free move %s removed)", IIS.FormatAP(free)) or ""
		Log("INT #%d   interrupter %d: %s ap=%s%s%s", n, i, Name(m), AP(m), joined_mark, free_mark)
	end
	SafeCall(nil, "before log", function()
		Log("INT #%d before: %s | ai_controller=%s awareness_pending=%s | %s", n, UIState(it),
			tostring(not not g_AIExecutionController), tostring(g_UnitAwarenessPending), RunningStateSnapshot())
	end)

	mover:InterruptBegin()
	-- InterruptBegin sets 3% animation speed for the overwatch slow motion. Hit reactions on the
	-- frozen enemy would then play 33 times slower.
	mover:SetAnimSpeedModifier(1000)
	if in_cmd then
		mover:PushDestructor(function()
			IIS.EndInterrupt(it, "mover_command_ended")
		end)
	end
	local sh = IIS.Activate(it, dummy)
	SafeCall(it, "BeginControl", BeginControl, it, sh)
	SafeCall(it, "UI.Begin", IIS.UI.Begin, it)
	SafeCall(it, "control log", function()
		Log("INT #%d control given: %s", n, UIState(it))
	end)

	local elapsed, next_heartbeat = 0, cfg.heartbeat_ms
	while IIS.active == it do
		local reason = IIS.CheckEnd(it)
		if reason then
			IIS.EndInterrupt(it, reason)
			break
		end
		sleep(100)
		elapsed = elapsed + 100
		SafeCall(it, "tick", IIS.Tick, it, elapsed)
		if elapsed >= next_heartbeat then
			next_heartbeat = next_heartbeat + cfg.heartbeat_ms
			SafeCall(it, "heartbeat", function()
				local aps = {}
				for _, m in ipairs(it:Interrupters()) do
					aps[#aps + 1] = string.format("%s=%s%s", Name(m), AP(m), it:CanAct(m) and RunsActionOrCommand(m) and "(busy)" or "")
				end
				local line = string.format("%s queue=%d end_requested=%s | %s | %s", table.concat(aps, " "), it:QueueLength(),
					tostring(it:HasEndRequest()), UIState(it), RunningStateSnapshot())
				if line ~= sh.wait_line or elapsed - sh.wait_logged >= cfg.heartbeat_repeat_ms then
					sh.wait_line, sh.wait_logged = line, elapsed
					Log("INT #%d waiting +%ss: %s", n, tostring(elapsed / 1000), line)
				end
			end)
		end
	end
	if in_cmd then
		mover:PopAndCallDestructor()
	end
	if cfg.after_interrupt == "stop" and it:Kind() == "move" then
		SafeCall(it, "StopMover", IIS.StopMover, it, sh.dummy)
	end
end

-- Returns the end reason code of IISInterrupt, or "end_check_error" when the check fails.
function IIS.CheckEnd(it)
	local ok, reason = SafeCall(it, "EndReason", it.EndReason, it)
	if not ok then
		return "end_check_error"
	end
	return reason
end

-- Runs every 100 ms of game time during an interrupt.
function IIS.Tick(it, elapsed)
	if it:Tick(100) then
		IIS.DumpStuck(it, string.format("a merc is busy for %sms", tostring(it:BusyMs())))
	end
	-- An interrupter that goes down must not stay selected.
	local sel = SelectedObj
	if IsKindOf(sel, "Unit") and it:IsInterrupter(sel) and not it:CanAct(sel) then
		local next_merc = it:Living()[1]
		if next_merc then
			Log("INT #%d %s is down, selecting %s", it:Number(), Name(sel), Name(next_merc))
			SelectObj(next_merc)
			IIS.UI.Refresh(it)
		end
	end
end

function IIS.EndInterrupt(it, reason)
	if IIS.active ~= it then return end
	IIS.active = false
	local n, mover, sh = it:Number(), it:Mover(), shell

	-- Queued actions that never started already paid their AP.
	for _, e in ipairs(it:Drain()) do
		SafeCall(it, "refund", function()
			local action_id, unit, ap = e.action_id, e.unit, e.ap
			if IsValid(unit) and (ap or 0) > 0 then
				unit:GainAP(ap)
			end
			Log("INT #%d dropped queued action %s of %s, refunded %s raw AP", n, tostring(action_id), Name(unit), tostring(ap))
		end)
	end

	SafeCall(it, "restore visibility", function()
		if IsValid(mover) then
			mover.visibility_override = sh.saved_visibility_override
		end
		VisibilityUpdate(true)
	end)
	SafeCall(it, "restore camera", function()
		for _, lock in ipairs(sh.camera_locks or empty_table) do
			LockCameraMovement(lock)
		end
		RestoreAICamera(it, sh)
	end)
	SafeCall(it, "restore player control", function()
		if g_Combat and sh.saved_player_control ~= nil then
			g_Combat:SetPlayerControl(sh.saved_player_control)
		end
	end)
	SafeCall(it, "UI.End", IIS.UI.End, it)

	local forced = {}
	for k, v in pairs(sh.forced) do
		forced[#forced + 1] = string.format("%s=%d", k, v)
	end
	table.sort(forced)
	local aps = {}
	for _, m in ipairs(it:Interrupters()) do
		aps[#aps + 1] = string.format("%s %s->%s", Name(m), IIS.FormatAP(sh.start_ap[m]), IsValid(m) and AP(m) or "?")
	end
	Log("INT #%d END (%s): %dms game time, actions=%d, ap: %s, forced: %s", n, reason, GameTime() - sh.start_time,
		it:Actions(), table.concat(aps, ", "), #forced > 0 and table.concat(forced, " ") or "(none)")
	SafeCall(it, "after log", function()
		Log("INT #%d after end: %s | %s", n, UIState(it), RunningStateSnapshot())
	end)
end

-- The enemy stays on the tile where the interrupt caught it and gets back the AP for the rest of
-- its path, like 1.13 (TeamTurns.cpp:1091). CombatGoto then sees a path of one tile and ends the
-- move. The path table is the local "path" of Unit:CombatGoto, so it changes in place.
function IIS.StopMover(it, dummy)
	local mover = it:Mover()
	if not IsValid(mover) or mover:IsDead() then return end
	if mover.command ~= "CombatGoto" or not E.InCommandThread(mover) then
		Log("INT #%d enemy %s not stopped: command is %s", it:Number(), Name(mover), tostring(mover.command))
		return
	end
	local path = mover.combat_path
	if type(path) ~= "table" or #path == 0 or type(dummy) ~= "table" or not dummy.pos then
		Log("INT #%d enemy %s not stopped: no path", it:Number(), Name(mover))
		return
	end
	-- A walk step between two path nodes can lie between tiles, and paths_ap has costs only for tiles.
	local tile = GetPassSlab(dummy.pos) or dummy.pos
	local here = point_pack(tile)
	local refund = 0
	local obj = mover.combat_path_obj
	if obj then
		local prev_cost = obj:GetAP(path[1])
		local new_cost = obj:GetAP(here)
		if not new_cost then
			Log("INT #%d enemy %s: no path cost at the stop tile %s, no refund", it:Number(), Name(mover), tostring(tile))
		end
		if prev_cost and new_cost and new_cost < prev_cost then
			refund = prev_cost - new_cost
			mover:GainAP(refund)
			-- Same free-move fix as Unit:CombatGotoInterrupt.
			if (mover.start_move_free_ap or 0) > 0 then
				local start_ui_ap = mover.start_move_total_ap - mover.start_move_free_ap
				mover.free_move_ap = Max(0, mover.ActionPoints - start_ui_ap)
			end
			ObjModified(mover)
		end
	end
	local steps_left = #path
	table.iclear(path)
	path[1] = here
	mover.iis_stopped = mover.command_thread
	Log("INT #%d enemy %s stops at %s (%d path nodes dropped), refund=%s AP, ap now %s", it:Number(), Name(mover),
		tostring(tile), steps_left - 1, IIS.FormatAP(refund), AP(mover))
end

-- The AI plays its attacks from ai_context.ai_destination (AIPlayAttacks, CombatAI.lua:211), so a
-- stopped enemy plans them from where it stands.
function IIS.OnStoppedMoverDone(unit)
	unit.iis_stopped = nil
	local ctx = unit.ai_context
	if ctx and ctx.ai_destination then
		local dest = GetPackedPosAndStance(unit)
		Log("enemy %s re-plans from its tile %s (old destination %s), ap=%s", Name(unit), Pos(unit),
			tostring(ctx.ai_destination), AP(unit))
		ctx.ai_destination = dest
	end
end

function IIS.RunMercAction(it, action_id, unit, ap, ...)
	if IIS.active ~= it then
		Log("INT #%d action %s not run: interrupt already ended", it:Number(), tostring(action_id))
		return
	end
	local count = it:ActionStarted()
	Log("INT #%d run action #%d %s merc=%s cost=%s ap_left=%s | %s", it:Number(), count, tostring(action_id), Name(unit),
		IIS.FormatAP(ap), AP(unit), RunningStateSnapshot())
	g_Combat:SetActiveUnit(unit)
	RunCombatAction(action_id, unit, ap, ...)
end

-- Starts queued interrupter actions by the vanilla rule of RunCombatActions, applied only to the
-- interrupters. The vanilla queue would wait for the frozen enemy's action, which does not end.
function IIS.TryRunQueue(it)
	if IIS.active ~= it then return end
	local function can_start(e)
		local states = {}
		for _, m in ipairs(it:Interrupters()) do
			local state = m ~= e.unit and CombatActions_RunningState[m]
			if state then
				states[#states + 1] = state
			end
		end
		return not CombatActions_RunningState[e.unit] and R.CanStartAction(e.simultaneous, states)
	end
	local function on_drop(e)
		Log("INT #%d dropped queued %s: the unit is gone", it:Number(), tostring(e.action_id))
	end
	local e = it:TakeNext(can_start, on_drop)
	while e do
		IIS.RunMercAction(it, unpack_params(e.packed))
		e = it:TakeNext(can_start, on_drop)
	end
end

------------------------------------------------------------------------------------------------
-- Overrides. Each one changes behavior only while an interrupt is active.

local orig_IsNetPlayerTurn = IsNetPlayerTurn
function IsNetPlayerTurn(...)
	if IIS.active then
		Forced("IsNetPlayerTurn")
		return true
	end
	return orig_IsNetPlayerTurn(...)
end

-- Vanilla refuses every unit while g_AIExecutionController exists. During an interrupt, the
-- interrupters can be controlled and the other player units cannot.
local orig_CanBeControlled = Unit.CanBeControlled
function Unit:CanBeControlled(...)
	local it = IIS.active
	if it and self.team and self.team.control == "UI" then
		if it:CanAct(self) then
			Forced("CanBeControlled")
			return true
		end
		return false, "iis_not_interrupter"
	end
	return orig_CanBeControlled(self, ...)
end

-- Vanilla refuses while any unit has an action that is not in PostAction, and the frozen enemy's
-- action never gets there during the interrupt. Only the interrupters count here.
local orig_CombatActionCannotBeStarted = CombatActionCannotBeStarted
function CombatActionCannotBeStarted(action_id, unit)
	local it = IIS.active
	if it and g_Combat and it:IsInterrupter(unit) then
		for _, m in ipairs(it:Interrupters()) do
			local state = CombatActions_RunningState[m]
			if state and state ~= "PostAction" then
				return true
			end
		end
		return false
	end
	return orig_CombatActionCannotBeStarted(action_id, unit)
end

local orig_NetStartCombatAction = NetStartCombatAction
function NetStartCombatAction(action_id, unit, ap, args, ...)
	local it = IIS.active
	if not it then
		return orig_NetStartCombatAction(action_id, unit, ap, args, ...)
	end
	SafeCall(it, "NetStartCombatAction log", function()
		Log("INT #%d NetStartCombatAction %s unit=%s ap=%s | cannot_start=%s vanilla_turn=%s controllable=%s ui_has_ap=%s awareness_pending=%s",
			it:Number(), tostring(action_id), Name(unit), tostring(ap),
			tostring(CombatActionCannotBeStarted(action_id, unit)), tostring(orig_IsNetPlayerTurn()),
			tostring(unit and unit:CanBeControlled()), tostring(unit and ap and unit:UIHasAP(ap, action_id, args)),
			tostring(g_UnitAwarenessPending))
	end)
	local result = orig_NetStartCombatAction(action_id, unit, ap, args, ...)
	Log("INT #%d NetStartCombatAction %s result=%s", it:Number(), tostring(action_id), tostring(result))
	return result
end

local orig_StartCombatAction = StartCombatAction
function StartCombatAction(action_id, unit, ap, ...)
	local it = IIS.active
	if not (it and g_Combat and it:IsInterrupter(unit)) then
		return orig_StartCombatAction(action_id, unit, ap, ...)
	end
	unit:ConsumeAP(ap, action_id, ...)
	local action = CombatActions[action_id]
	it:Enqueue{ action_id = action_id, unit = unit, ap = ap, simultaneous = action and action.SimultaneousPlay or false,
		packed = pack_params(action_id, unit, ap, ...) }
	IIS.TryRunQueue(it)
	local waiting = it:QueueLength()
	if waiting > 0 then
		Log("INT #%d queued %s: %d waiting | %s", it:Number(), tostring(action_id), waiting, RunningStateSnapshot())
	end
end

local function OnInterrupterActionStep(unit, what)
	local it = IIS.active
	if not it or not it:IsInterrupter(unit) then return end
	it:Activity()
	if what == "end" then
		Log("INT #%d merc %s action ended: ap_left=%s pos=%s status=%s | %s", it:Number(), Name(unit), AP(unit), Pos(unit),
			IIS.StatusList(unit), RunningStateSnapshot())
		SafeCall(it, "UI.Refresh", IIS.UI.Refresh, it)
		-- The frozen enemy's running action suspends VisibilityUpdate (Visibility.lua:1110), so a
		-- merc that moved would not see new enemies without a forced update.
		SafeCall(it, "VisibilityUpdate", VisibilityUpdate, true)
	end
	if it:QueueLength() > 0 then
		CreateGameTimeThread(IIS.TryRunQueue, it)
	end
end

function OnMsg.CombatActionEnd(unit)
	IIS.TraceEnemyActionEnd(unit)
	OnInterrupterActionStep(unit, "end")
end

function OnMsg.CombatPostAction(unit)
	OnInterrupterActionStep(unit, "post")
end

-- Unit:FirearmAttack (and GBO 4's copy of it) waits until its target is idle, and the frozen
-- enemy stays in its command until the interrupt ends.
local orig_IsIdleOrRunningBehavior = Unit.IsIdleOrRunningBehavior
function Unit:IsIdleOrRunningBehavior(...)
	local it = IIS.active
	if it and self == it:Mover() then
		Forced("TargetIdle")
		return true
	end
	return orig_IsIdleOrRunningBehavior(self, ...)
end

-- A unit with an interrupt on its path waits for every other running action, and the frozen
-- enemy waits for the interrupt. An interrupter waits only for the other interrupters.
local orig_WaitOtherCombatActionsEnd = WaitOtherCombatActionsEnd
function WaitOtherCombatActionsEnd(unit)
	local it = IIS.active
	if not (it and it:IsInterrupter(unit)) then
		return orig_WaitOtherCombatActionsEnd(unit)
	end
	Log("INT #%d WaitOtherCombatActionsEnd for %s waits for the other interrupters only | %s", it:Number(), Name(unit), RunningStateSnapshot())
	while IIS.active == it do
		local wait = false
		for _, m in ipairs(it:Interrupters()) do
			if m ~= unit and CombatActions_RunningState[m] and HasCombatActionInProgress(m) then
				wait = true
				break
			end
		end
		if not wait then
			return
		end
		WaitMsg("CombatActionEnd", 200)
	end
end

-- The click handler returns early unless the current team is UI-controlled
-- (IModeCombatMovement.lua:522).
local orig_OnMouseButtonDown = IModeCombatMovement.OnMouseButtonDown
function IModeCombatMovement:OnMouseButtonDown(pt, button, obj)
	local it = IIS.active
	if not it or not g_Teams or not it:Top().team then
		return orig_OnMouseButtonDown(self, pt, button, obj)
	end
	local prev = g_CurrentTeam
	local player_idx = table.find(g_Teams, it:Top().team)
	IIS.Verbose("INT #%d click %s on %s: g_CurrentTeam %s -> %s during the handler", it:Number(), tostring(button),
		obj and Name(obj) or "ground", tostring(prev), tostring(player_idx))
	g_CurrentTeam = player_idx
	local ok, result = pcall(orig_OnMouseButtonDown, self, pt, button, obj)
	g_CurrentTeam = prev
	if not ok then
		Log("INT #%d click handler error: %s", it:Number(), tostring(result))
		error(result)
	end
	return result
end

local orig_EndTurn = NetSyncEvents.EndTurn
function NetSyncEvents.EndTurn(player_id, ...)
	local it = IIS.active
	if it and player_id == netUniqueId then
		local press = it:EndTurnPressed()
		if press == "requested" then
			local busy = it:Busy()
			Log("INT #%d end requested (End Turn). busy=%s", it:Number(), tostring(busy))
			if busy then
				SafeCall(it, "UI.Refresh", IIS.UI.Refresh, it)
			end
		elseif press == "forced" then
			SafeCall(it, "DumpStuck", IIS.DumpStuck, it, "End Turn pressed again while a merc is busy")
			for _, m in ipairs(it:Living()) do
				if not m:IsIdleCommand() then
					Log("INT #%d sending merc %s to Idle (was %s)", it:Number(), Name(m), tostring(m.command))
					m:SetCommand("Idle")
				end
			end
		end
		return
	end
	return orig_EndTurn(player_id, ...)
end

-- Vanilla marks the local player as done with the turn as soon as End Turn is pressed.
local orig_EndTurnLocal = NetSyncLocalEffects.EndTurn
function NetSyncLocalEffects.EndTurn(...)
	if IIS.active then return end
	return orig_EndTurnLocal(...)
end

function OnMsg.CanSaveGameQuery(query)
	if IIS.active then
		query.iis_interrupt = true
	end
end

-- Portraits and number keys already ask CanBeControlled. This catches any other way to select a
-- player unit that is not an interrupter.
function OnMsg.SelectionChange()
	local it = IIS.active
	if not it then return end
	local sel = SelectedObj
	if IsKindOf(sel, "Unit") and sel.team and sel.team.control == "UI" and not it:IsInterrupter(sel) then
		CreateRealTimeThread(function()
			if IIS.active ~= it then return end
			local m = it:Living()[1]
			if m and SelectedObj ~= m and not it:IsInterrupter(SelectedObj) then
				Log("INT #%d %s is not an interrupter, selecting %s", it:Number(), Name(sel), Name(m))
				SelectObj(m)
			end
		end)
	end
end

IIS.control_hooks = {
	{ "IsNetPlayerTurn", function() return IsNetPlayerTurn end, IsNetPlayerTurn },
	{ "CanBeControlled", function() return Unit.CanBeControlled end, Unit.CanBeControlled },
	{ "CannotBeStarted", function() return CombatActionCannotBeStarted end, CombatActionCannotBeStarted },
	{ "NetStartCombatAction", function() return NetStartCombatAction end, NetStartCombatAction },
	{ "StartCombatAction", function() return StartCombatAction end, StartCombatAction },
	{ "WaitOtherCombatActionsEnd", function() return WaitOtherCombatActionsEnd end, WaitOtherCombatActionsEnd },
	{ "IsIdleOrRunningBehavior", function() return Unit.IsIdleOrRunningBehavior end, Unit.IsIdleOrRunningBehavior },
	{ "OnMouseButtonDown", function() return IModeCombatMovement.OnMouseButtonDown end, IModeCombatMovement.OnMouseButtonDown },
	{ "EndTurn", function() return NetSyncEvents.EndTurn end, NetSyncEvents.EndTurn },
}

local orig_HookStatus = IIS.HookStatus
function IIS.HookStatus()
	local replaced = {}
	for _, h in ipairs(IIS.control_hooks) do
		if h[2]() ~= h[3] then
			replaced[#replaced + 1] = h[1]
		end
	end
	return string.format("%s control_hooks=%s %s", orig_HookStatus(),
		#replaced == 0 and "ours" or ("REPLACED:" .. table.concat(replaced, ",")),
		IIS.UI and IIS.UI.HookStatus and IIS.UI.HookStatus() or "")
end

Log("control loaded: %s", IIS.HookStatus())
