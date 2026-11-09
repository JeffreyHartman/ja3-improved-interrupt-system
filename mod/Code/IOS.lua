-- Improved Overwatch System (IOS): the IISControl handler for "overwatch" entries. When the
-- Overwatch trigger of a merc happens, the merc acts in an interrupt as an overwatcher in place of
-- the vanilla Overwatch shot. It pays from an AP pool that it keeps in its Overwatch state.

IOS = IOS or {}

local E = IIS.E
local Log, Name, FormatAP = IIS.Log, IIS.Name, IIS.FormatAP

-- The number of the last interrupt that IOS.InterruptRequest asked for.
local ios_interrupt

function E.Overwatch(unit)
	local all = rawget(_G, "g_Overwatch")
	return all and all[unit]
end

function E.CombatTurn()
	return g_Combat and g_Combat.current_turn
end

function E.LogOverwatchReveal(mover)
	CombatLog("short", T{353305209140, "<LogName> was revealed by enemy overwatch", mover})
end

--- Returns the raw AP pool of an Overwatch state.
-- The stored pool is used only when the game has not changed the attack count or the turn since
-- IOS stored it. Otherwise, as for an Overwatch state from an old save or a set-up machine gun
-- after its turn start, the pool is the attack count multiplied by `cost`.
function IOS.Pool(overwatch, cost, turn)
	local pool = overwatch.ios_pool
	if pool and overwatch.ios_count == overwatch.num_attacks and overwatch.ios_turn == turn then
		return pool
	end
	return (overwatch.num_attacks or 0) * cost
end

--- Stores `pool` in the Overwatch state and sets the attack count to the number of attacks of
-- `cost` that the pool pays for. Returns that count.
function IOS.StorePool(overwatch, pool, cost, turn)
	local count = IISRules.idiv(pool, cost)
	overwatch.ios_pool, overwatch.ios_count, overwatch.ios_turn = pool, count, turn
	overwatch.num_attacks = count
	return count
end

-- Sets the attack count and the pool of `m` from the AP that it has left, and ends its Overwatch
-- when the pool cannot pay for one attack. A permanent Overwatch (a set-up machine gun) stays at 0
-- attacks, as in vanilla, until the game counts its attacks again.
local function FinishOverwatcher(m, left, n)
	local overwatch = E.Overwatch(m)
	if not overwatch then
		Log("INT #%d overwatcher %s is no longer on Overwatch, pool %s lost", n, Name(m), FormatAP(left))
		return
	end
	local cost = E.AttackCostRaw(m)
	if cost <= 0 then
		Log("INT #%d overwatcher %s: no attack cost, Overwatch ends", n, Name(m))
		m:InterruptPreparedAttack()
		return
	end
	local count = IOS.StorePool(overwatch, left, cost, E.CombatTurn())
	local params = m.combat_behavior == "OverwatchAction" and m.combat_behavior_params
	if params and type(params[3]) == "table" then
		params[3].num_attacks = count
	end
	Log("INT #%d overwatcher %s: pool %s, attack cost %s, attacks %d", n, Name(m), FormatAP(left), FormatAP(cost), count)
	if count < 1 and not overwatch.permanent then
		Log("INT #%d overwatcher %s: the pool cannot pay for one attack, Overwatch ends", n, Name(m))
		m:InterruptPreparedAttack()
		return
	end
	m:UpdateOverwatchVisual(overwatch)
	ObjModified(m)
end

--- The IISControl handler for "overwatch" entries. Returns the request for an IOS interrupt with
-- the mercs of `entries` as overwatchers, or nil when no entry is of a merc that can pay for an
-- attack from its pool. An entry of an enemy overwatcher goes to vanilla unchanged.
-- For each overwatcher, it does the bookkeeping of the vanilla Overwatch shot: the mover goes in
-- `triggered_by`, the mover loses Hidden, and the combat log names the mover.
function IOS.InterruptRequest(mover, entry, n, entries)
	local turn = E.CombatTurn()
	local overwatchers, grants, notes = {}, {}, {}
	for _, e in ipairs(entries or { entry }) do
		local m = e[2]
		local overwatch = E.CanControlTeam(m) and E.Overwatch(m)
		if overwatch then
			local cost = E.AttackCostRaw(m)
			local pool = cost > 0 and IOS.Pool(overwatch, cost, turn) or 0
			if cost > 0 and pool >= cost then
				overwatchers[#overwatchers + 1] = m
				grants[m] = pool
				notes[m] = string.format(" (overwatcher, pool %s, attack cost %s)", FormatAP(pool), FormatAP(cost))
			else
				Log("IOS: overwatcher %s cannot pay for an attack (pool %s, cost %s), vanilla handles it", Name(m),
					FormatAP(pool), FormatAP(cost))
			end
		end
	end
	if #overwatchers == 0 then return end

	for _, m in ipairs(overwatchers) do
		E.Overwatch(m).triggered_by[mover.handle] = true
	end
	mover:RemoveStatusEffect("Hidden")
	E.LogOverwatchReveal(mover)

	ios_interrupt = n
	return {
		interrupters = overwatchers,
		dummy = entry[4],
		stop = false,
		label = "IOS overwatch",
		notes = notes,
		banner = "Overwatch",
		ap_grants = grants,
		on_end = function(ap_left)
			for _, m in ipairs(overwatchers) do
				IIS.SafeCall(nil, "IOS end of " .. Name(m), FinishOverwatcher, m, ap_left[m] or 0, n)
			end
		end,
	}
end

--- Returns true when `unit` is an overwatcher in the active interrupt, and that interrupt is an IOS
-- interrupt.
function IOS.IsOverwatcher(unit)
	local it = IISControl.Active()
	return it and it:Number() == ios_interrupt and it:IsInterrupter(unit) or false
end

-- The crosshair's to-hit preview and Unit:FirearmAttack both get their attack args from here. The
-- vanilla Overwatch shot is always a firearm attack, so other attacks stay as they are.
local orig_PrepareAttackArgs = Unit.PrepareAttackArgs
function Unit:PrepareAttackArgs(action_id, args)
	local attack_args = orig_PrepareAttackArgs(self, action_id, args)
	if IsKindOf(attack_args.weapon, "Firearm") and IOS.IsOverwatcher(self) then
		attack_args.opportunity_attack = true
		attack_args.opportunity_attack_type = "Overwatch"
	end
	return attack_args
end

--- Registers the handler for "overwatch" entries when the IOS option is on, and removes it when
-- the option is off.
function IOS.Install()
	IISControl.Handle("overwatch", IIS.Config.ios and IOS.InterruptRequest or nil)
end

function OnMsg.ModsReloaded()
	IOS.Install()
end

-- IIS.lua applies the options in its own handler for this message, which runs first.
function OnMsg.ApplyModOptions(mod_id)
	if mod_id ~= rawget(_G, "CurrentModId") then return end
	IOS.Install()
end

Log("IOS loaded: on=%s", tostring(IIS.Config.ios))
