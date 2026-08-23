--!strict
-- HOW THE DEVELOPER LABORATORY REACHES A REAL BOSS FLOOR, as pure geometry.
--
-- The laboratory builds both authored boss floors for real (server/DevTestBossFloors): the same
-- `BossFloorPlan.plan` and `UnlittiusFloorPlan.plan` an expedition gets on floors 10 and 20, through
-- the same `FloorBuilder.build`. What neither of those floors has is an OUTSIDE — a shipped boss floor
-- is arrived at down a ladder, so every doorway either plan declares faces another room on the same
-- floor. The laboratory arrives on foot, which means one extra opening cut into the entry room and a
-- corridor that meets it exactly.
--
-- WHY THAT SUM LIVES HERE RATHER THAN IN THE BUILDER. It is six numbers that all have to agree — which
-- laboratory wall the corridor leaves, where along that wall, how long it runs, how wide it is, how
-- tall it is, and where it stops — and the failure mode when they do not is invisible. The previous
-- revision of this room authored all six by hand for each arena and shipped a shrine whose corridor
-- was two studs narrower than the doorway it fed, an arena doorway on the wrong wall, and a whole
-- second chamber behind a wall with no opening in it at all. None of those threw. A room you cannot
-- reach builds perfectly.
--
-- So: ONE authored number per floor (where its grid origin sits, relative to the laboratory) plus ONE
-- authored direction (which wall of the entry room the corridor comes in through), and everything else
-- is solved from the floor plan itself. `DevTestBossApproachTests` walks the result back the other way.
--
-- THE DOORWAY IS NOT WHERE YOU WOULD GUESS, and that is the single most important reason this is
-- derived rather than authored. `DoorwayGeometry.profile` rolls a width, a height AND a lateral offset
-- from the edge's own coordinates, so the opening cut into an entry room sits up to fourteen studs off
-- that room's centre line and can be anywhere from the floor's authored minimum to `doorwayMaxWidth`
-- (45) across. The corridor follows the opening; the opening is never moved to suit the corridor.

local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local BossFloorPlan = require(script.Parent.BossFloorPlan)
local UnlittiusFloorPlan = require(script.Parent.UnlittiusFloorPlan)
local DoorwayGeometry = require(script.Parent.DoorwayGeometry)

local DevTestBossApproach = {}

export type Params = {
	-- The authored floor, already planned. Passed in rather than re-derived so the entry room's grid
	-- position can only ever come from the plan the builder is actually about to carve.
	plan: Types.FloorPlan,
	-- Which wall of the entry room the corridor is cut into.
	entranceDirection: Types.Direction,
	-- The doorway minimum this floor holds every opening to (`BossFloorPlan.DOORWAY_MINIMUM`).
	doorwayMinimum: DoorwayGeometry.FloorProfile?,
	-- The laboratory: the centre of its floor, its interior box, and how thick its walls are.
	labCenter: Vector3,
	labInterior: Vector3,
	labWallThickness: number,
	-- Corridor floor is the boss floor's own plane, so a tester walks in on the level.
	floorY: number,
	-- Minimums. The solved corridor is never smaller than the opening it backs, so these only raise a
	-- comfortable corridor above a mean one; they never shrink it into the doorway.
	minimumCorridorWidth: number,
	minimumCorridorHeight: number,
	-- Clear rock left either side of, and above, the opening where the corridor meets it.
	corridorJamb: number,
	corridorHeadroom: number,
}

export type Approach = {
	-- The entry room's world centre, at the floor's own plane.
	entryCenter: Vector3,
	entranceDirection: Types.Direction,
	-- The opening actually cut, as `DoorwayGeometry` rolled it.
	entranceWidth: number,
	entranceHeight: number,
	entranceOffset: number,
	-- The centre of that opening on the entry room's outer face, at floor level.
	entrancePosition: Vector3,
	-- Unit vector pointing out of the floor, toward the laboratory.
	outward: Vector3,
	-- The corridor, as an axis-aligned interior box. `corridorCenter` is its geometric middle, so it
	-- sits half a corridor-height above the floor.
	corridorCenter: Vector3,
	corridorSize: Vector3,
	corridorLength: number,
	corridorWidth: number,
	corridorHeight: number,
	-- Which laboratory wall to cut, and where along it. The offset runs along that wall's own long
	-- axis in laboratory-local studs: X for the north and south walls, Z for the east and west.
	labWall: string,
	labDoorwayOffset: number,
}

-- The outward normal of a doorway direction, as a unit vector. N is -Z and S is +Z, matching
-- `DoorwayGeometry.NORMAL` and therefore every wall in the game.
local NORMAL: { [Types.Direction]: Vector3 } = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

-- Which laboratory wall faces a given direction of travel. `outward` points FROM the boss floor TOWARD
-- the laboratory, so the wall the corridor arrives at is the one whose own outward normal is its
-- opposite: walk east out of a floor and you meet the laboratory's WEST face.
local OPPOSING_WALL: { [Types.Direction]: string } = {
	N = "South",
	S = "North",
	E = "West",
	W = "East",
}

