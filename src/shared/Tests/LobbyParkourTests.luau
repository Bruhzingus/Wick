--!strict
-- The lobby platform course is the one fixture in the hub whose CONFIG IS ITS DESIGN: the route is a
-- list of coordinates, and nothing in the builder can be inspected to find out whether it is still
-- climbable, or still un-skippable. That has already gone wrong — the first build ran switchback lanes
-- twelve studs apart with one-stud rises, and a player could jump clean ACROSS from the low lane to
-- the high one and cut out half the course. Nothing caught it but a screenshot.
--
-- These re-derive both properties from the same jump physics the layout is authored against, so a
-- retune that reopens the shortcut fails here rather than shipping.

local Harness = require(script.Parent.Harness)
local Config = require(script.Parent.Parent.Config)

-- Roblox's default workspace gravity. Nothing in this project changes it (EnvironmentSetup owns
-- Lighting and FallenPartsDestroyHeight and deliberately not this), so the lobby body's jump is the
-- engine default arc driven by `LobbyRoom.jumpPower`.
local GRAVITY = 196.2

local function jumpPower(): number
	return Config.LobbyRoom.jumpPower
end

-- The highest a standing jump gets, ever. A landing further above you than this cannot be reached no
-- matter how much run-up there is, which is what keeps the return leg out of reach of the out leg.
local function maximumRise(): number
	return jumpPower() * jumpPower() / (2 * GRAVITY)
end

-- How much GROUND a jump covers on the way to a landing `rise` studs up, at full lobby run speed:
-- the later root of `rise = v*t - g*t^2/2`, times `runSpeed`. Negative means the rise is unreachable.
local function reachAtRise(rise: number): number
	local v = jumpPower()
	local discriminant = v * v - 2 * GRAVITY * rise
	if discriminant < 0 then
		return -1
	end
	return ((v + math.sqrt(discriminant)) / GRAVITY) * Config.LobbyRoom.runSpeed
end

type Landing = {
	index: number,
	x: number,
	y: number,
	z: number,
	halfX: number,
	halfZ: number,
	depth: number,
}

-- The same resolution `LobbyRoomBuilder.buildParkour` performs: the authored surface point, and each
-- style's own depth hung below it.
local function landings(): { Landing }
	local course = Config.LobbyRoom.parkour
	local built: { Landing } = {}
	for index, step in course.steps do
		local depth = if step.style == "Crate"
			then course.crateDepth
			elseif step.style == "Barrel" then course.barrelHeight
			elseif step.style == "Girder" then course.girderThickness
			elseif step.style == "Track" then course.trackThickness
			elseif step.style == "Deck" then course.deckThickness
			else course.plankThickness
		table.insert(built, {
			index = index,
			x = step.offset.X,
			y = step.offset.Y,
			z = step.offset.Z,
			halfX = step.size.X / 2,
			halfZ = step.size.Y / 2,
			depth = depth,
		})
	end
	return built
end

-- Edge to edge on the floor plane. Zero on an axis the two landings already overlap on.
local function gapBetween(from: Landing, to: Landing): number
	local dx = math.max(0, math.abs(to.x - from.x) - from.halfX - to.halfX)
	local dz = math.max(0, math.abs(to.z - from.z) - from.halfZ - to.halfZ)
	return math.sqrt(dx * dx + dz * dz)
end

