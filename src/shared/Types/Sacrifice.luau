--!strict
-- Basin sacrifice types (DESIGN §10). A sacrifice permanently removes an ability in exchange for wax.

local Tool = require(script.Parent.Tool)

-- Identifier for a sacrifice. Open string alias; add sacrifices as Config/Basin rows.
export type SacrificeId = string

-- What a sacrifice takes away. Closed union of the ability domains a sacrifice can touch (DESIGN §10 pool).
-- Adding a target means adding one handler in Logic/SacrificeRules and one applicability branch;
-- adding a new sacrifice over an EXISTING target is only a Config/Basin row.
export type SacrificeTarget =
	"MaxBrightness"
	| "DialFloor"
	| "MoveSpeed"
	| "CupSpeed"
	| "DripTrail"
	| "Relight"
	| "BeRelit"
	| "Hearing"
	| "WaxCapacity"
	| "BurnEfficiency"
	| "ToolSpeed"
	| "PeripheralDarkness"
	| "SightBrightness"
	| "SightSaturation"
	| "Tool"
	| "NextBasinPriceDoubled"

-- Static sacrifice definition. Pure data (see Config/Basin).
export type SacrificeDef = {
	id: SacrificeId,
	displayName: string,
	target: SacrificeTarget, -- which ability/aspect this removes or worsens
	waxGranted: number, -- wax units gained before the optional next-price penalty
	weight: number, -- relative likelihood in the v1 weighted-random pool
}

-- An offer as actually presented to one player: the "Tool" target resolved to a concrete owned
-- tool, and the grant already penalty-clamped so the player sees the real number.
export type ResolvedOffer = {
	def: SacrificeDef,
	toolId: Tool.ToolId?, -- set when def.target == "Tool"
	waxGranted: number, -- final grant for this player
}

-- The live effect of every sacrifice taken so far, derived once per choice and read every tick.
-- Defaults come from Logic/SacrificeRules.defaultModifiers.
export type SacrificeModifiers = {
	maxBurnRate: number, -- MaxBrightness sacrifice lowers this below Config/Light.maxBurnRate
	minBurnRate: number, -- DialFloor sacrifice raises this above Config/Light.minBurnRate
	moveSpeedMultiplier: number, -- MoveSpeed sacrifice slows walking and running alike
	cupSpeedMultiplier: number, -- CupSpeed sacrifice compounds with Config/Tools.Cup.speedMultiplier
	hasDripTrail: boolean,
	canRelight: boolean,
	canBeRelit: boolean,
	canHearThreats: boolean, -- Hearing sacrifice removes the nearby-threat cue entirely
	maxWaxMultiplier: number, -- WaxCapacity sacrifice shrinks the reserve the candle can hold
	waxDrainMultiplier: number, -- BurnEfficiency sacrifice makes every drain component cost more
	toolCooldownMultiplier: number, -- ToolSpeed sacrifice lengthens every tool cooldown
	peripheralDarkness: number, -- local screen-edge opacity added by the Basin
	sightBrightness: number, -- local ColorCorrection brightness offset
	sightSaturation: number, -- local ColorCorrection saturation offset
	lostTools: { [Tool.ToolId]: boolean },
}

return {}
