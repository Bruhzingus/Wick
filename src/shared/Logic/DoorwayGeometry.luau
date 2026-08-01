--!strict
-- Pure, deterministic doorway geometry shared by the builder (which cuts the opening) and the
-- navigation (which aims threats through it). Both adjacent rooms roll the identical width, height,
-- and lateral offset from ONE shared edge seed, so the physical hole and the AI's aim always agree —
-- even though openings vary from a tight crevice to a near-room-wide, off-centre breach.

local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local Types = require(script.Parent.Parent.Types)
local CaveFamilyRules = require(script.Parent.CaveFamilyRules)

local DoorwayGeometry = {}

export type Profile = { width: number, height: number, offset: number }

local NORMAL: { [Types.Direction]: { x: number, z: number } } = {
	N = { x = 0, z = -1 },
	S = { x = 0, z = 1 },
	E = { x = 1, z = 0 },
	W = { x = -1, z = 0 },
}

-- The doubled edge midpoint is identical from either adjacent room, so both sides seed the same rng.
--
-- `familyId` applies the cave family's doorway-width bias (Moss tighter, Ice wider). BOTH ADJACENT
-- ROOMS ARE ON THE SAME FLOOR AND THEREFORE IN THE SAME FAMILY, so the shared opening still rolls
-- one identical profile from either side. The bias is clamped inside
-- CaveFamilyRules.doorwayWidth against the mandatory lane width: a family may make its openings
-- tighter on average and can never make one impassable. An absent id resolves to the free family,
-- whose bias is exactly 1 — so a caller that has not been given a family gets the pre-family
-- geometry rather than a wrong one.
function DoorwayGeometry.profile(
	gridX: number,
	gridZ: number,
	direction: Types.Direction,
	depth: number,
	familyId: string?
): Profile
	local g = FloorsConfig.geometry
	local normal = NORMAL[direction]
	local edgeX2 = gridX * 2 + normal.x
	local edgeZ2 = gridZ * 2 + normal.z
	local seed = math.abs(edgeX2 * 92_837_111 + edgeZ2 * 689_287_499 + depth * 283_923_481) % 2_147_483_647
	local rng = Random.new(seed)
	-- Bias toward tighter openings (^2) so wide breaches feel earned and rare.
	local roll = rng:NextNumber() ^ 2
	local rolledWidth = g.doorwayMinWidth + (g.doorwayMaxWidth - g.doorwayMinWidth) * roll
	local width = CaveFamilyRules.doorwayWidth(CaveFamilyRules.resolve(familyId), rolledWidth)
	local height = rng:NextNumber(g.doorwayMinHeight, g.doorwayMaxHeight)
	local maxOffset = math.max(0, g.cellSize / 2 - width / 2 - g.doorwayCornerMargin)
	local offset = rng:NextNumber(-1, 1) * maxOffset
	return { width = width, height = height, offset = offset }
end

-- The wall's long (lateral) axis for a given doorway direction — the axis its offset runs along.
function DoorwayGeometry.lateralAxis(direction: Types.Direction): Vector3
	local normal = NORMAL[direction]
	return Vector3.new(math.abs(normal.z), 0, math.abs(normal.x))
end

return DoorwayGeometry
