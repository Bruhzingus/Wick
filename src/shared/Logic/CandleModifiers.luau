--!strict
-- Pure: every rule for the in-run roguelike candle modifiers (Config/CandleModifiers). This module
-- owns four things and nothing else:
--
--   1. `profile`  — the live burn profile the drain and light pipelines read every tick.
--   2. `step`     — what a tick does to the timed/consumable modifiers (Frozen Wax, Extra Wicks).
--   3. `applyPickup` — what collecting one does.
--   4. `absorb`   — what the Candle Sleeve takes off an incoming hit, and what that costs it.
--
-- NO ROBLOX INSTANCES, NO SERVICES. The server owns the PlayerRunState and calls these; every
-- function here takes a state and returns the NEXT state rather than mutating in place, so a tick
-- that half-applied cannot leave a candle in a state no rule produced.

local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config.CandleModifiers)
local LightConfig = require(script.Parent.Parent.Config.Light)

local CandleModifiers = {}

-- Where a hit came from in TIME, which is what decides how much of the sleeve it costs.
--   Hit        — a discrete swing; `seconds` is the attacker's own cooldown between swings.
--   Continuous — a per-tick drain; `seconds` is the tick's dt.
-- A caller with no timing information at all passes nil, which is read as one standalone hit.
export type ImpactSpan = {
	kind: "Hit" | "Continuous",
	seconds: number,
}

export type StepContext = {
	isLit: boolean,
	burnRate: Types.BurnRate,
	minBurnRate: Types.BurnRate, -- this player's effective dial floor (DialFloor sacrifice raises it)
	maxBurnRate: Types.BurnRate, -- this player's effective dial ceiling (MaxBrightness lowers it)
	maxWax: Types.WaxAmount,
}

export type StepEffects = {
	waxGain: number, -- wax melted out of the Frozen Wax reserve this tick
	frozenDepleted: boolean, -- the last of the reserve melted; the item is gone
	wicksExpired: boolean, -- the wick bundle burned out this tick
}

export type PickupOutcome = {
	modifierId: Types.CandleModifierId,
	lifeWax: number, -- stacks held after this pickup
	brightWax: number,
	drainReduction: number, -- live LifeWax effect after this pickup, 0..1
	brightnessBonus: number, -- live BrightWax effect after this pickup, 0..1
	wicks: number, -- wicks rolled by an Extra Wicks pickup
	wickSeconds: number, -- life granted by that bundle
	reserve: number, -- Frozen Wax banked, in wax units
	sleeveCharges: number,
}

-- A reserve smaller than this is GONE. Twenty subtractions of a fraction of a candle do not land on
-- a clean zero in binary, and a residue of 1e-18 wax units must not keep a consumed item alive for
-- another melt interval — the player was told the block was finished.
local EMPTY_RESERVE = 1e-9

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function sanitize(value: number, fallback: number): number
	if not isFinite(value) then
		return fallback
	end
	return value
end

-- The shared soft-knee curve. Below the knee a stack is worth face value; above it, `diminishedFactor`
-- of face value; the whole thing is capped. Monotonic and continuous at the knee by construction, so
-- an extra stack is never a downgrade and there is no cliff to memorize.
local function stackedBonus(stacks: number, tuning: Config.StackingBonusConfig): number
	local whole = math.max(0, math.floor(sanitize(stacks, 0)))
	if whole <= 0 then
		return 0
	end
	local nominal = whole * tuning.perStack
	if nominal <= tuning.diminishingAbove then
		return math.min(tuning.maximum, nominal)
	end
	local beyond = (nominal - tuning.diminishingAbove) * tuning.diminishedFactor
	return math.min(tuning.maximum, tuning.diminishingAbove + beyond)
end

-- Normalized dial position, 0 at this player's floor and 1 at their ceiling. Takes the EFFECTIVE
-- bounds rather than the config ones so a Basin sacrifice that narrowed the dial does not also
-- silently change what "burning hard" means to these items.
local function burnRateFraction(burnRate: number, minBurnRate: number, maxBurnRate: number): number
	local low = sanitize(minBurnRate, LightConfig.minBurnRate)
	local high = sanitize(maxBurnRate, LightConfig.maxBurnRate)
	local span = high - low
	if span <= 0 then
		return 0
	end
	return math.clamp((sanitize(burnRate, low) - low) / span, 0, 1)
