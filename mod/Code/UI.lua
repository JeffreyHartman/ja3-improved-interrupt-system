-- Improved Interrupt System UI: the interrupt banner, the portrait marks, the camera and the
-- sounds. Control.lua calls UI.Begin, UI.Refresh and UI.End; each call runs under pcall there.

IIS.UI = IIS.UI or {}
local UI = IIS.UI
local Log, Name = IIS.Log, IIS.Name

-- A TacticalNotification is the banner at the top center of the screen ("Enemy Turn"). A lower
-- SortKey wins, and the enemy turn banners use 0 or more.
local banner_id = "iisInterrupt"
local banner_sort_key = -1000

local tag_styles = {
	interrupter = { text = "INTERRUPT", background = RGBA(255, 196, 40, 255) },
	locked = { text = "LOCKED", background = RGBA(150, 146, 136, 235) },
}
local interrupter_glow = RGBA(255, 196, 40, 255)

local function DisplayName(unit)
	local ok, text = pcall(function()
		return _InternalTranslate(unit:GetDisplayName())
	end)
	if ok and type(text) == "string" and text ~= "" then
		return text
	end
	return tostring(unit.session_id or unit.class)
end
UI.DisplayName = DisplayName

local function NamesText(units)
	local parts = {}
	for _, u in ipairs(units) do
		parts[#parts + 1] = DisplayName(u)
	end
	if #parts < 2 then
		return parts[1] or ""
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

------------------------------------------------------------------------------------------------
-- Banner

-- Game data reloads can drop a preset made by mod code, so each show checks for it.
function UI.EnsureBannerPreset()
	local group = Presets.TacticalNotification and Presets.TacticalNotification.Default
	if group and group[banner_id] then
		return true
	end
	PlaceObj("TacticalNotification", {
		group = "Default",
		id = banner_id,
		SortKey = banner_sort_key,
		style = "yellow",
		text = Untranslated("INTERRUPT!"),
	})
	group = Presets.TacticalNotification and Presets.TacticalNotification.Default
	local ok = group and group[banner_id] and true or false
	Log("UI banner preset registered: %s", tostring(ok))
	return ok
end

-- Returns true when the banner shows.
function UI.ShowBanner()
	if not UI.EnsureBannerPreset() then
		return false
	end
	ShowTacticalNotification(banner_id, true)
	return true
end

function UI.HideBanner()
	HideTacticalNotification(banner_id)
end

------------------------------------------------------------------------------------------------
-- Portraits

-- "interrupter", "locked" or nil for a portrait context.
function UI.PortraitMark(unit)
	local it = IIS.active
	if not it or not IsKindOf(unit, "Unit") or not unit.team or unit.team.control ~= "UI" or unit:IsDead() then
		return
	end
	if it:CanAct(unit) then
		return "interrupter"
	end
	return "locked"
end

local function EnsureTag(win)
	local tag = win.iis_tag
	if tag and tag.window_state ~= "destroying" and tag.parent then
		return tag
	end
	local parent = win.idPortraitBG
	if not parent then
		return
	end
	tag = XText:new({
		HAlign = "center",
		VAlign = "top",
		Margins = box(0, 2, 0, 0),
		Padding = box(4, 0, 4, 0),
		ZOrder = 10,
		DrawOnTop = true,
		HandleMouse = false,
		Clip = false,
		UseClipBox = false,
		TextStyle = "HUDHeaderDarkSmall",
		Translate = false,
		TextHAlign = "center",
	}, parent)
	if parent.window_state == "open" then
		tag:Open()
	end
	win.iis_tag = tag
	return tag
end

local function ApplyMark(win, mark)
	if mark == "locked" then
		win.idPortraitBG:SetDesaturation(255)
		win.idPortrait:SetDesaturation(255)
		win:SetTransparency(110)
	elseif mark == "interrupter" then
		win.idPortraitBG:SetDesaturation(0)
		win.idPortrait:SetDesaturation(0)
		win:SetTransparency(0)
		-- SetupStyle never sets the glow size, so the mark keeps the old one to put back.
		if win.iis_glow_size == nil then
			win.iis_glow_size = win.idContent.BackgroundRectGlowSize
		end
		win.idContent:SetBackground(interrupter_glow)
		win.idContent:SetBackgroundRectGlowSize(2)
		win.idContent:SetBackgroundRectGlowColor(interrupter_glow)
	end
	local tag = EnsureTag(win)
	if tag then
		local style = tag_styles[mark]
		tag:SetText(style.text)
		tag:SetBackground(style.background)
		tag:SetVisible(true)
	end
end

local orig_SetupStyle = HUDMercClass.SetupStyle
function HUDMercClass:SetupStyle(...)
	local ok, mark = pcall(UI.PortraitMark, self.context)
	mark = ok and mark or nil
	-- SetupStyle returns early when its style string did not change, so a mark change clears it.
	if mark ~= self.iis_mark then
		self.style = false
	end
	local result = orig_SetupStyle(self, ...)
	self.iis_mark = mark
	if mark then
		local applied, err = pcall(ApplyMark, self, mark)
		if not applied then
			Log("UI portrait mark %s failed for %s: %s", tostring(mark), Name(self.context), tostring(err))
		end
	else
		if self.iis_tag and self.iis_tag.window_state ~= "destroying" then
			self.iis_tag:SetVisible(false)
		end
		if self.iis_glow_size ~= nil then
			self.idContent:SetBackgroundRectGlowSize(self.iis_glow_size)
			self.iis_glow_size = nil
		end
	end
	return result
end
UI.setup_style_hook = HUDMercClass.SetupStyle

-- Each HUD portrait listens to its unit, so ObjModified runs its OnContextUpdate and SetupStyle.
function UI.RefreshPortraits()
	local n = 0
	for _, u in ipairs(GetAllPlayerUnitsOnMap() or empty_table) do
		if IsValid(u) then
			ObjModified(u)
			n = n + 1
		end
	end
	return n
end

------------------------------------------------------------------------------------------------
-- Camera

function UI.FocusCamera(it)
	if CurrentActionCamera then
		return "action camera playing"
	end
	local mover = it:Mover()
	if IsValid(mover) then
		SnapCameraToObj(mover:GetVisualPos(), "force", GetFloorOfPos(mover:GetPosXYZ()))
		return "enemy"
	end
	local merc = it:Top()
	SnapCameraToObj(merc:GetVisualPos(), "force", GetFloorOfPos(merc:GetPosXYZ()))
	return "merc"
end

------------------------------------------------------------------------------------------------
-- Calls from Control.lua

function UI.Begin(it)
	local safe = IIS.SafeCall
	local banner_shown = false
	safe(it, "UI banner", function()
		banner_shown = UI.ShowBanner()
	end)
	local portraits = 0
	safe(it, "UI portraits", function()
		portraits = UI.RefreshPortraits()
	end)
	local camera = "?"
	safe(it, "UI camera", function()
		camera = UI.FocusCamera(it)
	end)
	safe(it, "UI sound", PlayFX, "PlayerCombatTurnStart", "start")
	safe(it, "UI floating text", function()
		for _, m in ipairs(it:Interrupters()) do
			CreateFloatingText(m, Untranslated("INTERRUPT!"), "FloatingTextMiss")
		end
		CreateFloatingText(it:Mover(), Untranslated("Interrupted"), "FloatingTextMiss")
	end)
	safe(it, "UI combat log", function()
		local units = it:Interrupters()
		CombatLog("important", T{Untranslated("<names> <verb> <mover>."), names = NamesText(units),
			verb = #units == 1 and "interrupts" or "interrupt", mover = it:Mover():GetLogName()})
	end)
	Log("INT #%d UI shown: banner=%s portraits_refreshed=%d camera=%s", it:Number(), tostring(banner_shown),
		portraits, tostring(camera))
end

-- Called when an action ends, a merc goes down or End Turn is pressed.
function UI.Refresh(it)
	if IIS.active ~= it then
		return
	end
	local safe = IIS.SafeCall
	safe(it, "UI banner", UI.ShowBanner)
	safe(it, "UI portraits", UI.RefreshPortraits)
end

function UI.End(it)
	local safe = IIS.SafeCall
	safe(it, "UI banner", UI.HideBanner)
	-- IIS.active is already false here, so the portraits go back to vanilla.
	safe(it, "UI portraits", UI.RefreshPortraits)
	safe(it, "UI sound", PlayFX, "PlayerCombatTurnEnd", "start")
	safe(it, "UI combat log", function()
		CombatLog("important", Untranslated("Interrupt over."))
	end)
	Log("INT #%d UI cleared", it:Number())
end

function UI.HookStatus()
	local replaced = {}
	if HUDMercClass.SetupStyle ~= UI.setup_style_hook then
		replaced[#replaced + 1] = "SetupStyle"
	end
	return "ui_hooks=" .. (#replaced == 0 and "ours" or ("REPLACED:" .. table.concat(replaced, ",")))
end

function OnMsg.ModsReloaded()
	IIS.SafeCall(nil, "UI preset", UI.EnsureBannerPreset)
	IIS.SafeCall(nil, "attack trace", IIS.HookAttackTrace)
	IIS.SafeCall(nil, "mod list", IIS.LogLoadedMods)
	Log("ModsReloaded: IIS %s active, %s", IIS.version, IIS.HookStatus())
end

Log("UI loaded: %s", UI.HookStatus())
