--!strict
-- Pure Ashamed Lurker rules: which arches can host one, where its lane and face sit inside an arch,
-- whether a moving player trips it, whether a grab connects at the impact frame, and whether a
-- reported camera is really staring at its face from the open lane. Planner, builder, server, client
-- and tests all read these, so "the safe lane always exists" is one testable function rather than a
-- convention repeated in three files.
--
-- Geometry convention (shared with FloorBuilder): the doorway root sits at the FLOOR CENTRE of the
-- opening. Local +X runs along the wall (which half of the arch you are in), local Z runs through
-- the opening (either approach is symmetric), local +Y is up.

local Config = require(script.Parent.Parent.Config.AshamedLurker)
local LightConfig = require(script.Parent.Parent.Config.Light)
local MovementConfig = require(script.Parent.Parent.Config.Movement)

local AshamedLurkerRules = {}

export type TrapSide = "Left" | "Right"

export type GazeInput = {
	facePosition: Vector3,
	cameraPosition: Vector3,
	lookVector: Vector3,
}

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function AshamedLurkerRules.isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

function AshamedLurkerRules.normalizeTrapSide(value: unknown): TrapSide
	return if value == "Left" then "Left" else "Right"
end

-- +1 puts the body against the local +X springer, -1 against the -X one.
function AshamedLurkerRules.sideSign(trapSide: TrapSide): number
	return if trapSide == "Right" then 1 else -1
end

