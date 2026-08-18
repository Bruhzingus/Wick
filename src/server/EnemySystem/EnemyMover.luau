--!strict
-- Movement for the wick-pack bodies: the Humanoid, the path, and the ground under it.
--
-- WHY A SHARED MOVER AND NOT ONE PER CREATURE. The three mobile bodies disagree about WHERE they want
-- to go and agree about everything involved in getting there — the rig, the agent size, how often to
-- repath, and what to do when the route fails. That last one is the whole reason this file exists:
-- `StoneWardenBehavior` learned the hard way that a failed `ComputeAsync` must HOLD, never fall
-- through to direct movement, because direct movement on a failed route walks a body into solid rock
-- and leaves it there. Writing that rule once is the difference between three creatures that behave
-- and three chances to get it wrong.
--
-- THE AGENT IS SIZED TO THE BODY THAT WAS ACTUALLY BUILT. The Warden's own comment records what
-- happens otherwise: it asked for a 12-stud agent, Config/Floors rolls doorways between 8 and 13
-- studs tall, and every route through a shorter opening failed — so most of the floor did not exist
-- for the pursuit. Elder bodies are 18% larger (EnemyKit.finish), so the agent is derived from the
-- built model's own extents rather than from a config constant.
--
-- ROUGH TERRAIN IS THE OTHER HALF. The cave floor is voxel Terrain written from an analytic field,
-- and the two disagree by up to a voxel. A body left to the Humanoid alone sinks into that error or
-- floats over it, so every mover step re-seats the body on MEASURED ground through `SurfaceProbe`,
-- the same reconciliation ThreatService and every static fixture already use.

local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local SurfaceProbe = require(script.Parent.Parent.SurfaceProbe)

local EnemyMover = {}
EnemyMover.__index = EnemyMover

export type Mover = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		humanoid: Humanoid,
		agentRadius: number,
		agentHeight: number,
		-- Distance from the rock to the root when standing in the rest pose. Sampled once; see `reseat`.
		-- A body that changes posture rather than merely animating — the Longarm folding to clear a
		-- doorway — restates it through `setRideHeight`, which is a deliberate act by a behaviour and
		-- not the per-frame re-measurement `reseat` warns against.
		rideHeight: number,
		-- The ride height measured at attach, so a posture change can always get back to it exactly.
		standingRideHeight: number,
		baseSpeed: number,
		-- The speed a behaviour last asked for, kept so the charge hatch can raise WalkSpeed for the
		-- duration of an override and put it back afterwards without the caller re-stating it.
		walkSpeed: number,
		-- The route currently being walked, and how far along it we are. Rebuilt on `repathInterval`
		-- or whenever the destination moves further than `repathMoveTolerance` from the one it was
		-- computed against.
		waypoints: { PathWaypoint },
		waypointIndex: number,
		destination: Vector3?,
		computedFor: Vector3?,
		nextRepathAt: number,
		-- Set while a caller is driving velocity directly (the Gnawer's charge). Pathing is entirely
		-- suspended for as long as this is non-nil.
		override: Vector3?,
		-- A direction to TURN the body toward while it is otherwise standing still. See `setFacing`.
		facing: Vector3?,
		blockedUntil: number,
		destroyed: boolean,
	},
	EnemyMover
))

local REPATH_INTERVAL = 0.45
local REPATH_MOVE_TOLERANCE = 6
local WAYPOINT_ARRIVE_TOLERANCE = 2.5
-- How long a body holds still after a route failed before trying again. Long enough that a creature
-- boxed in by geometry is not recomputing a doomed path every frame, short enough that it recovers
-- the moment the player moves somewhere reachable.
local BLOCKED_HOLD_SECONDS = 0.9

