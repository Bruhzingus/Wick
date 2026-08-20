--!strict
-- THE CAMERA'S OWN MOTION, as pure math. Head bob, the sprint stride, the landing dip and every
-- decaying shake in the game resolve here into one additive offset. `client/CameraMotionController`
-- is the only thing that turns that offset into a CFrame.
--
-- WHY THIS IS ONE MODULE AND NOT SEVEN. Before it, seven controllers each ended their render step
-- with `camera.CFrame = camera.CFrame * ...`: the dripstone impact, the dynamite blast, the Lurker's
-- grab, the Warden's rumble and footfalls, the Knotwalker's tripwire, Unlittius's slams, and the
-- sprint sway. Each was right on its own. Together they multiplied, at overlapping render
-- priorities, with no shared ceiling and no single place to turn any of it down -- and a player who
-- needs less camera motion needs less of ALL of it, not less of whichever system was rewritten last.
--
-- Everything here is a pure function of numbers: no Instances, no services, and no clock of its own.
-- The caller passes `now`, which is what makes the whole surface testable without an engine.
--
-- TWO FREQUENCY UNITS, DELIBERATELY. Stride values are authored in Hz because a designer thinks in
-- steps per second; shake values are authored in radians per second because that is how every
-- existing hazard config already expresses them (`impactShakeFrequency = 41`) and reinterpreting
-- those numbers would silently retune six creatures. Both fields are named for the unit they carry.

local CameraMotion = {}

-- Camera-local. +X right, +Y up, -Z forward; rotations in RADIANS, applied as Angles(pitch, yaw, roll).
export type Offset = {
	x: number,
	y: number,
	z: number,
	pitch: number,
	yaw: number,
	roll: number,
}

-- How much of the authored motion a player has asked to receive. `Off` is not "no feedback": the FOV
-- widen, the vignette, the grade and every audio cue survive it. It is "no camera movement".
export type Level = "Full" | "Reduced" | "Off"

export type Scales = {
	-- Continuous locomotion motion: head bob and the sprint sway.
	bob: number,
	-- One-shot and sustained impacts: explosions, falling stone, creature footfalls, grabs.
	shake: number,
	-- Motion that reports a game STATE rather than an event -- being knocked flat by a tripwire, the
	-- landing dip. Scaled less hard than a shake, because removing it removes information.
	posture: number,
	-- Screen effects that move without moving the camera: the sprint FOV widen and its heat shimmer.
	viewKick: number,
}

export type StrideBand = {
	frequencyHz: number,
	verticalStuds: number,
	lateralStuds: number,
	rollDegrees: number,
	pitchDegrees: number,
}

export type Stride = {
	frequencyHz: number,
	verticalStuds: number,
	lateralStuds: number,
	rollDegrees: number,
	pitchDegrees: number,
	weight: number,
}

export type HeadBobConfig = {
	minimumSpeed: number,
	fullBobSpeed: number,
	walk: StrideBand,
	run: StrideBand,
	easeSeconds: number,
	airEaseSeconds: number,
}

export type LandingConfig = {
	minimumFallSpeed: number,
	fullFallSpeed: number,
	dipStuds: number,
	pitchDegrees: number,
	durationSeconds: number,
}

export type Limits = {
	studs: number,
	degrees: number,
}

-- One decaying impact. `strength` is the caller's own 0..1 weighting (distance falloff, or how
-- directly the event happened to you); the envelope multiplies it.
export type Shake = {
	studs: number,
	degrees: number,
	frequencyRadians: number,
	durationSeconds: number,
	startedAt: number,
	strength: number,
	seed: number,
}

export type ShakeSpec = {
	studs: number,
	degrees: number,
	frequencyRadians: number,
	durationSeconds: number,
	strength: number?,
}

local TAU = math.pi * 2

function CameraMotion.zero(): Offset
	return { x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0 }
end

function CameraMotion.add(a: Offset, b: Offset): Offset
	return {
		x = a.x + b.x,
		y = a.y + b.y,
		z = a.z + b.z,
		pitch = a.pitch + b.pitch,
		yaw = a.yaw + b.yaw,
		roll = a.roll + b.roll,
	}
end

function CameraMotion.scale(offset: Offset, factor: number): Offset
	return {
		x = offset.x * factor,
		y = offset.y * factor,
		z = offset.z * factor,
		pitch = offset.pitch * factor,
		yaw = offset.yaw * factor,
		roll = offset.roll * factor,
	}
end

function CameraMotion.isZero(offset: Offset, epsilon: number?): boolean
	local tolerance = epsilon or 1e-5
	return math.abs(offset.x) < tolerance
		and math.abs(offset.y) < tolerance
		and math.abs(offset.z) < tolerance
		and math.abs(offset.pitch) < tolerance
		and math.abs(offset.yaw) < tolerance
		and math.abs(offset.roll) < tolerance
end

