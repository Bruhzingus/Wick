--!strict

local Harness = require(script.Parent.Harness)
local Rules = require(script.Parent.Parent.Logic.AshamedLurkerRules)
local Config = require(script.Parent.Parent.Config.AshamedLurker)
local LightConfig = require(script.Parent.Parent.Config.Light)
local MovementConfig = require(script.Parent.Parent.Config.Movement)

-- The doorway root: floor centre of the opening, local +X along the wall, local -Z through it.
-- Rotated deliberately so nothing below can pass by accidentally agreeing with world axes.
local ROOT = CFrame.lookAt(Vector3.new(120, 8, -40), Vector3.new(120, 8, -41))
local WIDTH = Config.placement.minDoorWidth
local HEIGHT = 10.5

local function pointInDoorway(lateral: number, up: number, through: number): Vector3
	return ROOT * Vector3.new(lateral, up, through)
end

-- Somewhere in the trap lane, at floor level, on the given approach side.
local function inTrapLane(trapSide: Rules.TrapSide, through: number): Vector3
	local side = Rules.sideSign(trapSide)
	return pointInDoorway(side * Rules.laneCenterX(WIDTH), 0.2, through)
end

local function inSafeLane(trapSide: Rules.TrapSide, through: number): Vector3
	local side = Rules.sideSign(trapSide)
	return pointInDoorway(-side * (Rules.clearLaneWidth(WIDTH) / 2 - 0.5), 0.2, through)
end

local function stareFrom(position: Vector3, trapSide: Rules.TrapSide): Rules.GazeInput
	local face = Rules.facePosition(ROOT, WIDTH, HEIGHT, trapSide)
	-- The camera rides above the candle's base; look straight at the face from there.
	local camera = position + Vector3.new(0, 4, 0)
	return {
		facePosition = face,
		cameraPosition = camera,
		lookVector = (face - camera).Unit,
	}
end

local FAST = MovementConfig.runSpeed
local SLOW = MovementConfig.walkSpeed * 0.5

