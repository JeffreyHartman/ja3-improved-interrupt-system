-- Tests for the "IISMovingTarget" to-hit modifier in mod/Code/MovingTarget.lua: given an active
-- interrupt, a shooter and a mover that moved in its current command, what penalty does it give?
-- run.lua runs this file after test_engine.lua, which loads IIS.lua and Control.lua with fakes.

local t = Test
local E = IIS.E

local tile = 1200
const.SlabSizeX = tile

Presets = { ChanceToHitModifier = { Default = {} } }
function PlaceObj(class, props)
	if class == "ChanceToHitModifier" then
		Presets.ChanceToHitModifier.Default[props.id] = props
	end
	return props
end
function Untranslated(s)
	return s
end

dofile("mod/Code/MovingTarget.lua")
OnMsg.ModsReloaded()

E.XY = function(p) return p.x, p.y end

local function Modifier()
	return Presets.ChanceToHitModifier.Default.IISMovingTarget
end

local player_team = { side = "player1", control = "UI" }
local enemy_team = { side = "enemy1", control = "AI" }

local function Unit_(id, team, x, y)
	local u = { kinds = { Unit = true }, session_id = id, handle = id, team = team, pos = { x = x, y = y },
		command_thread = id .. " command" }
	function u:GetPos() return self.pos end
	function u:GetVisualPos() return self.pos end
	function u:IsDead() return false end
	return u
end

local function EndActive()
	local it = IISControl.Active()
	if it then
		local ui = IIS.UI
		IIS.UI = { End = function() end }
		IISControl.EndInterrupt(it, "test")
		IIS.UI = ui
	end
end

local function Activate(interrupters, mover)
	EndActive()
	local it = IISInterrupt.Begin{ n = 1, mover = mover, interrupters = interrupters, cfg = IIS.Config }
	IISControl.Activate(it)
	return it
end

-- The mover starts its command at (sx, sy) tiles and walks to (ex, ey) tiles. The shooter stands at (0, 0).
local function Scene(sx, sy, ex, ey)
	local shooter = Unit_("a", player_team, 0, 0)
	local mover = Unit_("enemy", enemy_team, sx * tile, sy * tile)
	OnMsg.UnitAnyMovementStart(mover)
	mover.pos = { x = ex * tile, y = ey * tile }
	Activate({ shooter }, mover)
	return shooter, mover
end

local plain_weapon = { components = {} }

local function Penalty(shooter, mover, weapon)
	local apply, value = Modifier():CalcValue(shooter, mover, nil, { ActionType = "Ranged Attack" },
		weapon or plain_weapon, nil, false, 0, false, shooter:GetPos(), mover:GetPos())
	return apply and value or 0
end

t.case("Moving target: 10 tiles across the line of fire gives the full penalty", function()
	IIS.Config.moving_target_penalty = 25
	local shooter, mover = Scene(-10, 10, 0, 10)
	t.eq(Penalty(shooter, mover), -25)
	EndActive()
end)

t.case("Moving target: a mover that moved straight at the shooter gives no penalty", function()
	IIS.Config.moving_target_penalty = 25
	local shooter, mover = Scene(0, 20, 0, 10)
	t.eq(Penalty(shooter, mover), 0)
	EndActive()
end)

t.case("Moving target: 5 tiles across the line of fire gives half the penalty", function()
	IIS.Config.moving_target_penalty = 10
	local shooter, mover = Scene(-5, 10, 0, 10)
	t.eq(Penalty(shooter, mover), -5)
	EndActive()
end)

t.case("Moving target: a move longer than 10 tiles gives the full penalty, not more", function()
	IIS.Config.moving_target_penalty = 35
	local shooter, mover = Scene(-15, 10, 0, 10)
	t.eq(Penalty(shooter, mover), -35)
	EndActive()
end)

t.case("Moving target: a move at 45 degrees to the line of fire gives about 29% of the penalty", function()
	IIS.Config.moving_target_penalty = 35
	local shooter, mover = Scene(-10, 20, 0, 10)
	-- 35 x (1 - cos 45) x 10 / 10 = 10.25. The move is 14 tiles, so the distance factor is 1.
	t.eq(Penalty(shooter, mover), -10)
	EndActive()
end)