local suite: Harness.Suite = {
	name = "LobbyParkour",
	tests = {
		Harness.test("every platform is reachable from the one before it", function()
			local built = landings()
			Harness.expect(#built >= 6, "a course this short is not worth having")
			for index = 2, #built do
				local rise = built[index].y - built[index - 1].y
				local reach = reachAtRise(rise)
				Harness.expect(
					reach > 0,
					string.format("platform %d is %.2f studs up, past the jump entirely", index, rise)
				)
				local gap = gapBetween(built[index - 1], built[index])
				-- Inside the arc on purpose. This course is meant to bite because the landings are slim,
				-- never because a jump sits at the edge of what the engine allows: a jump you fail for
				-- want of a stud of run-up, eighteen studs up, reads as broken rather than as difficult.
				Harness.expect(
					gap <= reach * 0.8,
					string.format(
						"platform %d is %.0f%% of the reach available at that rise; difficulty belongs in the landing size",
						index,
						gap / reach * 100
					)
				)
			end
		end),

		Harness.test("the jumps are worth making", function()
			-- The first build of this was four and five stud hops a player could walk off the end of.
			-- At least half the course has to be a jump you actually commit to.
			local built = landings()
			local real = 0
			for index = 2, #built do
				local reach = reachAtRise(built[index].y - built[index - 1].y)
				if gapBetween(built[index - 1], built[index]) >= reach * 0.55 then
					real += 1
				end
			end
			Harness.expect(
				real * 2 >= #built - 1,
				string.format("only %d of %d jumps are more than half the available reach", real, #built - 1)
			)
		end),

		Harness.test("the landings get slimmer than they start", function()
			local built = landings()
			local widest, narrowest = 0, math.huge
			for _, landing in built do
				widest = math.max(widest, math.min(landing.halfX, landing.halfZ) * 2)
			end
			-- The summit deck is deliberately wide, so the narrowest is measured over the route itself.
			for index = 1, #built - 1 do
				narrowest = math.min(narrowest, math.min(built[index].halfX, built[index].halfZ) * 2)
			end
			Harness.expect(narrowest <= 1.6, string.format("the slimmest landing is %.2f studs", narrowest))
			Harness.expect(widest >= narrowest * 2)
		end),

		Harness.test("no platform can be skipped", function()
			local built = landings()
			for from = 1, #built do
				for to = from + 2, #built do
					local rise = built[to].y - built[from].y
					local reach = reachAtRise(rise)
					if reach >= 0 then
						local gap = gapBetween(built[from], built[to])
						Harness.expect(
							gap > reach,
							string.format(
								"platform %d can be jumped straight to platform %d (%.2f studs up, %.2f across, %.2f of reach)",
								from,
								to,
								rise,
								gap,
								reach
							)
						)
					end
				end
			end
		end),

		Harness.test("the course cannot be entered above its second platform", function()
			-- Platforms low enough to be jumped onto from the floor are entry points. One is the way in and
			-- two is harmless; three would mean the bottom of the course is decorative.
			local entryPoints = 0
			for _, landing in landings() do
				if landing.y <= maximumRise() then
					entryPoints += 1
				end
			end
			Harness.expect(
				entryPoints <= 2,
				string.format("%d platforms can be reached straight from the floor", entryPoints)
			)
		end),

		Harness.test("no platform hangs over another one a player can stand on", function()
			-- Two platforms sharing floor space is fine as long as the upper one is not low enough to be
			-- stood into. The route does not stack today; this is here so a later reshuffle that folds it
			-- back over itself has to notice.
			local built = landings()
			for _, below in built do
				for _, above in built do
					local overlaps = math.abs(above.x - below.x) < below.halfX + above.halfX
						and math.abs(above.z - below.z) < below.halfZ + above.halfZ
					local clearance = (above.y - above.depth) - below.y
					if above.index ~= below.index and overlaps and clearance > 0 then
						Harness.expect(
							clearance > 5.2,
							string.format(
								"platform %d has only %.2f studs of headroom under platform %d",
								below.index,
								clearance,
								above.index
							)
						)
					end
				end
			end
		end),

		Harness.test("the course clears the hub's roof and stands clear of the room's fixtures", function()
			local room = Config.LobbyRoom
			local course = room.parkour
			local built = landings()

			local summit = 0
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			for _, landing in built do
				summit = math.max(summit, landing.y)
				minX = math.min(minX, course.originOffset.X + landing.x - landing.halfX)
				maxX = math.max(maxX, course.originOffset.X + landing.x + landing.halfX)
				minZ = math.min(minZ, course.originOffset.Z + landing.z - landing.halfZ)
				maxZ = math.max(maxZ, course.originOffset.Z + landing.z + landing.halfZ)
			end

			-- `buildShell` hangs its ceiling beams 1.4 studs deep just under `wallHeight`, so the lowest
			-- thing over the summit is wallHeight - 1.4. A player is about five studs tall, and the lamp
			-- post stands on the summit deck on top of that.
			local beamUnderside = room.wallHeight - 1.4
			Harness.expect(
				summit + 5 < beamUnderside,
				string.format(
					"a player on the summit at %.1f reaches the ceiling beams at %.1f",
					summit + 5,
					beamUnderside
				)
			)
			Harness.expect(summit + course.lampPostHeight + course.lampShadeSize.Y < beamUnderside)

			local halfWidth = room.roomWidth / 2 - room.wallThickness
			local halfDepth = room.roomDepth / 2 - room.wallThickness
			Harness.expect(minX > -halfWidth and maxX < halfWidth, "the course reaches a side wall")
			Harness.expect(minZ > -halfDepth and maxZ < halfDepth, "the course reaches an end wall")
			-- Clear of the elevator band and of the two standings boards on the east wall, which are the
			-- parts of this room a player actually came here to reach.
			Harness.expect(maxZ < room.elevators[1].offset.Z - room.elevatorCarDepth / 2)
			Harness.expect(minZ > room.leaderboardOffset.Z + room.leaderboardHeight / 2)
			Harness.expect(minZ > room.updateBoardOffset.Z + room.updateBoardHeight / 2)
			-- Clear of the loaded wax carts `buildProps` parks around the room.
			for _, cart in room.mineCarts.waxCartOffsets do
				local clear = math.abs(cart.offset.X - (minX + maxX) / 2)
						> (maxX - minX) / 2 + room.mineCarts.floorSize.X
					or math.abs(cart.offset.Z - (minZ + maxZ) / 2) > (maxZ - minZ) / 2 + room.mineCarts.floorSize.Z
				Harness.expect(clear, "the course is built on top of a parked wax cart")
			end
		end),
	},
}

return suite
