-- Improved Interrupt System: the "Moving target" to-hit modifier for a shot by an interrupter at
-- the mover of the active interrupt. It follows the design of the vanilla EvasiveMovement
-- modifier, which vanilla turns off (Data/ChanceToHitModifier.lua:246).

local R = IISRules
local E = IIS.E

local max_dist_tiles = 10
local cos_scale = 1000

function E.XY(p)
	return p:xy()
end

-- JA3's Lua truncates "/" on integers, so the to-hit math stays in integers.
local function isqrt(n)
	if n < 2 then return n end
	local x, y = n, R.idiv(n + 1, 2)
	while y < x do
		x, y = y, R.idiv(y + R.idiv(n, y), 2)
	end
	return x
end

-- The penalty points (0 or more) for a move of (mx, my) seen along a line of fire (sx, sy).
local function Penalty(max, mx, my, sx, sy)
	local dist = isqrt(mx * mx + my * my)
	local lof = isqrt(sx * sx + sy * sy)
	if max <= 0 or dist == 0 or lof == 0 then
		return 0
	end
	local cos = R.idiv(math.abs(mx * sx + my * sy) * cos_scale, dist * lof)
	local max_dist = max_dist_tiles * const.SlabSizeX
	local num = max * (cos_scale - cos) * math.min(dist, max_dist)
	local den = cos_scale * max_dist
	return R.idiv(2 * num + den, 2 * den)
end

-- Vanilla and GBO 4 name each reflex sight component with "Reflex" in its id, for example
-- ReflexSightAdvanced and RAT_TOG_Reflex. Vanilla has no component effect for it.
local function HasReflexSight(weapon)
	for _, id in pairs(weapon and weapon.components or empty_table) do
		if type(id) == "string" and id:lower():find("reflex", 1, true) then
			return true
		end
	end
	return false
end

local function MoveStart(unit)
	local rec = unit.iis_move_start
	return rec and rec.thread == unit.command_thread and rec.pos or nil
end

function OnMsg.UnitAnyMovementStart(unit)
	local rec = unit.iis_move_start
	if not rec or rec.thread ~= unit.command_thread then
		unit.iis_move_start = { thread = unit.command_thread, pos = unit:GetVisualPos() }
	end
end

local function CalcValue(self, attacker, target, body_part_def, action, weapon1, weapon2, lof, aim,
	opportunity_attack, attacker_pos, target_pos)
	local it = IISControl.Active()
	if not it or not it:IsInterrupter(attacker) or target ~= it:Mover() then
		return false, 0
	end
	local start = MoveStart(target)
	if not start or HasReflexSight(weapon1) then
		return false, 0
	end
	local cx, cy = E.XY(target:GetVisualPos())
	local sx, sy = E.XY(start)
	local ax, ay = E.XY(attacker_pos or attacker:GetPos())
	local points = Penalty(IIS.Config.moving_target_penalty or 0, cx - sx, cy - sy, cx - ax, cy - ay)
	if points == 0 then
		return false, 0
	end
	return true, -points
end

local modifier_id = "IISMovingTarget"

-- Game data reloads can drop a preset made by mod code, so each data load places it again.
local function EnsureModifier()
	local group = Presets.ChanceToHitModifier and Presets.ChanceToHitModifier.Default
	if group and group[modifier_id] then
		return
	end
	PlaceObj("ChanceToHitModifier", {
		CalcValue = CalcValue,
		RequireTarget = true,
		RequireActionType = "Any Ranged Attack",
		display_name = Untranslated("Moving target"),
		group = "Default",
		id = modifier_id,
	})
end

function OnMsg.DataLoaded()
	EnsureModifier()
end

function OnMsg.ModsReloaded()
	EnsureModifier()
end