function AshamedLurkerRules.targetCount(depth: number): number
	if not Config.enabled or depth < Config.minDepth then
		return 0
	end
	local counts = Config.maxPerFloorByDepth
	if #counts == 0 then
		return 0
	end
	return math.max(0, counts[math.clamp(math.floor(depth), 1, #counts)])
end

-- VISUAL ONLY: how far the draped arm extends while dormant. The creature lunges well past this, so
-- this is the silhouette, not the danger — see `triggerReach`.
function AshamedLurkerRules.restArmReach(doorWidth: number): number
	local halfLane = doorWidth / 2 - Config.placement.edgeInset
	return math.max(0, math.min(Config.placement.restArmReach, halfLane))
end

-- How far the visible body may travel toward the centre line. Gameplay reach remains
-- `triggerReach`; this clamps presentation against a configured sliver of trapped-lane floor so an
-- animated hand can never imply that the open half is unsafe.
function AshamedLurkerRules.visualLungeStuds(doorWidth: number): number
	local edgeX = doorWidth / 2 - Config.placement.edgeInset
	local restingReach = AshamedLurkerRules.restArmReach(doorWidth)
	local desiredTravel = math.max(0, AshamedLurkerRules.triggerReach(doorWidth) - restingReach)
	local safeTravel = math.max(0, edgeX - restingReach - Config.motion.triggered.safeLaneMarginStuds)
	return math.min(desiredTravel, safeTravel)
end

-- Triggered begins at the first visible gathering motion, reaches impact after the grab delay, and
-- then owns a complete recovery. Keeping the sum here gives server state and client pose one
-- testable contract without duplicating either tuning value.
function AshamedLurkerRules.triggeredStateSeconds(): number
	local trigger = Config.trigger
	return math.max(0, trigger.grabCheckDelaySeconds) + math.max(0, trigger.recoverySeconds)
end

-- THE attack range: a fixed absolute distance in from the trapped springer, NOT a fraction of the
-- opening, so a wider arch is proportionally less covered rather than equally covered. Capped by the
-- trap half's own width so the lane can never cross the centre line, however the config is tuned.
function AshamedLurkerRules.triggerReach(doorWidth: number): number
	local halfLane = doorWidth / 2 - Config.placement.edgeInset
	return math.max(0, math.min(Config.trigger.reach, halfLane))
end

-- Distance from the doorway centre line to the middle of the trip lane, unsigned.
function AshamedLurkerRules.laneCenterX(doorWidth: number): number
	return doorWidth / 2 - Config.placement.edgeInset - AshamedLurkerRules.triggerReach(doorWidth) / 2
end

-- Clear floor left in the opening once the body and everything it can reach are accounted for. This
-- is the number the placement rule protects, and it is why an occupied arch is still a route.
-- Measured against the LUNGE, not the resting arm, so the guarantee covers what can actually hit you.
function AshamedLurkerRules.clearLaneWidth(doorWidth: number): number
	return doorWidth - Config.placement.edgeInset - AshamedLurkerRules.triggerReach(doorWidth)
end

function AshamedLurkerRules.isPlacementAllowed(doorWidth: number, doorHeight: number): boolean
	local placement = Config.placement
	if doorWidth < placement.minDoorWidth or doorWidth > placement.maxDoorWidth then
		return false
	end
	if doorHeight < placement.minDoorHeight or doorHeight > placement.maxDoorHeight then
		return false
	end
	return AshamedLurkerRules.clearLaneWidth(doorWidth) >= placement.minSafeLaneWidth
end

-- The point a player must stare at. Server and the client's model builder both call this, so the
-- validated target and the visible head are the same place.
function AshamedLurkerRules.facePosition(
	root: CFrame,
	doorWidth: number,
	doorHeight: number,
	trapSide: TrapSide
): Vector3
	local face = Config.face
	local side = AshamedLurkerRules.sideSign(trapSide)
	local lateral = math.max(0, doorWidth / 2 - Config.placement.edgeInset - face.lateralInset)
	return root * Vector3.new(side * lateral, doorHeight * face.heightFraction, face.forwardOffset)
end

local function insideLocalBox(root: CFrame, worldPoint: Vector3, center: Vector3, size: Vector3): boolean
	local localPoint = root:PointToObjectSpace(worldPoint) - center
	local half = size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- Dial position the flame must reach before a stare lands. Expressed against the ORDINARY dial's own
-- range, so "half brightness" means the middle of the slider the player drags, not half of an
-- absolute burn rate they never see.
function AshamedLurkerRules.requiredBurnRate(minBurnRate: number?, maxBurnRate: number?): number
	local floor = if minBurnRate ~= nil and minBurnRate == minBurnRate
		then math.clamp(minBurnRate, LightConfig.minBurnRate, LightConfig.maxBurnRate)
		else LightConfig.minBurnRate
	local ceiling = if maxBurnRate ~= nil and maxBurnRate == maxBurnRate
		then math.clamp(maxBurnRate, floor, LightConfig.maxBurnRate)
		else LightConfig.maxBurnRate
	return floor + (ceiling - floor) * Config.gaze.requiredDialFraction
end

-- Is this flame bright enough for the creature to know it is being looked at? A cupped near-ember
-- never is, whatever the dial says underneath it; FLARE always is. Mirrors VineRules.burnsVines.
function AshamedLurkerRules.lightRevealsWatcher(
	isLit: boolean,
	isCupping: boolean,
	burnRate: number,
	isFlaring: boolean,
	minBurnRate: number?,
	maxBurnRate: number?
): boolean
	if not isLit or isCupping then
		return false
	end
	if isFlaring then
		return true
	end
	return burnRate >= AshamedLurkerRules.requiredBurnRate(minBurnRate, maxBurnRate)
end

-- Measured speed at or above which a pass counts as running. Never a client claim.
function AshamedLurkerRules.triggerSpeed(): number
	return math.max(Config.trigger.minAbsoluteSpeed, MovementConfig.runSpeed * Config.trigger.minSpeedFraction)
end

local function laneBox(
	doorWidth: number,
	trapSide: TrapSide,
	lateralPadding: number,
	depthPadding: number
): (Vector3, Vector3)
	local trigger = Config.trigger
	local side = AshamedLurkerRules.sideSign(trapSide)
	local center = Vector3.new(side * AshamedLurkerRules.laneCenterX(doorWidth), trigger.laneCenterY, 0)
	local size = Vector3.new(
		AshamedLurkerRules.triggerReach(doorWidth) + lateralPadding * 2,
		trigger.laneHeight,
		trigger.laneDepth + depthPadding * 2
	)
	return center, size
end

-- The trip lane: the arm's own footprint, inside the trap half only.
function AshamedLurkerRules.insideArmLane(
	root: CFrame,
	position: Vector3,
	doorWidth: number,
	trapSide: TrapSide
): boolean
	local center, size = laneBox(doorWidth, trapSide, 0, 0)
	return insideLocalBox(root, position, center, size)
end

-- The volume checked when the hand closes. Wider than the trip lane, but leaving it during the
-- wind-up still means the grab misses and no wax is lost.
function AshamedLurkerRules.insideGrabVolume(
	root: CFrame,
	position: Vector3,
	doorWidth: number,
	trapSide: TrapSide
): boolean
	local trigger = Config.trigger
	local center, size = laneBox(doorWidth, trapSide, trigger.grabLateralPadding, trigger.grabDepthPadding)
	return insideLocalBox(root, position, center, size)
end

function AshamedLurkerRules.qualifiesRunTrigger(
	root: CFrame,
	position: Vector3,
	speed: number,
	doorWidth: number,
	trapSide: TrapSide
): boolean
	if not AshamedLurkerRules.isFiniteVector3(position) or not isFiniteNumber(speed) then
		return false
	end
	if speed < AshamedLurkerRules.triggerSpeed() then
		return false
	end
	return AshamedLurkerRules.insideArmLane(root, position, doorWidth, trapSide)
end

-- The geometry of a reported camera: close enough, and pointed at the face. Which half of the arch
-- the watcher stands in deliberately does NOT matter — being seen at all is what shames it, so
-- walking up to it head-on works, which is what a player actually tries first. Brightness is checked
-- separately (`lightRevealsWatcher`), and the caller still owns line of sight and sample freshness.
function AshamedLurkerRules.gazeQualifies(input: GazeInput): boolean
	local gaze = Config.gaze
	if
		not AshamedLurkerRules.isFiniteVector3(input.facePosition)
		or not AshamedLurkerRules.isFiniteVector3(input.cameraPosition)
		or not AshamedLurkerRules.isFiniteVector3(input.lookVector)
	then
		return false
	end

	local toFace = input.facePosition - input.cameraPosition
	local distance = toFace.Magnitude
	if distance <= 0.001 or distance > gaze.maxDistance then
		return false
	end
	-- A look vector is a unit vector. Anything else is a malformed or forged sample.
	local lookMagnitude = input.lookVector.Magnitude
	if lookMagnitude < 0.9 or lookMagnitude > 1.1 then
		return false
	end
	return input.lookVector.Unit:Dot(toFace.Unit) >= gaze.dotThreshold
end

function AshamedLurkerRules.advanceGazeProgress(current: number, dt: number, qualifies: boolean): number
	local gaze = Config.gaze
	if dt <= 0 then
		return current
	end
	if qualifies then
		return math.min(gaze.holdSeconds, current + dt)
	end
	return math.max(0, current - dt * gaze.decayPerSecond)
end

function AshamedLurkerRules.isGazeComplete(progress: number): boolean
	return progress >= Config.gaze.holdSeconds
end

return AshamedLurkerRules
