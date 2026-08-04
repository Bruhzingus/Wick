--!strict
-- Tool tuning (DESIGN §6). Tools spend wax to manipulate threats; they never damage them.
--
-- HOW OPPOSITION IS ENCODED: every tool changes the light field, and the two threat categories
-- read it differently. Ordinary flame strength influences hunter hunt/stalk reads; a Flare source
-- additionally carries the explicit panic-light flag that may force retreat. Decoy remains the one
-- asymmetric source hunters cannot perceive. The fixed three tools are data rows, not classes.
--
-- There is no tool that extinguishes your own flame. Cup is the hide action: it covers the light
-- the flame throws without killing it, so going dark is always a reversible held state rather than
-- a lit/unlit toggle.

local Types = require(script.Parent.Parent.Types)

local Tools: { [Types.ToolId]: Types.ToolDef } = {
	-- FLARE: a burst source far brighter than any flame. Repels dark-hunters, drags the drawn
	-- straight to you. Expensive.
	Flare = {
		id = "Flare",
		displayName = "FLARE",
		waxCost = 0.13, -- 10% of the current 1.3 max wax; a visible health/light sacrifice
		-- No cooldown: repeated panic use is allowed because every press pays directly in wax.
		cooldown = 0,
		duration = 1.5, -- seconds the burst lasts
		requiresLit = true,
		held = false,
		-- Light-field strength of the burst. Higher intensity/range = stronger repel AND stronger lure.
		burstIntensity = 3,
		-- Render output stays separate from threat perception and clearly exceeds a max-bright candle.
		burstBrightness = 6,
		burstRange = 60,
	},
	-- DECOY: a thrown blob of your own wax burning on the ground. A second light source the drawn
	-- prefer over you; dark-hunters do not perceive it as a repelling source. Wax spent is gone.
	Decoy = {
		id = "Decoy",
		displayName = "DECOY",
		waxCost = 0.04, -- higher = harder
		cooldown = 3,
		duration = 6, -- seconds the decoy burns; longer = more useful = easier
		requiresLit = true,
		held = false,
		-- Server clamps the client's aim point to this throw distance (studs).
		throwRange = 25,
		-- Stronger than the brightest flame a run can BUILD (a maxed BrightWax stack plus a live wick
		-- bundle reaches about 1.7x), so a legal placement stays a dependable Drawn distraction however
		-- far a player has built their candle. The panic Flare remains stronger still, and
		-- Tests/ToolRulesTests re-derives that ceiling from the live rules rather than from this note.
		decoyIntensity = 2.2,
		-- Attraction reach, not rendered light (decoyVisual.lightRange owns that). The drawn compare
		-- sources by perceived strength, so this must stay wide enough that a decoy thrown at full
		-- throwRange still out-pulls the brightest flame from a moth already sitting on that flame.
		decoyRange = 45,
		throwPlacement = {
			-- The server traces a segmented throw arc. It clears ordinary rolling ground, while
			-- walls, boulders, and the roof still shorten the throw before the obstruction.
			throwStartHeight = 1.5,
			throwArcHeight = 5,
			throwProbeSegments = 16,
			obstructionInset = 1,
			-- The shortened XZ point is then projected onto real WickFloors/Terrain. These bounds
			-- reach deep local troughs without seeing the floor stacked 96 studs below.
			groundProbeHeight = 8,
			groundProbeDepth = 24,
			groundProbeMaxHits = 3,
			groundProbeAdvance = 0.1,
			maximumGroundRise = 20,
			minimumDistance = 2.5,
			maxGroundSlopeDegrees = 38,
			surfaceOffset = 0.05,
		},
		decoyVisual = {
			bodyHeight = 1.15,
			bodyRadius = 0.35,
			rimHeight = 0.11,
			rimRadiusMultiplier = 1.12,
			wickHeight = 0.2,
			wickRadius = 0.04,
			flameSize = 0.34,
			lightBrightness = 3.4,
			lightRange = 22,
			bodyColor = Color3.fromRGB(225, 151, 71),
			rimColor = Color3.fromRGB(242, 181, 92),
			wickColor = Color3.fromRGB(37, 27, 20),
			flameColor = Color3.fromRGB(255, 168, 64),
			lightColor = Color3.fromRGB(255, 190, 100),
		},
	},
	-- CUP: hands around the flame — the game's only "go dark" action. Near-dark (the drawn barely
	-- notice you) and slow; but you can't see hunters coming and low light makes you huntable.
	-- The flame itself keeps burning, so the cost is upkeep and exposure, never a relight.
	Cup = {
		id = "Cup",
		displayName = "CUP",
		waxCost = 0.005, -- per SECOND held (held tool). Higher = harder.
		cooldown = 0,
		duration = 0, -- held: active until toggled off
		requiresLit = true,
		held = true,
		-- A tiny ember pocket: covered, not extinguished, so the player stays a faint but real
		-- source. Other nearby open flames still illuminate this player because threat reads sum
		-- the shared light field.
		lightMultiplier = 0.035,
		-- Your movement speed while cupping. Lower = harder.
		speedMultiplier = 0.5,
	},
}

return Tools