function DevTestBossApproach.normal(direction: Types.Direction): Vector3
	return NORMAL[direction]
end

-- Everything the laboratory needs to reach one authored boss floor.
--
-- Returns nil rather than erroring when the floor has been placed somewhere the corridor cannot
-- physically reach — an origin so close that the entry room overlaps the laboratory, or on the wrong
-- side of it entirely. A caller that gets nil has a configuration bug, not a runtime one, and the
-- laboratory reports it and builds without that floor rather than failing to build at all.
function DevTestBossApproach.solve(params: Params): Approach?
	local plan = params.plan
	local entryRoom = plan.rooms[plan.entryRoomIndex]
	if entryRoom == nil then
		return nil
	end
	local direction = params.entranceDirection
	local outward = NORMAL[direction]
	if outward == nil then
		return nil
	end
	local cell = FloorsConfig.geometry.cellSize

	-- THE OPENING FIRST, THEN THE CORRIDOR THAT BACKS IT. Rolled from the same edge coordinates
	-- `FloorBuilder` will roll it from when it cuts the wall, so the two cannot disagree.
	local profile = DoorwayGeometry.profile(
		entryRoom.gridX,
		entryRoom.gridZ,
		direction,
		plan.globalDepth,
		plan.familyId,
		params.doorwayMinimum
	)
	local lateral = DoorwayGeometry.lateralAxis(direction)

	local entryCenter = Vector3.new(
		plan.worldOrigin.X + entryRoom.gridX * cell,
		params.floorY,
		plan.worldOrigin.Z + entryRoom.gridZ * cell
	)
	local entrancePosition = entryCenter + outward * (cell / 2) + lateral * profile.offset

	-- NEVER NARROWER OR SHORTER THAN THE OPENING. A doorway may roll anywhere up to `doorwayMaxWidth`
	-- (45), which is wider than any corridor anybody would author by hand, and the corridor walls are
	-- the only thing standing behind that opening — undersize it and the tester gets a slot either side
	-- of the door looking straight out into the void between two carved cells.
	local corridorWidth = math.max(params.minimumCorridorWidth, profile.width + params.corridorJamb * 2)
	local corridorHeight = math.max(params.minimumCorridorHeight, profile.height + params.corridorHeadroom)

	-- The laboratory face the corridor runs back to: the one pointing at the floor.
	local labWall = OPPOSING_WALL[direction]
	local interiorHalf = math.abs(outward.X) * params.labInterior.X / 2 + math.abs(outward.Z) * params.labInterior.Z / 2
	local labFace = params.labCenter - outward * (interiorHalf + params.labWallThickness)
	local corridorLength = (labFace - entrancePosition):Dot(outward)
	if corridorLength <= 0 then
		return nil
	end

	local corridorCenter = entrancePosition + outward * (corridorLength / 2) + Vector3.new(0, corridorHeight / 2, 0)
	local along = Vector3.new(math.abs(outward.X), 0, math.abs(outward.Z))
	local corridorSize = along * corridorLength + lateral * corridorWidth + Vector3.new(0, corridorHeight, 0)

	-- Where the corridor meets the laboratory, along that wall's own long axis. The corridor is
	-- straight and axis-aligned, so this is just the opening's lateral position measured from the
	-- laboratory's centre — which is exactly the number `buildBoxShell` wants for its doorway.
	local labDoorwayOffset = (entrancePosition - params.labCenter):Dot(lateral)

	return {
		entryCenter = entryCenter,
		entranceDirection = direction,
		entranceWidth = profile.width,
		entranceHeight = profile.height,
		entranceOffset = profile.offset,
		entrancePosition = entrancePosition,
		outward = outward,
		corridorCenter = corridorCenter,
		corridorSize = corridorSize,
		corridorLength = corridorLength,
		corridorWidth = corridorWidth,
		corridorHeight = corridorHeight,
		labWall = labWall,
		labDoorwayOffset = labDoorwayOffset,
	}
end

-- Every room of a built floor as a containment box, so a service that asks "is this candle still
-- inside the laboratory" can be handed the boss floors without learning what a floor is.
--
-- ONE BOX PER CELL rather than one around the lot. The floors are five rooms in a plus and a
-- horseshoe; a single bounding box around either would also contain the empty cells they leave out,
-- and a tester who fell into one of those would read as safely contained while standing in the void.
function DevTestBossApproach.roomBoxes(plan: Types.FloorPlan, floorY: number): { { center: Vector3, size: Vector3 } }
	local cell = FloorsConfig.geometry.cellSize
	local boxes = {}
	for _, room in plan.rooms do
		table.insert(boxes, {
			-- THE FLOOR PLANE, NOT THE MIDDLE OF THE ROOM. `DevTestRoomRules.isInsideRoom` treats a
			-- box centre as the floor a candle stands on and measures the height upward from it, which
			-- is how the laboratory own box has always been expressed. Handing it a mid-height centre
			-- would leave the top half of every room reading as outside the laboratory.
			center = Vector3.new(
				plan.worldOrigin.X + room.gridX * cell,
				floorY,
				plan.worldOrigin.Z + room.gridZ * cell
			),
			size = Vector3.new(cell, room.ceilingHeight, cell),
		})
	end
	return boxes
