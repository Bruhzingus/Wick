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
	waxType: Types.WaxTypeDef,
	movementMode: Types.MovementMode,
	isCupping: boolean,
	cupUpkeepPerSecond: number, -- Cup's waxCost while held (0 when not cupping)
	inDraft: boolean,
	wading: boolean,
}

local WaxDrain = {}

-- Total wax lost per second in this context. Pure; tunable entirely from Config.
function WaxDrain.perSecond(ctx: DrainContext): number
	local drain = 0

	if ctx.isLit then
		-- Burning: idle cost plus the brightness curve, scaled by the wax type's hunger.
		local burn = WaxConfig.idleDrainPerSecond
			+ WaxConfig.burnDrainPerSecond * ctx.burnRate ^ WaxConfig.burnDrainExponent
		drain += burn * ctx.waxType.drainMultiplier

		if ctx.isCupping then
			drain += ctx.cupUpkeepPerSecond
		end

		if ctx.inDraft and not ctx.isCupping then
			local draft = HazardsConfig.definitions.Draft
			drain += draft.guttering :: number -- Draft rows always define guttering (Config/Hazards)
		end

		-- Movement melts wax only while the flame is burning (motion feeds the flame).
		if ctx.movementMode == "Run" then
			drain += MovementConfig.runWaxPerSecond * WaxConfig.movementCostMultiplier
		elseif ctx.movementMode == "Walk" then
			drain += MovementConfig.walkWaxPerSecond * WaxConfig.movementCostMultiplier
		end
	end

	if ctx.wading then
		-- Water eats wax lit or not: the body is soaking regardless.
		local water = HazardsConfig.definitions.Water
		drain += water.degradePerSecond :: number -- Water rows always define degradePerSecond
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
