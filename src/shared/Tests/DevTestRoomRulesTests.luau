--!strict

local Harness = require(script.Parent.Harness)
local Config = require(script.Parent.Parent.Config)
local DevTestRoomRules = require(script.Parent.Parent.Logic.DevTestRoomRules)
local DevTestBossApproach = require(script.Parent.Parent.Logic.DevTestBossApproach)

local suite: Harness.Suite = {
	name = "DevTestRoomRules",
	tests = {
		Harness.test("only the doorway remote actions are accepted", function()
			Harness.expect(DevTestRoomRules.isRemoteAction("sync"))
			Harness.expect(DevTestRoomRules.isRemoteAction("enter"))
			Harness.expect(DevTestRoomRules.isRemoteAction("clear"))
			-- The held sprint key. A remote action for the same reason the clear hotkey is one: it has no
			-- button, and needing one would defeat it.
			Harness.expect(DevTestRoomRules.isRemoteAction("sprint"))
			Harness.equal(DevTestRoomRules.isRemoteAction("spawn:DarkCrawler"), false)
			Harness.equal(DevTestRoomRules.isRemoteAction(610), false)
		end),

		Harness.test("the convenience PIN must be exact and bounded", function()
			Harness.expect(DevTestRoomRules.isValidCode("0610", "0610"))
			Harness.equal(DevTestRoomRules.isValidCode("610", "0610"), false)
			Harness.equal(DevTestRoomRules.isValidCode(string.rep("0", 17), "0610"), false)
			Harness.equal(DevTestRoomRules.isValidCode(610, "0610"), false)
		end),

		Harness.test("physical use distance includes its boundary", function()
			local terminal = Vector3.new(10, 2, -4)
			Harness.expect(DevTestRoomRules.isWithinRange(Vector3.new(13, 6, -4), terminal, 5))
			Harness.equal(DevTestRoomRules.isWithinRange(Vector3.new(16, 2, -4), terminal, 5), false)
			Harness.equal(DevTestRoomRules.isWithinRange(nil, terminal, 5), false)
			Harness.equal(DevTestRoomRules.isWithinRange(terminal, terminal, -1), false)
		end),

		Harness.test("session containment includes the authored room and bounded margin", function()
			local floorCenter = Vector3.new(100, 20, -50)
			local size = Vector3.new(64, 30, 64)
			Harness.expect(DevTestRoomRules.isInsideRoom(Vector3.new(135, 53, -50), floorCenter, size, 3))
			Harness.equal(DevTestRoomRules.isInsideRoom(Vector3.new(135.01, 53, -50), floorCenter, size, 3), false)
			Harness.equal(DevTestRoomRules.isInsideRoom(Vector3.new(100, 16.99, -50), floorCenter, size, 3), false)
			Harness.equal(DevTestRoomRules.isInsideRoom(nil, floorCenter, size, 3), false)
		end),

		Harness.test("containment is an OR of rooms, not a box around all of them", function()
			-- THE WHOLE REASON `isInsideAnyRoom` EXISTS. The laboratory, the corridor east out of it and
			-- the boss arena form an L, and a single bounding box around the three would admit the large
			-- empty volume off the corner — outside every wall, and reachable only by a player who should
			-- have been ejected. Each room is checked on its own so that volume stays out.
			local boxes = {
				{ center = Vector3.new(0, 0, 0), size = Vector3.new(40, 20, 40) },
				{ center = Vector3.new(40, 0, 10), size = Vector3.new(40, 12, 10) },
				{ center = Vector3.new(90, 0, 10), size = Vector3.new(40, 20, 40) },
			}
			Harness.expect(DevTestRoomRules.isInsideAnyRoom(Vector3.new(0, 4, 0), boxes, 2), "the main room")
			Harness.expect(DevTestRoomRules.isInsideAnyRoom(Vector3.new(40, 4, 10), boxes, 2), "the corridor")
			Harness.expect(DevTestRoomRules.isInsideAnyRoom(Vector3.new(90, 4, 10), boxes, 2), "the arena")
			Harness.equal(
				DevTestRoomRules.isInsideAnyRoom(Vector3.new(45, 4, -25), boxes, 2),
				false,
				"the corner off the L is outside every room"
			)
			Harness.equal(DevTestRoomRules.isInsideAnyRoom(nil, boxes, 2), false)
			Harness.equal(DevTestRoomRules.isInsideAnyRoom(Vector3.new(0, 4, 0), {}, 2), false)
		end),

		Harness.test("both boss floors are the authored ones, placed where the laboratory can reach", function()
			-- THE ROOMS AT THE END OF THESE CORRIDORS ARE NOT AUTHORED HERE ANY MORE, which is what this
			-- test exists to hold. The laboratory used to reach two Part boxes — a 96-cube and a 64-cube —
			-- described by twelve config numbers apiece, and every assertion in this file's previous
			-- version was checking that those twelve numbers were self-consistent. They were, and the
			-- boxes were still not her floor and his floor.
			--
			-- What is checked now is the JOIN: that the two authored plans, placed where the config puts
			-- them, are reachable on foot from the laboratory without the corridor cutting through
			-- anything, undersizing a doorway, or opening on a wall that already has a board on it.
			local room = Config.DevTestRoom.room
			local cfg = Config.DevTestRoom.bossFloors
			local cell = Config.Floors.geometry.cellSize
			local labCenter = Vector3.new(0, 0, 0)
			local session = Config.DevTestRoom.session

			Harness.equal(#cfg.definitions, 2, "the laboratory reaches exactly the two authored boss floors")

			type Solved = {
				id: string,
				plan: any,
				approach: any,
				cells: { { low: Vector3, high: Vector3 } },
			}
			local solved: { Solved } = {}
			local wallsUsed: { [string]: string } = {}

			for _, definition in cfg.definitions do
				local plan, approach =
					DevTestBossApproach.forDefinition(definition, labCenter, session.familyId, session.depth)
				Harness.expect(plan ~= nil, definition.id .. " could not be planned")
				Harness.expect(approach ~= nil, definition.id .. " cannot be reached from the laboratory")
				if plan == nil or approach == nil then
					continue
				end

				-- IT IS THE SHIPPED FLOOR. Five rooms, the boss flag, and the entry room carrying exactly
				-- one doorway more than the plan declares — the one the corridor comes in through.
				Harness.equal(#plan.rooms, 5, definition.id .. " is not a five-room authored floor")
				Harness.equal(plan.bossEncounter, true, definition.id .. " is not flagged as a boss floor")
				Harness.equal(plan.floorY, labCenter.Y, definition.id .. " is not built at the laboratory's height")
				local entry = plan.rooms[plan.entryRoomIndex]
				local hasEntrance = false
				for _, direction in entry.doorways do
					if direction == definition.entranceDirection then
						hasEntrance = true
					end
				end
				Harness.expect(hasEntrance, definition.id .. "'s entry room never gained the way in")

				-- THE CORRIDOR BACKS THE OPENING, whatever that opening rolled to. `DoorwayGeometry` can
				-- return anything from the floor's own minimum up to `doorwayMaxWidth` (45) and offset it
				-- up to fourteen studs off the room's centre line, so a hand-authored corridor width is a
				-- coin flip. Anything the corridor does not cover is a slot beside the door looking
				-- straight out into the void between two carved cells.
				Harness.expect(
					approach.corridorWidth >= approach.entranceWidth,
					definition.id .. "'s corridor is narrower than the doorway it feeds"
				)
				Harness.expect(
					approach.corridorHeight >= approach.entranceHeight,
					definition.id .. "'s corridor is shorter than the doorway it feeds"
				)
				Harness.expect(
					approach.corridorHeight <= room.interiorSize.Y,
					definition.id .. "'s corridor is taller than the laboratory wall it leaves through"
				)
				-- Long enough that the floor reads as a PLACE you went to rather than an alcove off the
				-- laboratory: the doorway at one end must not be in shot from the other.
				Harness.expect(
					approach.corridorLength >= cell / 2,
					definition.id .. "'s corridor is too short to be a threshold"
				)

				-- No two floors may leave by the same wall: the openings are placed from solved offsets
				-- that neither knows about, so two on one wall is two openings that can overlap.
				Harness.equal(
					wallsUsed[approach.labWall],
					nil,
					string.format(
						"%s and %s both leave by the laboratory's %s wall",
						definition.id,
						tostring(wallsUsed[approach.labWall]),
						approach.labWall
					)
				)
				wallsUsed[approach.labWall] = definition.id

				local cells = {}
				for _, placement in plan.rooms do
					local center = Vector3.new(
						plan.worldOrigin.X + placement.gridX * cell,
						0,
						plan.worldOrigin.Z + placement.gridZ * cell
					)
					table.insert(cells, {
						low = center - Vector3.new(cell / 2, 0, cell / 2),
						high = center + Vector3.new(cell / 2, 0, cell / 2),
					})
				end
				table.insert(solved, { id = definition.id, plan = plan, approach = approach, cells = cells })
			end

			-- NOTHING MAY BE INSIDE ANYTHING ELSE. Terrain is written per cell and Part corridors are
			-- written per approach, and neither knows the other exists — the whole point of solving these
			-- from one origin each is that this check can be made at all.
			local labLow = Vector3.new(
				-room.interiorSize.X / 2 - room.wallThickness,
				0,
				-room.interiorSize.Z / 2 - room.wallThickness
			)
			local labHigh = -labLow
			local function overlapsXZ(aLow: Vector3, aHigh: Vector3, bLow: Vector3, bHigh: Vector3): boolean
				return aLow.X < bHigh.X and bLow.X < aHigh.X and aLow.Z < bHigh.Z and bLow.Z < aHigh.Z
			end
			local corridors = {}
			for _, entry in solved do
				local half = entry.approach.corridorSize / 2
				table.insert(corridors, {
					id = entry.id,
					low = Vector3.new(
						entry.approach.corridorCenter.X - half.X,
						0,
						entry.approach.corridorCenter.Z - half.Z
					),
					high = Vector3.new(
						entry.approach.corridorCenter.X + half.X,
						0,
						entry.approach.corridorCenter.Z + half.Z
					),
				})
			end
			for indexA, entry in solved do
				for _, cellBox in entry.cells do
					Harness.equal(
						overlapsXZ(cellBox.low, cellBox.high, labLow, labHigh),
						false,
						entry.id .. " has a carved room inside the laboratory"
					)
					-- A corridor is allowed to end AT its own floor's entry room and nowhere else. It is
					-- a Part tube in open space, and a tube that clips a carved cell is a tube whose
					-- walls are buried in that room's rock.
					for indexB, corridor in corridors do
						if indexB == indexA then
							continue
						end
						Harness.equal(
							overlapsXZ(cellBox.low, cellBox.high, corridor.low, corridor.high),
							false,
							string.format("%s's corridor runs through a room of %s", corridor.id, entry.id)
						)
					end
					for indexB, other in solved do
						if indexB <= indexA then
							continue
						end
						for _, otherCell in other.cells do
							Harness.equal(
								overlapsXZ(cellBox.low, cellBox.high, otherCell.low, otherCell.high),
								false,
								string.format("%s and %s overlap", entry.id, other.id)
							)
						end
					end
				end
			end
		end),

		Harness.test("entity controls stay cave-grouped, compact and fully documented", function()
			local actionIds: { [string]: boolean } = {}
			local spawnIds: { [string]: boolean } = {}
			local pickerGroupCounts: { [string]: number } = {}
			local actionCount = 0
			local controls = Config.DevTestRoom.controls
			for _, board in Config.DevTestRoom.controls.boards do
				-- FIVE, NOT FOUR, SINCE THE PACK GAINED UNLITTIUS. The cap exists to keep the console
				-- readable from one standing position rather than to pin a number, and the two checks
				-- below are what actually keep a deep group honest: they re-derive the header clearance
				-- and the bottom edge from this board's own height, so a sixth row or a shorter panel
				-- fails here instead of quietly overrunning the paint.
				Harness.expect(board.maxRows <= 5)
				-- THE REFLOW BUDGET, asserted rather than trusted. DevTestRoomBuilder computes every
				-- button position from `buttonSize`/`buttonSpacing`/`buttonTopInset` and the group's
				-- `columns`, and it has no way to notice that the result has run off its own panel: a
				-- board too small for its buttons builds perfectly and just looks broken in Studio. The
				-- 0.33 is where `groupHeader` stops drawing (position 0.19 + height 0.14 in board scale).
				local totalColumns = 0
				for _, group in board.groups do
					totalColumns += math.max(1, math.floor(group.columns))
				end
				Harness.expect((totalColumns - 1) * controls.buttonSpacing.X + controls.buttonSize.X <= board.size.X)
				Harness.expect(controls.buttonTopInset - controls.buttonSize.Y / 2 >= board.size.Y * 0.33)
				Harness.expect(
					controls.buttonTopInset + (board.maxRows - 1) * controls.buttonSpacing.Y + controls.buttonSize.Y / 2
						<= board.size.Y
				)
				for _, group in board.groups do
					Harness.expect(group.columns >= 1)
					Harness.expect(math.ceil(#group.definitions / group.columns) <= board.maxRows)
					if board.id == "entities" then
						pickerGroupCounts[group.id] = #group.definitions
					end
					for _, definition in group.definitions do
						Harness.equal(actionIds[definition.actionId], nil)
						actionIds[definition.actionId] = true
						actionCount += 1
						local entityId = string.match(definition.actionId, "^spawn:(.+)$")
						if entityId ~= nil then
							spawnIds[entityId] = true
						end
					end
				end
			end
			Harness.equal(actionCount, 23)
			-- ARM CAVE replaced the three per-family columns. Three buttons instead of six, and the
			-- variant coverage went from one cave to all three — that trade is the point of the layout.
			Harness.equal(pickerGroupCounts.CAVE, 3)
			Harness.equal(pickerGroupCounts.SHARED, 4)
			-- The pack is family-agnostic like SHARED but gets its own column: five bespoke encounters a
			-- tester should find together rather than at the bottom of an eight-deep shared list. The
			-- fifth is UNLITTIUS, which is why the picker board is the tall one — see `buttonTopInset`.
			Harness.equal(pickerGroupCounts.PACK, 5)
			-- The armed cave's own two creatures: one signature, one Warden, both resolved at press time.
			Harness.equal(pickerGroupCounts.SIGNATURE, 2)
			Harness.isNil(pickerGroupCounts.STONE, "per-family columns were replaced by ARM CAVE")
			Harness.isNil(pickerGroupCounts.MOSS, "per-family columns were replaced by ARM CAVE")
			Harness.isNil(pickerGroupCounts.ICE, "per-family columns were replaced by ARM CAVE")

			local guideIds: { [string]: boolean } = {}
			local guideGroupCounts: { [string]: number } = {}
			local guideCount = 0
			for _, board in Config.DevTestRoom.guide.boards do
				for _, group in board.groups do
					guideGroupCounts[group.id] = #group.entries
					for _, entry in group.entries do
						Harness.equal(guideIds[entry.entityId], nil)
						guideIds[entry.entityId] = true
						guideCount += 1
					end
				end
			end
			-- 10 before the wick pack's own guide board, 14 with it, and 15 with Unlittius (DESIGN §9b).
			--
			-- HIS BUTTON IS NOT A SPAWN, WHATEVER ITS ACTION ID SAYS. `spawn:Unlittius` runs the same
			-- `startShrineEncounter` the prompt inside the shrine does, because he is an encounter with a
			-- dais, a candle ring and a ceiling and none of that can be dropped on the laboratory floor.
			-- It carries the `spawn:` prefix so the loop below still demands a guide entry for him — a
			-- tester who has not read `Config/Unlittius` has no other way to learn he cannot be damaged.
			Harness.equal(guideCount, 15)
			Harness.equal(guideGroupCounts.SHARED, 4)
			Harness.equal(guideGroupCounts.PACK, 5)
			Harness.equal(guideGroupCounts.STONE, 2)
			Harness.equal(guideGroupCounts.MOSS, 2)
			Harness.equal(guideGroupCounts.ICE, 2)
			-- SIGNATURE and WARDEN are meta-actions rather than creatures: which body they produce is
			-- decided by the armed cave at press time, so they have no guide entry of their own and every
			-- creature they can resolve to has one instead. Everything else must be documented directly.
			local META_ACTIONS = { Signature = true, Warden = true }
			for entityId in spawnIds do
				if not META_ACTIONS[entityId] then
					Harness.expect(guideIds[entityId] == true, entityId .. " has a button but no guide entry")
				end
			end
			for _, entityId in { "Listener", "Knotwalker", "Calver", "StoneWarden", "MossWarden", "IceWarden" } do
				Harness.expect(
					guideIds[entityId] == true,
					entityId .. " is reachable through a meta-action and must stay documented"
				)
			end
		end),

		Harness.test("the route chamber still holds its four-cell cycle, with room around it", function()
			local room = Config.DevTestRoom.room
			local geometry = Config.Floors.geometry
			-- THE CYCLE IS UNCHANGED AND THE ROOM GREW AROUND IT. `buildRouteDividers` places its arches
			-- at +-halfCell from the centre regardless of the interior, so the 2x2 grid RoomNavigation
			-- receives is still exactly four cells — what the extra width buys is an apron for a Gnawer's
			-- forty-stud charge and headroom for the Queen. Asserted as "at least the cycle, square, and
			-- a whole number of cells" so the cycle can never be squeezed out and the bays stay aligned.
			Harness.expect(room.interiorSize.X >= geometry.cellSize * 2, "the four-cell cycle must still fit")
			Harness.equal(room.interiorSize.X, room.interiorSize.Z, "the chamber must stay square")
			Harness.equal(room.interiorSize.X % geometry.cellSize, 0, "the interior must be whole cells")
			-- Tall enough for the creature authored for the largest chamber in the game
			-- (Logic/BossFloorPlan gives the Queen a 46-stud ceiling).
			Harness.expect(room.interiorSize.Y >= 46, "the Queen must physically fit in the laboratory")
			Harness.expect(room.routeOpeningWidth <= geometry.cellSize)
			Harness.expect(room.routeOpeningWidth >= geometry.cellSize - geometry.doorwayCornerMargin * 2)
			Harness.expect(room.routeOpeningHeight >= geometry.doorwayMaxHeight)

			local noiseDistance = (room.noiseLocalPosition - room.threatLocalPosition).Magnitude
			Harness.expect(noiseDistance + 5 < Config.Sound.emitters.MineBreak.radius)
			local calverStrike = Config.Threats.definitions.Calver.ceilingStrike
			if calverStrike == nil then
				error("Calver test coverage requires its ceiling-strike profile")
			end
			Harness.expect(
				(room.threatLocalPosition - room.hazardLocalPosition).Magnitude + 5 + calverStrike.patrolRadius
					<= calverStrike.strikeRadius
			)
		end),

		--------------------------------------------------------------------------------
		-- Console board layout
		--
		-- The button-width guard, actionId uniqueness and "every spawn button has a guide entry" are
		-- all already asserted by the entity-controls test above; what follows is only what that test
		-- does not cover, because widening a board to fit the wick-pack column touches two things it
		-- never had reason to look at.
		--------------------------------------------------------------------------------

		Harness.test("the ceiling lights actually reach the floor and cover the room", function()
			-- THE EXACT WAY THIS BROKE. The fixtures hang from the ceiling, so their range has to span the
			-- full interior height before any of it lands on the floor — and when the room grew from 30
			-- studs tall to 52, a range of 36 silently stopped reaching. Nothing errors, the lights build
			-- perfectly, and the room is simply dark below head height.
			local room = Config.DevTestRoom.room
			local lighting = Config.DevTestRoom.lighting
			Harness.expect(
				lighting.range > room.interiorSize.Y,
				"a ceiling fixture's range must clear the drop to the floor, or the room is lit at the ceiling only"
			)

			-- And the grid has to span the room rather than a footprint it used to have. Every fixture
			-- must sit inside the interior, and the outermost ones must be within one range of the wall
			-- so the corners are not black.
			local half = room.interiorSize.X / 2
			local reachX, reachZ = 0, 0
			for _, offset in lighting.localOffsets do
				Harness.expect(
					math.abs(offset.X) <= half and math.abs(offset.Z) <= half,
					"a light fixture is outside the room"
				)
				reachX = math.max(reachX, math.abs(offset.X))
				reachZ = math.max(reachZ, math.abs(offset.Z))
			end
			Harness.expect(half - reachX < lighting.range, "the room's X extremes are beyond every fixture's reach")
			Harness.expect(half - reachZ < lighting.range, "the room's Z extremes are beyond every fixture's reach")

			-- It is a FILL, not daylight. If this ever climbs, the silhouettes and eye glow the room
			-- exists to show off start washing out.
			Harness.expect(lighting.brightness > 0, "the laboratory must not be pitch dark")
			Harness.expect(lighting.brightness <= 1, "the laboratory fill must stay ambient, not floodlit")
		end),

		Harness.test("the remove-enemies hotkey is a real key and is not a gameplay binding", function()
			-- The hotkey has no button to discover it from, so the two things that can silently break it
			-- are it colliding with a key the game already uses and the room subtitle — its only
			-- signposting — drifting away from the key actually bound.
			local hotkeys = Config.DevTestRoom.hotkeys
			Harness.expect(hotkeys.clearEnemies ~= nil, "the clear hotkey needs a KeyCode")

			Harness.expect(hotkeys.superSprint ~= nil, "the super-sprint hotkey needs a KeyCode")
			Harness.expect(hotkeys.superSprint ~= hotkeys.clearEnemies, "the two lab hotkeys collide")

			local taken = { Config.Feel.controls.spectatorFollowKey, Config.Feel.controls.dynamite.keyCode }
			for _, control in Config.Feel.controls.tools do
				table.insert(taken, control.keyCode)
			end
			for _, keyCode in taken do
				Harness.expect(hotkeys.clearEnemies ~= keyCode, "the clear hotkey collides with a gameplay binding")
				Harness.expect(hotkeys.superSprint ~= keyCode, "the sprint hotkey collides with a gameplay binding")
			end

			for _, label in { hotkeys.clearEnemiesLabel, hotkeys.superSprintLabel } do
				Harness.expect(
					string.find(Config.DevTestRoom.room.roomSubtitle, label, 1, true) ~= nil,
					"the room subtitle must name every hotkey, since nothing else does"
				)
			end

			-- Fast enough to be worth a key at all, and never so fast that the room is a blur. The sanity
			-- service derives its correction ceiling from this same number, so a value below 1 would
			-- quietly mean "slower than running" rather than "no sprint".
			Harness.expect(
				Config.DevTestRoom.session.superSprintMultiplier > 1,
				"a sprint slower than running is not a sprint"
			)
			Harness.expect(
				Config.DevTestRoom.session.superSprintMultiplier <= 8,
				"the developer sprint must stay a camera speed, not a teleport"
			)
		end),

		Harness.test("arming a cave covers every family, and each has a signature", function()
			-- The picker's whole reorganisation rests on this: one button per cave, and the signature
			-- button resolving through the armed one. A family with no cave button is a family whose
			-- variants can never be looked at, which is the exact gap this replaced.
			local caveActions: { [string]: boolean } = {}
			for _, board in Config.DevTestRoom.controls.boards do
				for _, group in board.groups do
					for _, definition in group.definitions do
						local familyId = string.match(definition.actionId, "^cave:(.+)$")
						if familyId ~= nil then
							caveActions[familyId] = true
						end
					end
				end
			end
			for _, familyId in { "STONE", "MOSS", "ICE" } do
				Harness.expect(caveActions[familyId] == true, familyId .. " has no cave button")
			end
			-- And nothing may arm a family that does not exist.
			for familyId in caveActions do
				local known = false
				for _, family in Config.CaveFamilies.families do
					if family.id == familyId then
						known = true
						break
					end
				end
				Harness.expect(known, "cave button arms unknown family " .. familyId)
			end
		end),

		Harness.test("every board renders text at the same pixel density", function()
			-- The boards are authored at 20 px per stud on both axes so identical text sizes render
			-- identically across panels. Resizing a board without resizing its canvas silently changes
			-- the type size on that panel alone, which reads as a font bug rather than a layout one.
			local function checkDensity(label: string, size: Vector3, canvas: Vector2)
				Harness.near(canvas.X / size.X, 20, 0.01, label .. " drifted from 20 px/stud on X")
				Harness.near(canvas.Y / size.Y, 20, 0.01, label .. " drifted from 20 px/stud on Y")
			end
			for _, board in Config.DevTestRoom.controls.boards do
				checkDensity("control board " .. board.id, board.size, board.canvasSize)
			end
			for _, board in Config.DevTestRoom.guide.boards do
				checkDensity("guide board " .. board.id, board.size, board.canvasSize)
			end
		end),

		Harness.test("no two boards on the same wall overlap, and none leaves the room", function()
			-- A board's `size.X` is its width along the wall it is mounted on, which is Z for the
			-- control wall and X for the guide walls. Widening one to fit a new column is exactly the
			-- change that can push it into its neighbour, and nothing in the builder would notice.
			type Span = { id: string, axis: string, wall: number, low: number, high: number }
			local spans: { Span } = {}
			local function record(board: any)
				local alongZ = math.abs(board.facing.X) > 0.5
				local centre = if alongZ then board.localPosition.Z else board.localPosition.X
				table.insert(spans, {
					id = board.id,
					axis = if alongZ then "Z" else "X",
					wall = if alongZ then board.localPosition.X else board.localPosition.Z,
					low = centre - board.size.X / 2,
					high = centre + board.size.X / 2,
				})
			end
			for _, board in Config.DevTestRoom.controls.boards do
				record(board)
			end
			for _, board in Config.DevTestRoom.guide.boards do
				record(board)
			end

			local half = Config.DevTestRoom.room.interiorSize.X / 2
			for _, span in spans do
				Harness.expect(
					span.low >= -half and span.high <= half,
					string.format("board %q spans %.1f..%.1f, outside the room", span.id, span.low, span.high)
				)
			end
			-- AND NOTHING MAY COVER EITHER DOOR OUT TO A BOSS FLOOR.
			--
			-- THIS IS NOT A HYPOTHETICAL. The shrine corridor was authored at x = -40 on the north wall
			-- and its 28-stud opening ran to -26, two studs under a guide board whose edge is at -28 and
			-- which stands 0.8 studs proud of the wall. It built perfectly. A board that covers a doorway
			-- entirely does worse than look wrong — it walls a boss floor off behind itself, which is
			-- indistinguishable from the floor never having been built.
			--
			-- BOTH OPENINGS ARE SOLVED, NOT READ. Where each one lands depends on a doorway roll out on
			-- the boss floor's own entry room, so there is no config field to compare a board against;
			-- the only honest check is to solve the approach exactly as the builder will and measure it.
			local session = Config.DevTestRoom.session
			local WALL_AXIS: { [string]: { axis: string, sign: number } } = {
				North = { axis = "X", sign = -1 },
				South = { axis = "X", sign = 1 },
				East = { axis = "Z", sign = 1 },
				West = { axis = "Z", sign = -1 },
			}
			for _, definition in Config.DevTestRoom.bossFloors.definitions do
				local _, approach =
					DevTestBossApproach.forDefinition(definition, Vector3.new(0, 0, 0), session.familyId, session.depth)
				if approach == nil then
					continue
				end
				local wall = WALL_AXIS[approach.labWall]
				Harness.expect(wall ~= nil, "unknown laboratory wall " .. approach.labWall)
				local openingLow = approach.labDoorwayOffset - approach.corridorWidth / 2
				local openingHigh = approach.labDoorwayOffset + approach.corridorWidth / 2
				local wallHalf = if wall.axis == "X"
					then Config.DevTestRoom.room.interiorSize.X / 2
					else Config.DevTestRoom.room.interiorSize.Z / 2
				Harness.expect(
					openingLow > -wallHalf and openingHigh < wallHalf,
					string.format("the door to %s runs off the end of the %s wall", definition.id, approach.labWall)
				)
				for _, span in spans do
					if span.axis ~= wall.axis or span.wall * wall.sign <= 0 then
						continue
					end
					Harness.expect(
						span.high <= openingLow or span.low >= openingHigh,
						string.format("board %q covers the door out to %s", span.id, definition.id)
					)
				end
			end

			for indexA = 1, #spans do
				for indexB = indexA + 1, #spans do
					local a, b = spans[indexA], spans[indexB]
					if a.axis ~= b.axis or math.abs(a.wall - b.wall) > 0.5 then
						continue
					end
					Harness.expect(
						a.high <= b.low or b.high <= a.low,
						string.format("boards %q and %q overlap on the same wall", a.id, b.id)
					)
				end
			end
		end),
	},
}

return suite
