--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local DeadCandleRules = require(script.Parent.Parent.Logic.DeadCandleRules)
local DeadCandleConfig = require(script.Parent.Parent.Config.DeadCandle)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local ThreatRules = require(script.Parent.Parent.Logic.ThreatRules)

local function moduleAllowingTheFly(): Types.RoomModuleDef
	for _, def in FloorsConfig.roomModules do
		for _, threatId in def.allowedThreats do
			if threatId == DeadCandleConfig.threatId then
				return def
			end
		end
	end
	error("no room module admits the dead candle's creature")
end

local function moduleRefusingTheFly(): Types.RoomModuleDef?
	for _, def in FloorsConfig.roomModules do
		local admits = false
		for _, threatId in def.allowedThreats do
			if threatId == DeadCandleConfig.threatId then
				admits = true
				break
			end
		end
		if not admits then
			return def
		end
	end
	return nil
end

local function room(ceilingHeight: number): Types.RoomPlacement
	return {
		moduleId = moduleAllowingTheFly().id,
		gridX = 0,
		gridZ = 0,
		doorways = { "N" },
		ceilingHeight = ceilingHeight,
		footprint = {
			kind = "Rectangle",
			rotation = 0,
			centerX = 0,
			centerZ = 0,
			primaryX = 1,
			primaryZ = 1,
			secondaryX = 1,
			secondaryZ = 1,
			lobeOffset = 0,
			roughness = 0,
			roughPhase = 0,
		},
	}
end

local suite: Harness.Suite = {
	name = "DeadCandleRules",
	tests = {
		Harness.test("the encounter names a creature that exists and lives on ceilings", function()
			-- The whole tableau is "reward under a nest". A row that was not roof-bound would leave three
			-- ordinary threats standing around a pickup, which is a different (and much worse) encounter.
			local def = ThreatsConfig.definitions[DeadCandleConfig.threatId]
			Harness.expect(def ~= nil, "Config/DeadCandle.threatId must name a real roster row")
			Harness.expect(
				ThreatRules.roofProfile(def :: Types.ThreatDef) ~= nil,
				"the dead candle's creature must be roof-bound"
			)
			Harness.expect(DeadCandleConfig.flyCount >= 2, "one fly is an ordinary room, not an encounter")
			Harness.expect(DeadCandleConfig.lootCount >= 1, "the tableau has to be worth the decision")
		end),

		Harness.test("it is a deep-floor encounter and nothing shallower", function()
			Harness.expect(
				DeadCandleConfig.minGlobalDepth >= 10,
				"the dead candle is late-run variance; DESIGN places it at Floor 10+"
			)
			Harness.equal(DeadCandleRules.depthAllows(DeadCandleConfig.minGlobalDepth - 1), false)
			Harness.equal(DeadCandleRules.depthAllows(DeadCandleConfig.minGlobalDepth), true)
			Harness.equal(DeadCandleRules.depthAllows(DeadCandleConfig.minGlobalDepth + 25), true)
		end),

		Harness.test("it never lands on a room the floor requires", function()
			-- Entry, Basin, Brazier and the Warden's den are rooms a party has to use. An encounter that
			-- put three snuffers in one of them would not be optional content any more.
			local ceiling = DeadCandleRules.maximumCeilingHeight() - 1
			local moduleDef = moduleAllowingTheFly()
			Harness.equal(DeadCandleRules.roomIsEligible(room(ceiling), 2, { [2] = true }, moduleDef), false)
			Harness.equal(DeadCandleRules.roomIsEligible(room(ceiling), 2, {}, moduleDef), true)
		end),

		Harness.test("it refuses ceilings its own creature cannot hold", function()
			-- A fly hung above its own maximum is out of earshot and out of reach: the reward would be
			-- free and the encounter would not exist. Read from the roster, so the two cannot drift apart.
			local limit = DeadCandleRules.maximumCeilingHeight()
			Harness.expect(limit > 0, "the roster must supply a roof profile for this row")
			local moduleDef = moduleAllowingTheFly()
			Harness.equal(DeadCandleRules.roomIsEligible(room(limit), 3, {}, moduleDef), true)
			Harness.equal(DeadCandleRules.roomIsEligible(room(limit + 0.5), 3, {}, moduleDef), false)
		end),

		Harness.test("it never puts a creature in a room module that refused it", function()
			local ceiling = DeadCandleRules.maximumCeilingHeight() - 1
			Harness.equal(DeadCandleRules.roomIsEligible(room(ceiling), 3, {}, nil), false)
			local refusing = moduleRefusingTheFly()
			if refusing ~= nil then
				Harness.equal(DeadCandleRules.roomIsEligible(room(ceiling), 3, {}, refusing), false)
			end
		end),

		Harness.test("the layout is two rings, and no pickup starts under a fly", function()
			local corpse = Vector3.new(7, 0, -3)
			local layout = DeadCandleRules.layout(corpse)
			Harness.equal(#layout.loot, DeadCandleConfig.lootCount)
			Harness.equal(#layout.flies, DeadCandleConfig.flyCount)

			for _, offset in layout.loot do
				Harness.near(
					(offset - corpse).Magnitude,
					DeadCandleConfig.layout.lootRingRadius,
					1e-5,
					"every pickup sits on the loot ring"
				)
				Harness.near(offset.Y, corpse.Y, 1e-9, "the rings are laid out on the room plane")
			end
			for _, offset in layout.flies do
				Harness.near(
					(offset - corpse).Magnitude,
					DeadCandleConfig.layout.flyRingRadius,
					1e-5,
					"every fly anchors on the wider ring"
				)
			end

			-- The rings are rotated against each other so the reward is never spawned directly beneath a
			-- creature: a player has to walk INTO the nest rather than start inside a dive.
			for _, loot in layout.loot do
				for _, fly in layout.flies do
					local lootBearing = math.atan2(loot.Z - corpse.Z, loot.X - corpse.X)
					local flyBearing = math.atan2(fly.Z - corpse.Z, fly.X - corpse.X)
					local separation = math.abs(((lootBearing - flyBearing + math.pi) % (2 * math.pi)) - math.pi)
					Harness.expect(separation > 1e-3, "a pickup must never share a fly's bearing")
				end
			end
		end),

		Harness.test("the flies stand off the corpse further than the loot does", function()
			-- The ordering is the encounter's shape: the reward is in the middle and the creatures are
			-- around it, so every approach crosses at least one territory.
			Harness.expect(
				DeadCandleConfig.layout.flyRingRadius > DeadCandleConfig.layout.lootRingRadius,
				"a fly ring inside the loot ring would put the creatures in the reward's own footprint"
			)
			Harness.expect(
				DeadCandleConfig.layout.corpseClearance > 0,
				"the body needs its own ground kept clear of dressing"
			)
		end),

		Harness.test("an empty ring is empty rather than an error", function()
			-- `ring` is shared by both rings and is the one function a future encounter would reuse; a
			-- zero count is a legitimate authored value and must not produce a stray offset at the centre.
			Harness.equal(#DeadCandleRules.ring(Vector3.zero, 0, 5, 0), 0)
			Harness.equal(#DeadCandleRules.ring(Vector3.zero, 1, 5, 0), 1)
		end),
	},
}

return suite
