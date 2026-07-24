--!strict
-- Tool tuning (DESIGN §6). Tools spend wax to manipulate threats; they never damage them.
--
-- HOW OPPOSITION IS ENCODED: every tool is a change to the light field, and the two threat
-- categories react to light in opposite directions via the SIGN of lightResponse in
-- Config/Threats. So each row below states its physical light change; the per-category
-- outcome (listed in the row comments) emerges from the numbers, never from tool-specific
-- branches in logic. A fifth tool is a new row here, nothing else.

local Types = require(script.Parent.Parent.Types)

local Tools: { [Types.ToolId]: Types.ToolDef } = {
	-- SNUFF: your flame -> zero light. The drawn lose you completely; dark-hunters gain the
	-- space (you drop below their hunt threshold). You are blind. Free (DESIGN §6).
	Snuff = {
		id = "Snuff",
		displayName = "SNUFF",
		waxCost = 0,
		cooldown = 0.5, -- seconds; higher = harder to flicker on/off
		duration = 0,
		requiresLit = false, -- also the relight action after a voluntary snuff
		togglesLit = true,
		held = false,
	},
	-- FLARE: a burst source far brighter than any flame. Repels dark-hunters, drags the drawn
	-- straight to you. Expensive.
	Flare = {
		id = "Flare",
		displayName = "FLARE",
		waxCost = 0.06, -- higher = harder
		cooldown = 4,
		duration = 1.5, -- seconds the burst lasts
		requiresLit = true,
		togglesLit = false,
		held = false,
		-- Light-field strength of the burst. Higher intensity/range = stronger repel AND stronger lure.
		burstIntensity = 3,
		burstRange = 60,
	},
	-- CAST: a thrown blob of your own wax burning on the ground. A second light source the drawn
	-- prefer over you; dark-hunters merely avoid its glow. Wax spent is gone for good.
	Cast = {
		id = "Cast",
		displayName = "CAST",
		waxCost = 0.04, -- higher = harder
		cooldown = 3,
		duration = 6, -- seconds the decoy burns; longer = more useful = easier
		requiresLit = true,
		togglesLit = false,
		held = false,
		-- Server clamps the client's aim point to this throw distance (studs).
		castRange = 25,
		-- The decoy's light-field strength. Must out-shine a dimmed player to actually divert the drawn.
		decoyIntensity = 0.8,
		decoyRange = 15,
		-- Visual diameter of the blob (studs).
		decoySize = 0.8,
	},
	-- CUP: hands around the flame. Near-dark (the drawn barely notice you), slow, immune to draft;
	-- but you can't see hunters coming and low light makes you huntable.
	Cup = {
		id = "Cup",
		displayName = "CUP",
		waxCost = 0.005, -- per SECOND held (held tool). Higher = harder.
		cooldown = 0.5,
		duration = 0, -- held: active until toggled off
		requiresLit = true,
		togglesLit = false,
		held = true,
		-- Your flame's light output while cupping. Lower = better hidden AND blinder.
		lightMultiplier = 0.08,
		-- Your movement speed while cupping. Lower = harder.
		speedMultiplier = 0.5,
	},
}

return Tools
