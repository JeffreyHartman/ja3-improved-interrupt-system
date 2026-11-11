-- Improved Interrupt System: the wrap of Unit:GetBaseAimLevelRange that changes the aim range of an
-- interrupter: it raises the minimum to the free aim levels and lowers the maximum to the aim limit
-- of the active interrupt's request.

local R = IISRules
local Log = IIS.Log

-- `percent` of `max` aim levels, rounded up, and never below `min`.
local function LimitedMax(min, max, percent)
	local limit = R.idiv(max * percent + 99, 100)
	if limit >= max then return max end
	return limit > min and limit or min
end

-- The aim range of interrupter `unit` under request `req`, from the range `min`, `max` of the game.
-- Vanilla Unit:GetAttackAPCost charges only for the levels above the minimum, so the free levels
-- cost no AP.
local function InterrupterRange(req, unit, action, target, min, max)
	if req.free_aim then
		local free = req.free_aim(unit, action, target)
		if free > min then
			min = free < max and free or max
		end
	end
	if req.aim_limit then
		max = LimitedMax(min, max, req.aim_limit)
	end
	return min, max
end

--- Wraps Unit:GetBaseAimLevelRange, unless the wrap is already in place.
-- GBO 4 replaces the function when its code loads, which can be after this mod, so this runs on
-- ModsReloaded.
function IIS.HookAimRange()
	if Unit.GetBaseAimLevelRange == IIS.aim_hook then return end
	local orig = Unit.GetBaseAimLevelRange
	IIS.aim_hook = function(self, action, target, ...)
		local it = IISControl.Active()
		local req = it and it:IsInterrupter(self) and IISControl.Request()
		if not (req and (req.aim_limit or req.free_aim)) then
			return orig(self, action, target, ...)
		end
		local min, max = orig(self, action, target, ...)
		local ok, new_min, new_max = pcall(InterrupterRange, req, self, action, target, min, max)
		if not ok then
			Log("INT #%s aim range failed: %s", tostring(it:Number()), tostring(new_min))
			return min, max
		end
		return new_min, new_max
	end
	Unit.GetBaseAimLevelRange = IIS.aim_hook
end

function OnMsg.ModsReloaded()
	IIS.SafeCall(nil, "aim range hook", IIS.HookAimRange)
	Log("aim range hook: %s", Unit.GetBaseAimLevelRange == IIS.aim_hook and "ours" or "REPLACED")
end