local suite: Harness.Suite = {
	name = "AshamedLurkerRules",
	tests = {
		Harness.test("no arch can host one before the minimum depth, and the first deep floor can", function()
			Harness.equal(Rules.targetCount(1), 0)
			Harness.equal(Rules.targetCount(Config.minDepth - 1), 0)
			Harness.expect(Rules.targetCount(Config.minDepth) >= 1, "depth 4 must be able to host one")
		end),

		Harness.test("doorways that are too small, too large, or too short are rejected", function()
			local placement = Config.placement
			Harness.equal(Rules.isPlacementAllowed(placement.minDoorWidth - 0.5, HEIGHT), false)
			Harness.equal(Rules.isPlacementAllowed(placement.maxDoorWidth + 0.5, HEIGHT), false)
			Harness.equal(Rules.isPlacementAllowed(WIDTH, placement.minDoorHeight - 0.5), false)
			Harness.equal(Rules.isPlacementAllowed(WIDTH, placement.maxDoorHeight + 0.5), false)
			Harness.equal(Rules.isPlacementAllowed(WIDTH, HEIGHT), true)
		end),

		-- THE placement guarantee: an occupied arch is always still a route.
		Harness.test("every allowed width keeps a clear lane and an arm that stays in its own half", function()
			local placement = Config.placement
			for step = 0, 40 do
				local width = placement.minDoorWidth + (placement.maxDoorWidth - placement.minDoorWidth) * (step / 40)
				if not Rules.isPlacementAllowed(width, HEIGHT) then
					continue
				end
				Harness.expect(
					Rules.clearLaneWidth(width) >= placement.minSafeLaneWidth,
					string.format("width %.2f left only %.2f studs of lane", width, Rules.clearLaneWidth(width))
				)
				-- Inner edge of the trip lane, measured from the centre line.
				local innerEdge = Rules.laneCenterX(width) - Rules.triggerReach(width) / 2
				Harness.expect(
					innerEdge >= -1e-6,
					string.format("width %.2f let the arm cross the centre line by %.3f", width, -innerEdge)
				)
			end
		end),

		Harness.test("running through the trip lane triggers it from either approach", function()
			for _, through in { 1.2, -1.2 } do
				Harness.equal(
					Rules.qualifiesRunTrigger(ROOT, inTrapLane("Right", through), FAST, WIDTH, "Right"),
					true,
					"a runner in the lane must trip it from both sides of the arch"
				)
			end
		end),

		Harness.test("walking through the trip lane does not trigger it", function()
			Harness.equal(Rules.qualifiesRunTrigger(ROOT, inTrapLane("Right", 0), SLOW, WIDTH, "Right"), false)
			-- Ordinary walking pace must be unambiguously safe, not borderline.
			Harness.expect(
				Rules.triggerSpeed() > MovementConfig.walkSpeed,
				"the trigger threshold must sit above walk speed"
			)
			Harness.expect(
				Rules.triggerSpeed() < MovementConfig.runSpeed,
				"a real sprint must always be fast enough to trip it"
			)
			Harness.equal(
				Rules.qualifiesRunTrigger(ROOT, inTrapLane("Right", 0), MovementConfig.walkSpeed, WIDTH, "Right"),
				false
			)
		end),

		-- The reach is absolute, so a bigger arch is proportionally LESS covered rather than equally
		-- covered. This is what keeps a wide opening from reading as half-blocked.
		Harness.test("attack reach is fixed in studs and never scales with the arch", function()
			local placement = Config.placement
			local narrow = Rules.triggerReach(placement.minDoorWidth)
			local wide = Rules.triggerReach(placement.maxDoorWidth)
			Harness.near(narrow, wide, 1e-6, "reach must not grow with doorway width")
			Harness.expect(
				wide / placement.maxDoorWidth < narrow / placement.minDoorWidth,
				"the widest arch must be proportionally less covered than the narrowest"
			)
			-- And the lunge must still reach meaningfully further than the resting arm, or the attack
			-- only lands on someone who walks into the body.
			Harness.expect(
				Rules.triggerReach(WIDTH) > Rules.restArmReach(WIDTH) * 1.5,
				"the lunge must extend well past where the arm rests"
			)
		end),

		Harness.test("running through the open lane does not trigger it", function()
			Harness.equal(Rules.qualifiesRunTrigger(ROOT, inSafeLane("Right", 0), FAST, WIDTH, "Right"), false)
		end),

		-- Left and right are the same trap mirrored, never two different rules.
		Harness.test("the trap side mirrors exactly", function()
			Harness.equal(Rules.qualifiesRunTrigger(ROOT, inTrapLane("Left", 0), FAST, WIDTH, "Left"), true)
			Harness.equal(Rules.qualifiesRunTrigger(ROOT, inTrapLane("Left", 0), FAST, WIDTH, "Right"), false)
			Harness.equal(Rules.qualifiesRunTrigger(ROOT, inTrapLane("Right", 0), FAST, WIDTH, "Left"), false)
			Harness.near(
				Rules.facePosition(ROOT, WIDTH, HEIGHT, "Left").Y,
				Rules.facePosition(ROOT, WIDTH, HEIGHT, "Right").Y,
				1e-4
			)
		end),

		Harness.test("an impossible speed or position is rejected rather than trusted", function()
			Harness.equal(Rules.qualifiesRunTrigger(ROOT, inTrapLane("Right", 0), 0 / 0, WIDTH, "Right"), false)
			Harness.equal(Rules.qualifiesRunTrigger(ROOT, Vector3.new(math.huge, 0, 0), FAST, WIDTH, "Right"), false)
		end),

		-- The grab is checked once, later, in a slightly larger volume. Leaving is an escape.
		Harness.test("a player who leaves the lane before the impact frame is not grabbed", function()
			local escaped = inSafeLane("Right", 0)
			Harness.equal(Rules.insideGrabVolume(ROOT, inTrapLane("Right", 0), WIDTH, "Right"), true)
			Harness.equal(Rules.insideGrabVolume(ROOT, escaped, WIDTH, "Right"), false)
		end),

		Harness.test("the grab volume is wider than the lane that triggered it", function()
			local side = Rules.sideSign("Right")
			local justOutside = pointInDoorway(side * Rules.laneCenterX(WIDTH), 0.2, Config.trigger.laneDepth / 2 + 0.5)
			Harness.equal(Rules.insideArmLane(ROOT, justOutside, WIDTH, "Right"), false)
			Harness.equal(Rules.insideGrabVolume(ROOT, justOutside, WIDTH, "Right"), true)
		end),

		Harness.test("a direct stare completes in exactly the configured hold", function()
			-- Close to the opening: the stare only reaches `maxDistance`, so standing well back in the
			-- room is deliberately out of range no matter how squarely it is framed.
			for _, through in { 3, -3 } do
				local input = stareFrom(inSafeLane("Right", through), "Right")
				Harness.equal(Rules.gazeQualifies(input), true, "the face must be readable from both approaches")

				local progress = 0
				local step = 1 / 30
				local elapsed = 0
				while not Rules.isGazeComplete(progress) and elapsed < 10 do
					progress = Rules.advanceGazeProgress(progress, step, true)
					elapsed += step
				end
				Harness.expect(Rules.isGazeComplete(progress), "a held stare must resolve")
				Harness.near(elapsed, Config.gaze.holdSeconds, step * 1.01)
			end
		end),

		-- Which half you stand in deliberately does not matter: being seen is being seen, and walking
		-- up to it head-on is what a player actually tries first.
		Harness.test("a stare counts from the trapped half and from dead centre too", function()
			Harness.equal(Rules.gazeQualifies(stareFrom(inTrapLane("Right", 4), "Right")), true)
			Harness.equal(Rules.gazeQualifies(stareFrom(pointInDoorway(0, 0.2, 5), "Right")), true)
		end),

		Harness.test("a stare from beyond the range or off-axis never counts", function()
			local far = stareFrom(inSafeLane("Right", Config.gaze.maxDistance + 12), "Right")
			Harness.equal(Rules.gazeQualifies(far), false)

			local askew = stareFrom(inSafeLane("Right", 6), "Right")
			askew.lookVector = (CFrame.Angles(0, math.rad(45), 0) * askew.lookVector).Unit
			Harness.equal(Rules.gazeQualifies(askew), false)
		end),

		-- It has to be able to see that it is being seen.
		Harness.test("only a flame at least half-way up the dial can shame it", function()
			local required = Rules.requiredBurnRate()
			Harness.near(
				required,
				LightConfig.minBurnRate
					+ (LightConfig.maxBurnRate - LightConfig.minBurnRate) * Config.gaze.requiredDialFraction
			)
			Harness.equal(Rules.lightRevealsWatcher(true, false, required, false), true)
			Harness.equal(Rules.lightRevealsWatcher(true, false, required - 0.01, false), false)
			-- A snuffed or cupped candle is dark whatever the dial says underneath it.
			Harness.equal(Rules.lightRevealsWatcher(false, false, LightConfig.maxBurnRate, false), false)
			Harness.equal(Rules.lightRevealsWatcher(true, true, LightConfig.maxBurnRate, false), false)
			-- FLARE always reveals you, however low the dial was.
			Harness.equal(Rules.lightRevealsWatcher(true, false, LightConfig.minBurnRate, true), true)
		end),

		Harness.test("a malformed camera sample is rejected", function()
			local nonUnit = stareFrom(inSafeLane("Right", 6), "Right")
			nonUnit.lookVector = nonUnit.lookVector * 40
			Harness.equal(Rules.gazeQualifies(nonUnit), false, "a look vector must be a unit vector")

			local infinite = stareFrom(inSafeLane("Right", 6), "Right")
			infinite.cameraPosition = Vector3.new(0 / 0, 0, 0)
			Harness.equal(Rules.gazeQualifies(infinite), false)
		end),

		Harness.test("looking away decays banked progress instead of holding it", function()
			local hold = Config.gaze.holdSeconds
			-- Progress never banks past a completed hold, however long you keep looking.
			local progress = Rules.advanceGazeProgress(0, hold * 4, true)
			Harness.near(progress, hold)
			local decayed = Rules.advanceGazeProgress(progress, 0.1, false)
			Harness.near(decayed, math.max(0, hold - 0.1 * Config.gaze.decayPerSecond))
			Harness.equal(Rules.isGazeComplete(decayed), false)
		end),

		Harness.test("the face sits inside the arch, above the floor, in the plane of the opening", function()
			local face = Rules.facePosition(ROOT, WIDTH, HEIGHT, "Right")
			local localFace = ROOT:PointToObjectSpace(face)
			Harness.expect(localFace.X > 0, "the face belongs to the trapped half")
			Harness.expect(math.abs(localFace.X) < WIDTH / 2, "the face must stay inside the opening")
			Harness.expect(localFace.Y > 0 and localFace.Y < HEIGHT, "the face must sit within the arch")
			Harness.near(localFace.Z, Config.face.forwardOffset, 1e-4)
		end),
	},
}

return suite
