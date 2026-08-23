--!strict

local Harness = require(script.Parent.Harness)
local CameraMotion = require(script.Parent.Parent.Logic.CameraMotion)
local CameraMotionConfig = require(script.Parent.Parent.Config.CameraMotion)
local MovementConfig = require(script.Parent.Parent.Config.Movement)
local FeelConfig = require(script.Parent.Parent.Config.Feel)

local headBob = CameraMotionConfig.headBob
local landing = CameraMotionConfig.landing

local function strideAt(speed: number): CameraMotion.Stride
	return CameraMotion.stride(speed, MovementConfig.walkSpeed, MovementConfig.runSpeed, headBob)
end

-- The largest magnitude the walk cycle reaches over a full stride, sampled densely enough that a
-- component peaking somewhere other than a quarter-cycle boundary is still caught.
local function peakTranslation(stride: CameraMotion.Stride): number
	local peak = 0
	for step = 0, 240 do
		local offset = CameraMotion.bob(step / 240 * math.pi * 2, stride)
		peak = math.max(peak, math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z))
	end
	return peak
end

return {
	name = "CameraMotion",
	tests = {
		Harness.test("a standing body has no walk cycle", function()
			local stride = strideAt(0)
			Harness.equal(stride.weight, 0, "a stationary body must not bob")
			local offset = CameraMotion.bob(1.2, stride)
			Harness.expect(CameraMotion.isZero(offset), "a zero-weight stride must produce a zero offset")
		end),

		Harness.test("the bob eases in rather than switching on at the movement threshold", function()
			Harness.equal(strideAt(headBob.minimumSpeed).weight, 0, "the threshold itself is still standing still")
			local justMoving = strideAt((headBob.minimumSpeed + headBob.fullBobSpeed) / 2).weight
			Harness.expect(justMoving > 0 and justMoving < 1, "mid-ramp speed must be partially weighted")
			Harness.equal(strideAt(headBob.fullBobSpeed).weight, 1, "the full-bob speed must reach full weight")
			Harness.equal(strideAt(MovementConfig.runSpeed * 4).weight, 1, "weight must never exceed 1")
		end),

		Harness.test("running bobs harder and faster than walking", function()
			local walk = strideAt(MovementConfig.walkSpeed)
			local run = strideAt(MovementConfig.runSpeed)
			Harness.expect(run.frequencyHz > walk.frequencyHz, "a run must have a faster cadence")
			Harness.expect(run.verticalStuds > walk.verticalStuds, "a run must drop the eye further")
			Harness.expect(run.rollDegrees > walk.rollDegrees, "a run must bank further")
		end),

		-- The whole point of the authored frequencies. A stride is two steps, so the stride rate has to
		-- be half the footfall rate or the camera's low point drifts against the footstep sample until
		-- they are landing in opposite phase, which reads as somebody else walking behind you.
		Harness.test("stride cadence is half the footstep cadence at both ends", function()
			local footsteps = FeelConfig.footsteps
			Harness.near(
				headBob.walk.frequencyHz,
				0.5 / footsteps.walkIntervalSeconds,
				0.02,
				"the walk stride must be half the walk footfall rate"
			)
			Harness.near(
				headBob.run.frequencyHz,
				0.5 / footsteps.runIntervalSeconds,
				0.02,
				"the run stride must be half the run footfall rate"
			)
		end),

		Harness.test("the bob drops the eye and never lifts it above standing height", function()
			local stride = strideAt(MovementConfig.runSpeed)
			local sawDrop = false
			for step = 0, 240 do
				local offset = CameraMotion.bob(step / 240 * math.pi * 2, stride)
				Harness.expect(offset.y <= 1e-9, "the walk cycle must never raise the eye")
				if offset.y < -1e-3 then
					sawDrop = true
				end
			end
			Harness.expect(sawDrop, "the walk cycle must actually drop the eye somewhere in its cycle")
		end),

		-- DESIGN section 5: this layer must stay "at the edge of conscious notice". A regression that
		-- makes the cave lurch is a design violation, not a taste dispute, so it is asserted.
		Harness.test("the authored walk cycle stays restrained", function()
			local peak = peakTranslation(strideAt(MovementConfig.runSpeed))
			Harness.expect(peak > 0, "a running body must produce some motion")
			Harness.expect(peak < 0.04, "the run bob peaked at " .. tostring(peak) .. " studs, which is not subtle")
		end),

		Harness.test("routine sprint feedback cannot become a major camera effect", function()
			local sprint = FeelConfig.sprintFeedback
			local run = strideAt(MovementConfig.runSpeed)
			local worstTranslation = math.sqrt(
				(run.lateralStuds + sprint.cameraSwayStuds) ^ 2 + (run.verticalStuds + sprint.cameraBobStuds) ^ 2
			)
			Harness.expect(worstTranslation < 0.05, "the combined run motion must stay below a twentieth of a stud")
			Harness.expect(sprint.sprintFov - sprint.normalFov <= 5, "routine running must only widen FOV gently")
		end),

		Harness.test("phase advances with frequency and stays inside one turn", function()
			local phase = CameraMotion.advancePhase(0, 0.5, 1)
			Harness.near(phase, math.pi, 1e-9, "half a second at 1 Hz is half a turn")
			for _ = 1, 50 do
				phase = CameraMotion.advancePhase(phase, 0.1, 3)
				Harness.expect(phase >= 0 and phase < math.pi * 2, "phase must stay wrapped")
			end
		end),

		Harness.test("approach moves toward the target and settles exactly on it", function()
			Harness.near(CameraMotion.approach(0, 1, 0.05, 0.1), 0.5, 1e-9)
			Harness.equal(CameraMotion.approach(0, 1, 1, 0.1), 1, "a large step must not overshoot")
			Harness.equal(CameraMotion.approach(1, 0, 1, 0.1), 0, "a large step down must not undershoot")
			Harness.equal(CameraMotion.approach(0.3, 1, 0.016, 0), 1, "a zero ease must snap")
		end),

		-- The hop is terrain recovery and players use it constantly on uneven rock. If it dips the
		-- camera, the effect becomes a tic attached to ordinary movement.
		Harness.test("an ordinary hop produces no landing dip", function()
			Harness.equal(
				CameraMotion.landingStrength(MovementConfig.hopPower, landing),
				0,
				"a hop landing at hopPower must not register"
			)
			Harness.expect(
				CameraMotion.landingStrength(landing.fullFallSpeed, landing) == 1,
				"a full-speed fall must register fully"
			)
			Harness.expect(
				CameraMotion.landingStrength(landing.minimumFallSpeed * 1.5, landing) > 0,
				"a real drop must register"
			)
		end),

		Harness.test("the landing dip starts and ends at rest, and only ever sinks", function()
			Harness.expect(CameraMotion.isZero(CameraMotion.landing(0, 1, landing)), "the dip must start from rest")
			Harness.expect(
				CameraMotion.isZero(CameraMotion.landing(landing.durationSeconds, 1, landing)),
				"the dip must have finished by its own duration"
			)
			local lowest = 0
			for step = 1, 200 do
				local offset = CameraMotion.landing(step / 200 * landing.durationSeconds, 1, landing)
				Harness.expect(offset.y <= 1e-9, "the landing dip must never lift the eye")
				lowest = math.min(lowest, offset.y)
			end
			Harness.near(lowest, -landing.dipStuds * 0.385, 0.05, "the dip must reach roughly its authored depth")
		end),

		Harness.test("a shake decays to nothing and reports its own expiry", function()
			local shake = CameraMotion.newShake({
				studs = 0.2,
				degrees = 2,
				frequencyRadians = 30,
				durationSeconds = 0.5,
			}, 100, 0)
			Harness.expect(not CameraMotion.isExpired(shake, 100.4), "a live shake must not report expired")
			Harness.expect(CameraMotion.isExpired(shake, 100.5), "a shake must expire at its duration")
			Harness.expect(
				CameraMotion.isZero(CameraMotion.shakeOffset(shake, 100.5)),
				"an expired shake must contribute nothing"
			)
			Harness.expect(
				CameraMotion.isZero(CameraMotion.shakeOffset(shake, 99.9)),
				"a shake must contribute nothing before it starts"
			)
		end),

		Harness.test("shake amplitude falls away over its life", function()
			local shake = CameraMotion.newShake({
				studs = 0.2,
				degrees = 2,
				frequencyRadians = 60,
				durationSeconds = 1,
			}, 0, 0)
			-- The offset oscillates by design, so what has to decay is the SIZE OF THE SWING rather than
			-- the instantaneous value. Each window spans a couple of full oscillations at the authored
			-- frequency, so every one of them samples a real peak instead of wherever the sine happened
			-- to be at a single instant.
			local function peakOver(from: number, to: number): number
				local peak = 0
				for step = 0, 200 do
					local at = from + (to - from) * step / 200
					local offset = CameraMotion.shakeOffset(shake, at)
					peak = math.max(peak, math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z))
				end
				return peak
			end
			local quarters = { peakOver(0, 0.25), peakOver(0.25, 0.5), peakOver(0.5, 0.75), peakOver(0.75, 1) }
			for index = 2, #quarters do
				Harness.expect(quarters[index] < quarters[index - 1], "each quarter must swing less than the last")
			end
			Harness.expect(quarters[1] > 0, "a live shake must actually move the camera")
			Harness.expect(quarters[4] < quarters[1] * 0.25, "the tail must be a small fraction of the opening")
		end),

		Harness.test("shake strength scales the whole contribution", function()
			local spec = { studs = 0.2, degrees = 2, frequencyRadians = 30, durationSeconds = 0.5 }
			local full = CameraMotion.shakeOffset(CameraMotion.newShake(spec, 0, 0), 0.1)
			local half = CameraMotion.shakeOffset(
				CameraMotion.newShake({
					studs = spec.studs,
					degrees = spec.degrees,
					frequencyRadians = spec.frequencyRadians,
					durationSeconds = spec.durationSeconds,
					strength = 0.5,
				}, 0, 0),
				0.1
			)
			Harness.near(half.x, full.x * 0.5, 1e-9, "half strength must be half the offset")
			Harness.near(half.roll, full.roll * 0.5, 1e-9, "half strength must be half the roll")
		end),

		Harness.test("distance strength falls off to the floor value and never below it", function()
			Harness.near(CameraMotion.distanceStrength(0, 70, 0.18), 1, 1e-9, "point blank is full strength")
			Harness.near(CameraMotion.distanceStrength(35, 70, 0.18), 0.5, 1e-9, "half the radius is half strength")
			Harness.near(
				CameraMotion.distanceStrength(200, 70, 0.18),
				0.18,
				1e-9,
				"beyond the radius the floor value is what remains"
			)
			Harness.near(CameraMotion.distanceStrength(200, 70, 0), 0, 1e-9, "a zero floor makes the event local")
		end),

		Harness.test("the clamp bounds the sum while keeping its direction", function()
			local limits = { studs = 0.75, degrees = 7 }
			local clamped = CameraMotion.clampOffset({
				x = 3,
				y = 4,
				z = 0,
				pitch = math.rad(40),
				yaw = 0,
				roll = math.rad(-40),
			}, limits)
			Harness.near(
				math.sqrt(clamped.x * clamped.x + clamped.y * clamped.y),
				limits.studs,
				1e-9,
				"translation must be clamped to the limit"
			)
			-- 3-4-5: the direction survives, so a clamped shake still points where it did.
			Harness.near(clamped.x / clamped.y, 0.75, 1e-9, "clamping must preserve translation direction")
			Harness.near(clamped.pitch, math.rad(limits.degrees), 1e-9, "pitch must be clamped")
			Harness.near(clamped.roll, -math.rad(limits.degrees), 1e-9, "roll must be clamped in both directions")
		end),

		Harness.test("an offset inside the limits is left alone", function()
			local offset = { x = 0.1, y = -0.2, z = 0.05, pitch = 0.01, yaw = 0, roll = -0.02 }
			local clamped = CameraMotion.clampOffset(offset, { studs = 0.75, degrees = 7 })
			Harness.near(clamped.x, offset.x, 1e-9)
			Harness.near(clamped.y, offset.y, 1e-9)
			Harness.near(clamped.roll, offset.roll, 1e-9)
		end),

		Harness.test("offset algebra adds and scales every axis", function()
			local sum = CameraMotion.add(
				{ x = 1, y = 2, z = 3, pitch = 4, yaw = 5, roll = 6 },
				{ x = 10, y = 20, z = 30, pitch = 40, yaw = 50, roll = 60 }
			)
			Harness.equal(sum.x, 11)
			Harness.equal(sum.z, 33)
			Harness.equal(sum.yaw, 55)
			local scaled = CameraMotion.scale(sum, 0.5)
			Harness.equal(scaled.y, 11)
			Harness.equal(scaled.roll, 33)
			Harness.expect(CameraMotion.isZero(CameraMotion.scale(sum, 0)), "scaling to zero must zero every axis")
		end),

		--------------------------------------------------------------------------------
		-- Reduced motion
		--------------------------------------------------------------------------------

		Harness.test("every authored level resolves to a scale set", function()
			for _, id in CameraMotionConfig.levelOrder do
				local set = CameraMotion.scalesFor(id, CameraMotionConfig.scales)
				Harness.expect(set ~= nil, "level " .. id .. " must have scales")
				Harness.expect(CameraMotionConfig.levelLabels[id] ~= nil, "level " .. id .. " must have a label")
				for _, channel in { set.bob, set.shake, set.posture, set.viewKick } do
					Harness.expect(channel >= 0 and channel <= 1, "every scale must sit in 0..1")
				end
			end
			Harness.expect(CameraMotion.isLevel(CameraMotionConfig.defaultLevel), "the default must be a real level")
		end),

		Harness.test("an unknown level falls back to Full rather than to nothing", function()
			local fallback = CameraMotion.scalesFor("Nonsense" :: any, CameraMotionConfig.scales)
			Harness.equal(fallback, CameraMotionConfig.scales.Full, "an unrecognised level must fall back to Full")
			Harness.expect(not CameraMotion.isLevel("Nonsense"), "an unrecognised level must not validate")
			Harness.expect(not CameraMotion.isLevel(nil), "nil must not validate as a level")
		end),

		Harness.test("levels get quieter in the authored order", function()
			local order = CameraMotionConfig.levelOrder
			for index = 2, #order do
				local previous = CameraMotion.scalesFor(order[index - 1], CameraMotionConfig.scales)
				local current = CameraMotion.scalesFor(order[index], CameraMotionConfig.scales)
				Harness.expect(current.bob <= previous.bob, "bob must not increase down the list")
				Harness.expect(current.shake <= previous.shake, "shake must not increase down the list")
				Harness.expect(current.posture <= previous.posture, "posture must not increase down the list")
				Harness.expect(current.viewKick <= previous.viewKick, "view kick must not increase down the list")
			end
			Harness.equal(CameraMotionConfig.scales.Full.bob, 1, "Full must be the authored motion, unscaled")
			Harness.equal(CameraMotionConfig.scales.Off.bob, 0, "Off must remove the walk cycle entirely")
			Harness.equal(CameraMotionConfig.scales.Off.shake, 0, "Off must remove impact shakes entirely")
		end),

		-- A knockdown is the only way a first-person body can report that it is on the floor. Zeroing it
		-- would turn an accessibility setting into a rule change, which is exactly what this must not be.
		Harness.test("posture survives at every level", function()
			for _, id in CameraMotionConfig.levelOrder do
				local set = CameraMotion.scalesFor(id, CameraMotionConfig.scales)
				Harness.expect(set.posture > 0, "level " .. id .. " must keep some posture motion")
			end
		end),

		Harness.test("the level stepper wraps in both directions", function()
			local order = CameraMotionConfig.levelOrder
			local first = order[1]
			local last = order[#order]
			Harness.equal(CameraMotion.nextLevel(first, order), order[2], "forward must advance")
			Harness.equal(CameraMotion.nextLevel(last, order), first, "forward must wrap off the end")
			Harness.equal(CameraMotion.nextLevel(first, order, -1), last, "backward must wrap off the front")
			Harness.equal(CameraMotion.nextLevel(order[2], order, -1), first, "backward must retreat")
			-- Walking the whole list forward has to return to where it started, or the row can strand a
			-- player on a setting they cannot leave.
			local walked = first
			for _ = 1, #order do
				walked = CameraMotion.nextLevel(walked, order)
			end
			Harness.equal(walked, first, "a full forward cycle must return to the start")
		end),

		Harness.test("an unrecognised current level recovers to the first entry", function()
			Harness.equal(
				CameraMotion.nextLevel("Nonsense" :: any, CameraMotionConfig.levelOrder),
				CameraMotionConfig.levelOrder[1],
				"stepping from an unknown level must land on a real one"
			)
		end),

		--------------------------------------------------------------------------------
		-- The shared budget
		--------------------------------------------------------------------------------

		-- The reason the ceiling exists. Every authored shake in the game firing at once has to stay
		-- inside something a player can still aim through.
		Harness.test("stacked authored shakes stay inside the ceiling", function()
			local limits = CameraMotionConfig.limits
			local total = CameraMotion.zero()
			for index = 1, CameraMotionConfig.maximumShakes do
				local shake = CameraMotion.newShake({
					studs = 0.2,
					degrees = 2,
					frequencyRadians = 26,
					durationSeconds = 0.5,
				}, 0, index * 1.37)
				total = CameraMotion.add(total, CameraMotion.shakeOffset(shake, 0.01))
			end
			local clamped = CameraMotion.clampOffset(total, limits)
			local magnitude = math.sqrt(clamped.x * clamped.x + clamped.y * clamped.y + clamped.z * clamped.z)
			Harness.expect(magnitude <= limits.studs + 1e-9, "the clamped sum must respect the translation limit")
			Harness.expect(
				math.abs(clamped.pitch) <= math.rad(limits.degrees) + 1e-9,
				"the clamped sum must respect the rotation limit"
			)
		end),

		Harness.test("posture has enough headroom for the authored knockdown", function()
			-- client/TripwireController drops the eye 2.2 studs and pitches it 78 degrees. Sharing the
			-- ordinary budget would clip that to a stumble, which is why it is bounded separately.
			local knockdown = { x = 0, y = -2.2, z = 0, pitch = math.rad(-78), yaw = 0, roll = 0 }
			local clamped = CameraMotion.clampOffset(knockdown, CameraMotionConfig.postureLimits)
			Harness.near(clamped.y, knockdown.y, 1e-9, "the knockdown drop must survive the posture bound")
			Harness.near(clamped.pitch, knockdown.pitch, 1e-9, "the knockdown pitch must survive the posture bound")
			Harness.expect(
				CameraMotionConfig.postureLimits.studs > CameraMotionConfig.limits.studs,
				"posture must be bounded more loosely than the shared budget"
			)
		end),
	},
}
