-- Quickdraw UI: the interrupt banner, the portrait marks, the End Turn label, the camera and the
-- sounds. Control.lua calls UI.Begin, UI.Refresh and UI.End; each call runs under pcall there.

Quickdraw.UI = Quickdraw.UI or {}
local UI = Quickdraw.UI
local Log, Name = Quickdraw.Log, Quickdraw.Name

-- A TacticalNotification is the banner at the top center of the screen ("Enemy Turn"). A lower
-- SortKey wins, and the enemy turn banners use 0 or more.
local banner_id = "quickdrawInterrupt"
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
	return table.concat(parts, ", ")
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
		secondaryText = Untranslated("<names> can act. <mover> waits.<newline><hint>"),
	})
	group = Presets.TacticalNotification and Presets.TacticalNotification.Default
	local ok = group and group[banner_id] and true or false
	Log("UI banner preset registered: %s", tostring(ok))
	return ok
end

local function BannerHint(st)
	if st.end_requested then
		return "Ending the interrupt when the current action is done."
	end
	return "Only they can be selected. End Turn resumes the enemy turn."
end

function UI.ShowBanner(st)
	if not UI.EnsureBannerPreset() then
		return
	end
	-- ShowTacticalNotification ignores a mode that is already shown, so a new text needs a hide first.
	HideTacticalNotification(banner_id, true)
	local living = Quickdraw.LivingInterrupters(st)
	ShowTacticalNotification(banner_id, true, nil, {
		names = NamesText(#living > 0 and living or st.mercs),
		mover = DisplayName(st.mover),
		hint = BannerHint(st),
	})
	st.banner_shown = true
end

function UI.HideBanner()
	HideTacticalNotification(banner_id)
end

------------------------------------------------------------------------------------------------
-- Portraits

-- "interrupter", "locked" or nil for a portrait context.
function UI.PortraitMark(unit)
	local st = Quickdraw.active
	if not st or not IsKindOf(unit, "Unit") or not unit.team or unit.team.control ~= "UI" or unit:IsDead() then
		return
	end
	if st.is_merc[unit] and not unit:IsIncapacitated() then
		return "interrupter"
	end
	return "locked"
end

local function EnsureTag(win)
	local tag = win.qd_tag
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
	win.qd_tag = tag
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
		if win.qd_glow_size == nil then
			win.qd_glow_size = win.idContent.BackgroundRectGlowSize
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
	if mark ~= self.qd_mark then
		self.style = false
	end
	local result = orig_SetupStyle(self, ...)
	self.qd_mark = mark
	if mark then
		local applied, err = pcall(ApplyMark, self, mark)
		if not applied then
			Log("UI portrait mark %s failed for %s: %s", tostring(mark), Name(self.context), tostring(err))
		end
	else
		if self.qd_tag and self.qd_tag.window_state ~= "destroying" then
			self.qd_tag:SetVisible(false)
		end
		if self.qd_glow_size ~= nil then
			self.idContent:SetBackgroundRectGlowSize(self.qd_glow_size)
			self.qd_glow_size = nil
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
-- End Turn button

local function EndTurnLabel(st)
	return st.end_requested and "ENDING..." or "END INTERRUPT"
end

local function WrapEndTurnUpdate(orig)
	return function(self, context, ...)
		local result
		if orig then
			result = orig(self, context, ...)
		end
		local st = Quickdraw.active
		if st and self.idLargeText then
			self.idLargeText:SetText(Untranslated(EndTurnLabel(st)))
		end
		return result
	end
end

local function FindTemplateNode(node, id)
	if type(node) ~= "table" then
		return
	end
	if node.Id == id then
		return node
	end
	for _, child in ipairs(node) do
		local found = FindTemplateNode(child, id)
		if found then
			return found
		end
	end
end

-- The idTurn button of XTemplates.IModeCombatMovement sets "END TURN" in its OnContextUpdate.
-- New HUDs copy the wrapped function from the template node.
function UI.PatchEndTurnTemplate()
	local template = rawget(_G, "XTemplates") and XTemplates.IModeCombatMovement
	local node = template and FindTemplateNode(template, "idTurn")
	if not node then
		Log("UI: idTurn not found in XTemplates.IModeCombatMovement, the End Turn label stays vanilla")
		return false
	end
	if not node.qd_patched then
		node.OnContextUpdate = WrapEndTurnUpdate(node.OnContextUpdate)
		node.qd_patched = true
		Log("UI: End Turn button template patched")
	end
	UI.end_turn_node = node
	return true
end

-- A HUD that was open before the template patch keeps the old function, so its button gets the
-- same wrapper.
local function LiveEndTurnButton()
	local dlg = GetInGameInterfaceModeDlg()
	local frame = dlg and rawget(dlg, "idEndTurnFrame")
	return frame and rawget(frame, "idTurn")
end

function UI.RefreshEndTurnButton()
	local button = LiveEndTurnButton()
	if button and not button.qd_patched then
		button.OnContextUpdate = WrapEndTurnUpdate(button.OnContextUpdate)
		button.qd_patched = true
	end
	ObjModified(Selection)
	return button and true or false
end

------------------------------------------------------------------------------------------------
-- Camera

local camera_midpoint_tiles = 20

function UI.FocusCamera(st)
	if CurrentActionCamera then
		return "action camera playing"
	end
	local merc, mover = st.top, st.mover
	local target = merc:GetVisualPos()
	local how = "merc"
	if IsValid(mover) and merc:GetDist(mover) <= camera_midpoint_tiles * const.SlabSizeX then
		target = (merc:GetVisualPos() + mover:GetVisualPos()) / 2
		how = "midpoint"
	end
	SnapCameraToObj(target, "force", GetFloorOfPos(merc:GetPosXYZ()))
	return how
end

------------------------------------------------------------------------------------------------
-- Calls from Control.lua

function UI.Begin(st)
	local safe = Quickdraw.SafeCall
	safe(st, "UI patch", UI.PatchEndTurnTemplate)
	safe(st, "UI banner", UI.ShowBanner, st)
	local portraits = 0
	safe(st, "UI portraits", function()
		portraits = UI.RefreshPortraits()
	end)
	local live_button = false
	safe(st, "UI end turn", function()
		live_button = UI.RefreshEndTurnButton()
	end)
	local camera = "?"
	safe(st, "UI camera", function()
		camera = UI.FocusCamera(st)
	end)
	safe(st, "UI sound", PlayFX, "PlayerCombatTurnStart", "start")
	safe(st, "UI floating text", function()
		for _, m in ipairs(st.mercs) do
			CreateFloatingText(m, Untranslated("INTERRUPT!"), "FloatingTextMiss")
		end
		CreateFloatingText(st.mover, Untranslated("Interrupted"), "FloatingTextMiss")
	end)
	safe(st, "UI combat log", function()
		CombatLog("important", T{Untranslated("<names> interrupt <mover>! End Turn resumes the enemy turn."),
			names = NamesText(st.mercs), mover = st.mover:GetLogName()})
	end)
	Log("INT #%d UI shown: banner=%s portraits_refreshed=%d end_turn_button=%s camera=%s", st.n, tostring(not not st.banner_shown),
		portraits, live_button and "live" or "not found", tostring(camera))
end

-- Called when an action ends, a merc goes down or End Turn is pressed.
function UI.Refresh(st)
	if Quickdraw.active ~= st then
		return
	end
	local safe = Quickdraw.SafeCall
	safe(st, "UI banner", UI.ShowBanner, st)
	safe(st, "UI portraits", UI.RefreshPortraits)
	safe(st, "UI end turn", UI.RefreshEndTurnButton)
end

function UI.End(st, reason)
	local safe = Quickdraw.SafeCall
	safe(st, "UI banner", UI.HideBanner)
	-- Quickdraw.active is already false here, so the portraits and the button go back to vanilla.
	safe(st, "UI portraits", UI.RefreshPortraits)
	safe(st, "UI end turn", UI.RefreshEndTurnButton)
	safe(st, "UI sound", PlayFX, "PlayerCombatTurnEnd", "start")
	safe(st, "UI combat log", function()
		CombatLog("important", T{Untranslated("Interrupt over (<reason>). The enemy turn continues."), reason = reason})
	end)
	Log("INT #%d UI cleared", st.n)
end

function UI.HookStatus()
	local replaced = {}
	if HUDMercClass.SetupStyle ~= UI.setup_style_hook then
		replaced[#replaced + 1] = "SetupStyle"
	end
	if UI.end_turn_node and UI.end_turn_node.qd_patched ~= true then
		replaced[#replaced + 1] = "EndTurnButton"
	end
	return "ui_hooks=" .. (#replaced == 0 and "ours" or ("REPLACED:" .. table.concat(replaced, ",")))
end

function OnMsg.ModsReloaded()
	Quickdraw.SafeCall(nil, "UI patch", UI.PatchEndTurnTemplate)
	Quickdraw.SafeCall(nil, "UI preset", UI.EnsureBannerPreset)
	Quickdraw.SafeCall(nil, "attack trace", Quickdraw.HookAttackTrace)
	Quickdraw.SafeCall(nil, "mod list", Quickdraw.LogLoadedMods)
	Log("ModsReloaded: Quickdraw %s active, %s", Quickdraw.version, Quickdraw.HookStatus())
end

Quickdraw.SafeCall(nil, "UI patch", UI.PatchEndTurnTemplate)
Log("UI loaded: %s", UI.HookStatus())