end

function CandleModifiers.newState(): Types.CandleModifierState
	return {
		lifeWax = 0,
		brightWax = 0,
		frozen = { reserve = 0, atMaxSeconds = 0 },
		wicks = { wicks = 0, remaining = 0 },
		sleeve = { charges = 0 },
	}
end

-- The neutral candle: what a body with no run state behind it emits (the lobby ride body, a preview).
function CandleModifiers.neutralProfile(): Types.CandleProfile
	return {
		drainMultiplier = 1,
		brightnessMultiplier = 1,
		attractsDrawn = true,
	}
end

function CandleModifiers.lifeWaxDrainReduction(stacks: number): number
	return stackedBonus(stacks, Config.lifeWax)
end

function CandleModifiers.brightWaxBrightnessBonus(stacks: number): number
	return stackedBonus(stacks, Config.brightWax)
end

-- THE LIVE PROFILE. Read every tick by WaxDrain (drain) and BrightnessMap (light and, through it,
-- what threats perceive).
--
-- `isCupping` is a parameter rather than something this module infers, because of one rule: CUPPING
-- MUST STILL PUT YOU AT THE SAME DARKNESS IT ALWAYS DID. Extra Wicks are an OPEN flame effect — you
-- cannot cup three wicks and keep them all — so the bundle's bonus is dropped entirely while the
-- hand is over the flame. BrightWax is not dropped: that is the candle's own wax burning brighter,
-- and a cupped candle made of better wax is still a cupped candle.
function CandleModifiers.profile(state: Types.CandleModifierState, isCupping: boolean): Types.CandleProfile
	local brightness = 1 + CandleModifiers.brightWaxBrightnessBonus(state.brightWax)
	if not isCupping and state.wicks.remaining > 0 and state.wicks.wicks > 0 then
		brightness += Config.extraWicks.brightnessBonus
	end
	return {
		drainMultiplier = 1 - CandleModifiers.lifeWaxDrainReduction(state.lifeWax),
		brightnessMultiplier = brightness,
		-- No modifier in the pool hides a flame from the Drawn. The field is kept because the light
		-- pipeline is built around it (Types/LightSource, Logic/LightField) and a future item may.
		attractsDrawn = true,
	}
end

-- How fast one second of real time spends one second of wick. A dim flame stretches a bundle, a
-- hard-pushed one eats it — which is the whole "3 to 5 minutes depending on your flame profile".
function CandleModifiers.wickSpendRate(ctx: StepContext): number
	local tuning = Config.extraWicks
	local t = burnRateFraction(ctx.burnRate, ctx.minBurnRate, ctx.maxBurnRate)
	local stretch = tuning.stretchAtMinBurn + (tuning.stretchAtMaxBurn - tuning.stretchAtMinBurn) * t
	if stretch <= 0 then
		return 1
	end
	return 1 / stretch
end

-- Is this dial high enough to melt frozen wax? Measured against the player's OWN ceiling, so a
-- MaxBrightness sacrifice narrows the candle without making the item dead weight.
function CandleModifiers.isAtMaximumBrightness(ctx: StepContext): boolean
	local ceiling = sanitize(ctx.maxBurnRate, LightConfig.maxBurnRate)
	return sanitize(ctx.burnRate, 0) >= ceiling * Config.frozenWax.maxBurnRateFraction
end

