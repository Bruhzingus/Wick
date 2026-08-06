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

		Harness.test("entity controls stay cave-grouped, compact and fully documented", function()
			local actionIds: { [string]: boolean } = {}
			local spawnIds: { [string]: boolean } = {}
			local pickerGroupCounts: { [string]: number } = {}
			local actionCount = 0
			for _, board in Config.DevTestRoom.controls.boards do
				Harness.expect(board.maxRows <= 3)
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
			Harness.equal(actionCount, 18)
			Harness.equal(pickerGroupCounts.SHARED, 4)
			Harness.equal(pickerGroupCounts.STONE, 2)
			Harness.equal(pickerGroupCounts.MOSS, 2)
			Harness.equal(pickerGroupCounts.ICE, 2)

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
			Harness.equal(guideCount, 10)
			Harness.equal(guideGroupCounts.SHARED, 4)
			Harness.equal(guideGroupCounts.STONE, 2)
			Harness.equal(guideGroupCounts.MOSS, 2)
			Harness.equal(guideGroupCounts.ICE, 2)
			for entityId in spawnIds do
				Harness.expect(guideIds[entityId] == true)
			end
		end),

		Harness.test("the simple route chamber is exactly one four-cell cycle", function()
			local room = Config.DevTestRoom.room
			local geometry = Config.Floors.geometry
			Harness.equal(room.interiorSize.X, geometry.cellSize * 2)
			Harness.equal(room.interiorSize.Z, geometry.cellSize * 2)
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
	},
}

return suite
