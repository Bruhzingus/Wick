--!strict
-- Room footprints: the open interior shape inside a room cell.
--
-- THE ONE THING THIS SUITE IS FOR. A shape may change what a room looks like and may never change
-- what a room GUARANTEES. Every test below is a restatement of that: a footprint is contained, it is
-- one connected piece, its narrowest point is walkable, and the doorway lanes and navigation hub
-- survive it whatever it does. The connectivity checks are pure geometry on a sampled grid rather
-- than a call back into the module's own helpers — a test that asked the mask whether the mask was
-- connected would only prove it is self-consistent.

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local RoomFootprint = require(script.Parent.Parent.Logic.RoomFootprint)
local CaveFamilyRules = require(script.Parent.Parent.Logic.CaveFamilyRules)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local DoorwayGeometry = require(script.Parent.Parent.Logic.DoorwayGeometry)

local NORMALS: { [Types.Direction]: { x: number, z: number } } = {
	N = { x = 0, z = -1 },
	S = { x = 0, z = 1 },
	E = { x = 1, z = 0 },
	W = { x = -1, z = 0 },
}

local function familyById(id: string)
	local profile = CaveFamilyRules.byId(id)
	assert(profile ~= nil, "test fixture requires family " .. id)
	return profile
end

local function makeRoom(doorways: { Types.Direction }, footprint: RoomFootprint.Footprint): Types.RoomPlacement
	return {
		moduleId = "Chamber",
		gridX = 0,
		gridZ = 0,
		doorways = doorways,
		ceilingHeight = 24,
		footprint = footprint :: any,
	}
end

-- FLOOD FILL over the open mask, sampled on a fixed grid. Returns the reached set keyed by "x,z".
-- Started from the room centre, which the navigation hub guarantees is open in every footprint.
local STEP = 2
local function floodFromHub(mask: RoomFootprint.OpenMask): ({ [string]: boolean }, number)
	local half = FloorsConfig.geometry.cellSize / 2
	local function key(x: number, z: number): string
		return x .. "," .. z
	end
	local reached: { [string]: boolean } = {}
	local open = 0
	for x = -half, half, STEP do
		for z = -half, half, STEP do
			if RoomFootprint.isOpen(mask, x, z) then
				open += 1
			end
		end
	end

	local queue: { { x: number, z: number } } = { { x = 0, z = 0 } }
	reached[key(0, 0)] = true
	local head = 1
	while head <= #queue do
		local node = queue[head]
		head += 1
		for _, delta in { { x = STEP, z = 0 }, { x = -STEP, z = 0 }, { x = 0, z = STEP }, { x = 0, z = -STEP } } do
			local nx, nz = node.x + delta.x, node.z + delta.z
			if math.abs(nx) > half or math.abs(nz) > half or reached[key(nx, nz)] then
				continue
			end
			if RoomFootprint.isOpen(mask, nx, nz) then
				reached[key(nx, nz)] = true
				table.insert(queue, { x = nx, z = nz })
			end
		end
	end
	return reached, open
end

-- A point just inside the room from a doorway's threshold — where a body actually stands as it steps
-- through the opening.
local function thresholdPoint(room: Types.RoomPlacement, direction: Types.Direction, familyId: string): (number, number)
	local half = FloorsConfig.geometry.cellSize / 2
	local profile = DoorwayGeometry.profile(room.gridX, room.gridZ, direction, 1, familyId)
	local normal = NORMALS[direction]
	local inward = half - 4
	return normal.x * inward + math.abs(normal.z) * profile.offset,
		normal.z * inward + math.abs(normal.x) * profile.offset
end

