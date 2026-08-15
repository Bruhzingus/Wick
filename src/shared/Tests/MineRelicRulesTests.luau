--!strict

local Harness = require(script.Parent.Harness)
local MineRelicsConfig = require(script.Parent.Parent.Config.MineRelics)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local MineRelicRules = require(script.Parent.Parent.Logic.MineRelicRules)
local MineRelics = require(script.Parent.Parent.NewModelsAndObjects.MineRelics)

local function idsOf(defs: { MineRelicRules.RelicDef }): { string }
	local ids: { string } = {}
	for _, def in defs do
		table.insert(ids, def.id)
	end
	return ids
end

local suite: Harness.Suite = {
	name = "MineRelicRules",
	tests = {
		Harness.test("the catalog satisfies every rule a relic row may not break", function()
			local ok, issues = MineRelicRules.validate()
			local message = ""
			for _, issue in issues do
				message ..= string.format("\n  %s.%s: %s", issue.relicId, issue.field, issue.message)
			end
			Harness.expect(ok, "mine relic config issues:" .. message)
		end),

		Harness.test("every catalog row has a silhouette and every silhouette has a row", function()
			-- A config row with no builder behind it would place an EMPTY MODEL in somebody's cave and
			-- fail nowhere: `MineRelics.build` returns nil, the floor carries on, and the only symptom is
			-- a relic that never appears. A builder with no row is dead code nobody can reach.
			for _, def in MineRelicsConfig.catalog do
				Harness.expect(MineRelics.hasBuilder(def.id), "catalog row " .. def.id .. " has no silhouette")
			end
			for _, builtId in MineRelics.builtIds() do
				Harness.expect(
					MineRelicRules.definitionById(builtId) ~= nil,
					"silhouette " .. builtId .. " is not in the catalog and can never be placed"
				)
			end
		end),

		Harness.test("depth gates hold in both directions", function()
			Harness.expect(MineRelicRules.isAvailable(MineRelicsConfig.placement.minDepth))
			Harness.expect(not MineRelicRules.isAvailable(MineRelicsConfig.placement.minDepth - 1))
			for _, def in MineRelicsConfig.catalog do
				local tooShallow = MineRelicRules.eligible(def.minDepth - 1)
				Harness.expect(
					table.find(idsOf(tooShallow), def.id) == nil,
					def.id .. " is eligible one floor above its own minDepth"
				)
				Harness.expect(
					table.find(idsOf(MineRelicRules.eligible(def.minDepth)), def.id) ~= nil,
					def.id .. " never becomes eligible at its own minDepth"
				)
			end
		end),

		Harness.test("a floor never draws the same piece twice, and never repeats the floor above", function()
			-- THE PROPERTY THE CATALOG WALK EXISTS FOR. A weighted per-placement roll satisfies "rare"
			-- and still hands a player the same rusted cart on three floors running, which is the thing
			-- that actually makes dressing feel repetitive.
			local previous: { string } = {}
			for depth = 1, 40 do
				local draw = idsOf(MineRelicRules.floorDraw(depth))
				local seen: { [string]: boolean } = {}
				for _, id in draw do
					Harness.expect(not seen[id], "depth " .. depth .. " drew " .. id .. " twice")
					seen[id] = true
					Harness.expect(
						table.find(previous, id) == nil,
						"depth " .. depth .. " repeats " .. id .. " from the floor above"
					)
				end
				previous = draw
			end
		end),

		Harness.test("the walk covers the whole catalog rather than favouring a few rows", function()
			-- Over a full cycle every eligible piece must come round. A rotation that skipped rows would
			-- be a catalog with dead entries in it, which is worse than not authoring them.
			local deepEnough = 12
			local eligible = MineRelicRules.eligible(deepEnough)
			local seen: { [string]: boolean } = {}
			local perFloor = MineRelicsConfig.placement.maxPerFloor
			-- One full cycle, rounded up, plus a floor of slack for the starting offset.
			for depth = deepEnough, deepEnough + math.ceil(#eligible / perFloor) do
				for _, id in idsOf(MineRelicRules.floorDraw(depth)) do
					seen[id] = true
				end
			end
			for _, def in eligible do
				Harness.expect(seen[def.id] == true, def.id .. " never comes round in a full catalog cycle")
			end
		end),

		Harness.test("a floor's draw is identical every time it is rebuilt", function()
			-- Floors are rebuilt from depth alone, so a draw that moved between builds would mean a
			-- rejoining player saw different equipment to everyone else.
			for depth = 1, 15 do
				local first = idsOf(MineRelicRules.floorDraw(depth))
				local second = idsOf(MineRelicRules.floorDraw(depth))
				Harness.equal(#first, #second)
				for index, id in first do
					Harness.equal(second[index], id, "depth " .. depth .. " drew a different piece on rebuild")
				end
			end
		end),

		Harness.test("wall pieces are sampled further out than open ones and fit their own rooms", function()
			local cell = FloorsConfig.geometry.cellSize
			local half = cell / 2
			for _, def in MineRelicsConfig.catalog do
				local low, high = MineRelicRules.ringBand(def, cell)
				Harness.expect(low > 0 and high >= low, def.id .. " has an invalid ring band")
				-- The sweep must stay inside the room cell with the piece's own footprint on it, or every
				-- bearing starts outside the rock and is rejected before anything else is checked.
				Harness.expect(high + def.footprintRadius <= half, def.id .. " samples outside its own room cell")
				Harness.expect(
					def.minCeilingHeight >= FloorsConfig.geometry.ceilingMinHeight,
					def.id .. " asks for less headroom than the shortest room in the game has"
				)
				Harness.expect(
					def.minCeilingHeight <= FloorsConfig.geometry.ceilingMaxHeight,
					def.id .. " needs a taller room than the generator can produce"
				)
				Harness.expect(MineRelicRules.fitsRoom(def, def.minCeilingHeight))
				Harness.expect(not MineRelicRules.fitsRoom(def, def.minCeilingHeight - 0.01))
			end
			local openBand = { MineRelicRules.ringBand(MineRelicsConfig.catalog[1], cell) }
			Harness.equal(
				MineRelicsConfig.catalog[1].anchoring,
				"Open",
				"the first row is expected to be open-standing"
			)
			Harness.near(openBand[1], cell * MineRelicsConfig.placement.openRingMinFactor)
		end),
	},
}

return suite