-- THE CEILING THAT MAKES STACKING SAFE. Nothing here decides which effects are allowed to overlap --
-- a blast during a Warden's approach while a tripwire has you on the floor is a legitimate moment,
-- and dropping one of them would be a worse answer than bounding the sum. Translation is scaled as a
-- whole so a clamped offset keeps its DIRECTION; rotations are clamped per axis, because they do not
-- read as a single vector.
function CameraMotion.clampOffset(offset: Offset, limits: Limits): Offset
	local maxRadians = math.rad(math.max(limits.degrees, 0))
	local magnitude = math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
	local factor = 1
	if limits.studs <= 0 then
		factor = 0
	elseif magnitude > limits.studs then
		factor = limits.studs / magnitude
	end
	return {
		x = offset.x * factor,
		y = offset.y * factor,
		z = offset.z * factor,
		pitch = math.clamp(offset.pitch, -maxRadians, maxRadians),
		yaw = math.clamp(offset.yaw, -maxRadians, maxRadians),
		roll = math.clamp(offset.roll, -maxRadians, maxRadians),
	}
end

--------------------------------------------------------------------------------
-- Reduced motion
--------------------------------------------------------------------------------

function CameraMotion.isLevel(value: unknown): boolean
	return value == "Full" or value == "Reduced" or value == "Off"
end

function CameraMotion.scalesFor(level: Level, byLevel: { [string]: Scales }): Scales
	local found = byLevel[level]
	if found ~= nil then
		return found
	end
	return byLevel.Full
end

-- The settings row is a stepper rather than three radio buttons, so the order in config IS the order a
-- player walks through, and `step` is which button they pressed. Both directions wrap, so neither
-- button can ever strand them at an end of the list with nothing to press.
function CameraMotion.nextLevel(level: Level, order: { Level }, step: number?): Level
	local count = #order
	if count == 0 then
		return level
	end
	local delta = step or 1
	for index, candidate in order do
		if candidate == level then
			-- `- 1` into 0-based, wrap, `+ 1` back out: Lua's `%` already returns a non-negative result
			-- for a positive divisor, so stepping backward off the front lands on the last entry.
			return order[(index - 1 + delta) % count + 1]
		end
	end
	return order[1]
end

--------------------------------------------------------------------------------
-- Head bob
--------------------------------------------------------------------------------

-- Amplitude and cadence for the speed the body is ACTUALLY moving at, interpolated between the
-- authored walk and run bands. Two separate ramps, which is the whole trick:
--
--   `weight` eases the bob in from a standstill, so stepping off is a fade rather than a switch.
--   `alpha`  blends walk into run, so a Cup-slowed body bobs slowly and a sprint bobs hard.
--
-- Speed is MEASURED horizontal speed, passed in by the caller. Never the input vector: a body pinned
-- against a wall is holding full deflection and going nowhere, and bobbing there is the single most
-- obvious way a first-person camera announces that it is faking.
function CameraMotion.stride(speed: number, walkSpeed: number, runSpeed: number, config: HeadBobConfig): Stride
	local floorSpeed = math.max(config.minimumSpeed, 0)
	local fullSpeed = math.max(config.fullBobSpeed, floorSpeed + 0.001)
	local weight = math.clamp((speed - floorSpeed) / (fullSpeed - floorSpeed), 0, 1)
	local span = math.max(runSpeed - walkSpeed, 0.001)
	local alpha = math.clamp((speed - walkSpeed) / span, 0, 1)
	local walk = config.walk
	local run = config.run
	local function blend(from: number, to: number): number
		return from + (to - from) * alpha
	end
	return {
		frequencyHz = blend(walk.frequencyHz, run.frequencyHz),
		verticalStuds = blend(walk.verticalStuds, run.verticalStuds),
		lateralStuds = blend(walk.lateralStuds, run.lateralStuds),
		rollDegrees = blend(walk.rollDegrees, run.rollDegrees),
		pitchDegrees = blend(walk.pitchDegrees, run.pitchDegrees),
		weight = weight,
	}
end

-- Phase is carried by the caller across frames and advanced by frequency, never derived from the
-- clock. Deriving it as `os.clock() * frequency` makes every speed change jump the sine to a new
-- point in its cycle, which reads as a stumble every time you start or stop running.
function CameraMotion.advancePhase(phase: number, dt: number, frequencyHz: number): number
	return (phase + dt * frequencyHz * TAU) % TAU
end

-- Toward `target` at a fixed rate expressed as seconds for the full 0..1 travel. Used for the bob's
-- ease and for the airborne fade, so leaving the ground stops the cadence over a few frames instead
-- of cutting it dead.
function CameraMotion.approach(current: number, target: number, dt: number, seconds: number): number
	if seconds <= 0 then
		return target
	end
	local step = dt / seconds
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

