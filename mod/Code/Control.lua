-- Quickdraw: runs an interrupt. The frozen enemy's command thread waits in RunInterrupt while the
-- interrupters take orders. End Turn (Enter) ends the interrupt. The overrides at the end of the
-- file change behavior only while Quickdraw.active is set.

local R = QuickdrawRules
local E = Quickdraw.E
local Log, Name, AP, Pos, NameList = Quickdraw.Log, Quickdraw.Name, Quickdraw.AP, Quickdraw.Pos, Quickdraw.NameList

Quickdraw.active = false
Quickdraw.interrupt_count = Quickdraw.interrupt_count or 0

local function IsInterrupter(unit)
	local st = Quickdraw.active
	return st and unit and st.is_merc[unit] or false
end
Quickdraw.IsInterrupter = IsInterrupter

local function Forced(st, what)
	st.forced[what] = (st.forced[what] or 0) + 1
end

local function Living(st)
	local list = {}
	for _, m in ipairs(st.mercs) do
		if IsValid(m) and not m:IsIncapacitated() then
			list[#list + 1] = m
		end
	end
	return list
end
Quickdraw.LivingInterrupters = Living

-- An error in code that runs in the frozen enemy's command thread ends the enemy's command, so
-- everything that is not the wait itself runs under pcall.
local function SafeCall(st, what, f, ...)
	local ok, err = pcall(f, ...)
	if not ok then
		Log("INT #%s %s failed: %s", st and tostring(st.n) or "-", what, tostring(err))
	end
	return ok, err
end
Quickdraw.SafeCall = SafeCall

local function RunningStateSnapshot()
	local parts = {}
	for u, state in pairs(CombatActions_RunningState or empty_table) do
		parts[#parts + 1] = string.format("%s=%s", Name(u), tostring(state))
	end
	table.sort(parts)
	return string.format("running={%s} waiting=%d", table.concat(parts, " "), #(CombatActions_Waiting or empty_table))
end
Quickdraw.RunningStateSnapshot = RunningStateSnapshot

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

local function UIState(st)
	local mover = st.mover
	return string.format("selected=%s igi=%s mover_visible=%s camera_locks=%s",
		Name(SelectedObj), tostring(GetInGameInterfaceMode()),
		tostring(IsValid(mover) and st.top.team and HasVisibilityTo(st.top.team, mover)),
		ReasonsToString(CameraLockReasons()))
end
Quickdraw.UIState = UIState

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

local function MercBusy(m)
	return IsValid(m) and not m:IsIncapacitated() and (HasCombatActionInProgress(m) or not m:IsIdleCommand())
end

local function AnyBusy(st)
	if #st.queue > 0 then
		return true
	end
	for _, m in ipairs(st.mercs) do
		if MercBusy(m) then
			return true
		end
	end
	return false
end
Quickdraw.AnyBusy = AnyBusy

function Quickdraw.DumpStuck(st, why)
	local mover = st.mover
	Log("INT #%d STUCK? %s: mover cmd=%s interrupted=%s pain_thread=%s | %s", st.n, why,
		tostring(mover.command), tostring(mover.interrupted), tostring((IsValidThread(mover.pain_thread))), RunningStateSnapshot())
	for _, m in ipairs(st.mercs) do
		if MercBusy(m) then
			Log("INT #%d   merc %s cmd=%s idle=%s running=%s, command thread stack:", st.n, Name(m), tostring(m.command),
				tostring((m:IsIdleCommand())), tostring(CombatActions_RunningState[m]))
			for _, line in ipairs(ThreadStackLines(m.command_thread)) do
				Log("INT #%d     %s", st.n, line)
			end
		end
	end
end

-- No interrupter can take one step, so nothing is left to do.
local function OutOfAP(st)
	local walk = E.WalkRaw()
	for _, m in ipairs(Living(st)) do
		if E.APRaw(m) >= walk then
			return false
		end
	end
	return true
end

local function StopReason(st)
	local cfg = Quickdraw.Config
	if not g_Combat then return "combat ended" end
	if not IsValid(st.mover) or st.mover:IsDead() then return "enemy dead" end
	if #Living(st) == 0 then return "all interrupters are down" end
	if st.force_end then return "forced: End Turn pressed again while a merc was busy" end
	local busy = AnyBusy(st)
	if st.end_requested and not busy then return "player ended the interrupt" end
	if cfg.auto_end and st.actions > 0 and not busy and OutOfAP(st)
		and GameTime() - st.last_activity >= cfg.auto_end_delay_ms then
		return "interrupters are out of AP (auto end)"
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

local function SuspendAICamera(st)
	local ctrl = g_AIExecutionController
	if not ctrl then return end
	st.ai_camera_ctrl = ctrl
	st.ai_camera = {}
	local parts = {}
	for _, f in ipairs(ai_camera_fields) do
		st.ai_camera[f] = ctrl[f]
		parts[#parts + 1] = string.format("%s=%s", f, FieldToString(ctrl[f]))
		ctrl[f] = false
	end
	Log("INT #%d AI camera tracking suspended: %s", st.n, table.concat(parts, " "))
end

local function RestoreAICamera(st)
	local ctrl = st.ai_camera_ctrl
	if not ctrl then return end
	if ctrl ~= g_AIExecutionController then
		Log("INT #%d AI camera tracking not restored: the AI controller changed", st.n)
		return
	end
	for _, f in ipairs(ai_camera_fields) do
		ctrl[f] = st.ai_camera[f]
	end
	Log("INT #%d AI camera tracking restored", st.n)
end

local function BeginControl(st)
	local mover, dummy = st.mover, st.dummy

	-- CombatGoto points visibility_override at the path end when the enemy was hidden at the start.
	st.saved_visibility_override = mover.visibility_override
	if type(dummy) == "table" and dummy.pos and not IsValid(dummy) then
		mover.visibility_override = dummy
	end
	VisibilityUpdate(true)

	st.camera_locks = CameraLockReasons()
	UnlockCameraMovement(nil, "unlock_all")
	SuspendAICamera(st)

	-- Fast forward applies while is_player_control is false (UpdateFastForwardGameSpeed).
	st.saved_player_control = g_Combat.is_player_control
	g_Combat:SetPlayerControl(true)

	SelectObj(st.top)
	if GetInGameInterfaceMode() ~= "IModeCombatMovement" then
		SetInGameInterfaceMode("IModeCombatMovement")
	end
end

------------------------------------------------------------------------------------------------
-- Interrupt lifecycle

-- IIS collective interrupts (Soldier Control.cpp:24960): teammates within 5 tiles of an original
-- winner join it by chance.
local function AddCollective(st_mercs, mover, n)
	local rc = Quickdraw.RulesConfig()
	local originals = {}
	for i, m in ipairs(st_mercs) do
		originals[i] = m
	end
	local joined = {}
	for _, leader in ipairs(originals) do
		for _, mate in ipairs(E.PlayerUnits()) do
			if not table.find(st_mercs, mate) and not Quickdraw.ObserverSkipReason(mate, mover)
				and not Quickdraw.WinSkipReason(mate, "IIS") and E.DistTiles(leader, mate:GetPos()) <= rc.collective_radius then
				local chance = R.CollectiveChance(
					{ leadership = leader:GetProperty("Leadership"), level = leader:GetLevel() },
					{ level = mate:GetLevel(), agility = mate:GetProperty("Agility"), wisdom = mate:GetProperty("Wisdom") })
				local roll = E.Rand(100)
				local ok = roll < chance
				Log("INT #%d collective: %s -> %s chance=%d roll=%d %s", n, Name(leader), Name(mate), chance, roll, ok and "JOINS" or "no")
				if ok then
					st_mercs[#st_mercs + 1] = mate
					joined[#joined + 1] = mate
					Quickdraw.ResetCounter(mate, mover)
				end
			end
		end
	end
	return joined
end

function Quickdraw.RunInterrupt(mover, info, dummy)
	local cfg = Quickdraw.Config
	if type(info) ~= "table" or not info.mercs then
		Log("interrupt skipped: bad entry from an older version")
		return
	end
	if not CanYield() then
		Log("interrupt skipped: cannot Sleep in this thread (mover=%s)", Name(mover))
		return
	end
	if Quickdraw.active then
		Log("interrupt skipped: INT #%d is still active", Quickdraw.active.n)
		return
	end
	if not IsValid(mover) or mover:IsDead() then
		Log("interrupt skipped: mover %s is gone", Name(mover))
		return
	end
	local mercs = {}
	for _, m in ipairs(info.mercs) do
		if IsValid(m) and not m:IsIncapacitated() and not Quickdraw.WinSkipReason(m, info.system) then
			mercs[#mercs + 1] = m
		else
			Log("interrupt: winner %s can no longer act, dropped", Name(m))
		end
	end
	if #mercs == 0 then
		Log("interrupt skipped: no winner of check #%d can act", info.check or 0)
		return
	end

	Quickdraw.interrupt_count = Quickdraw.interrupt_count + 1
	local n = Quickdraw.interrupt_count

	local joined = {}
	if info.system == "IIS" then
		SafeCall(nil, "IIS commit", function()
			if info.kind == "move" then
				Quickdraw.CommitPlan(info.plan, info.step, "interrupt #" .. n)
			end
			for _, m in ipairs(mercs) do
				Quickdraw.ResetCounter(m, mover)
			end
		end)
		if cfg.collective then
			SafeCall(nil, "collective", function()
				joined = AddCollective(mercs, mover, n)
			end)
		end
	end
	SafeCall(nil, "seen marks", function()
		local mem = Quickdraw.Memory()
		for _, m in ipairs(mercs) do
			Quickdraw.Mark(mem.seen_turn, m, mover)
			Quickdraw.Mark(mem.seen_ever, m, mover)
		end
	end)

	local st = {
		n = n,
		mover = mover,
		mercs = mercs,
		is_merc = {},
		top = mercs[1],
		joined = joined,
		kind = info.kind,
		system = info.system,
		info = info,
		dummy = dummy,
		start_time = GameTime(),
		start_ap = {},
		end_requested = false,
		force_end = false,
		queue = {},
		actions = 0,
		forced = {},
		last_activity = GameTime(),
	}
	for _, m in ipairs(mercs) do
		st.is_merc[m] = true
		st.start_ap[m] = E.APRaw(m)
	end

	local in_cmd = E.InCommandThread(mover)
	Log("INT #%d BEGIN %s %s: mover=%s pos=%s ap=%s %s in_command_thread=%s", n, info.system, info.kind, Name(mover), Pos(mover),
		AP(mover), info.where or "", tostring(in_cmd))
	for i, m in ipairs(mercs) do
		local joined_mark = table.find(joined, m) and " (collective)" or ""
		Log("INT #%d   interrupter %d: %s ap=%s%s", n, i, Name(m), AP(m), joined_mark)
	end
	SafeCall(nil, "before log", function()
		Log("INT #%d before: %s | ai_controller=%s awareness_pending=%s | %s", n, UIState(st),
			tostring(not not g_AIExecutionController), tostring(g_UnitAwarenessPending), RunningStateSnapshot())
	end)

	mover:InterruptBegin()
	-- InterruptBegin sets 3% animation speed for the overwatch slow motion. Hit reactions on the
	-- frozen enemy would then play 33 times slower.
	mover:SetAnimSpeedModifier(1000)
	if in_cmd then
		mover:PushDestructor(function()
			Quickdraw.EndInterrupt(st, "enemy command ended (destructor)")
		end)
	end
	Quickdraw.active = st
	SafeCall(st, "BeginControl", BeginControl, st)
	SafeCall(st, "UI.Begin", Quickdraw.UI.Begin, st)
	SafeCall(st, "control log", function()
		Log("INT #%d control given: %s", n, UIState(st))
	end)

	local elapsed, next_heartbeat = 0, cfg.heartbeat_ms
	while Quickdraw.active == st do
		local ok, reason = SafeCall(st, "StopReason", StopReason, st)
		if not ok then
			reason = "error in StopReason"
		end
		if reason then
			Quickdraw.EndInterrupt(st, reason)
			break
		end
		Sleep(100)
		elapsed = elapsed + 100
		SafeCall(st, "tick", Quickdraw.Tick, st, elapsed)
		if elapsed >= next_heartbeat then
			next_heartbeat = next_heartbeat + cfg.heartbeat_ms
			SafeCall(st, "heartbeat", function()
				local aps = {}
				for _, m in ipairs(st.mercs) do
					aps[#aps + 1] = string.format("%s=%s%s", Name(m), AP(m), MercBusy(m) and "(busy)" or "")
				end
				Log("INT #%d waiting +%ss: %s queue=%d end_requested=%s | %s | %s", st.n, tostring(elapsed / 1000),
					table.concat(aps, " "), #st.queue, tostring(st.end_requested), UIState(st), RunningStateSnapshot())
			end)
		end
	end
	if in_cmd then
		mover:PopAndCallDestructor()
	end
	if cfg.after_interrupt == "stop" and st.kind == "move" then
		SafeCall(st, "StopMover", Quickdraw.StopMover, st)
	end
end

-- Runs every 100 ms of game time during an interrupt.
function Quickdraw.Tick(st, elapsed)
	local cfg = Quickdraw.Config
	if AnyBusy(st) then
		st.last_activity = GameTime()
		st.busy_ms = (st.busy_ms or 0) + 100
		if st.busy_ms >= (st.next_dump_ms or cfg.stuck_ms) then
			st.next_dump_ms = st.busy_ms + 10000
			Quickdraw.DumpStuck(st, string.format("a merc is busy for %sms", tostring(st.busy_ms)))
		end
	else
		st.busy_ms, st.next_dump_ms = 0, nil
	end
	-- An interrupter that goes down must not stay selected.
	local sel = SelectedObj
	if IsKindOf(sel, "Unit") and st.is_merc[sel] and sel:IsIncapacitated() then
		local next_merc = Living(st)[1]
		if next_merc then
			Log("INT #%d %s is down, selecting %s", st.n, Name(sel), Name(next_merc))
			SelectObj(next_merc)
			Quickdraw.UI.Refresh(st)
		end
	end
end

function Quickdraw.EndInterrupt(st, reason)
	if Quickdraw.active ~= st then return end
	Quickdraw.active = false
	local mover = st.mover

	-- Queued actions that never started already paid their AP.
	for _, p in ipairs(st.queue) do
		SafeCall(st, "refund", function()
			local action_id, unit, ap = unpack_params(p, 1, 3)
			if IsValid(unit) and (ap or 0) > 0 then
				unit:GainAP(ap)
			end
			Log("INT #%d dropped queued action %s of %s, refunded %s raw AP", st.n, tostring(action_id), Name(unit), tostring(ap))
		end)
	end
	st.queue = {}

	SafeCall(st, "restore visibility", function()
		if IsValid(mover) then
			mover.visibility_override = st.saved_visibility_override
		end
		VisibilityUpdate(true)
	end)
	SafeCall(st, "restore camera", function()
		for _, lock in ipairs(st.camera_locks or empty_table) do
			LockCameraMovement(lock)
		end
		RestoreAICamera(st)
	end)
	SafeCall(st, "restore player control", function()
		if g_Combat and st.saved_player_control ~= nil then
			g_Combat:SetPlayerControl(st.saved_player_control)
		end
	end)
	SafeCall(st, "UI.End", Quickdraw.UI.End, st, reason)

	local forced = {}
	for k, v in pairs(st.forced) do
		forced[#forced + 1] = string.format("%s=%d", k, v)
	end
	table.sort(forced)
	local aps = {}
	for _, m in ipairs(st.mercs) do
		aps[#aps + 1] = string.format("%s %s->%s", Name(m), Quickdraw.FormatAP(st.start_ap[m]), IsValid(m) and AP(m) or "?")
	end
	Log("INT #%d END (%s): %dms game time, actions=%d, ap: %s, forced: %s", st.n, reason, GameTime() - st.start_time,
		st.actions, table.concat(aps, ", "), #forced > 0 and table.concat(forced, " ") or "(none)")
	SafeCall(st, "after log", function()
		Log("INT #%d after end: %s | %s", st.n, UIState(st), RunningStateSnapshot())
	end)
end

-- The enemy stays on the tile where the interrupt caught it and gets back the AP for the rest of
-- its path, like 1.13 (TeamTurns.cpp:1091). CombatGoto then sees a path of one tile and ends the
-- move. The path table is the local "path" of Unit:CombatGoto, so it changes in place.
function Quickdraw.StopMover(st)
	local mover, dummy = st.mover, st.dummy
	if not IsValid(mover) or mover:IsDead() then return end
	if mover.command ~= "CombatGoto" or not E.InCommandThread(mover) then
		Log("INT #%d enemy %s not stopped: command is %s", st.n, Name(mover), tostring(mover.command))
		return
	end
	local path = mover.combat_path
	if type(path) ~= "table" or #path == 0 or type(dummy) ~= "table" or not dummy.pos then
		Log("INT #%d enemy %s not stopped: no path", st.n, Name(mover))
		return
	end
	local here = point_pack(dummy.pos)
	local refund = 0
	local obj = mover.combat_path_obj
	if obj then
		local prev_cost = obj:GetAP(path[1])
		local new_cost = obj:GetAP(here)
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
	mover.qd_stopped = mover.command_thread
	Log("INT #%d enemy %s stops at %s (%d path nodes dropped), refund=%s AP, ap now %s", st.n, Name(mover),
		tostring(dummy.pos), steps_left - 1, Quickdraw.FormatAP(refund), AP(mover))
end

-- The AI plays its attacks from ai_context.ai_destination (AIPlayAttacks, CombatAI.lua:211), so a
-- stopped enemy plans them from where it stands.
function Quickdraw.OnStoppedMoverDone(unit)
	unit.qd_stopped = nil
	local ctx = unit.ai_context
	if ctx and ctx.ai_destination then
		local dest = GetPackedPosAndStance(unit)
		Log("enemy %s re-plans from its tile %s (old destination %s), ap=%s", Name(unit), Pos(unit),
			tostring(ctx.ai_destination), AP(unit))
		ctx.ai_destination = dest
	end
end

function Quickdraw.RunMercAction(st, action_id, unit, ap, ...)
	if Quickdraw.active ~= st then
		Log("INT #%d action %s not run: interrupt already ended", st.n, tostring(action_id))
		return
	end
	st.actions = st.actions + 1
	st.last_activity = GameTime()
	Log("INT #%d run action #%d %s merc=%s cost=%s ap_left=%s | %s", st.n, st.actions, tostring(action_id), Name(unit),
		Quickdraw.FormatAP(ap), AP(unit), RunningStateSnapshot())
	g_Combat:SetActiveUnit(unit)
	RunCombatAction(action_id, unit, ap, ...)
end

-- Starts queued interrupter actions by the vanilla rule of RunCombatActions, applied only to the
-- interrupters. The vanilla queue would wait for the frozen enemy's action, which does not end.
function Quickdraw.TryRunQueue(st)
	if Quickdraw.active ~= st then return end
	local i = 1
	while i <= #st.queue do
		local p = st.queue[i]
		local action_id, unit = unpack_params(p, 1, 2)
		local action = CombatActions[action_id]
		local simultaneous = action and action.SimultaneousPlay or false
		if not IsValid(unit) or unit:IsDead() then
			table.remove(st.queue, i)
			Log("INT #%d dropped queued %s: the unit is gone", st.n, tostring(action_id))
		else
			local states = {}
			for _, m in ipairs(st.mercs) do
				local state = m ~= unit and CombatActions_RunningState[m]
				if state then
					states[#states + 1] = state
				end
			end
			if not CombatActions_RunningState[unit] and R.CanStartAction(simultaneous, states) then
				table.remove(st.queue, i)
				Quickdraw.RunMercAction(st, unpack_params(p))
			else
				i = i + 1
				if not simultaneous then
					break
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- Overrides. Each one changes behavior only while an interrupt is active.

local orig_IsNetPlayerTurn = IsNetPlayerTurn
function IsNetPlayerTurn(...)
	local st = Quickdraw.active
	if st then
		Forced(st, "IsNetPlayerTurn")
		return true
	end
	return orig_IsNetPlayerTurn(...)
end

-- Vanilla refuses every unit while g_AIExecutionController exists. During an interrupt, the
-- interrupters can be controlled and the other player units cannot.
local orig_CanBeControlled = Unit.CanBeControlled
function Unit:CanBeControlled(...)
	local st = Quickdraw.active
	if st and self.team and self.team.control == "UI" then
		if st.is_merc[self] and IsValid(self) and not self:IsIncapacitated() then
			Forced(st, "CanBeControlled")
			return true
		end
		return false, "quickdraw_not_interrupter"
	end
	return orig_CanBeControlled(self, ...)
end

-- Vanilla refuses while any unit has an action that is not in PostAction, and the frozen enemy's
-- action never gets there during the interrupt. Only the interrupters count here.
local orig_CombatActionCannotBeStarted = CombatActionCannotBeStarted
function CombatActionCannotBeStarted(action_id, unit)
	local st = Quickdraw.active
	if st and g_Combat and IsInterrupter(unit) then
		for _, m in ipairs(st.mercs) do
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
	local st = Quickdraw.active
	if not st then
		return orig_NetStartCombatAction(action_id, unit, ap, args, ...)
	end
	SafeCall(st, "NetStartCombatAction log", function()
		Log("INT #%d NetStartCombatAction %s unit=%s ap=%s | cannot_start=%s vanilla_turn=%s controllable=%s ui_has_ap=%s awareness_pending=%s",
			st.n, tostring(action_id), Name(unit), tostring(ap),
			tostring(CombatActionCannotBeStarted(action_id, unit)), tostring(orig_IsNetPlayerTurn()),
			tostring(unit and unit:CanBeControlled()), tostring(unit and ap and unit:UIHasAP(ap, action_id, args)),
			tostring(g_UnitAwarenessPending))
	end)
	local result = orig_NetStartCombatAction(action_id, unit, ap, args, ...)
	Log("INT #%d NetStartCombatAction %s result=%s", st.n, tostring(action_id), tostring(result))
	return result
end

local orig_StartCombatAction = StartCombatAction
function StartCombatAction(action_id, unit, ap, ...)
	local st = Quickdraw.active
	if not (st and g_Combat and IsInterrupter(unit)) then
		return orig_StartCombatAction(action_id, unit, ap, ...)
	end
	unit:ConsumeAP(ap, action_id, ...)
	table.insert(st.queue, pack_params(action_id, unit, ap, ...))
	st.last_activity = GameTime()
	Quickdraw.TryRunQueue(st)
	if #st.queue > 0 then
		Log("INT #%d queued %s: %d waiting | %s", st.n, tostring(action_id), #st.queue, RunningStateSnapshot())
	end
end

local function OnInterrupterActionStep(unit, what)
	local st = Quickdraw.active
	if not st or not st.is_merc[unit] then return end
	st.last_activity = GameTime()
	if what == "end" then
		Log("INT #%d merc %s action ended: ap_left=%s pos=%s | %s", st.n, Name(unit), AP(unit), Pos(unit), RunningStateSnapshot())
		SafeCall(st, "UI.Refresh", Quickdraw.UI.Refresh, st)
		-- The frozen enemy's running action suspends VisibilityUpdate (Visibility.lua:1110), so a
		-- merc that moved would not see new enemies without a forced update.
		SafeCall(st, "VisibilityUpdate", VisibilityUpdate, true)
	end
	if #st.queue > 0 then
		CreateGameTimeThread(Quickdraw.TryRunQueue, st)
	end
end

function OnMsg.CombatActionEnd(unit)
	OnInterrupterActionStep(unit, "end")
end

function OnMsg.CombatPostAction(unit)
	OnInterrupterActionStep(unit, "post")
end

-- Unit:FirearmAttack (and GBO 4's copy of it) waits until its target is idle, and the frozen
-- enemy stays in its command until the interrupt ends.
local orig_IsIdleOrRunningBehavior = Unit.IsIdleOrRunningBehavior
function Unit:IsIdleOrRunningBehavior(...)
	local st = Quickdraw.active
	if st and self == st.mover then
		Forced(st, "TargetIdle")
		return true
	end
	return orig_IsIdleOrRunningBehavior(self, ...)
end

-- A unit with an interrupt on its path waits for every other running action, and the frozen
-- enemy waits for the interrupt. An interrupter waits only for the other interrupters.
local orig_WaitOtherCombatActionsEnd = WaitOtherCombatActionsEnd
function WaitOtherCombatActionsEnd(unit)
	local st = Quickdraw.active
	if not (st and IsInterrupter(unit)) then
		return orig_WaitOtherCombatActionsEnd(unit)
	end
	Log("INT #%d WaitOtherCombatActionsEnd for %s waits for the other interrupters only | %s", st.n, Name(unit), RunningStateSnapshot())
	while Quickdraw.active == st do
		local wait = false
		for _, m in ipairs(st.mercs) do
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
	local st = Quickdraw.active
	if not st or not g_Teams or not st.top.team then
		return orig_OnMouseButtonDown(self, pt, button, obj)
	end
	local prev = g_CurrentTeam
	local player_idx = table.find(g_Teams, st.top.team)
	Quickdraw.Verbose("INT #%d click %s on %s: g_CurrentTeam %s -> %s during the handler", st.n, tostring(button),
		obj and Name(obj) or "ground", tostring(prev), tostring(player_idx))
	g_CurrentTeam = player_idx
	local ok, result = pcall(orig_OnMouseButtonDown, self, pt, button, obj)
	g_CurrentTeam = prev
	if not ok then
		Log("INT #%d click handler error: %s", st.n, tostring(result))
		error(result)
	end
	return result
end

local orig_EndTurn = NetSyncEvents.EndTurn
function NetSyncEvents.EndTurn(player_id, ...)
	local st = Quickdraw.active
	if st and player_id == netUniqueId then
		if not st.end_requested then
			st.end_requested = true
			Log("INT #%d end requested (End Turn). busy=%s", st.n, tostring(AnyBusy(st)))
			if AnyBusy(st) then
				SafeCall(st, "UI.Refresh", Quickdraw.UI.Refresh, st)
			end
		elseif AnyBusy(st) and not st.force_end then
			SafeCall(st, "DumpStuck", Quickdraw.DumpStuck, st, "End Turn pressed again while a merc is busy")
			st.force_end = true
			for _, m in ipairs(Living(st)) do
				if not m:IsIdleCommand() then
					Log("INT #%d sending merc %s to Idle (was %s)", st.n, Name(m), tostring(m.command))
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
	if Quickdraw.active then return end
	return orig_EndTurnLocal(...)
end

function OnMsg.CanSaveGameQuery(query)
	if Quickdraw.active then
		query.quickdraw_interrupt = true
	end
end

-- Portraits and number keys already ask CanBeControlled. This catches any other way to select a
-- player unit that is not an interrupter.
function OnMsg.SelectionChange()
	local st = Quickdraw.active
	if not st then return end
	local sel = SelectedObj
	if IsKindOf(sel, "Unit") and sel.team and sel.team.control == "UI" and not st.is_merc[sel] then
		CreateRealTimeThread(function()
			if Quickdraw.active ~= st then return end
			local m = Living(st)[1]
			if m and SelectedObj ~= m and not st.is_merc[SelectedObj] then
				Log("INT #%d %s is not an interrupter, selecting %s", st.n, Name(sel), Name(m))
				SelectObj(m)
			end
		end)
	end
end

Quickdraw.control_hooks = {
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

local orig_HookStatus = Quickdraw.HookStatus
function Quickdraw.HookStatus()
	local replaced = {}
	for _, h in ipairs(Quickdraw.control_hooks) do
		if h[2]() ~= h[3] then
			replaced[#replaced + 1] = h[1]
		end
	end
	return string.format("%s control_hooks=%s %s", orig_HookStatus(),
		#replaced == 0 and "ours" or ("REPLACED:" .. table.concat(replaced, ",")),
		Quickdraw.UI and Quickdraw.UI.HookStatus and Quickdraw.UI.HookStatus() or "")
end

Log("control loaded: %s", Quickdraw.HookStatus())
