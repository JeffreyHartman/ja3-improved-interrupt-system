-- Tests for the combat log text of IIS.UI.Begin and IIS.UI.End (mod/Code/UI.lua).
-- run.lua runs this file after test_engine.lua, which loads IIS.lua and Control.lua. The fakes
-- here cover only what UI.lua needs to load and what UI.Begin and UI.End call.

local t = Test

function RGBA(r, g, b, a)
	return { r, g, b, a }
end
HUDMercClass = { SetupStyle = function() end }
-- The debug build of JA3 logs a Lua error when a T{} parameter is a plain string, so the fake T fails on one.
local UntranslatedMeta = { __tostring = function(u) return u.s end }
function Untranslated(s)
	return setmetatable({ s = s }, UntranslatedMeta)
end
function T(o)
	local text = getmetatable(o[1]) == UntranslatedMeta and o[1].s or o[1]
	return (text:gsub("<(%w+)>", function(k)
		if type(o[k]) == "string" then
			error("T{} parameter '" .. k .. "' is a plain string", 0)
		end
		return tostring(o[k])
	end))
end
function HideTacticalNotification() end
function GetAllPlayerUnitsOnMap() return {} end
function PlayFX() end

local combat_log = {}
function CombatLog(kind, text)
	combat_log[#combat_log + 1] = text
end

dofile("mod/Code/UI.lua")

local function Merc(name)
	return { session_id = name }
end

local function BeginText(names)
	combat_log = {}
	local interrupters = {}
	for i, name in ipairs(names) do
		interrupters[i] = Merc(name)
	end
	local mover = { GetLogName = function() return Untranslated("Legion Goon") end }
	IIS.UI.Begin(IISInterrupt.Begin{ n = 1, mover = mover, interrupters = interrupters, cfg = IIS.Config })
	return combat_log[1]
end

t.case("UI.Begin: the combat log names the interrupters and the enemy", function()
	t.eq(BeginText({ "Pie" }), "Pie interrupts Legion Goon.")
	t.eq(BeginText({ "Pie", "Livewire" }), "Pie and Livewire interrupt Legion Goon.")
	t.eq(BeginText({ "Pie", "Livewire", "Blood" }), "Pie, Livewire and Blood interrupt Legion Goon.")
end)

t.case("UI.End: the combat log text is the same for every end reason", function()
	combat_log = {}
	IIS.UI.End(IISInterrupt.Begin{ n = 1, mover = {}, interrupters = {}, cfg = IIS.Config })
	t.eq(tostring(combat_log[1]), "Interrupt over.")
end)

t.case("UI.Begin: a request banner shows its label and the interrupter names in place of INTERRUPT!", function()
	local shown = {}
	Presets = { TacticalNotification = { Default = { iisInterrupt = true } } }
	function ShowTacticalNotification(id, keep, text) shown[#shown + 1] = text or "preset" end
	local it = IISInterrupt.Begin{ n = 1, mover = { GetLogName = function() return "Legion Goon" end },
		interrupters = { Merc("Pie") }, cfg = IIS.Config }
	IIS.UI.Begin(it, "Overwatch")
	IIS.UI.Begin(it)
	IIS.UI.Begin(IISInterrupt.Begin{ n = 2, mover = { GetLogName = function() return "Legion Goon" end },
		interrupters = { Merc("Pie"), Merc("Livewire") }, cfg = IIS.Config }, "Overwatch")
	Presets, ShowTacticalNotification = nil, nil
	t.eq(tostring(shown[1]), "Overwatch: Pie")
	t.eq(shown[2], "preset")
	t.eq(tostring(shown[3]), "Overwatch: Pie and Livewire")
end)
