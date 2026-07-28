--!strict
-- Tool-domain types (DESIGN §6). Tools spend wax to manipulate threats; they never damage them (invariant).
--
-- Tool definitions describe physical light changes rather than hard-coded enemy classes. Emitted
-- LightSource data carries the one DESIGN exception: Decoy attracts Drawn but does not repel
-- dark-hunters.

-- The three tools. Closed union — fixed by design, never extended.
export type ToolId = "Flare" | "Decoy" | "Cup"

export type ThrowPlacement = {
	throwStartHeight: number, -- studs above the candle base where the validated throw arc begins/ends
	throwArcHeight: number, -- additional height at the midpoint of the validated throw arc
	throwProbeSegments: number, -- server ray segments used to approximate the throw arc
	obstructionInset: number, -- studs before the first wall/formation where the landing is pulled back
	groundProbeHeight: number, -- studs above the horizontal candidate where the ground probe begins
	groundProbeDepth: number, -- studs below the caster plane the ground probe may search
	groundProbeMaxHits: number, -- downward-facing roof hits skipped before giving up
	groundProbeAdvance: number, -- studs advanced past a rejected roof underside per probe
	maximumGroundRise: number, -- highest legal landing above the caster's current base
	minimumDistance: number, -- placements closer than this to the caster are rejected
	maxGroundSlopeDegrees: number, -- steepest upward-facing surface that may hold the decoy
	surfaceOffset: number, -- small lift above the hit surface that prevents visible embedding
}

export type DecoyVisual = {
	bodyHeight: number,
	bodyRadius: number,
	rimHeight: number,
	rimRadiusMultiplier: number,
	wickHeight: number,
	wickRadius: number,
	flameSize: number,
	lightBrightness: number,
	lightRange: number, -- rendered PointLight range, kept separate from the decoy's attraction range
	bodyColor: Color3,
	rimColor: Color3,
	wickColor: Color3,
	flameColor: Color3,
	lightColor: Color3,
}

-- Static tool definition. Pure data; one generic system consumes every row.
export type ToolDef = {
	id: ToolId,
	displayName: string,
	waxCost: number, -- wax per activation; for held tools (Cup) this is upkeep per SECOND held
	cooldown: number, -- seconds before reusable; 0 means wax/state alone gates the tool
	duration: number, -- seconds the effect lasts (0 = instant or held)
	requiresLit: boolean, -- tool only usable while the flame is burning
	held: boolean, -- Cup: active while toggled on, paying waxCost per second
	-- Optional physical parameters; which apply is documented per row in Config/Tools.
	burstIntensity: number?, -- Flare: light-field intensity of the burst
	burstBrightness: number?, -- Flare: rendered PointLight brightness, separate from threat intensity
	burstRange: number?, -- Flare: studs the burst reaches
	throwRange: number?, -- Decoy: max throw distance (server clamps the client aim point)
	decoyIntensity: number?, -- Decoy: light-field intensity of the burning decoy
	decoyRange: number?, -- Decoy: studs the decoy's pull on the drawn reaches
	throwPlacement: ThrowPlacement?, -- Decoy: authoritative obstruction and ground-probe rules
	decoyVisual: DecoyVisual?, -- Decoy: miniature distraction-candle presentation
	lightMultiplier: number?, -- Cup: multiplier on your flame's light output while held (the hide action)
	speedMultiplier: number?, -- Cup: multiplier on your movement speed while held
}

return {}
