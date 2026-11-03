-- Tests for the combat log text of IIS.UI.End (mod/Code/UI.lua).
-- run.lua runs this file after test_engine.lua, which loads IIS.lua and Control.lua. The fakes
-- here cover only what UI.lua needs to load and what UI.End calls.

local t = Test

function RGBA(r, g, b, a)
	return { r, g, b, a }
end
HUDMercClass = { SetupStyle = function() end }
function Untranslated(s)
	return s
end
function T(o)
	return (o[1]:gsub("<(%w+)>", function(k) return tostring(o[k]) end))
end
function HideTacticalNotification() end
function GetAllPlayerUnitsOnMap() return {} end
function PlayFX() end

local combat_log = {}
function CombatLog(kind, text)
	combat_log[#combat_log + 1] = text
end

dofile("mod/Code/UI.lua")

local function EndText(code)
	combat_log = {}
	IIS.UI.End(IISInterrupt.Begin{ n = 1, mover = {}, winners = {}, system = "IIS", kind = "move", cfg = IIS.Config }, code)
	return combat_log[1]
end

t.case("UI.End: the combat log text for each end reason code", function()
	local expected = {
		combat_ended = "combat ended",
		mover_dead = "enemy dead",
		interrupters_down = "all interrupters are down",
		forced_end = "forced: End Turn pressed again while a merc was busy",
		end_request = "player ended the interrupt",
		auto_end = "interrupters are out of AP (auto end)",
		end_check_error = "error in EndReason",
		mover_command_ended = "enemy command ended (destructor)",
	}
	for code, reason in pairs(expected) do
		t.eq(EndText(code), "Interrupt over (" .. reason .. "). The enemy turn continues.", code)
	end
end)