local suite: Harness.Suite = {
	name = "RoomFootprint",
	tests = {
		Harness.test("the canonical rectangle is the full cell inside the wall clearance", function()
			local rectangle = RoomFootprint.rectangle()
			Harness.equal(rectangle.kind, "Rectangle")
			Harness.equal(rectangle.rotation, 0)
			Harness.equal(rectangle.roughness, 0, "the regression baseline must have no edge noise")
			local halfX, halfZ = RoomFootprint.extents(rectangle)
			Harness.near(halfX, RoomFootprint.maximumHalfExtent())
			Harness.near(halfZ, RoomFootprint.maximumHalfExtent())
			Harness.expect(RoomFootprint.isValid(rectangle), "the canonical rectangle must be valid")

			-- STONE REGRESSION: the old planner accepted anything inside this radius and nothing
			-- outside it. A full-cell rectangle must still answer exactly that question.
			local limit = RoomFootprint.maximumHalfExtent()
			local mask = RoomFootprint.maskFor(makeRoom({}, rectangle), 1, "STONE")
			Harness.expect(RoomFootprint.isOpen(mask, limit - 0.5, limit - 0.5), "just inside must be open")
			Harness.expect(not RoomFootprint.isOpen(mask, limit + 3, limit + 3), "well outside must be rock")
		end),

		Harness.test("every rolled footprint is contained, connected, and walkable at its narrowest", function()
			local rng = Random.new(90_210)
			local counts: { [string]: number } = {}
			local fallbacks = 0
			for _, profile in CaveFamilyRules.list() do
				for _ = 1, 600 do
					local result = RoomFootprint.roll(profile, rng:NextNumber(), rng)
					local footprint = result.footprint
					counts[footprint.kind] = (counts[footprint.kind] or 0) + 1
					if result.fellBack then
						fallbacks += 1
					end

					Harness.expect(
						RoomFootprint.isContained(footprint),
						profile.id .. " rolled a " .. footprint.kind .. " that leaves the cell"
					)
					Harness.expect(
						RoomFootprint.isConnected(footprint),
						profile.id .. " rolled a disconnected " .. footprint.kind
					)
					Harness.expect(
						RoomFootprint.isValid(footprint),
						profile.id .. " recorded an invalid " .. footprint.kind
					)
					if footprint.kind == "TwinLobe" then
						Harness.expect(
							RoomFootprint.neckWidth(footprint) * (1 - footprint.roughness)
								>= RoomFootprint.requiredLaneWidth(),
							"a twin lobe's neck must stay at least a navigation lane wide"
						)
					end
				end
			end
			-- All four kinds actually occur, so the assertions above are not vacuous.
			for _, kind in CaveFamilyRules.shapeKinds() do
				Harness.expect((counts[kind] or 0) > 0, "the sweep never produced a " .. kind)
			end
			-- And the fallback is genuinely a last resort rather than the common path.
			Harness.expect(fallbacks < 1_800 * 0.02, "shapes are falling back to Rectangle too often")
		end),

		Harness.test("shape selection is deterministic and follows the family's weights", function()
			local moss = familyById("MOSS")
			local rngA, rngB = Random.new(7), Random.new(7)
			for _ = 1, 200 do
				local roll = rngA:NextNumber()
				local first = RoomFootprint.roll(moss, roll, Random.new(11))
				local second = RoomFootprint.roll(moss, roll, Random.new(11))
				Harness.equal(first.footprint.kind, second.footprint.kind, "same inputs, different shape")
				Harness.near(first.footprint.primaryX, second.footprint.primaryX, 1e-9)
				Harness.near(first.footprint.rotation, second.footprint.rotation, 1e-9)
				rngB:NextNumber()
			end

			-- Moss is the twin-lobe family and Ice is the capsule family; the roll must reflect that.
			local ice = familyById("ICE")
			local mossLobes, iceCapsules = 0, 0
			for index = 0, 999 do
				local roll = index / 1000
				if CaveFamilyRules.selectShapeKind(moss, roll) == "TwinLobe" then
					mossLobes += 1
				end
				if CaveFamilyRules.selectShapeKind(ice, roll) == "Capsule" then
					iceCapsules += 1
				end
			end
			Harness.near(mossLobes / 1000, 0.3, 0.01, "Moss's twin-lobe share")
			Harness.near(iceCapsules / 1000, 0.25, 0.01, "Ice's capsule share")
		end),

		Harness.test("an ellipse and a capsule stay inside their own boundary", function()
			-- Containment as an independent geometric statement: sample the analytic form and check
			-- nothing it calls inside reaches past the extents it reports.
			local rng = Random.new(31_337)
			for _, familyId in { "STONE", "ICE" } do
				local profile = familyById(familyId)
				for _ = 1, 400 do
					local footprint = RoomFootprint.roll(profile, rng:NextNumber(), rng).footprint
					if footprint.kind ~= "Ellipse" and footprint.kind ~= "Capsule" then
						continue
					end
					local halfX, halfZ = RoomFootprint.extents(footprint)
					local limit = RoomFootprint.maximumHalfExtent()
					for x = -limit, limit, 3 do
						for z = -limit, limit, 3 do
							if RoomFootprint.inside(footprint, x, z) then
								Harness.expect(
									math.abs(x) <= halfX + 1e-3 and math.abs(z) <= halfZ + 1e-3,
									footprint.kind .. " reported extents that do not contain it"
								)
							end
						end
					end
				end
			end
		end),

		Harness.test("a twin lobe is one piece, and two separated lobes are refused", function()
			local base = RoomFootprint.rectangle()
			-- Deliberately pulled apart: the lobes no longer overlap at all.
			local split: RoomFootprint.Footprint = {
				kind = "TwinLobe",
				rotation = 0,
				centerX = 0,
				centerZ = 0,
				primaryX = 8,
				primaryZ = 8,
				secondaryX = 8,
				secondaryZ = 8,
				lobeOffset = 40,
				roughness = 0,
				roughPhase = 0,
			}
			Harness.equal(RoomFootprint.neckWidth(split), 0, "separated lobes have no neck")
			Harness.expect(not RoomFootprint.isConnected(split), "separated lobes are not one room")
			Harness.expect(not RoomFootprint.isValid(split), "a disconnected footprint must be refused")

			-- Overlapping, but through a neck too narrow for a body: still refused.
			local pinched = table.clone(split)
			pinched.lobeOffset = 15.6
			Harness.expect(RoomFootprint.isConnected(pinched), "these lobes do meet")
			Harness.expect(
				RoomFootprint.neckWidth(pinched) < RoomFootprint.requiredLaneWidth(),
				"this fixture must actually be too narrow"
			)
			Harness.expect(not RoomFootprint.isValid(pinched), "a neck below the lane width must be refused")

			-- A generous pair passes, and the whole union floods as one piece.
			local joined = table.clone(split)
			joined.primaryX, joined.primaryZ = 16, 20
			joined.secondaryX, joined.secondaryZ = 15, 19
			joined.lobeOffset = 14
			Harness.expect(RoomFootprint.isValid(joined), "a generous twin lobe must be accepted")
			local mask = RoomFootprint.maskFor(makeRoom({}, joined), 1, "MOSS")
			local reached, open = floodFromHub(mask)
			local count = 0
			for _ in reached do
				count += 1
			end
			Harness.equal(count, open, "the open footprint must be reachable as one connected piece")
			local _ = base
		end),

		Harness.test("invalid footprints are refused rather than silently repaired", function()
			local broken = RoomFootprint.rectangle()
			broken.primaryX = 0
			Harness.expect(not RoomFootprint.isValid(broken), "a zero-width footprint is not a room")
			broken.primaryX = 0 / 0
			Harness.expect(not RoomFootprint.isValid(broken), "a NaN dimension must be refused")
			broken.primaryX = RoomFootprint.maximumHalfExtent() * 4
			Harness.expect(not RoomFootprint.isValid(broken), "a footprint larger than the cell must be refused")

			local rough = RoomFootprint.rectangle()
			rough.roughness = 1.5
			Harness.expect(not RoomFootprint.isValid(rough), "roughness at or above 1 would invert the boundary")
		end),

		Harness.test("every doorway threshold reaches the navigation hub, in every footprint", function()
			-- THE pathing guarantee, restated geometrically. Whatever a shape does, a body must be able
			-- to walk from the inside of every real opening to the room's centre. The mask unions the
			-- lanes and the hub over the shape precisely so this can never fail.
			local rng = Random.new(555_111)
			local checked = 0
			for _, profile in CaveFamilyRules.list() do
				for _ = 1, 120 do
					local footprint = RoomFootprint.roll(profile, rng:NextNumber(), rng).footprint
					-- Every combination of doorways a room can actually have, up to all four.
					local doorways: { Types.Direction } = {}
					for _, direction: Types.Direction in { "N", "S", "E", "W" } do
						if rng:NextNumber() < 0.6 then
							table.insert(doorways, direction)
						end
					end
					if #doorways == 0 then
						doorways = { "N" }
					end
					local room = makeRoom(doorways, footprint)
					local mask = RoomFootprint.maskFor(room, 1, profile.id)
					local reached = floodFromHub(mask)
					for _, direction in doorways do
						local x, z = thresholdPoint(room, direction, profile.id)
						Harness.expect(
							RoomFootprint.isOpen(mask, x, z),
							string.format(
								"%s %s doorway threshold was sealed by a %s",
								profile.id,
								direction,
								footprint.kind
							)
						)
						-- Snap to the sample grid the flood fill ran on.
						local gx = math.floor(x / STEP + 0.5) * STEP
						local gz = math.floor(z / STEP + 0.5) * STEP
						Harness.expect(
							reached[gx .. "," .. gz] == true,
							string.format(
								"%s %s doorway could not reach the hub through a %s",
								profile.id,
								direction,
								footprint.kind
							)
						)
						checked += 1
					end
				end
			end
			Harness.expect(checked > 500, "the sweep must actually check a meaningful number of doorways")
		end),

		Harness.test("protected reservations are open air whatever the shape says", function()
			-- A fixture the floor cannot function without — the descent pad, the Brazier pedestal, a
			-- Warden's encounter pad — is reserved into the mask, and the union means the shape cannot
			-- take it back.
			local rng = Random.new(24_601)
			local moss = familyById("MOSS")
			for _ = 1, 300 do
				local footprint = RoomFootprint.roll(moss, rng:NextNumber(), rng).footprint
				local room = makeRoom({ "N", "E" }, footprint)
				local mask = RoomFootprint.maskFor(room, 1, moss.id)
				-- A pad way out in a corner, which most shapes would leave as solid rock.
				local padX, padZ, padRadius = 20, -20, 7
				RoomFootprint.reserve(mask, padX, padZ, padRadius)
				Harness.expect(RoomFootprint.isOpen(mask, padX, padZ), "a reserved pad must be open air")
				Harness.expect(
					RoomFootprint.containsBox(mask, Vector3.new(padX, 0, padZ), Vector3.new(4, 0, 4)),
					"a reserved pad must hold a real footprint, not just its centre point"
				)
			end
		end),

		Harness.test("the construction lip lies outside every boundary, never inside it", function()
			-- THE BUG THIS PINS. Two different questions about the same boundary, and the builder's
			-- answer has to be at least as generous as the planner's. The lip exists so the voxel face
			-- reads as erosion rather than a cliff; easing it INWARD made the outermost `blend` studs of
			-- every room — including the canonical full-cell rectangle — partly-solid Terrain, so
			-- deposits and pickups the planner had accepted came out buried in it or perched part-way
			-- up its face. Anything placement accepts must be carved as complete air.
			local mask = RoomFootprint.maskFor(makeRoom({ "N" }, RoomFootprint.rectangle()), 1, "STONE")
			local limit = RoomFootprint.maximumHalfExtent()
			Harness.expect(mask.blend > 0, "the terrain lip must have real width")
			Harness.equal(RoomFootprint.openness(mask, 0, 0), 1, "the hub is fully open")
			Harness.equal(
				RoomFootprint.openness(mask, 0, limit - 1),
				1,
				"floor a placement may use must be carved as complete air"
			)
			Harness.equal(
				RoomFootprint.openness(mask, 0, limit),
				1,
				"the boundary itself is still inside the room, so it is still air"
			)
			Harness.expect(
				RoomFootprint.isOpen(mask, 0, limit - 1),
				"a placement inside the boundary must not be refused by the construction lip"
			)
			Harness.expect(not RoomFootprint.isOpen(mask, 0, limit + 0.5), "past the boundary is rock")
			-- Openness is a real 0..1 field, monotonic outward across the boundary.
			Harness.expect(
				RoomFootprint.openness(mask, 0, limit + 0.5) < 1,
				"the lip must start easing in the moment the boundary is crossed"
			)
			Harness.expect(
				RoomFootprint.openness(mask, 0, limit + 0.5) >= RoomFootprint.openness(mask, 0, limit + 3),
				"openness must not increase as you leave the room"
			)
			-- The canonical rectangle's smallest radius IS `limit`, so its lip is exactly `blend` studs
			-- of real width measured outward along an axis.
			Harness.equal(
				RoomFootprint.openness(mask, 0, limit + mask.blend + 1),
				0,
				"past the far side of the lip is solid rock"
			)
		end),

		Harness.test("a reserved disc is open air across its whole radius, not just its centre", function()
			-- A reservation is the promise that a planned spawn cannot be buried, and it is only worth
			-- anything if the disc the caller asked for is the disc the builder carves. With the lip
			-- easing inward a disc narrower than the blend opened NOTHING — a loot spawn reserves 1.7
			-- studs against a 7-stud lip — which is why pickups ended up inside the rock even though the
			-- builder had dutifully reserved them.
			local mask = RoomFootprint.maskFor(makeRoom({ "N" }, RoomFootprint.rectangle()), 1, "STONE")
			for _, radius in { 1.7, 3.5, 6.5 } do
				local x, z = 22, -22 -- out where a full-cell rectangle's own lip used to reach
				RoomFootprint.reserve(mask, x, z, radius)
				Harness.equal(
					RoomFootprint.openness(mask, x, z),
					1,
					string.format("a %s-stud reservation must open air at its centre", tostring(radius))
				)
				Harness.equal(
					RoomFootprint.openness(mask, x + radius, z),
					1,
					string.format("a %s-stud reservation must open air out to its rim", tostring(radius))
				)
			end
		end),
	},
}

return suite
