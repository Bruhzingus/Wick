--!strict

local Harness = require(script.Parent.Harness)
local WallLampRules = require(script.Parent.Parent.Logic.WallLampRules)
local WallLampConfig = require(script.Parent.Parent.Config.WallLamp)
local LightConfig = require(script.Parent.Parent.Config.Light)

-- A request that is allowed in every respect, so each test can spoil exactly one thing and know
-- which rule refused it.
local function validRequest(): WallLampRules.LightRequest
	return {
		lampLit = false,
		lampDepth = 3,
		alive = true,
		finished = false,
		isLit = true,
		isCupping = false,
		playerDepth = 3,
		distance = 2,
	}
end

local function refusalFor(mutate: (WallLampRules.LightRequest) -> ()): WallLampRules.Refusal?
	local request = validRequest()
	mutate(request)
	local _, refusal = WallLampRules.canLight(request)
	return refusal
end

local suite: Harness.Suite = {
	name = "WallLampRules",
	tests = {
		Harness.test("a live player with a burning candle at a cold lamp may light it", function()
			local allowed, refusal = WallLampRules.canLight(validRequest())
			Harness.equal(allowed, true)
			Harness.isNil(refusal)
		end),

		Harness.test("a lamp only lights once", function()
			Harness.equal(
				refusalFor(function(r)
					r.lampLit = true
				end),
				"alreadyLit"
			)
		end),

		Harness.test("lamps take fire and never give it", function()
			-- THE RULE THAT PROTECTS THE RELIGHT ECONOMY. If an unlit player could light a lamp, a lit
			-- floor would be a network of free respawns and bringing a teammate back would stop being
			-- something only a teammate can do.
			Harness.equal(
				refusalFor(function(r)
					r.isLit = false
				end),
				"unlit"
			)
		end),

		Harness.test("a covered flame cannot light anything", function()
			-- Cup is the "go dark" tool. Letting a cupped player light a lamp would hand them the
			-- benefits of hiding and of lighting the room in the same second.
			Harness.equal(
				refusalFor(function(r)
					r.isCupping = true
				end),
				"cupped"
			)
		end),

		Harness.test("the dead and the finished light nothing", function()
			Harness.equal(
				refusalFor(function(r)
					r.alive = false
				end),
				"notAlive"
			)
			Harness.equal(
				refusalFor(function(r)
					r.finished = true
				end),
				"finished"
			)
		end),

		Harness.test("a lamp on another floor is out of reach at any distance", function()
			-- Floors stack vertically in one place, so a lamp directly above a player can be metres away
			-- in world space. Depth is the authority, never proximity.
			Harness.equal(
				refusalFor(function(r)
					r.playerDepth = 4
					r.distance = 0
				end),
				"wrongFloor"
			)
		end),

		Harness.test("range is the prompt plus the trust slack, and not a stud more", function()
			local range = WallLampRules.serverRange()
			Harness.equal(
				range,
				WallLampConfig.interaction.promptRange + WallLampConfig.interaction.positionToleranceStuds
			)
			Harness.equal(
				refusalFor(function(r)
					r.distance = range
				end),
				nil
			)
			Harness.equal(
				refusalFor(function(r)
					r.distance = range + 0.01
				end),
				"tooFar"
			)
			-- A forged non-finite distance must fail closed rather than sneak past a comparison.
			Harness.equal(
				refusalFor(function(r)
					r.distance = 0 / 0
				end),
				"tooFar"
			)
			Harness.equal(
				refusalFor(function(r)
					r.distance = math.huge
				end),
				"tooFar"
			)
		end),

		Harness.test("the crowned lamp asks for a longer hold than a room lamp", function()
			-- It answers a whole floor. If the two holds were equal there would be nothing in the input
			-- that said one of these was a bigger decision than the other.
			local room = WallLampRules.holdSecondsFor("Room")
			local main = WallLampRules.holdSecondsFor("Main")
			Harness.expect(room > 0, "a room lamp with no hold would be lit by walking past it")
			Harness.expect(main > room, "the crowned lamp must cost more than a room lamp")
		end),

		Harness.test("an instant completion is refused and an honest one is not", function()
			local hold = WallLampRules.holdSecondsFor("Room")
			local grace = WallLampConfig.interaction.holdGraceSeconds
			Harness.equal(WallLampRules.holdSatisfied("Room", 100, 100), false)
			Harness.equal(WallLampRules.holdSatisfied("Room", 100, 100 + hold - grace * 2), false)
			-- One bad round trip early still counts; the grace exists for exactly this case.
			Harness.equal(WallLampRules.holdSatisfied("Room", 100, 100 + hold - grace), true)
			Harness.equal(WallLampRules.holdSatisfied("Room", 100, 100 + hold), true)
			Harness.expect(grace < hold, "a grace at or above the hold would make the hold decorative")
		end),

		Harness.test("a forged timestamp cannot satisfy a hold", function()
			Harness.equal(WallLampRules.holdSatisfied("Room", 0 / 0, 100), false)
			Harness.equal(WallLampRules.holdSatisfied("Room", -math.huge, 100), false)
			Harness.equal(WallLampRules.holdSatisfied("Main", 100, 0 / 0), false)
		end),

		Harness.test("an abandoned hold expires and a live one does not", function()
			local expiry = WallLampConfig.interaction.holdExpirySeconds
			Harness.equal(WallLampRules.holdExpired(100, 100 + expiry), false)
			Harness.equal(WallLampRules.holdExpired(100, 100 + expiry + 0.01), true)
			-- A corrupted record is treated as expired: dropping a hold costs a player one retry,
			-- keeping a bad one leans their candle at a wall until the floor is torn down.
			Harness.equal(WallLampRules.holdExpired(0 / 0, 100), true)
			Harness.expect(
				expiry > WallLampRules.holdSecondsFor("Main"),
				"a hold must never expire before it could legitimately complete"
			)
		end),

		Harness.test("the cascade fits inside its budget however large the floor is", function()
			local cascade = WallLampConfig.cascade
			for _, count in { 1, 4, 12, 40, 200 } do
				local step = WallLampRules.cascadeStepSeconds(count)
				local total = WallLampRules.cascadeLeadSeconds() + step * count
				Harness.expect(
					total <= cascade.maximumSeconds + 1e-9,
					string.format(
						"a %d-lamp cascade ran %.2fs, over the %.2fs budget",
						count,
						total,
						cascade.maximumSeconds
					)
				)
				Harness.expect(step >= 0, "a step may never be negative")
				Harness.expect(step <= cascade.stepSeconds, "a small floor must not run slower than the authored step")
			end
			-- A small floor gets the full authored step: compression is a ceiling, not a target.
			Harness.near(WallLampRules.cascadeStepSeconds(1), cascade.stepSeconds)
			Harness.equal(WallLampRules.cascadeStepSeconds(0), 0)
			Harness.equal(WallLampRules.cascadeStepSeconds(-3), 0)
		end),

		Harness.test("a lit lamp is real light: it repels hunters and pulls the Drawn", function()
			-- The whole reason the lamps are worth building. A lamp that only illuminated would be
			-- scenery, and lighting the cave would be free.
			for _, variant in { "Room" :: WallLampRules.LampVariant, "Main" :: WallLampRules.LampVariant } do
				local source = WallLampRules.lightSource(variant, Vector3.new(1, 2, 3))
				Harness.equal(source.kind, "Lamp")
				Harness.equal(source.repelsDarkHunters, true)
				Harness.equal(source.attractsDrawn, true)
				Harness.isNil(source.ownerId, "a lamp belongs to nobody")
				Harness.expect(source.intensity > 0 and source.range > 0, "a lit lamp must reach something")
			end
			Harness.vectorNear(WallLampRules.lightSource("Room", Vector3.new(1, 2, 3)).position, Vector3.new(1, 2, 3))
		end),

		Harness.test("no lamp can ever force a dark-hunter to retreat", function()
			-- The panic retreat belongs to Flare alone (DESIGN §6). A fixture that could trigger it would
			-- be a permanent, free Flare bolted to a wall, and one lit room would disarm the counterplay
			-- the entire tool exists for.
			Harness.equal(WallLampRules.lightSource("Room", Vector3.zero).forcesDarkHunterRetreat, false)
			Harness.equal(WallLampRules.lightSource("Main", Vector3.zero).forcesDarkHunterRetreat, false)
		end),

		Harness.test("a room lamp is dimmer than a player at full dial", function()
			-- The cave staying dark is the game. A fixture in every room that out-reached the flame in
			-- your hands would end it one hold at a time, and the wall lamps would become the light
			-- source instead of the record of where you have been.
			local room = WallLampRules.lightSource("Room", Vector3.zero)
			Harness.expect(
				room.range < LightConfig.maxRange,
				"a room lamp must not out-reach a full-dial candle in the light field"
			)
			Harness.expect(
				room.intensity < LightConfig.maxIntensity,
				"a room lamp must not out-shine a full-dial candle in the light field"
			)
			Harness.expect(
				WallLampConfig.roomOutput.spotRange <= LightConfig.maxRange,
				"a room lamp must not out-reach a full-dial candle on screen either"
			)
		end),

		Harness.test("the crowned lamp outweighs a room lamp in every dimension", function()
			local room = WallLampRules.lightSource("Room", Vector3.zero)
			local main = WallLampRules.lightSource("Main", Vector3.zero)
			Harness.expect(main.range > room.range, "the lamp that answers a floor must reach further")
			Harness.expect(main.intensity > room.intensity, "the lamp that answers a floor must burn brighter")
			Harness.expect(
				WallLampConfig.mainOutput.spotRange > WallLampConfig.roomOutput.spotRange,
				"the crowned lamp must look like what it is"
			)
		end),

		Harness.test("the rollback switch takes the whole feature out", function()
			-- A disabled layer must refuse the ACTION, not merely skip the fixtures: a lamp left in a
			-- world by a mid-run flag flip has to be inert rather than half-wired.
			if WallLampConfig.enabled then
				Harness.equal(WallLampRules.isEnabled(), true)
			else
				Harness.equal(refusalFor(function() end), "disabled")
			end
		end),
	},
}

return suite
