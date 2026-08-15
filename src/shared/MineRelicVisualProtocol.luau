--!strict
-- The whole replicated contract for an abandoned working: one tag and one named attachment.
--
-- There is no state here and there never should be. The server builds the model once and never
-- touches it again; the only thing any client does with a relic is occasionally hang an ambient
-- one-shot off it (`client/AmbientCaveDirector`), which needs to find the model and know where its
-- mass is. A relic that needed attributes would be a relic that had started doing something, and
-- dressing that does something belongs to a service (see the header of `Config/MineRelics`).

local MineRelicVisualProtocol = {
	tag = "WickMineRelic",
	-- Sits at the piece's acoustic centre rather than its pivot, which is on the floor: a creak from
	-- an ore cart should come from the cart, not from the rock under it.
	emitterName = "RelicEmitter",
}

return table.freeze(MineRelicVisualProtocol)
