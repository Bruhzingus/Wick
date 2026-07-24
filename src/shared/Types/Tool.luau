--!strict
-- Tool-domain types (DESIGN §6). Tools spend wax to manipulate threats; they never damage them (invariant).
--
-- Tools do NOT carry per-category effect flags. Every tool works by changing the light field
-- (your flame, a burst, a decoy, a shroud), and the two threat categories react in opposite
-- directions to light via the sign of ThreatDef.lightResponse. The opposition is data:
-- Tools config supplies the physical light change, Threats config supplies the signed reaction.

-- The four tools. Closed union — fixed by design, never extended.
export type ToolId = "Snuff" | "Flare" | "Cast" | "Cup"

-- Static tool definition. Pure data; one generic system consumes every row.
export type ToolDef = {
	id: ToolId,
	displayName: string,
	waxCost: number, -- wax per activation; for held tools (Cup) this is upkeep per SECOND held
	cooldown: number, -- seconds before reusable
	duration: number, -- seconds the effect lasts (0 = instant or held)
	requiresLit: boolean, -- tool only usable while the flame is burning
	togglesLit: boolean, -- Snuff: toggles the flame off/on rather than producing an effect
	held: boolean, -- Cup: active while toggled on, paying waxCost per second
	-- Optional physical parameters; which apply is documented per row in Config/Tools.
	burstIntensity: number?, -- Flare: light-field intensity of the burst
	burstRange: number?, -- Flare: studs the burst reaches
	castRange: number?, -- Cast: max throw distance (server clamps the client aim point)
	decoyIntensity: number?, -- Cast: light-field intensity of the burning decoy
	decoyRange: number?, -- Cast: studs the decoy's light reaches
	decoySize: number?, -- Cast: visual diameter of the blob (studs)
	lightMultiplier: number?, -- Cup: multiplier on your flame's light output while held
	speedMultiplier: number?, -- Cup: multiplier on your movement speed while held
}

return {}