t.case("Moving target: a reflex sight gives no penalty", function()
	IIS.Config.moving_target_penalty = 25
	local shooter, mover = Scene(-10, 10, 0, 10)
	t.eq(Penalty(shooter, mover, { components = { Scope = "ReflexSightAdvanced", Muzzle = "Compensator" } }), 0)
	t.eq(Penalty(shooter, mover, { components = { Scope = "RAT_TOG_Reflex" } }), 0)
	t.eq(Penalty(shooter, mover, { components = { Scope = "LROptics" } }), -25)
	EndActive()
end)

t.case("Moving target: only the move of the mover's current command counts", function()
	IIS.Config.moving_target_penalty = 10
	local shooter, mover = Scene(-10, 10, -5, 10)
	mover.command_thread = "a later command"
	t.eq(Penalty(shooter, mover), 0)
	OnMsg.UnitAnyMovementStart(mover)
	mover.pos = { x = 0, y = 10 * tile }
	t.eq(Penalty(shooter, mover), -5)
	EndActive()
end)

t.case("Moving target: a second movement start in the same command keeps the first start", function()
	IIS.Config.moving_target_penalty = 25
	local shooter, mover = Scene(-10, 10, -5, 10)
	OnMsg.UnitAnyMovementStart(mover)
	mover.pos = { x = 0, y = 10 * tile }
	t.eq(Penalty(shooter, mover), -25)
	EndActive()
end)

t.case("Moving target: the modifier is a ranged-attack preset named Moving target", function()
	t.eq(Modifier().display_name, "Moving target")
	t.eq(Modifier().RequireActionType, "Any Ranged Attack")
	t.eq(Modifier().RequireTarget, true)
end)

t.case("Moving target: a data reload that drops the preset places it again", function()
	Presets.ChanceToHitModifier.Default = {}
	OnMsg.DataLoaded()
	t.eq(Modifier().id, "IISMovingTarget")
end)

t.case("Moving target: the mod option sets the maximum penalty", function()
	CurrentModOptions.MovingTargetPenalty = "15"
	OnMsg.ApplyModOptions(rawget(_G, "CurrentModId"))
	local shooter, mover = Scene(-10, 10, 0, 10)
	t.eq(Penalty(shooter, mover), -15)
	CurrentModOptions.MovingTargetPenalty = nil
	OnMsg.ApplyModOptions(rawget(_G, "CurrentModId"))
	t.eq(Penalty(shooter, mover), 0)
	EndActive()
end)

t.case("Moving target: the value 0 gives no penalty", function()
	IIS.Config.moving_target_penalty = 0
	local shooter, mover = Scene(-10, 10, 0, 10)
	t.eq(Penalty(shooter, mover), 0)
	EndActive()
end)

t.case("Moving target: no penalty when no interrupt is active", function()
	IIS.Config.moving_target_penalty = 25
	local shooter, mover = Scene(-10, 10, 0, 10)
	EndActive()
	t.eq(Penalty(shooter, mover), 0)
end)

t.case("Moving target: no penalty for a shooter that is not an interrupter", function()
	IIS.Config.moving_target_penalty = 25
	local _, mover = Scene(-10, 10, 0, 10)
	local other = Unit_("b", player_team, 0, 0)
	t.eq(Penalty(other, mover), 0)
	EndActive()
end)

t.case("Moving target: no penalty for an enemy shot at an interrupter", function()
	IIS.Config.moving_target_penalty = 25
	local shooter, mover = Scene(-10, 10, 0, 10)
	OnMsg.UnitAnyMovementStart(shooter)
	shooter.pos = { x = -10 * tile, y = 0 }
	t.eq(Penalty(mover, shooter), 0)
	EndActive()
end)

t.case("Moving target: no penalty at a target that is not the mover of the interrupt", function()
	IIS.Config.moving_target_penalty = 25
	local shooter = Scene(-10, 10, 0, 10)
	local other = Unit_("enemy2", enemy_team, -10 * tile, 10 * tile)
	OnMsg.UnitAnyMovementStart(other)
	other.pos = { x = 0, y = 10 * tile }
	t.eq(Penalty(shooter, other), 0)
	EndActive()
end)