-- One authoritative tick of the timed and consumable modifiers. Returns the next state plus what
-- the server has to act on (wax to grant, messages to send).
function CandleModifiers.step(
	state: Types.CandleModifierState,
	dt: number,
	ctx: StepContext
): (Types.CandleModifierState, StepEffects)
	local step = math.max(0, sanitize(dt, 0))
	local effects: StepEffects = { waxGain = 0, frozenDepleted = false, wicksExpired = false }
	if step <= 0 then
		return state, effects
	end

	local frozen: Types.FrozenWaxState = { reserve = state.frozen.reserve, atMaxSeconds = state.frozen.atMaxSeconds }
	local wicks: Types.ExtraWicksState = { wicks = state.wicks.wicks, remaining = state.wicks.remaining }

	-- Both effects are things a BURNING candle does. A snuffed one is not melting anything and its
	-- extra wicks are not being consumed either.
	if ctx.isLit then
		if frozen.reserve > EMPTY_RESERVE and CandleModifiers.isAtMaximumBrightness(ctx) then
			local tuning = Config.frozenWax
			frozen.atMaxSeconds += step
			local perMelt = math.max(0, sanitize(ctx.maxWax, 0)) * tuning.meltFraction
			while frozen.atMaxSeconds >= tuning.meltSeconds and frozen.reserve > EMPTY_RESERVE and perMelt > 0 do
				frozen.atMaxSeconds -= tuning.meltSeconds
				local melted = math.min(perMelt, frozen.reserve)
				frozen.reserve -= melted
				effects.waxGain += melted
			end
			if frozen.reserve <= EMPTY_RESERVE then
				-- Whatever residue is left is handed over rather than rounded away, so the ledger still
				-- reconciles against the reserve the pickup actually banked.
				effects.waxGain += frozen.reserve
				frozen.reserve = 0
				frozen.atMaxSeconds = 0
				effects.frozenDepleted = effects.waxGain > 0
			end
		end

		if wicks.remaining > 0 and wicks.wicks > 0 then
			wicks.remaining -= step * CandleModifiers.wickSpendRate(ctx)
			if wicks.remaining <= 0 then
				wicks.remaining = 0
				wicks.wicks = 0
				effects.wicksExpired = true
			end
		end
	end

	return {
		lifeWax = state.lifeWax,
		brightWax = state.brightWax,
		frozen = frozen,
		wicks = wicks,
		sleeve = { charges = state.sleeve.charges },
	},
		effects
end

-- Roll a wick count from a 0..1 value the caller supplies. Kept here (and kept pure) so the number
-- of wicks is a RULE rather than something a service invents next to its own Random.
function CandleModifiers.rollWickCount(roll: number): number
	local tuning = Config.extraWicks
	local low = math.max(1, math.floor(tuning.minimumWicks))
	local high = math.max(low, math.floor(tuning.maximumWicks))
	local normalized = math.clamp(sanitize(roll, 0), 0, 1)
	return math.min(high, low + math.floor(normalized * (high - low + 1)))
end

