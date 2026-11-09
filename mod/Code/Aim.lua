-- Improved Interrupt System: the wrap of Unit:GetBaseAimLevelRange that lowers the maximum aim
-- level of an interrupter to the aim limit of the active interrupt's request.

local R = IISRules
local Log = IIS.Log

-- `percent` of `max` aim levels, rounded up, and never below `min`.
local function LimitedMax(min, max, percent)
	local limit = R.idiv(max * percent + 99, 100)
	if limit >= max then return max end
	return limit > min and limit or min
end

--- Wraps Unit:GetBaseAimLevelRange, unless the wrap is already in place.
-- GBO 4 replaces the function when its code loads, which can be after this mod, so this runs on
-- ModsReloaded.
function IIS.HookAimRange()
	if Unit.GetBaseAimLevelRange == IIS.aim_hook then return end
	local orig = Unit.GetBaseAimLevelRange
	IIS.aim_hook = function(self, action, target, ...)
		local it = IISControl.Active()
		local percent = it and it:IsInterrupter(self) and IISControl.Request().aim_limit
		if not percent then
			return orig(self, action, target, ...)
		end
		local min, max = orig(self, action, target, ...)
		local ok, limited = pcall(LimitedMax, min, max, percent)
		if not ok then
			Log("INT #%s aim limit failed: %s", tostring(it:Number()), tostring(limited))
			return min, max
		end
		return min, limited
	end
	Unit.GetBaseAimLevelRange = IIS.aim_hook
end

function OnMsg.ModsReloaded()
	IIS.SafeCall(nil, "aim range hook", IIS.HookAimRange)
	Log("aim range hook: %s", Unit.GetBaseAimLevelRange == IIS.aim_hook and "ours" or "REPLACED")
end
