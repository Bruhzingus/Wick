--!strict
-- Dynamite-domain types. Dynamite is a FOUND CONSUMABLE, not a fourth tool: it is not a `ToolId`, it
-- costs no wax to use, it has no cooldown, and it cannot be sacrificed away at the Basin. What it has
-- instead is a count, which is the same shape the solo-run Match already uses (`Types/Player`).
--
-- WHY IT IS NOT A TOOL ROW. `Types/Tool.ToolId` is a closed union DESIGN §6 fixes at three, and every
-- one of those three is a wax-priced light change with a cooldown that the Basin may worsen. Dynamite
-- is none of those things: it is a physical object you either have or do not have. Modelling it as a
-- fourth tool would have meant a row whose `waxCost` is zero, whose `cooldown` is zero, and whose real
-- gate — "do you have one" — no `ToolDef` field can express. The count IS the item.

export type DynamiteStyle = "Stick" | "Crate"

-- WHAT A LIVE STICK IS DOING. A thrown stick is lying on the cave floor with its fuse burning; a
-- socketed one is seated in a blast door's own charge pocket. Both detonate through exactly the same
-- blast, and the only difference is what the fuse is attached to.
export type LiveDynamiteKind = "Thrown" | "Socketed"

-- One armed stick, server-owned. Both live kinds are already lit: throwing lights a loose stick, and
-- the blast-door hold atomically seats and lights a socketed one.
export type LiveDynamite = {
	ownerId: number,
	kind: LiveDynamiteKind,
	depth: number,
	position: Vector3,
	-- os.clock() the fuse was lit. Optional only while a charge is being constructed internally; every
	-- registered live charge is lit. Never a shared-clock value: this is the authoritative fuse clock.
	litAt: number?,
	-- Index into the floor's blast doors, for a socketed stick only.
	doorIndex: number?,
}

-- WHAT SEALS A BLAST VAULT, per cave family. The rock a family is cut from is the rock across its
-- vault door, which is the whole reason this is a style rather than one shared slab: Config/CaveFamilies
-- already owns what a cave is MADE OF, and a door that ignored it would be the one man-made-looking
-- object in a natural cave.
export type BlastDoorStyle = "Rock" | "MossRock" | "Ice"

return {}
