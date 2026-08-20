--!strict
-- THE ONLY THING IN THIS GAME THAT MOVES THE CAMERA. Head bob, the landing dip, every decaying
-- shake and every sustained pose arrive here, are scaled by the player's reduced-motion setting,
-- summed, bounded, and written to `camera.CFrame` exactly once per frame.
--
-- WHY IT IS A SINGLE WRITER. Seven controllers used to end their own render step with
-- `camera.CFrame = camera.CFrame * ...`. That is fine in isolation and wrong in aggregate: the
-- dripstone impact, the dynamite blast, the Lurker's grab, the Warden's rumble, the tripwire, the
-- Unlittius slams and the sprint sway all multiplied into each other at overlapping priorities, with
-- no combined ceiling, and -- the part that actually matters -- no single place a player could turn
-- any of it down. `client/CameraController` already reached the same conclusion for
-- `Humanoid.CameraOffset` and put the elevator's ride vibration behind one writer; this is that rule
-- applied to the other half of the camera.
--
-- WHAT LIVES WHERE. The MATH is `shared/Logic/CameraMotion`, pure and testable without an engine.
-- The POLICY -- how much motion, and the ceiling -- is `Config/CameraMotion`. This file is the thin
-- adapter between them and the Roblox camera: it reads the humanoid, keeps the phase, and writes the
-- CFrame. Each creature and hazard keeps authoring its own shake numbers in its own config and hands
-- them over through `impulse`; nothing about a Warden's footfall belongs in a camera file.
--
-- IT NEVER DECIDES ANYTHING. No rule, no speed, no wax, no damage. It renders motion the server has
-- already caused.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CameraMotion = require(ReplicatedStorage.Shared.Logic.CameraMotion)
local LobbyVisualProtocol = require(ReplicatedStorage.Shared.LobbyVisualProtocol)

local CameraMotionController = {}

export type Level = CameraMotion.Level
export type Offset = CameraMotion.Offset
export type ShakeSpec = CameraMotion.ShakeSpec

-- Which reduced-motion scale a contribution is measured against. `Bob` and `Shake` share the bounded
-- budget; `Posture` is a deliberate authored pose (a tripwire knockdown) and is bounded separately.
export type Category = "Bob" | "Shake" | "Posture"

type Sustained = {
	offset: CameraMotion.Offset,
	category: Category,
}

-- After the wall-lamp look takeover (+3) and after `WickCamera` (+2) has settled the subject and the
-- first-person eye offset, so this multiplies a camera that is already where it belongs.
local RENDER_STEP_NAME = "WickCameraMotion"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 6

local player = Players.LocalPlayer

local level: CameraMotion.Level = Config.CameraMotion.defaultLevel
local scales: CameraMotion.Scales = CameraMotion.scalesFor(level, Config.CameraMotion.scales)

local shakes: { CameraMotion.Shake } = {}
local sustained: { [string]: Sustained } = {}
local nextSeed = 0

-- Walk cycle state. `phase` is carried rather than derived from the clock so a change of speed never
-- jumps the sine (see `CameraMotion.advancePhase`); `groundedWeight` fades the whole cycle out when
-- the feet leave the rock.
local phase = 0
local groundedWeight = 0
local bobWeight = 0

-- Landing state. The humanoid reports that it landed but not how hard, so the fall speed is sampled
-- while airborne and read back at touchdown.
local wasGrounded = true
local fallSpeed = 0
local landedAt = -math.huge
local landingStrength = 0

