-- Sets claude_auto_hooks for the ja3-play auto-player (lua/autoplay.lua of the ja3-play skill) from IISControl.Active and IIS.WinSkipReason.
-- Run it with the skill's lua.py before autoplay.lua, once after each launch.
local m = table.find_value(ModsLoaded, "id", "ImprovedInterruptSystem")
if not m then return "ImprovedInterruptSystem is not loaded" end
local env = m.env
claude_auto_hooks = {
	interrupt_active = function() return env.IISControl.Active() end,
	note = env.IIS.WinSkipReason and function(enemy) return env.IIS.WinSkipReason(enemy, "IIS") or "can_win" end,
}
return "hooks set for IIS " .. tostring(m.version)
