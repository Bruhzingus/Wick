--!strict
-- Server authority for dynamite: the bag, the throw, the socket, the fuse, and everything the blast
-- touches. `Logic/DynamiteRules` owns every decision; this file owns the Instances and the clock.
--
-- THE ONE PLACE A THREAT CAN DIE. That is a deliberate, narrow exception to DESIGN pillar 2, taken as
-- an owner decision and recorded in DESIGN §6a — not a drift toward combat. What keeps it narrow is
-- not this file's restraint but the item's economics (Config/Dynamite): roughly one stick every two
-- floors, a carry cap of four, the largest single self-inflicted wax hit in the game, and a detonation
-- that calls the entire floor to the crater. Every one of those is a number a designer can retune,
-- which is the point — the exception is bounded by config rather than by convention.
--
-- THREE THINGS ARM A STICK, and they are the same stick:
--
--   * THROWN — aimed and thrown along the Decoy's own validated arc. Defensive, and the risky one:
--     the fuse is short and the blast does not care who lit it.
--   * SOCKETED — one confirmed hold seats and lights the charge in a blast-door pocket. The outlined
--     silhouette previews the exact placement before the player commits.
--   * THROWN AT A DOOR — a stick that comes to rest near a door face breaks it anyway. Deliberately
--     generous: a player who improvised should be rewarded for the idea rather than punished for
--     their aim.
--
-- WHAT THIS FILE DOES NOT DECIDE: how much damage a distance is worth, how many sticks a body is
-- worth, whether the bag has room, or which floors carry supply. All four are pure functions in
-- `Logic/DynamiteRules`, so what a cold test asserts and what a live server does are one function.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local DynamiteRules = require(ReplicatedStorage.Shared.Logic.DynamiteRules)
local DynamiteModel = require(ReplicatedStorage.Shared.NewModelsAndObjects.Dynamite)
local DynamiteVisualProtocol = require(ReplicatedStorage.Shared.DynamiteVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local FloorBuilder = require(script.Parent.FloorBuilder)
local PlayerState = require(script.Parent.PlayerState)
local SurfaceProbe = require(script.Parent.SurfaceProbe)
local CharacterService = require(script.Parent.CharacterService)
local RequestGuard = require(script.Parent.RequestGuard)
local ActionFeedbackService = require(script.Parent.ActionFeedbackService)
local NoiseService = require(script.Parent.NoiseService)
local ThreatService = require(script.Parent.ThreatService)
local WaxService = require(script.Parent.WaxService)
local WardenRegistry = require(script.Parent.WardenRegistry)
local EnemyRegistry = require(script.Parent.EnemyRegistry)
local QueenRegistry = require(script.Parent.QueenRegistry)
local Telemetry = require(script.Parent.Telemetry)

local DynamiteService = {}

-- The action id the hotbar chip and the feedback channel both key off.
local ACTION_ID = "Dynamite"

type Door = FloorBuilder.BlastDoorRuntime & {
	broken: boolean,
	-- The seated charge, if somebody has placed one. Held here rather than looked up by name so a
	-- second player cannot socket a stick into a pocket that already has one.
	charge: Charge?,
}

type Charge = {
	ownerId: Types.PlayerId,
	kind: Types.LiveDynamiteKind,
	depth: number,
	position: Vector3,
	litAt: number?,
	built: DynamiteModel.BuiltStick,
	doorIndex: number?,
	-- Which floor's door list `doorIndex` points into. A charge outlives nothing, but a floor being
	-- torn down under it would otherwise leave an index into a table that has been replaced.
	doorDepth: number?,
}

local charges: { Charge } = {}
local doorsByDepth: { [number]: { Door } } = {}
local chargeFolder: Folder? = nil

local function ensureChargeFolder(): Folder
	local current = chargeFolder
	if current ~= nil and current.Parent ~= nil then
		return current
	end
	local folder = Instance.new("Folder")
	folder.Name = "WickDynamite"
	folder.Parent = Workspace
	chargeFolder = folder
	return folder
end

--------------------------------------------------------------------------------
-- Landing a thrown stick
--------------------------------------------------------------------------------

-- Deliberately the SAME raycast filters the Decoy uses, because a player who has learned where a decoy
-- will land has learned where a stick will land. Terrain is the floor; the floor model carries walls
-- and formations that shorten a throw.
-- THE DEVELOPER LAB, opted in exactly as it is for the Decoy in `server/ToolService`. The lab is a
-- part-built room under `workspace.WickDevTestRoom` with no Terrain and no `WickFloors` folder, so
-- without these a throw down there found no obstruction filter at all, `resolveThrow` returned nil
-- and every throw came back refused — a stick that equips and will not leave the hand.
local devTestGeometry: Instance? = nil
local devTestGround: BasePart? = nil

local function obstructionParams(): RaycastParams?
	local floors = Workspace:FindFirstChild("WickFloors")
	local devGeometry = devTestGeometry
	local devLive = devGeometry ~= nil and devGeometry.Parent ~= nil
	if floors == nil and not devLive then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local roots: { Instance } = { Workspace.Terrain }
	if floors ~= nil then
		table.insert(roots, floors)
	end
	if devLive then
		table.insert(roots, devGeometry :: Instance)
	end
	params.FilterDescendantsInstances = roots
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

local function groundParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	-- Gameplay floor is Terrain; the lab's slab is the one part allowed to seat a stick, so the fallback
	-- ray finds ground down there instead of leaving the charge hovering at throw height.
	local roots: { Instance } = { Workspace.Terrain }
	local devGround = devTestGround
	if devGround ~= nil and devGround.Parent ~= nil then
		table.insert(roots, devGround)
	end
	params.FilterDescendantsInstances = roots
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

-- Opt the isolated lab floor into the ordinary throw solver. Mirrors `ToolService.setDevTestGeometry`
-- and is called from the same place.
function DynamiteService.setDevTestGeometry(geometry: Instance?, ground: BasePart?)
	devTestGeometry = geometry
	devTestGround = ground
end

-- What a throw resolved to. `door`/`doorIndex` are set only when the flight passed through a blast
-- door's charge pocket, in which case the stick seats there instead of coming to rest on the floor.
type ThrowResult = {
	position: Vector3,
	door: Door?,
	doorIndex: number?,
	-- The launch velocity the arc was simulated with, handed on so the visible flight replays the same
	-- parabola the solver walked.
	velocity: Vector3,
}

-- Seat a resting point on real ground.
--
-- SEATED THROUGH `SurfaceProbe`, not through a bare downward ray. The single-raycast version this
-- replaces put thrown sticks in the floor, and the reason is the reason `SurfaceProbe` exists at all:
-- Terrain is written on a 4-stud voxel grid, so one centre hit can easily be a couple of studs below
-- the rock a player is standing on a foot away. `tryGroundY` requires complete support around the
-- stick's footprint and keeps the centre hit as its seat, which is the same tangent-aware support rule
-- used by planned floor objects.
local function seatOnGround(point: Vector3): Vector3
	local throwConfig = Config.Dynamite.throw
	local sampled = SurfaceProbe.tryGroundY(point.Y, point.X, point.Z, throwConfig.restSampleRadius)
	if sampled ~= nil then
		return Vector3.new(point.X, sampled + throwConfig.restHeight, point.Z)
	end

	-- The probe found no supported Terrain in its window. Fall back to a wide ray rather than refusing
	-- the throw: a stick a stud out of place still explodes, and eating a player's rarest consumable
	-- over a raycast that clipped a voxel would be far worse than a badly seated stick.
	local probeOrigin = point + Vector3.new(0, throwConfig.groundProbeHeight, 0)
	local ground = Workspace:Raycast(
		probeOrigin,
		Vector3.new(0, -(throwConfig.groundProbeHeight + throwConfig.groundProbeDepth), 0),
		groundParams()
	)
	if ground == nil then
		return point + Vector3.yAxis * throwConfig.restHeight
	end
	return ground.Position + Vector3.yAxis * throwConfig.restHeight
end

-- Every unbroken, uncharged blast door on this floor, as socket positions the arc can be tested
-- against. Resolved once per throw rather than per simulation step.
local function socketTargets(depth: number): { { door: Door, index: number, position: Vector3 } }
	local targets: { { door: Door, index: number, position: Vector3 } } = {}
	local floorDoors = doorsByDepth[depth]
	if floorDoors == nil then
		return targets
	end
	for index, door in floorDoors do
		if door.broken or door.charge ~= nil or door.model.Parent == nil then
			continue
		end
		table.insert(targets, { door = door, index = index, position = door.socket.WorldPosition })
	end
	return targets
end

-- WHERE A THROWN STICK ACTUALLY GOES.
--
-- This is a simulated projectile, not a placement. `origin` is the candle's base and `direction` is
-- the camera's full 3D look — pitch included, which is the entire point: the old solver flattened the
-- aim and resolved to exactly `range` studs every time, so where a player looked changed nothing.
--
-- The arc is walked in fixed time steps with a raycast between consecutive points, so the first thing
-- in its path stops it. Two outcomes matter along the way:
--
--   * IT PASSED THROUGH A CHARGE POCKET. Checked BEFORE the obstruction ray for that step, because a
--     socket sits proud of a door the ray is about to hit — testing after would mean a dead-centre
--     throw at the marker registered as "hit the rock" every time.
--   * IT HIT SOMETHING. The stick is pulled back off the surface and seated on the ground below.
--
-- A FAILED FLIGHT IS NOT FATAL. If the arc runs its full length in open air the stick still resolves
-- to the last point, seated on whatever ground is under it. Refusing the throw would eat the player's
-- rarest consumable over geometry that happened to be missing.
local function resolveThrow(origin: Vector3, direction: Vector3, depth: number): ThrowResult?
	local throwConfig = Config.Dynamite.throw
	local obstruction = obstructionParams()
	if obstruction == nil then
		return nil
	end
	local velocity = DynamiteRules.throwVelocity(direction)
	if velocity == nil then
		return nil
	end

	local launch = origin + Vector3.yAxis * throwConfig.launchHeight
	local targets = socketTargets(depth)
	local step = DynamiteRules.flightStepSeconds()
	local steps = math.max(1, math.floor(throwConfig.simulationSteps))
	local previous = launch

	for index = 1, steps do
		local point = DynamiteRules.ballisticPoint(launch, velocity :: Vector3, index * step)

		-- THE SOCKET CATCH, tested against the segment rather than only its endpoints: at full launch
		-- speed a step covers several studs, so a marker could otherwise sit between two samples and be
		-- missed by a throw that visibly went straight through it.
		for _, target in targets do
			if DynamiteRules.catchesSocket(DynamiteRules.distanceToSegment(target.position, previous, point)) then
				return {
					position = target.position,
					door = target.door,
					doorIndex = target.index,
					velocity = velocity :: Vector3,
				}
			end
		end

		local hit = Workspace:Raycast(previous, point - previous, obstruction)
		if hit ~= nil then
			-- Pulled back along the flight rather than dropped at the impact point, so a stick never
			-- resolves flush inside the rock it struck.
			local travel = point - previous
			local back = if travel.Magnitude > 1e-4 then travel.Unit * throwConfig.obstructionInset else Vector3.zero
			return {
				position = seatOnGround(hit.Position - back),
				door = nil,
				doorIndex = nil,
				velocity = velocity :: Vector3,
			}
		end
		previous = point
	end

	return { position = seatOnGround(previous), door = nil, doorIndex = nil, velocity = velocity :: Vector3 }
end

--------------------------------------------------------------------------------
-- Arming
--------------------------------------------------------------------------------

-- Tell every client a fuse is burning, and where. Fired for BOTH kinds of charge: `dynamiteLit` is
-- what puts the sputtering cue in the world, and a fuse nobody can hear is a fuse nobody can react to.
local function announceLit(charge: Charge)
	Remotes.get("RunEvent"):FireAllClients("dynamiteLit", {
		position = charge.position,
		depth = charge.depth,
		fuseSeconds = DynamiteRules.fuseSecondsFor(charge.kind),
	})
end

-- THE FLIGHT THE PLAYER WATCHES, and it is the same parabola the solver already walked rather than a
-- decorative lob laid over the answer. `resolveThrow` simulated real ballistics to find the landing;
-- replaying that arc means the stick visibly travels the path that actually decided where it stopped,
-- so a steep throw looks steep and a flat one skims.
--
-- The end is PINNED to the resolved landing rather than trusted to the simulation. The solver pulled
-- the point back off whatever it struck and seated it on ground; re-deriving the position from time
-- alone would put the stick back inside the rock the inset exists to keep it out of.
local function animateThrownCharge(
	built: DynamiteModel.BuiltStick,
	origin: Vector3,
	landing: Vector3,
	velocity: Vector3?
)
	local throwConfig = Config.Dynamite.throw
	local startPoint = origin + Vector3.yAxis * throwConfig.launchHeight
	-- SCALED BY HOW FAR IT ACTUALLY WENT. `animationSeconds` is the FULL-RANGE flight; a stick dropped
	-- at the thrower's own feet covered a fraction of that distance and has no business taking the same
	-- third of a second to arrive. Floored at `minimumAnimationFraction` so the shortest drop still
	-- visibly falls instead of appearing on the ground.
	local travelled = (landing - startPoint).Magnitude
	local reach = math.max(throwConfig.range, 0.001)
	local fraction = math.clamp(travelled / reach, math.clamp(throwConfig.minimumAnimationFraction, 0, 1), 1)
	local duration = math.max(throwConfig.animationSeconds, 0) * fraction
	if duration <= 0 then
		built.model:PivotTo(CFrame.new(landing))
		return
	end
	local startedAt = os.clock()
	task.spawn(function()
		while built.model.Parent ~= nil do
			local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
			local point: Vector3
			if velocity ~= nil then
				-- Replay the real arc, then converge onto the resolved landing as the flight completes so
				-- the two agree exactly at the moment the stick stops.
				local flown = DynamiteRules.ballisticPoint(startPoint, velocity, alpha * duration)
				point = flown:Lerp(landing, alpha * alpha)
			else
				point = startPoint:Lerp(landing, alpha)
			end
			built.model:PivotTo(
				CFrame.new(point) * CFrame.Angles(alpha * math.pi * 4, alpha * math.pi * 1.5, alpha * math.pi)
			)
			if alpha >= 1 then
				built.model:PivotTo(CFrame.new(landing))
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function spawnCharge(
	state: Types.PlayerRunState,
	kind: Types.LiveDynamiteKind,
	position: Vector3,
	lit: boolean,
	doorIndex: number?,
	throwOrigin: Vector3?,
	-- The launch velocity the solver actually used, so the flight the player watches is the parabola
	-- that decided the landing rather than a lob drawn over the top of it.
	throwVelocity: Vector3?
): Charge
	local built = DynamiteModel.buildArmed()
	built.model:PivotTo(CFrame.new(throwOrigin or position))
	built.model.Parent = ensureChargeFolder()
	DynamiteModel.setLit(built, lit)
	if throwOrigin ~= nil then
		animateThrownCharge(built, throwOrigin, position, throwVelocity)
	end

	local charge: Charge = {
		ownerId = state.playerId,
		kind = kind,
		depth = state.depth,
		position = position,
		litAt = if lit then os.clock() else nil,
		built = built,
		doorIndex = doorIndex,
		doorDepth = if doorIndex ~= nil then state.depth else nil,
	}
	table.insert(charges, charge)
	-- ANNOUNCED HERE RATHER THAN AT THE CALL SITES, so a charge that is born burning (a thrown stick)
	-- and a socketed one use the same path, so they cannot disagree about whether anybody hears the fuse.
	if lit then
		announceLit(charge)
	end
	return charge
end

local function removeCharge(charge: Charge)
	for index = #charges, 1, -1 do
		if charges[index] == charge then
			table.remove(charges, index)
			break
		end
	end
	charge.built.model:Destroy()
end

local function doorFor(charge: Charge): Door?
	local depth = charge.doorDepth
	local index = charge.doorIndex
	if depth == nil or index == nil then
		return nil
	end
	local floorDoors = doorsByDepth[depth]
	if floorDoors == nil then
		return nil
	end
	return floorDoors[index]
end

--------------------------------------------------------------------------------
-- The blast
--------------------------------------------------------------------------------

-- Break one door: drop its collision, throw its face, and leave the opening walkable.
--
-- COLLISION IS DROPPED FIRST, BEFORE A SINGLE PIECE MOVES: the thing that blocks must stop blocking
-- immediately, and a player standing in the opening must never be caught by geometry that is on its
-- way out.
local function breakDoor(door: Door)
	if door.broken or door.model.Parent == nil then
		return
	end
	door.broken = true
	door.barrier.CanCollide = false
	door.barrier.CanQuery = false
	door.model:SetAttribute(DynamiteVisualProtocol.attributes.open, false)
	door.model:SetAttribute(DynamiteVisualProtocol.attributes.charged, false)
	CollectionService:RemoveTag(door.model, DynamiteVisualProtocol.doorTag)

	-- The face is thrown rather than deleted. Unanchored, briefly: it is the only physics in the whole
	-- feature, it is purely cosmetic, and it cleans itself up on a timer so a floor never accumulates
	-- rubble it has to remember.
	local rubbleRng = Random.new()
	local thrown = 0
	local limit = math.max(0, math.floor(Config.Dynamite.door.rubblePieces))
	for _, piece in door.pieces do
		if piece.Parent == nil then
			continue
		end
		if thrown >= limit then
			piece:Destroy()
			continue
		end
		thrown += 1
		piece.Anchored = false
		-- NON-COLLIDING, and `rubbleLifetimeSeconds` is tuned around that. Colliding debris would be
		-- free to shove a candle into a wall or off a shelf for a second after their own explosion —
		-- the same failure dropping a barrier before its geometry moves avoids.
		-- Non-colliding rubble sinks through the floor instead, so the lifetime is short enough that
		-- every piece is destroyed while it is still on the way UP and the sink is never seen.
		piece.CanCollide = false
		piece.CanQuery = false
		piece.AssemblyLinearVelocity =
			Vector3.new(rubbleRng:NextNumber(-18, 18), rubbleRng:NextNumber(16, 32), rubbleRng:NextNumber(-18, 18))
		piece.AssemblyAngularVelocity =
			Vector3.new(rubbleRng:NextNumber(-8, 8), rubbleRng:NextNumber(-8, 8), rubbleRng:NextNumber(-8, 8))
	end
	local model = door.model
	task.delay(Config.Dynamite.door.rubbleLifetimeSeconds, function()
		if model.Parent ~= nil then
			model:Destroy()
		end
	end)
end

-- EVERYTHING A STICK DOES, in this order:
--
--   1. every candle in radius loses wax, falling off with distance — including the one that lit it;
--   2. every creature in radius takes blast damage, and dies if that finishes it;
--   3. a live Warden in radius is damaged, stunned and slowed, but effectively never killed;
--   4. any blast door in radius breaks;
--   5. a very loud, slow-decaying noise is left on the crater;
--   6. every threat on the floor is called to it.
--
-- STEPS 5 AND 6 ARE THE PRICE, and they run even when the stick killed everything nearby — especially
-- then. The whole design of the item is that the loud answer works and then bills you for it.
local function detonate(charge: Charge)
	local position = charge.position
	local depth = charge.depth
	local radius = Config.Dynamite.blast.radius

	removeCharge(charge)

	local caught = 0
	for playerId, state in PlayerState.all() do
		if state.depth ~= depth or not state.alive or state.finished then
			continue
		end
		local cost = DynamiteRules.blastWaxCost((state.position - position).Magnitude)
		if cost <= 0 then
			continue
		end
		caught += 1
		-- Through WaxService like every other hit in the game, so a Candle Sleeve protects against your
		-- own dynamite for free and the ledger records what actually left the candle.
		WaxService.drainExternal(
			playerId,
			cost,
			"DynamiteBlast" :: Types.WaxSource,
			"You were caught in your own blast.",
			{ kind = "Hit", seconds = 0 },
			"DynamiteBlast"
		)
	end

	local blast = ThreatService.applyBlast(depth, position, radius)

	local wardensHit = 0
	local wardensKilled = 0
	for _, entry in WardenRegistry.positionsAtDepth(depth) do
		local distance = (entry.position - position).Magnitude
		if distance > radius then
			continue
		end
		local damage = DynamiteRules.blastDamage(distance)
		if damage <= 0 then
			continue
		end
		wardensHit += 1
		if entry.warden.blast(damage) then
			wardensKilled += 1
		end
	end

	-- THE WICK PACK'S BODIES (server/EnemyRegistry). Identical shape to the Warden loop above and
	-- deliberately so: they are bespoke bodies rather than Config/Threats rows, so `ThreatService`
	-- cannot see them, and without this they would be the only creatures in the cave immune to the one
	-- thing that kills everything else. Distance-scaled exactly like every other body — the per-species
	-- toughness lives in each creature's own `blast.hitPoints` (Config/WaxGrub, Longarm, StoneGnawer).
	local enemiesHit = 0
	local enemiesKilled = 0
	for _, entry in EnemyRegistry.positionsAtDepth(depth) do
		local distance = (entry.position - position).Magnitude
		if distance > radius then
			continue
		end
		local damage = DynamiteRules.blastDamage(distance)
		if damage <= 0 then
			continue
		end
		enemiesHit += 1
		if entry.enemy.blast(damage) then
			enemiesKilled += 1
		end
	end

	-- THE GRUB QUEEN, and the one place in this file that does NOT scale with distance.
	--
	-- She counts STICKS, not damage (Config/GrubQueen): six detonations inside the radius kill her,
	-- whether each was thrown at her face or bounced off a wall twenty studs away. That is an owner
	-- decision and it is what keeps her difficulty knob ("number of charges required") a literal
	-- integer the designer can read, instead of a damage pool that has to be reverse-engineered from a
	-- falloff curve. It also matters in play: her chamber forces the player to keep moving and throw
	-- from wherever they happen to be, and a distance falloff would quietly punish exactly the
	-- desperate cross-room throw the encounter is built to produce.
	local queensHit = 0
	local queensKilled = 0
	for _, entry in QueenRegistry.positionsAtDepth(depth) do
		if (entry.position - position).Magnitude > radius then
			continue
		end
		queensHit += 1
		if entry.queen.applyDynamite(Config.GrubQueen.dynamiteDamage) then
			queensKilled += 1
		end
	end

	local doorsBroken = 0
	local floorDoors = doorsByDepth[depth]
	if floorDoors ~= nil then
		for _, door in floorDoors do
			if door.broken or door.model.Parent == nil then
				continue
			end
			-- Measured to the door's own centre, not to the socket: a charge seated in the pocket and a
			-- stick that landed against the face are the same event as far as the rock is concerned.
			if DynamiteRules.breaksDoor((door.position - position).Magnitude) then
				breakDoor(door)
				doorsBroken += 1
			end
		end
	end

	NoiseService.emit(Config.Dynamite.blast.noiseKind, position, nil)
	local roused =
		ThreatService.alertAll(depth, position, Config.Dynamite.blast.alertRadius, Config.Dynamite.blast.alertSeconds)

	Remotes.get("RunEvent"):FireAllClients("dynamiteExploded", {
		position = position,
		depth = depth,
		radius = radius,
		shakeRadius = Config.Dynamite.blast.shakeRadius,
	})
	Telemetry.event("dynamite_exploded", charge.ownerId, {
		depth = depth,
		kind = charge.kind,
		caught = caught,
		killed = blast.killed,
		staggered = blast.staggered,
		wardensHit = wardensHit,
		wardensKilled = wardensKilled,
		enemiesHit = enemiesHit,
		enemiesKilled = enemiesKilled,
		queensHit = queensHit,
		queensKilled = queensKilled,
		doorsBroken = doorsBroken,
		roused = roused,
	})
end

--------------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------------

-- Find the door a client named, by its barrier part. Re-resolved from THIS service's own registry
-- rather than trusted from the client: the part is only ever used as a key.
local function doorFromPart(state: Types.PlayerRunState, part: unknown): (Door?, number?)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil, nil
	end
	local floorDoors = doorsByDepth[state.depth]
	if floorDoors == nil then
		return nil, nil
	end
	for index, door in floorDoors do
		if door.barrier == part and not door.broken and door.model.Parent ~= nil then
			return door, index
		end
	end
	return nil, nil
end

local function withinSocketRange(state: Types.PlayerRunState, door: Door): boolean
	return (state.position - door.socket.WorldPosition).Magnitude <= Config.Dynamite.door.socketRange
end

-- `aim` is a DIRECTION, not a point: the client sends its camera's look vector and the server throws
-- along it. Only the direction survives `DynamiteRules.throwVelocity`'s normalisation, so a client
-- cannot buy distance by sending a longer vector — the arc's reach comes from config alone.
local function handleThrow(player: Player, state: Types.PlayerRunState, aim: unknown, now: number)
	if not RequestGuard.finiteVector3(aim) then
		ActionFeedbackService.send(player, state, ACTION_ID, false, now, "InvalidTarget")
		return
	end
	local origin = CharacterService.basePosition(player.UserId) or state.position
	local result = resolveThrow(origin, aim :: Vector3, state.depth)
	if result == nil then
		ActionFeedbackService.send(player, state, ACTION_ID, false, now, "InvalidTarget")
		return
	end
	-- The stick leaves the bag only once the world has accepted a landing, so a refused throw never
	-- costs the player their rarest consumable.
	local remaining = DynamiteRules.spend(state.dynamiteCharges)
	if remaining == nil then
		ActionFeedbackService.send(player, state, ACTION_ID, false, now, "Empty")
		return
	end
	state.dynamiteCharges = remaining

	-- THE THROW LANDED IN A CHARGE POCKET. Same outcome as walking up and confirming the prompt: the
	-- stick seats in the socket, arms itself, and the door stops offering the marker to anybody. The
	-- longer socketed fuse applies rather than the thrown one — it is a door charge however it got
	-- there, and the thrower is already at range, so the extra second only ever helps.
	local door = result.door
	if door ~= nil and result.doorIndex ~= nil and door.charge == nil then
		local charge =
			spawnCharge(state, "Socketed", door.socket.WorldPosition, true, result.doorIndex, origin, result.velocity)
		door.charge = charge
		door.model:SetAttribute(DynamiteVisualProtocol.attributes.charged, true)
		ActionFeedbackService.send(player, state, ACTION_ID, true, now, nil)
		Telemetry.event("dynamite_socketed", player.UserId, { depth = state.depth, thrown = true })
		return
	end

	spawnCharge(state, "Thrown", result.position, true, nil, origin, result.velocity)
	ActionFeedbackService.send(player, state, ACTION_ID, true, now, nil)
	Telemetry.event("dynamite_thrown", player.UserId, { depth = state.depth })
end

local function handlePlace(player: Player, state: Types.PlayerRunState, target: unknown, now: number)
	local door, index = doorFromPart(state, target)
	if door == nil or index == nil then
		ActionFeedbackService.send(player, state, ACTION_ID, false, now, "InvalidTarget")
		return
	end
	if door.charge ~= nil then
		ActionFeedbackService.send(player, state, ACTION_ID, false, now, "AlreadyPlaced")
		return
	end
	if not withinSocketRange(state, door) then
		ActionFeedbackService.send(player, state, ACTION_ID, false, now, "InvalidTarget")
		return
	end
	local remaining = DynamiteRules.spend(state.dynamiteCharges)
	if remaining == nil then
		ActionFeedbackService.send(player, state, ACTION_ID, false, now, "Empty")
		return
	end
	state.dynamiteCharges = remaining
	-- The confirmed hold is one atomic placement-and-light action. There is no inert seated state for
	-- another client to race or for the prompt to misrepresent.
	local charge = spawnCharge(state, "Socketed", door.socket.WorldPosition, true, index, nil)
	door.charge = charge
	door.model:SetAttribute(DynamiteVisualProtocol.attributes.charged, true)
	ActionFeedbackService.send(player, state, ACTION_ID, true, now, nil)
	Telemetry.event("dynamite_placed", player.UserId, { depth = state.depth })
end

function DynamiteService.init()
	Remotes.get("DynamiteAction").OnServerEvent:Connect(function(player: Player, action: unknown, target: unknown)
		if not RequestGuard.allow(player, "DynamiteAction") or typeof(action) ~= "string" then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil then
			return
		end
		local now = os.clock()

		-- Both accepted actions spend and immediately light one stick.
		local ok, denial = DynamiteRules.validate(state)
		if not ok then
			ActionFeedbackService.send(player, state, ACTION_ID, false, now, denial)
			return
		end
		if action == "throw" then
			handleThrow(player, state, target, now)
		elseif action == "place" then
			handlePlace(player, state, target, now)
		end
	end)
end

-- Register one floor's blast doors. Called by RunOrchestrator with what FloorBuilder produced.
function DynamiteService.registerFloor(depth: number, inputs: { FloorBuilder.BlastDoorRuntime })
	local floorDoors: { Door } = {}
	for _, input in inputs do
		table.insert(floorDoors, {
			model = input.model,
			barrier = input.barrier,
			pieces = input.pieces,
			socket = input.socket,
			depth = input.depth,
			position = input.position,
			roomIndex = input.roomIndex,
			style = input.style,
			openingWidth = input.openingWidth,
			openingHeight = input.openingHeight,
			broken = false,
			charge = nil,
		})
	end
	doorsByDepth[depth] = floorDoors
end

function DynamiteService.tick()
	local now = os.clock()
	for index = #charges, 1, -1 do
		local charge = charges[index]
		if charge.built.model.Parent == nil then
			table.remove(charges, index)
			continue
		end
		local litAt = charge.litAt
		if litAt == nil then
			continue
		end
		local progress = DynamiteRules.fuseProgress(now - litAt, DynamiteRules.fuseSecondsFor(charge.kind))
		DynamiteModel.setFuseProgress(charge.built, progress)
		if progress >= 1 then
			local door = doorFor(charge)
			if door ~= nil then
				door.charge = nil
			end
			detonate(charge)
		end
	end
end

function DynamiteService.clearDepth(depth: number)
	for index = #charges, 1, -1 do
		if charges[index].depth == depth then
			charges[index].built.model:Destroy()
			table.remove(charges, index)
		end
	end
	doorsByDepth[depth] = nil
end

function DynamiteService.reset()
	for _, charge in charges do
		charge.built.model:Destroy()
	end
	table.clear(charges)
	table.clear(doorsByDepth)
	if chargeFolder ~= nil then
		chargeFolder:Destroy()
		chargeFolder = nil
	end
end

-- Test and diagnostic read only. Nothing in gameplay may branch on a vault being open, or the vault
-- would have become required progression.
function DynamiteService.doorsRemaining(depth: number): number
	local floorDoors = doorsByDepth[depth]
	if floorDoors == nil then
		return 0
	end
	local remaining = 0
	for _, door in floorDoors do
		if not door.broken then
			remaining += 1
		end
	end
	return remaining
end

return DynamiteService
