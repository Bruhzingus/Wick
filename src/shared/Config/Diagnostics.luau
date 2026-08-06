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
	itemTag = "WickDevItem",
	itemNameAttribute = "WickDevItemName",
	descentTag = "WickDevDescent",
}

return Diagnostics