local function currentCharacter(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, if root ~= nil and root:IsA("BasePart") then root :: BasePart else nil
end

-- Locomotion motion belongs to the first-person run body only. The hub avatar is viewed in third
-- person, where a head bob would be moving an orbit camera around a body that is already animating
-- itself -- the same signal the run body has no other way to show. Impacts are NOT gated on this:
-- a blast is a blast wherever you are standing.
local function hasRunBody(character: Model?): boolean
	return character ~= nil and character:GetAttribute(LobbyVisualProtocol.attributes.runBody) == true
end

local function resetLocomotion()
	phase = 0
	groundedWeight = 0
	bobWeight = 0
	wasGrounded = true
	fallSpeed = 0
	landedAt = -math.huge
	landingStrength = 0
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

-- ONE DECAYING IMPACT. Callers pass their OWN authored numbers -- the dripstone's studs, the blast's
-- duration, the Warden's frequency -- because a shake is part of the thing that caused it and belongs
-- in that thing's config. All this file adds is the reduced-motion scale, the shared ceiling and the
-- fact that everyone's shakes now sum instead of multiplying.
function CameraMotionController.impulse(spec: CameraMotion.ShakeSpec)
	if not Config.CameraMotion.enabled or spec.durationSeconds <= 0 then
		return
	end
	local strength = math.clamp(spec.strength or 1, 0, 1)
	if strength <= 0 or (spec.studs <= 0 and spec.degrees <= 0) then
		return
	end
	-- The oldest is also the most decayed, so it is the least visible thing that can be dropped.
	while #shakes >= Config.CameraMotion.maximumShakes do
		table.remove(shakes, 1)
	end
	nextSeed += 1
	-- A non-integer stride so two impulses fired on the same frame never share a phase and reinforce
	-- into one larger sine.
	table.insert(shakes, CameraMotion.newShake(spec, os.clock(), nextSeed * 1.37))
end

-- The same impulse, weighted by how far away it happened. `floorStrength` is what someone elsewhere on
-- the floor still feels; passing 0 makes the event purely local.
function CameraMotionController.impulseAt(
	spec: CameraMotion.ShakeSpec,
	distance: number,
	radius: number,
	floorStrength: number
)
	local strength = CameraMotion.distanceStrength(distance, radius, floorStrength) * (spec.strength or 1)
	if strength <= 0 then
		return
	end
	CameraMotionController.impulse({
		studs = spec.studs,
		degrees = spec.degrees,
		frequencyRadians = spec.frequencyRadians,
		durationSeconds = spec.durationSeconds,
		strength = strength,
	})
end

-- A CONTINUOUS CONTRIBUTION the caller recomputes each frame and owns until it clears it with `nil`.
-- For motion that is not an event with a decay of its own: the Warden's proximity rumble, which stops
-- because he left rather than because it ran out; the sprint's instability; the tripwire's fall.
-- Keyed, so a source can be updated or cleared without knowing about any other source.
function CameraMotionController.setSustained(key: string, offset: CameraMotion.Offset?, category: Category?)
	if offset == nil or not Config.CameraMotion.enabled then
		sustained[key] = nil
		return
	end
	sustained[key] = { offset = offset, category = category or "Shake" }
end

function CameraMotionController.setLevel(next_: CameraMotion.Level)
	level = next_
	scales = CameraMotion.scalesFor(level, Config.CameraMotion.scales)
	if scales.shake <= 0 then
		table.clear(shakes)
	end
end

function CameraMotionController.getLevel(): CameraMotion.Level
	return level
end

function CameraMotionController.cycleLevel(step: number?): CameraMotion.Level
	CameraMotionController.setLevel(CameraMotion.nextLevel(level, Config.CameraMotion.levelOrder, step))
	return level
end

function CameraMotionController.levelLabel(): string
	return Config.CameraMotion.levelLabels[level] or level
end

-- For the screen effects this file does not draw but whose policy it owns -- the sprint FOV widen and
-- its heat shimmer live in `SprintFeedbackController`, and they answer to the same setting.
function CameraMotionController.scales(): CameraMotion.Scales
	return scales
end

--------------------------------------------------------------------------------
-- Per-frame solve
--------------------------------------------------------------------------------

local function stepLocomotion(dt: number, character: Model?, humanoid: Humanoid?, root: BasePart?): CameraMotion.Offset
	if humanoid == nil or root == nil or not hasRunBody(character) then
		resetLocomotion()
		return CameraMotion.zero()
	end

	local config = Config.CameraMotion
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	-- LANDING. Sampled from the fall itself rather than from `Humanoid.StateChanged`, because the
	-- state fires without telling you how far the body dropped and a hop and a shaft are the same
	-- event to it. The deepest downward speed reached while airborne is the honest measure.
	if not grounded then
		fallSpeed = math.max(fallSpeed, -velocity.Y)
	elseif not wasGrounded then
		local strength = CameraMotion.landingStrength(fallSpeed, config.landing)
		if strength > 0 then
			landedAt = os.clock()
			landingStrength = strength
		end
		fallSpeed = 0
	end
	wasGrounded = grounded

	local stride = CameraMotion.stride(speed, Config.Movement.walkSpeed, Config.Movement.runSpeed, config.headBob)
	groundedWeight = CameraMotion.approach(groundedWeight, if grounded then 1 else 0, dt, config.headBob.airEaseSeconds)
	bobWeight = CameraMotion.approach(bobWeight, stride.weight, dt, config.headBob.easeSeconds)
	-- The cycle keeps turning at the current cadence even while it is faded out, so re-entering it
	-- picks up where the stride left off rather than restarting mid-step.
	phase = CameraMotion.advancePhase(phase, dt, stride.frequencyHz)

	stride.weight = bobWeight * groundedWeight
	local offset = CameraMotion.scale(CameraMotion.bob(phase, stride), scales.bob)

	local landing = CameraMotion.landing(os.clock() - landedAt, landingStrength, config.landing)
	return CameraMotion.add(offset, CameraMotion.scale(landing, scales.posture))
end

local function stepShakes(now: number): CameraMotion.Offset
	local total = CameraMotion.zero()
	local index = 1
	while index <= #shakes do
		local shake = shakes[index]
		if CameraMotion.isExpired(shake, now) then
			-- Swap-remove: order is meaningless here and the list is walked every frame.
			shakes[index] = shakes[#shakes]
			shakes[#shakes] = nil
			continue
		end
		total = CameraMotion.add(total, CameraMotion.shakeOffset(shake, now))
		index += 1
	end
	return CameraMotion.scale(total, scales.shake)
end

local function scaleFor(category: Category): number
	if category == "Bob" then
		return scales.bob
	elseif category == "Posture" then
		return scales.posture
	end
	return scales.shake
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil or not Config.CameraMotion.enabled then
		return
	end
	local character, humanoid, root = currentCharacter()
	local now = os.clock()

	local bounded = CameraMotion.add(stepLocomotion(dt, character, humanoid, root), stepShakes(now))
	local posture = CameraMotion.zero()
	for _, entry in sustained do
		local scaled = CameraMotion.scale(entry.offset, scaleFor(entry.category))
		if entry.category == "Posture" then
			posture = CameraMotion.add(posture, scaled)
		else
			bounded = CameraMotion.add(bounded, scaled)
		end
	end

	local config = Config.CameraMotion
	local total = CameraMotion.add(
		CameraMotion.clampOffset(bounded, config.limits),
		CameraMotion.clampOffset(posture, config.postureLimits)
	)
	if CameraMotion.isZero(total) then
		return
	end
	camera.CFrame = camera.CFrame
		* CFrame.new(total.x, total.y, total.z)
		* CFrame.Angles(total.pitch, total.yaw, total.roll)
end

function CameraMotionController.start()
	CameraMotionController.setLevel(Config.CameraMotion.defaultLevel)
	-- Every floor and every death hands the player an entirely new candle model. Carrying a walk phase
	-- or a half-finished landing across that boundary would put a stumble on the first frame of a
	-- floor the player has not taken a step on yet.
	player.CharacterAdded:Connect(resetLocomotion)
	RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_PRIORITY, step)
end

return CameraMotionController