function CandleModifiers.wickSecondsFor(wicks: number): number
	local authored = Config.extraWicks.secondsByWickCount
	if #authored == 0 then
		return 0
	end
	return math.max(0, authored[math.clamp(math.floor(wicks), 1, #authored)])
end

-- Collect one modifier. Returns the next state and a summary of what the player actually got, or
-- nil for a row this module has no rule for (a malformed content row fails closed rather than
-- silently granting nothing and consuming the pickup).
function CandleModifiers.applyPickup(
	state: Types.CandleModifierState,
	modifierId: Types.CandleModifierId?,
	maxWax: Types.WaxAmount,
	roll: number
): (Types.CandleModifierState?, PickupOutcome?)
	if modifierId == nil then
		return nil, nil
	end

	local updated: Types.CandleModifierState = {
		lifeWax = state.lifeWax,
		brightWax = state.brightWax,
		frozen = { reserve = state.frozen.reserve, atMaxSeconds = state.frozen.atMaxSeconds },
		wicks = { wicks = state.wicks.wicks, remaining = state.wicks.remaining },
		sleeve = { charges = state.sleeve.charges },
	}

	if modifierId == "LifeWax" then
		updated.lifeWax += 1
	elseif modifierId == "BrightWax" then
		updated.brightWax += 1
	elseif modifierId == "FrozenWax" then
		-- Blocks stack without a ceiling. The reserve is not a second wax meter — it is fuel that only
		-- exists while it is being spent, and it can only be spent by holding the dial at maximum.
		local capacity = math.max(0, sanitize(maxWax, 0))
		updated.frozen.reserve += capacity * Config.frozenWax.reservePerPickup
	elseif modifierId == "ExtraWicks" then
		local wicks = CandleModifiers.rollWickCount(roll)
		local seconds = CandleModifiers.wickSecondsFor(wicks)
		-- A second bundle over a burning one REPLACES it when it is the better bundle rather than
		-- adding to it, so wick bonuses can never compound into a permanent +50% flame.
		if seconds > updated.wicks.remaining then
			updated.wicks = { wicks = wicks, remaining = seconds }
		else
			updated.wicks = { wicks = math.max(updated.wicks.wicks, wicks), remaining = updated.wicks.remaining }
		end
	elseif modifierId == "CandleSleeve" then
		-- A fresh sleeve replaces a scuffed one; it never stacks past a full one.
		updated.sleeve = { charges = math.max(updated.sleeve.charges, Config.sleeve.charges) }
	else
		return nil, nil
	end

	return updated,
		{
			modifierId = modifierId,
			lifeWax = updated.lifeWax,
			brightWax = updated.brightWax,
			drainReduction = CandleModifiers.lifeWaxDrainReduction(updated.lifeWax),
			brightnessBonus = CandleModifiers.brightWaxBrightnessBonus(updated.brightWax),
			wicks = updated.wicks.wicks,
			wickSeconds = updated.wicks.remaining,
			reserve = updated.frozen.reserve,
			sleeveCharges = updated.sleeve.charges,
		}
end

-- What one charge of the sleeve is worth against this impact.
--
--   A discrete swing costs `cooldown / referenceHitSeconds` charges, floored so no cadence is free
--   and capped at 1 so a slow attacker never takes two. That is the "adjust for enemies that hit
--   fast" rule: the sleeve is five REFERENCE hits' worth of protection, not five swings' worth,
--   so a fast attacker gets more swings out of the same cardboard.
--
--   A continuous drain costs `dt / referenceHitSeconds`, unfloored, so it accumulates to exactly
--   one charge per reference-second of standing in it.
function CandleModifiers.chargeCostFor(impact: ImpactSpan?): number
	local tuning = Config.sleeve
	local reference = math.max(1e-3, tuning.referenceHitSeconds)
	if impact == nil then
		return 1
	end
	local seconds = math.max(0, sanitize(impact.seconds, 0))
	if impact.kind == "Continuous" then
		return seconds / reference
	end
	if seconds <= 0 then
		return 1
	end
	return math.clamp(seconds / reference, tuning.minimumChargeCost, 1)
end

-- Run an incoming hit through the sleeve. Returns the SURVIVING fraction of the damage (1 = the
-- sleeve did nothing), the next state, and whether this hit was the one that finished it.
--
-- A hit that lands while any charge remains is reduced in full. The sleeve is generous on the way
-- out on purpose: "five hits" has to mean five hits that were actually softened, not four and a
-- part-hit whose protection a player could not have predicted.
function CandleModifiers.absorb(
	state: Types.CandleModifierState,
	source: Types.WaxSource,
	impact: ImpactSpan?
): (number, Types.CandleModifierState, boolean)
	local tuning = Config.sleeve
	if state.sleeve.charges <= 0 or not tuning.protects[source] then
		return 1, state, false
	end

	local remaining = state.sleeve.charges - CandleModifiers.chargeCostFor(impact)
	local broke = remaining <= 0
	local updated: Types.CandleModifierState = {
		lifeWax = state.lifeWax,
		brightWax = state.brightWax,
		frozen = { reserve = state.frozen.reserve, atMaxSeconds = state.frozen.atMaxSeconds },
		wicks = { wicks = state.wicks.wicks, remaining = state.wicks.remaining },
		sleeve = { charges = if broke then 0 else remaining },
	}
	return math.clamp(1 - tuning.damageReduction, 0, 1), updated, broke
end

return CandleModifiers
