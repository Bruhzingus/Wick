--!strict
-- Developer diagnostics. The access code is an intentional convenience gate, not a security
-- boundary; the server still validates every request and diagnostics never mutate gameplay state.

export type DiagnosticsConfig = {
	unlockCode: string,
	statsHz: number,
	highlightColor: Color3,
	highlightFillTransparency: number,
	highlightOutlineTransparency: number,
	markerMaxDistance: number,
	wardenTag: string,
	enemyVisualTag: string,
	-- The wick-pack bodies (shared/Enemies). They need a tag of their own because they are the one
	-- creature family the overlay cannot otherwise see: `enemyVisualTag` is added CLIENT-side by the
	-- visual controllers that build proxy bodies, and `Feel.threatWarning.collectionTag` is a GAMEPLAY
	-- tag (it drives the proximity warning) rather than a diagnostic one — borrowing either would mean
	-- either no marker at all or silently giving these creatures a mechanic they were never designed
	-- with.
	packEnemyTag: string,
	itemTag: string,
	itemNameAttribute: string,
	descentTag: string,
}

local Diagnostics: DiagnosticsConfig = {
	unlockCode = "0610",
	statsHz = 1,
	highlightColor = Color3.fromRGB(255, 38, 38),
	highlightFillTransparency = 0.45,
	highlightOutlineTransparency = 0,
	markerMaxDistance = 10000,
	wardenTag = "WickDevWarden",
	enemyVisualTag = "WickDevEnemyVisual",
	packEnemyTag = "WickDevPackEnemy",
	itemTag = "WickDevItem",
	itemNameAttribute = "WickDevItemName",
	descentTag = "WickDevDescent",
}

return Diagnostics