end

--------------------------------------------------------------------------------
-- The authored plan, positioned beside the laboratory
--------------------------------------------------------------------------------

export type Definition = typeof(Config.DevTestRoom.bossFloors.definitions[1])

-- WHICH DEPTH EACH FLOOR IS DRESSED AS. Not the laboratory's scope key: the scope key is what services
-- file the floor under, and this is what the floor IS. `globalDepth` seeds every doorway roll, every
-- formation and every dripstone on it, so a Queen floor built at 10 and an Unlittius floor built at 20
-- are the exact rooms a player meets at those depths rather than two that merely resemble them.
local GLOBAL_DEPTH: { [string]: number } = {
	GrubQueen = 10,
	Unlittius = 20,
}

local DOORWAY_MINIMUM: { [string]: DoorwayGeometry.FloorProfile } = {
	GrubQueen = BossFloorPlan.DOORWAY_MINIMUM,
	Unlittius = UnlittiusFloorPlan.DOORWAY_MINIMUM,
}

-- The authored plan for one boss, placed beside the laboratory and opened onto its corridor.
--
-- `worldOrigin` carries only X and Z; the height travels in `plan.floorY`, because `FloorStacking`
-- derives the descent pad from `worldOrigin` and would otherwise count the laboratory's altitude
-- twice — once through the pad and once through the floor plane.
function DevTestBossApproach.planFor(
	definition: Definition,
	labCenter: Vector3,
	familyId: string,
	depth: number
): Types.FloorPlan?
	local globalDepth = GLOBAL_DEPTH[definition.bossId]
	if globalDepth == nil then
		return nil
	end
	local worldOrigin =
		Vector3.new(labCenter.X + definition.worldOriginOffset.X, 0, labCenter.Z + definition.worldOriginOffset.Z)
	local plan: Types.FloorPlan
	if definition.bossId == "GrubQueen" then
		plan = BossFloorPlan.plan(globalDepth, depth, familyId, worldOrigin)
	elseif definition.bossId == "Unlittius" then
		plan = UnlittiusFloorPlan.plan(globalDepth, depth, familyId, worldOrigin)
	else
		return nil
	end
	plan.floorY = labCenter.Y

	-- THE ONE EDIT THE LABORATORY MAKES TO AN AUTHORED FLOOR, and it is purely additive: the entry room
	-- gains the wall the corridor comes in through. Nothing is moved and nothing is removed, so every
	-- other opening, every fixture offset and every ceiling height is the shipped one. The doorway is
	-- still CUT by `FloorBuilder` from `DoorwayGeometry` at whatever width and offset that rolls;
	-- `solve` below follows the opening rather than the opening being moved to suit the corridor.
	local entryRoom = plan.rooms[plan.entryRoomIndex]
	if entryRoom ~= nil then
		local already = false
		for _, existing in entryRoom.doorways do
			if existing == definition.entranceDirection then
				already = true
			end
		end
		if not already then
			table.insert(entryRoom.doorways, definition.entranceDirection :: any)
		end
	end
	return plan
end

-- The plan and the way in, together — what every caller actually wants. Returns nil if the floor
-- cannot be planned or cannot be reached from where it has been placed.
function DevTestBossApproach.forDefinition(
	definition: Definition,
	labCenter: Vector3,
	familyId: string,
	depth: number
): (Types.FloorPlan?, Approach?)
	local plan = DevTestBossApproach.planFor(definition, labCenter, familyId, depth)
	if plan == nil then
		return nil, nil
	end
	local room = Config.DevTestRoom.room
	local floors = Config.DevTestRoom.bossFloors
	local approach = DevTestBossApproach.solve({
		plan = plan,
		entranceDirection = definition.entranceDirection :: any,
		doorwayMinimum = DOORWAY_MINIMUM[definition.bossId],
		labCenter = labCenter,
		labInterior = room.interiorSize,
		labWallThickness = room.wallThickness,
		floorY = labCenter.Y,
		minimumCorridorWidth = floors.corridorWidth,
		minimumCorridorHeight = floors.corridorHeight,
		corridorJamb = floors.wallThickness,
		-- Two studs of rock above the opening, so the lintel reads as a lintel rather than the corridor
		-- ceiling running straight into the room.
		corridorHeadroom = 2,
	})
	if approach == nil then
		return nil, nil
	end
	return plan, approach
end

return DevTestBossApproach