-- Everything a pack body needs to be moved by a Humanoid, added around the model the pack built.
-- The pack deliberately creates no Humanoid (that is documented as the host's job), and its root is
-- an ordinary unanchored Part, so this is the whole adapter.
-- How far a built body's root sits above the lowest point of that body, in its REST pose.
--
-- This is the number every ground-seating step needs, and it must be sampled once. Read live it would
-- be measuring a model mid-animation: the extents breathe as the creature walks, so the height it
-- believes it should stand at changes with its own gait and it drives itself up and down through the
-- rock. It is also a full descendant walk, which is not something a floor carrying a brood plus two
-- Longarms should be doing per body per frame.
local function measureRideHeight(model: Model, root: BasePart): number
	local boundingCFrame, boundingSize = model:GetBoundingBox()
	local lowestY = boundingCFrame.Position.Y - boundingSize.Y * 0.5
	return math.max(root.Position.Y - lowestY, 0.5)
end

-- `agentHeightOverride` is for a body that can get through an opening SHORTER THAN IT IS. The Longarm
-- stands 11.8 studs against doorways that roll 8 to 13 (Config/Floors) and folds to 7.1 to pass, so
-- routed at its standing height every cross-room path would fail to compute — and a failed path makes
-- this mover HOLD, by design. It would stand at the doorway it was about to duck through, forever.
-- What the agent height has to state is the smallest gap the body can get through by any means, not
-- how tall it is when it is not trying.
function EnemyMover.attach(model: Model, root: BasePart, speed: number, agentHeightOverride: number?): Mover
	local extents = model:GetExtentsSize()
	-- Radius from the body's own footprint with a small margin; height from its real standing height.
	-- Both floored so a very small body (a grub) still gets an agent PathfindingService will accept.
	local agentRadius = math.max(1.5, math.max(extents.X, extents.Z) * 0.5 + 0.4)
	local agentHeight = math.max(3, (agentHeightOverride or extents.Y) + 0.5)

	-- Measured from the REST pose, before any animation has run.
	local rideHeight = measureRideHeight(model, root)

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	-- R15, THOUGH NOTHING HERE IS AN AVATAR. This is the only RigType under which `HipHeight` means
	-- "distance from the ground to the bottom of the root"; under the R6 default it is an offset onto a
	-- standing height derived from limbs named "Left Leg"/"Right Leg", which a pack rig does not have.
	humanoid.RigType = Enum.HumanoidRigType.R15
	-- THE HUMANOID HAS TO AGREE WITH `reseat` ABOUT HOW TALL THIS BODY STANDS, and left at the default
	-- HipHeight of 0 it does not. The Humanoid holds the root's underside on the rock — for the Gnawer's
	-- 1.02-stud root block that is a root centre half a stud up, while its legs reach well over a stud
	-- below — so the creature is held with its feet inside the floor, and every `reseat` correction is
	-- immediately undone by the Humanoid's own controller on the next physics step. That standoff is
	-- what a body sunk into the ground and juddering across it actually is. Stating the measured ride
	-- height here makes the two agree, and leaves `reseat` correcting only real voxel error.
	humanoid.HipHeight = math.max(rideHeight - root.Size.Y * 0.5, 0)
	-- A pack body is not a character: it has no state machine worth running, no jump, no climb, and
	-- no ragdoll. Disabling the states it will never enter is the cheapest performance win available
	-- on a floor that may hold a brood plus two Longarms.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = speed
	humanoid.Parent = model

	-- Roblox finds the root by NAME. The pack names its root after the creature's own anatomy
	-- ("Body0", "Torso", …), so without this rename the Humanoid has no root part and MoveTo silently
	-- does nothing — which presents as a creature that animates perfectly and never travels.
	root.Name = "HumanoidRootPart"
	model.PrimaryPart = root

	-- FREEFALL IS NOT ON THIS LIST, though every other airborne state is. A cave floor is voxel relief
	-- and a body crossing it steps off small drops constantly; without Freefall the state machine has
	-- nowhere to go when the ground leaves, so it stays in Running and keeps solving for a surface that
	-- is no longer under it. What that looks like is a creature hitching at every lip in the rock. The
	-- states below are ones these bodies genuinely never enter — they do not jump, climb, swim, or
	-- ragdoll — so disabling those is still free.
	for _, state in
		{
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Jumping,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.PlatformStanding,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.StrafingNoPhysics,
		}
	do
		pcall(humanoid.SetStateEnabled, humanoid, state, false)
	end

	-- SEAT THE BODY BEFORE IT TAKES A STEP, because it did not arrive seated. `EnemyMover.groundedSpawn`
	-- returns the measured GROUND POINT and every pack constructor pivots its model there, which puts
	-- the root — not the feet — on the rock and buries everything below it. This is the one place that
	-- can fix it for all three Humanoid bodies: the ride height is not known until the model is built,
	-- and it is measured right here. Attach is called once, immediately after construction, so the lift
	-- applies exactly once.
	local spawnPosition = root.Position
	local spawnGroundY = SurfaceProbe.tryGroundY(spawnPosition.Y, spawnPosition.X, spawnPosition.Z, 0)
		-- A floor with a Part floor rather than Terrain (the developer laboratory) probes to nothing, and
		-- its spawner has already resolved a flat height. The spawn point is the ground either way.
		or spawnPosition.Y
	-- PivotTo rather than a write to `root.CFrame`: this is a whole-body move of an unanchored Motor6D
	-- assembly, and only the pivot carries every jointed part with it in the same frame. (`reseat` writes
	-- the root directly because its corrections are sub-voxel and run every frame — see there.)
	model:PivotTo(
		CFrame.new(spawnPosition.X, spawnGroundY + rideHeight, spawnPosition.Z) * (root.CFrame - spawnPosition)
	)

	return setmetatable({
		model = model,
		root = root,
		humanoid = humanoid,
		agentRadius = agentRadius,
		agentHeight = agentHeight,
		rideHeight = rideHeight,
		standingRideHeight = rideHeight,
		baseSpeed = speed,
		walkSpeed = speed,
		waypoints = {},
		waypointIndex = 1,
		destination = nil,
		computedFor = nil,
		nextRepathAt = 0,
		override = nil,
		facing = nil,
		blockedUntil = 0,
		destroyed = false,
	}, EnemyMover)
end

-- RESTATE HOW TALL THE BODY IS STANDING RIGHT NOW. Only for a body that genuinely changes posture —
-- today that is the Longarm folding to clear a doorway — and it moves BOTH numbers that decide where
-- the body sits, because moving one alone is the creature-in-the-ground bug in a different costume:
-- `reseat` corrects toward `rideHeight` while the Humanoid's own controller holds `HipHeight`, and a
-- disagreement between them is a body that stutters between two heights every frame.
--
-- It is deliberately a call rather than a per-frame measurement (see the note on `reseat`): a
-- behaviour knows it is folding, and a measurement of a body mid-fold cannot tell that from a gait.
function EnemyMover.setRideHeight(self: Mover, rideHeight: number)
	if self.destroyed or self.humanoid.Parent == nil then
		return
	end
	local clamped = math.max(rideHeight, 0.5)
	if math.abs(self.rideHeight - clamped) < 0.01 then
		return
	end
	self.rideHeight = clamped
	self.humanoid.HipHeight = math.max(clamped - self.root.Size.Y * 0.5, 0)
end

-- The ride height this body was built standing at, for a behaviour returning from a posture change.
function EnemyMover.standingRide(self: Mover): number
	return self.standingRideHeight
end

-- TURN A STANDING BODY TO FACE A DIRECTION, WITHOUT TELEPORTING IT.
--
-- The obvious way to aim a creature is to write `root.CFrame = CFrame.lookAt(...)`, and on a body with
-- no Humanoid it is the right way — the grub does exactly that. On a Humanoid body it is a teleport:
-- the controller loses the floor it was holding the body above, the body enters Freefall, and
-- `Humanoid:Move` has no traction until it lands again. The Stone Gnawer's own charge did this at the
-- start of every wind-up, which is why it sank into the ground, stood there unable to travel, and
-- popped back up when the state ended (Enemies/StoneGnawer.beginCharge records the same story).
--
-- WalkSpeed 0 plus a Move direction is the Humanoid-native way to say the same thing: AutoRotate turns
-- the body toward the commanded direction and the zero speed means it does not travel while doing it.
-- Cleared with nil, which hands WalkSpeed back to whatever the behaviour last asked for.
function EnemyMover.setFacing(self: Mover, direction: Vector3?)
	if direction == nil then
		self.facing = nil
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	self.facing = if flat.Magnitude > 0.01 then flat.Unit else nil
end

function EnemyMover.setSpeed(self: Mover, speed: number)
	if self.destroyed or self.humanoid.Parent == nil then
		return
	end
	self.walkSpeed = speed
	-- An override owns WalkSpeed for as long as it is set; it is restored from `walkSpeed` on release.
	if self.override ~= nil then
		return
	end
	if math.abs(self.humanoid.WalkSpeed - speed) > 0.01 then
		self.humanoid.WalkSpeed = speed
	end
end

-- THE CHARGE HATCH. While an override is set the mover drives the commanded direction at the commanded
-- speed and does not path, steer, or correct — which is the entire counter to the Gnawer and the one
-- behaviour the pack is explicit must not be smoothed away. Clearing it hands control back to
-- pathfinding.
--
-- THE DIRECTION GOES THROUGH THE HUMANOID, NOT THROUGH `AssemblyLinearVelocity`. Writing the velocity
-- directly reads like the more literal way to honour "does not steer", and on flat ground it is — but
-- the Humanoid's controller is still running underneath, and it re-solves the body's velocity against
-- the ground every physics step. A charge written once per Heartbeat is being damped several times per
-- Heartbeat by the controller that owns the body, so it crawls, stutters, and dies against the smallest
-- rise. `Move` is the same commitment expressed to the thing actually in charge of the legs: a fixed
-- world direction, no target, no re-aim, and the slope handling that gets it across a cave floor.
function EnemyMover.setVelocityOverride(self: Mover, velocity: Vector3?)
	self.override = velocity
	if velocity == nil then
		if self.humanoid.Parent ~= nil then
			self.humanoid.WalkSpeed = self.walkSpeed
			self.humanoid:Move(Vector3.zero, false)
		end
	end
	if velocity ~= nil then
		-- Drop any route in progress. Resuming a stale path after a charge would walk the body back
		-- toward wherever it was going before it committed.
		table.clear(self.waypoints)
		self.waypointIndex = 1
		self.destination = nil
		self.computedFor = nil
	end
end

function EnemyMover.isOverridden(self: Mover): boolean
	return self.override ~= nil
end

function EnemyMover.setDestination(self: Mover, position: Vector3?)
	self.destination = position
end

local function computePath(self: Mover, from: Vector3, to: Vector3): boolean
	local path = PathfindingService:CreatePath({
		AgentRadius = self.agentRadius,
		AgentHeight = self.agentHeight,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return false
	end
	local waypoints = path:GetWaypoints()
	if #waypoints < 2 then
		return false
	end
	self.waypoints = waypoints
	-- Index 1 is the body's own position; walking to it is a no-op that stalls the route for a tick.
	self.waypointIndex = 2
	self.computedFor = to
	return true
end

-- Re-seat the body on the Terrain that was actually written, rather than on wherever physics has
-- settled it. The probe is a narrow window around the current height on purpose: a long ray finds
-- shelves, overhangs and the roof, and none of those is this creature's floor.
-- THE RIDE HEIGHT IS SAMPLED ONCE, AT ATTACH. Measuring it here from live extents would sample a
-- body mid-animation, so a walking creature's own gait would change the height it thinks it should be
-- standing at and drive it visibly up and down through the floor. It is also a descendant walk per
-- body per frame, which a floor carrying a brood plus two Longarms cannot afford.
-- A POINT QUERY, NOT A FOOTPRINT ONE, and that is the difference between a body that walks and one
-- that does not. `tryGroundY` with a sample radius fires eight extra rays and refuses unless all of
-- them land within `maxPeripheralDeltaStuds` of the centre's tangent plane. That is the right question
-- for a PERMANENT placement — a loot pickup must not straddle a hump — and the wrong one for a body
-- crossing the room, because the answer is "no" precisely where the floor is uneven, which is where the
-- correction was needed. A creature mid-stride does not need a certified seat; it needs the rock under
-- it right now. `ThreatService.resolveGroundY` already asks it this way for the older roster.
local function reseat(self: Mover)
	local position = self.root.Position
	local half = self.rideHeight
	local measured = SurfaceProbe.tryGroundY(position.Y - half, position.X, position.Z, 0)
	if measured == nil then
		return
	end
	local desiredY = measured + half
	-- Only correct real disagreement. Writing CFrame every frame fights the Humanoid's own controller
	-- and produces a body that visibly stutters while walking.
	if math.abs(position.Y - desiredY) > 0.35 then
		self.root.CFrame = CFrame.new(position.X, desiredY, position.Z) * (self.root.CFrame - position)
	end
end

-- STANDING STILL, which for two of these creatures is most of their life. A body with a facing turns
-- on the spot (WalkSpeed 0 leaves AutoRotate to do the work); one without holds the heading it has.
local function hold(self: Mover)
	local facing = self.facing
	if facing ~= nil then
		self.humanoid.WalkSpeed = 0
		self.humanoid:Move(facing, false)
		return
	end
	if math.abs(self.humanoid.WalkSpeed - self.walkSpeed) > 0.01 then
		self.humanoid.WalkSpeed = self.walkSpeed
	end
	self.humanoid:Move(Vector3.zero, false)
end

-- `now` is os.clock(); the mover keeps no clock of its own so every body on a floor shares the one
-- the owning service already sampled.
function EnemyMover.step(self: Mover, now: number)
	if self.destroyed or self.root.Parent == nil or self.humanoid.Parent == nil then
		return
	end

	local override = self.override
	if override ~= nil then
		-- A FIXED WORLD DIRECTION, NO PATHING. Only the horizontal component is commanded, because a
		-- charge is a ground manoeuvre — the Humanoid keeps the body on the floor and carries it up the
		-- rises it meets, which is exactly what a direct velocity write was fighting.
		local flat = Vector3.new(override.X, 0, override.Z)
		local speed = flat.Magnitude
		if speed > 0.01 then
			self.humanoid.WalkSpeed = speed
			self.humanoid:Move(flat.Unit, false)
		else
			self.humanoid:Move(Vector3.zero, false)
		end
		reseat(self)
		return
	end

	if now < self.blockedUntil then
		hold(self)
		return
	end

	local destination = self.destination
	if destination == nil then
		hold(self)
		return
	end

	local computedFor = self.computedFor
	local needsRepath = now >= self.nextRepathAt
		or computedFor == nil
		or (computedFor - destination).Magnitude > REPATH_MOVE_TOLERANCE
	if needsRepath then
		self.nextRepathAt = now + REPATH_INTERVAL
		if not computePath(self, self.root.Position, destination) then
			-- STRUCTURAL ROCK IS A HARDER BOUNDARY THAN PURSUIT. Hold and retry rather than moving
			-- directly at the target: direct movement on a failed route is exactly how a body walks
			-- into a cave wall and stays there.
			table.clear(self.waypoints)
			self.waypointIndex = 1
			self.computedFor = nil
			self.blockedUntil = now + BLOCKED_HOLD_SECONDS
			self.humanoid:Move(Vector3.zero, false)
			return
		end
	end

	local waypoint = self.waypoints[self.waypointIndex]
	if waypoint == nil then
		self.humanoid:Move(Vector3.zero, false)
		return
	end

	local delta = waypoint.Position - self.root.Position
	if Vector3.new(delta.X, 0, delta.Z).Magnitude <= WAYPOINT_ARRIVE_TOLERANCE then
		self.waypointIndex += 1
		waypoint = self.waypoints[self.waypointIndex]
		if waypoint == nil then
			self.humanoid:Move(Vector3.zero, false)
			return
		end
		delta = waypoint.Position - self.root.Position
	end

	self.humanoid:MoveTo(waypoint.Position)
	reseat(self)
end

function EnemyMover.destroy(self: Mover)
	self.destroyed = true
	table.clear(self.waypoints)
	if self.humanoid.Parent ~= nil then
		self.humanoid:Destroy()
	end
end

-- The ground point a body should be placed at when it is first built, or nil when the proposed spot
-- has no measured Terrain under it. Spawners refuse rather than guess: a body seated on an analytic
-- height it cannot verify is a body standing inside a wall.
function EnemyMover.groundedSpawn(position: Vector3, footprintRadius: number): Vector3?
	local measured = SurfaceProbe.tryGroundY(position.Y, position.X, position.Z, footprintRadius)
	if measured == nil then
		return nil
	end
	return Vector3.new(position.X, measured, position.Z)
end

-- Whether a straight line from `from` to `to` is clear of cave geometry, used by the Gnawer to see
-- whether its charge is about to hit rock. Terrain plus the floor model, matching the filters the
-- rest of the game already raycasts against.
function EnemyMover.chargeObstruction(from: Vector3, direction: Vector3, radius: number): RaycastResult?
	local floors = Workspace:FindFirstChild("WickFloors")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if floors ~= nil then { Workspace.Terrain, floors } else { Workspace.Terrain }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return Workspace:Spherecast(from, math.max(radius, 0.5), direction, params)
end

-- HOW MUCH ROCK IS OVERHEAD, in studs, up to `upTo` — which is also what it returns when the answer
-- is "nothing within that". Cast from a little above the floor rather than from the root, so the
-- answer is the height of the OPENING and not the height of the gap above the creature's own hips.
--
-- One ray, asked by a body that already knows it is tall. It is the Longarm's whole basis for
-- deciding to fold, and it is asked about a point AHEAD of the body rather than under it: a creature
-- that starts folding once it is already under the lintel has folded too late.
function EnemyMover.overheadClearance(from: Vector3, upTo: number): number
	local floors = Workspace:FindFirstChild("WickFloors")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if floors ~= nil then { Workspace.Terrain, floors } else { Workspace.Terrain }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local origin = from + Vector3.new(0, 0.5, 0)
	local hit = Workspace:Raycast(origin, Vector3.new(0, upTo, 0), params)
	if hit == nil then
		return upTo
	end
	return math.max((hit.Position - from).Magnitude, 0)
end

-- Exposed so bodies that do NOT take a Mover — the grub, which is CFrame-driven, and anything else
-- that seats itself — measure their ride height exactly the way the mover does rather than each
-- inventing an approximation.
function EnemyMover.measureRideHeight(model: Model, root: BasePart): number
	return measureRideHeight(model, root)
end

return EnemyMover
