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
local ToolRules = require(ReplicatedStorage.Shared.Logic.ToolRules)
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
local function obstructionParams(): RaycastParams?
	local floors = Workspace:FindFirstChild("WickFloors")
	if floors == nil then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain, floors }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

local function groundParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

-- Where a thrown stick comes to rest, or nil if there is nowhere legal.
--
-- UNLIKE A DECOY, A FAILED GROUND PROBE IS NOT FATAL. A decoy has to sit upright and burn on real
-- floor, so a probe that finds nothing means "refuse". A stick only has to be somewhere, and refusing
-- the throw would eat the player's rarest consumable over a raycast that clipped a voxel — so a
-- missing floor falls back to the arc's own end point. It will still detonate; it may simply detonate
-- a stud off the rock.
local function resolveLanding(origin: Vector3, aim: Vector3): Vector3?
	local placement = Config.Dynamite.throw.placement
	local obstruction = obstructionParams()
	if obstruction == nil then
		return nil
	end

	local horizontal = ToolRules.throwHorizontalPoint(
		origin,
		aim,
		Config.Dynamite.throw.range,
		nil,
		placement.obstructionInset,
		placement.minimumDistance
	)
	if horizontal == nil then
		return nil
	end

	-- The same segmented arc the Decoy traces: rolling ground does not stop a throw, but a wall, a
	-- boulder or the cave roof shortens it before the obstruction.
	local arcStart = origin + Vector3.yAxis * placement.throwStartHeight
	local arcEnd = horizontal + Vector3.yAxis * placement.throwStartHeight
	local previous = arcStart
	local segments = math.max(1, math.floor(placement.throwProbeSegments))
	for step = 1, segments do
		local point = ToolRules.throwArcPoint(arcStart, arcEnd, placement.throwArcHeight, step / segments)
		local hit = Workspace:Raycast(previous, point - previous, obstruction)
		if hit ~= nil then
			local distance = Vector3.new(hit.Position.X - origin.X, 0, hit.Position.Z - origin.Z).Magnitude
			local shortened = ToolRules.throwHorizontalPoint(
				origin,
				aim,
				Config.Dynamite.throw.range,
				distance,
				placement.obstructionInset,
				placement.minimumDistance
			)
			-- A throw blocked at point blank still has to go somewhere: it drops at the thrower's feet,
			-- which is exactly what throwing a stick into a wall one stud away should do to you.
			horizontal = shortened or Vector3.new(origin.X, horizontal.Y, origin.Z)
			break
		end
		previous = point
	end

	-- SEATED THROUGH `SurfaceProbe`, not through a bare downward ray.
	--
	-- The single-raycast version this replaces put thrown sticks in the floor, and the reason is the
	-- reason `SurfaceProbe` exists at all: Terrain is written on a 4-stud voxel grid, so one centre hit
	-- can easily be a couple of studs below the rock a player is standing on a foot away. `tryGroundY`
	-- takes the HIGHEST of nine samples across the stick's own footprint, which is exactly what every
	-- loot pickup and every deposit already does.
	local sampled =
		SurfaceProbe.tryGroundY(horizontal.Y, horizontal.X, horizontal.Z, Config.Dynamite.throw.restSampleRadius)
	if sampled ~= nil then
		return Vector3.new(horizontal.X, sampled + Config.Dynamite.throw.restHeight, horizontal.Z)
	end

	-- The probe found no upward-facing Terrain in its window. Fall back to the old wide ray rather than
	-- refusing the throw: a stick a stud out of place still explodes, and eating a player's rarest
	-- consumable over a raycast that clipped a voxel would be far worse than a badly seated stick.
	local probeOrigin = horizontal + Vector3.new(0, placement.groundProbeHeight, 0)
	local ground = Workspace:Raycast(
		probeOrigin,
		Vector3.new(0, -(placement.groundProbeHeight + placement.groundProbeDepth), 0),
		groundParams()
	)
	if ground == nil then
		return horizontal + Vector3.yAxis * Config.Dynamite.throw.restHeight
	end
	return ground.Position + Vector3.yAxis * Config.Dynamite.throw.restHeight
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

local function animateThrownCharge(built: DynamiteModel.BuiltStick, origin: Vector3, landing: Vector3)
	local duration = math.max(Config.Dynamite.throw.animationSeconds, 0)
	if duration <= 0 then
		built.model:PivotTo(CFrame.new(landing))
		return
	end
	local startPoint = origin + Vector3.yAxis * Config.Dynamite.throw.placement.throwStartHeight
	local startedAt = os.clock()
	task.spawn(function()
		while built.model.Parent ~= nil do
			local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
			local point = ToolRules.throwArcPoint(
				startPoint,
				landing,
				Config.Dynamite.throw.placement.throwArcHeight * 0.55,
				alpha
			)
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
	throwOrigin: Vector3?
): Charge
	local built = DynamiteModel.buildArmed()
	built.model:PivotTo(CFrame.new(throwOrigin or position))
	built.model.Parent = ensureChargeFolder()
	DynamiteModel.setLit(built, lit)
	if throwOrigin ~= nil then
		animateThrownCharge(built, throwOrigin, position)
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

local function handleThrow(player: Player, state: Types.PlayerRunState, aim: unknown, now: number)
	if not RequestGuard.finiteVector3(aim) then
		ActionFeedbackService.send(player, state, ACTION_ID, false, now, "InvalidTarget")
		return
	end
	local origin = CharacterService.basePosition(player.UserId) or state.position
	local landing = resolveLanding(origin, aim :: Vector3)
	if landing == nil then
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
	spawnCharge(state, "Thrown", landing, true, nil, origin)
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