-- THE WALK CYCLE. A stride is two steps, so the VERTICAL component runs at double the stride
-- frequency -- the body drops once per foot -- while the lateral sway and the roll run at the stride
-- frequency itself, alternating left and right over a full pair of steps. `-abs(sin)` rather than a
-- plain sine, because a walking body dips at each footfall and returns to level between them; it
-- does not rise above standing height.
--
-- The authored bands are paced to `Feel.footsteps`: 0.52 s per step at a walk and 0.33 s at a run
-- mean 0.96 Hz and 1.52 Hz strides, so the camera's low point and the footstep sample land together
-- instead of drifting in and out of phase with each other over a corridor.
function CameraMotion.bob(phase: number, stride: Stride): Offset
	local amount = stride.weight
	if amount <= 0 then
		return CameraMotion.zero()
	end
	return {
		x = math.sin(phase) * stride.lateralStuds * amount,
		y = -math.abs(math.sin(phase)) * stride.verticalStuds * amount,
		z = 0,
		-- A quarter cycle behind the drop: the view noses down as weight lands, not in lockstep with it.
		pitch = math.rad(math.sin(phase * 2 - math.pi * 0.5) * stride.pitchDegrees * amount),
		yaw = 0,
		roll = math.rad(math.sin(phase) * stride.rollDegrees * amount),
	}
end

--------------------------------------------------------------------------------
-- Landing
--------------------------------------------------------------------------------

-- How hard a landing at this fall speed reads, 0..1. Below `minimumFallSpeed` a landing produces
-- nothing at all: the hop is terrain recovery (DESIGN section 5) and players use it constantly on
-- uneven ground, so a dip on every seam-clearing hop would be a tic rather than an impact.
function CameraMotion.landingStrength(fallSpeed: number, config: LandingConfig): number
	local floor = math.max(config.minimumFallSpeed, 0)
	local full = math.max(config.fullFallSpeed, floor + 0.001)
	return math.clamp((math.abs(fallSpeed) - floor) / (full - floor), 0, 1)
end

-- Down, then back up, over `durationSeconds`. `sin(pi*u) * (1-u)` starts at zero, reaches its low
-- point about a third of the way through and returns to zero without overshooting, which is what a
-- knee absorbing a drop does. A spring would ring, and a ringing camera on every landing is exactly
-- the kind of effect players go looking for a setting to turn off.
function CameraMotion.landing(elapsed: number, strength: number, config: LandingConfig): Offset
	local duration = math.max(config.durationSeconds, 0.001)
	if elapsed < 0 or elapsed >= duration or strength <= 0 then
		return CameraMotion.zero()
	end
	local u = elapsed / duration
	local curve = math.sin(math.pi * u) * (1 - u) * strength
	return {
		x = 0,
		y = -config.dipStuds * curve,
		z = 0,
		pitch = math.rad(-config.pitchDegrees * curve),
		yaw = 0,
		roll = 0,
	}
end

--------------------------------------------------------------------------------
-- Shakes
--------------------------------------------------------------------------------

function CameraMotion.newShake(spec: ShakeSpec, now: number, seed: number): Shake
	return {
		studs = spec.studs,
		degrees = spec.degrees,
		frequencyRadians = spec.frequencyRadians,
		durationSeconds = math.max(spec.durationSeconds, 0.001),
		startedAt = now,
		strength = math.clamp(spec.strength or 1, 0, 1),
		seed = seed,
	}
end

function CameraMotion.isExpired(shake: Shake, now: number): boolean
	return now - shake.startedAt >= shake.durationSeconds
end

-- One impact, sampled. The envelope is `remaining^2`, the curve every hand-rolled shake in this
-- codebase already used: it drops fast enough that a blast is over before the player can resent it,
-- and slowly enough at the tail that it settles rather than snapping off.
--
-- The translation and rotation axes run at mutually off-multiples of one phase so the sample never
-- repeats visibly, and `seed` offsets that phase per event so two impacts close together stay
-- distinguishable instead of reinforcing into one large sine.
function CameraMotion.shakeOffset(shake: Shake, now: number): Offset
	local elapsed = now - shake.startedAt
	if elapsed < 0 or elapsed >= shake.durationSeconds then
		return CameraMotion.zero()
	end
	local remaining = 1 - elapsed / shake.durationSeconds
	local envelope = remaining * remaining * shake.strength
	local phase = elapsed * shake.frequencyRadians + shake.seed
	local studs = shake.studs * envelope
	local radians = math.rad(shake.degrees) * envelope
	return {
		x = math.sin(phase * 1.17) * studs,
		y = math.cos(phase * 1.53) * studs,
		z = math.sin(phase * 0.89) * studs * 0.4,
		pitch = math.cos(phase * 0.83) * radians * 0.55,
		yaw = 0,
		roll = math.sin(phase) * radians,
	}
end

-- How strongly an event at `distance` lands. `floorStrength` is what a player anywhere else on the
-- floor still feels: a blast is a floor-wide event, and reporting nothing to someone two rooms away
-- would misdescribe it as something local.
function CameraMotion.distanceStrength(distance: number, radius: number, floorStrength: number): number
	local near = math.clamp(1 - distance / math.max(radius, 0.001), 0, 1)
	return math.max(math.clamp(floorStrength, 0, 1), near)
end

return CameraMotion
