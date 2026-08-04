--!strict
-- Pure: the complete per-tick wax drain pipeline. Every way wax leaves a candle per-second flows
-- through here — burning, moving, guttering, wading — so the economy is auditable in one place.
-- (Instant costs — tools, dodges, relights — are charged where they happen, via the same store.)

local Types = require(script.Parent.Parent.Types)
local WaxConfig = require(script.Parent.Parent.Config.Wax)
local MovementConfig = require(script.Parent.Parent.Config.Movement)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)

-- Everything that affects this player's drain this tick. Assembled by the server from state.
export type DrainContext = {
	isLit: boolean,
	burnRate: Types.BurnRate,
	candle: Types.CandleProfile, -- derived live by Logic/CandleModifiers.profile
	movementMode: Types.MovementMode,
	isCupping: boolean,
	cupUpkeepPerSecond: number, -- Cup's waxCost while held (0 when not cupping)
	wading: boolean,
}

-- One attributed component of the recurring drain. Ordered, not keyed, so summing the list is
-- float-for-float identical to the single expression this replaced.
export type DrainComponent = {
	source: Types.WaxSource,
	perSecond: number,
}

local WaxDrain = {}

-- The recurring drain, split by what is causing it. This is the accounting source of truth for
-- passive pressure: add a new recurring cost here and it is categorized everywhere automatically.
function WaxDrain.breakdown(ctx: DrainContext): { DrainComponent }
	local components: { DrainComponent } = {}

	if ctx.isLit then
		-- Burning: idle cost plus the brightness curve, scaled by the candle's own hunger. This is
		-- where a run's LifeWax stack lands, and deliberately ONLY here: an item that also made wading
		-- and movement cheaper would be a global difficulty dial rather than a better candle.
		local burn = WaxConfig.idleDrainPerSecond
			+ WaxConfig.burnDrainPerSecond * ctx.burnRate ^ WaxConfig.burnDrainExponent
		table.insert(components, { source = "PassiveBurn", perSecond = burn * ctx.candle.drainMultiplier })

		if ctx.isCupping then
			table.insert(components, { source = "ToolCup", perSecond = ctx.cupUpkeepPerSecond })
		end

		-- Movement melts wax only while the flame is burning (motion feeds the flame).
		if ctx.movementMode == "Run" then
			table.insert(components, {
				source = "MovementRun",
				perSecond = MovementConfig.runWaxPerSecond * WaxConfig.movementCostMultiplier,
			})
		elseif ctx.movementMode == "Walk" then
			table.insert(components, {
				source = "MovementWalk",
				perSecond = MovementConfig.walkWaxPerSecond * WaxConfig.movementCostMultiplier,
			})
		end
	end

	if ctx.wading then
		-- Water eats wax lit or not: the body is soaking regardless.
		local water = HazardsConfig.definitions.Water
		table.insert(components, {
			source = "DamageWater",
			perSecond = water.degradePerSecond :: number, -- Water rows always define degradePerSecond
		})
	end

	return components
end

-- Total wax lost per second in this context. Pure; tunable entirely from Config.
function WaxDrain.perSecond(ctx: DrainContext): number
	local drain = 0
	for _, component in WaxDrain.breakdown(ctx) do
		drain += component.perSecond
	end
	return drain
end

-- Apply a drain (or any deduction) to a wax state. Returns the new state and whether it burned out.
function WaxDrain.apply(wax: Types.WaxState, amount: number): (Types.WaxState, boolean)
	local current = math.clamp(wax.current - amount, 0, wax.max)
	return { current = current, max = wax.max }, current <= 0
end

-- Movement mode from MEASURED horizontal speed (the server never trusts a client-claimed mode).
function WaxDrain.movementModeForSpeed(speed: number): Types.MovementMode
	local t = MovementConfig.drainThresholds
	if speed >= MovementConfig.runSpeed * t.runAtFractionOfRunSpeed then
		return "Run"
	elseif speed >= MovementConfig.walkSpeed * t.walkAtFractionOfWalkSpeed then
		return "Walk"
	end
	return "Idle"
end

return WaxDrain
