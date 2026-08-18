--!strict

local Harness = require(script.Parent.Harness)
local Config = require(script.Parent.Parent.Config)
local DevTestRoomRules = require(script.Parent.Parent.Logic.DevTestRoomRules)

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

		Harness.test("the boss arena is a room the Queen and her encounter physically fit in", function()
			local arena = Config.DevTestRoom.arena
			local room = Config.DevTestRoom.room

			-- THE ONE DIMENSION THAT IS NOT NEGOTIABLE. She is authored for a 46-stud chamber; a short
			-- ceiling is most of what "the Queen did not spawn" has historically meant.
			Harness.expect(
				arena.interiorSize.Y >= 46,
				"the arena must clear the Queen's authored 46-stud chamber ceiling"
			)
			-- Her authored posts come from BossFloorPlan and are mapped in from the entrance, so the room
			-- has to be at least as deep as the offsets it is being handed. cell * 0.3 is the furthest
			-- guard offset; doubling it plus her own setback is the minimum honest span.
			local cell = Config.Floors.geometry.cellSize
			Harness.expect(arena.interiorSize.X >= cell, "the arena is narrower than the authored chamber")
			Harness.expect(arena.interiorSize.Z >= cell, "the arena is shallower than the authored chamber")

			-- The arena's own doorway matches the encounter minimum; the corridor is allowed to be
			-- tighter, but never taller than the passage it runs into or wider than its own walls.
			Harness.expect(arena.doorwayWidth >= 26, "the arena doorway is below BossFloorPlan's minimum")
			Harness.expect(arena.doorwayHeight >= 14, "the arena doorway is below BossFloorPlan's minimum")
			Harness.expect(arena.doorwayWidth <= arena.interiorSize.Z, "the doorway is wider than the wall")
			Harness.expect(arena.doorwayHeight <= arena.interiorSize.Y, "the doorway is taller than the wall")
			Harness.expect(arena.corridorHeight <= room.interiorSize.Y, "the corridor cannot exceed the lab wall")
			Harness.expect(arena.corridorWidth > 0 and arena.corridorLength > 0)

			-- THE CORRIDOR BACKS THE ARENA'S DOORWAY. Its side walls and ceiling are the only thing behind
			-- the opening, so anything the corridor does not cover is a slot in the arena wall looking
			-- straight out into the void — it builds perfectly and you only find it by walking up to it.
			Harness.expect(
				arena.corridorWidth >= arena.doorwayWidth,
				"a corridor narrower than the arena doorway leaves a gap either side of the door"
			)
			Harness.expect(
				arena.corridorHeight >= arena.doorwayHeight,
				"a corridor shorter than the arena doorway leaves the top of the door open to the void"
			)

			-- The corridor leaves through the laboratory's east wall, so its opening must fit in that wall
			-- and clear the Warden's emergence pile rather than opening into it.
			local halfDepth = room.interiorSize.Z / 2
			Harness.expect(
				math.abs(arena.corridorLocalZ) + arena.corridorWidth / 2 <= halfDepth,
				"the corridor opening runs off the end of the laboratory's east wall"
			)
			Harness.expect(
				math.abs(arena.corridorLocalZ - room.wardenLocalPosition.Z) > arena.corridorWidth,
				"the corridor opens into the Warden's emergence pile"
			)

			-- The start button sits on the entry wall (local +Z), inside the room, and clear of the
			-- doorway a tester walks through to reach it — a button in the doorway is a button you press
			-- by accident on the way in.
			local button = arena.startButtonLocalPosition
			Harness.expect(
				button.Z > 0 and button.Z < arena.interiorSize.Z / 2,
				"the start button must be inside the room, on the entry wall"
			)
			Harness.expect(
				math.abs(button.X) - arena.startButtonSize.X / 2 > arena.doorwayWidth / 2,
				"the start button overlaps the doorway it is beside"
			)
			Harness.expect(
				math.abs(button.X) + arena.startButtonSize.X / 2 <= arena.interiorSize.X / 2,
				"the start button hangs off the end of its wall"
			)
			Harness.expect(button.Y > 0 and button.Y < arena.doorwayHeight, "the start button is out of reach")

			-- The sign hangs on the same wall and must clear the opening rather than fill it.
			local sign = arena.signLocalPosition
			Harness.expect(
				sign.Y - arena.signSize.Y / 2 >= arena.doorwayHeight,
				"the arena sign hangs across the doorway instead of over it"
			)
			Harness.expect(
				sign.Y + arena.signSize.Y / 2 <= arena.interiorSize.Y,
				"the arena sign is inside the ceiling"
			)
			Harness.expect(sign.Z > 0 and sign.Z < arena.interiorSize.Z / 2, "the arena sign is not on the entry wall")
			-- A held press, unlike every board button: this one starts a fight.
			Harness.expect(arena.promptHoldSeconds > 0, "the encounter must not start on a brushed prompt")

			-- The arena lights have the same job the laboratory's do and the same way of silently failing:
			-- a range shorter than the drop from the ceiling lights the ceiling only.
			Harness.expect(
				arena.lightingRange > arena.interiorSize.Y,
				"an arena fixture's range must clear the drop to the floor"
			)
			for _, offset in arena.lightingLocalOffsets do
				Harness.expect(
					math.abs(offset.X) <= arena.interiorSize.X / 2 and math.abs(offset.Z) <= arena.interiorSize.Z / 2,
					"an arena light is outside the arena"
				)
			end
			Harness.expect(arena.lightingBrightness > 0 and arena.lightingBrightness <= 1)
		end),

		Harness.test("entity controls stay cave-grouped, compact and fully documented", function()
			local actionIds: { [string]: boolean } = {}
			local spawnIds: { [string]: boolean } = {}
			local pickerGroupCounts: { [string]: number } = {}
			local actionCount = 0
			local controls = Config.DevTestRoom.controls
			for _, board in Config.DevTestRoom.controls.boards do
				Harness.expect(board.maxRows <= 4)
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
			Harness.equal(actionCount, 22)
			-- ARM CAVE replaced the three per-family columns. Three buttons instead of six, and the
			-- variant coverage went from one cave to all three — that trade is the point of the layout.
			Harness.equal(pickerGroupCounts.CAVE, 3)
			Harness.equal(pickerGroupCounts.SHARED, 4)
			-- The pack is family-agnostic like SHARED but gets its own column: four bespoke bodies a
			-- tester should find together rather than at the bottom of an eight-deep shared list.
			Harness.equal(pickerGroupCounts.PACK, 4)
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
			-- 10 before the wick pack's own guide board.
			Harness.equal(guideCount, 14)
			Harness.equal(guideGroupCounts.SHARED, 4)
			Harness.equal(guideGroupCounts.PACK, 4)
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
			-- AND NOTHING MAY COVER THE DOOR TO THE ARENA. The corridor is punched through the east wall
			-- (positive X, spanning Z) precisely because it was the one wall carrying no board; a board
			-- moved onto it later would build perfectly and wall the boss room off behind itself.
			local arena = Config.DevTestRoom.arena
			local openingLow = arena.corridorLocalZ - arena.corridorWidth / 2
			local openingHigh = arena.corridorLocalZ + arena.corridorWidth / 2
			for _, span in spans do
				if span.axis == "Z" and span.wall > 0 then
					Harness.expect(
						span.high <= openingLow or span.low >= openingHigh,
						string.format("board %q covers the doorway to the boss arena", span.id)
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
