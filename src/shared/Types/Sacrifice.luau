--!strict
-- Basin sacrifice types (DESIGN §10). A sacrifice permanently removes an ability in exchange for wax.

local Tool = require(script.Parent.Tool)

-- Identifier for a sacrifice. Open string alias; add sacrifices as Config/Basin rows.
export type SacrificeId = string

-- What a sacrifice takes away. Closed union of the ability domains a sacrifice can touch (DESIGN §10 pool).
export type SacrificeTarget =
	"MaxBrightness"
	| "Slide"
	| "Dodge"
	| "DripTrail"
	| "Relight"
	| "BeRelit"
	| "Tool"
	| "NextBasinPriceDoubled"

-- Static sacrifice definition. Pure data (see Config/Basin).
export type SacrificeDef = {
	id: SacrificeId,
	displayName: string,
	target: SacrificeTarget, -- which ability/aspect this removes or worsens
	waxGranted: number, -- wax gained by accepting, 0..1 (before depth scaling)
	weight: number, -- relative likelihood in the v1 weighted-random pool
}

-- An offer as actually presented to one player: the "Tool" target resolved to a concrete owned
-- tool, and the grant already depth-scaled so the player sees real numbers.
export type ResolvedOffer = {
	def: SacrificeDef,
	toolId: Tool.ToolId?, -- set when def.target == "Tool"
	waxGranted: number, -- final grant at this depth for this player
}

-- The live effect of every sacrifice taken so far, derived once per choice and read every tick.
-- Defaults come from Logic/SacrificeRules.defaultModifiers.
export type SacrificeModifiers = {
	maxBurnRate: number, -- MaxBrightness sacrifice lowers this below Config/Light.maxBurnRate
	canSlide: boolean,
	dodgeDistanceMultiplier: number, -- Dodge sacrifice shortens the dash
	hasDripTrail: boolean,
	canRelight: boolean,
	canBeRelit: boolean,
	lostTools: { [Tool.ToolId]: boolean },
}

return {}
