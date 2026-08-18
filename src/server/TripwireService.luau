--!strict
-- Server authority for the Knotwalker's doorway tripwires: laying them, catching people with them,
-- burning them off, and owning the seconds a caught player spends on the floor.
--
-- WHY THE WIRE IS A SERVICE AND NOT PART OF THE CREATURE. A laid trap outlives the moment it was
-- laid, and it has to keep working while its owner is in another room, while it is being burnt by a
-- player the owner cannot see, and after the owner is dead. A creature that owned its own traps would
-- have to be stepped for all of that, which is exactly the coupling `server/DripstoneService` and
-- `server/VineService` exist to avoid for hazards nobody is standing next to. The Knotwalker asks this
-- service to lay one and asks it who has just been caught; it owns nothing about the wire itself.
--
-- THE TRIP TEST IS A SWEPT SEGMENT, NOT A PROXIMITY CHECK, and that is the whole reason this creature
-- catches anybody. See `Logic/TripwireRules.trips`: a player at run speed moves further between two
-- server ticks than any sane trigger radius, so the wire is tested against the LINE the player
-- travelled. This service's only job in that is to remember where each player's feet were last tick.
--
-- THE WIRE IS INVISIBLE TO QUERIES (`CanQuery = false`), like a vine curtain and for the same reason:
-- every threat's obstacle raycast, every dynamite arc and every ground probe in the game would
-- otherwise find a strand of grass across a doorway and treat it as the world. The wire's only
-- interaction with anything is the maths below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local TripwireRules = require(ReplicatedStorage.Shared.Logic.TripwireRules)
local RoomNavigation = require(ReplicatedStorage.Shared.Logic.RoomNavigation)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local MovementService = require(script.Parent.MovementService)
local WaxService = require(script.Parent.WaxService)
local NoiseService = require(script.Parent.NoiseService)
local SurfaceProbe = require(script.Parent.SurfaceProbe)
local Telemetry = require(script.Parent.Telemetry)

local TripwireService = {}

type Wire = {
	depth: number,
	model: Model,
	strands: { BasePart },
	-- The two ends of the strand, at wire height. The trip test is against exactly this segment.
	anchorA: Vector3,
	anchorB: Vector3,
	center: Vector3,
	-- Qualifying light held at this wire so far, in seconds. Never decays, exactly like a vine
	-- curtain's: a player can back off to refill their dial and come back to where they left off.
	exposure: number,
	-- Set when the strand has been burnt or sprung. It stops catching anyone immediately; the model
	-- lingers until `removeAt` so the player sees what happened to it.
	spent: boolean,
	removeAt: number?,
	expiresAt: number,
}

-- ONE MOMENT OF SOMEBODY BEING CAUGHT, kept only until the creature that laid the wire reads it.
-- ThreatService polls this rather than being called back, because a callback would run the
-- Knotwalker's state changes inside this service's player loop.
export type Catch = {
	depth: number,
	playerId: Types.PlayerId,
	position: Vector3,
	at: number,
}

local wiresByDepth: { [number]: { Wire } } = {}
-- Where each player's feet were on the previous tick, so a step is a segment rather than a point.
local previousFoot: { [Types.PlayerId]: Vector3 } = {}
-- Wires cannot catch this player again until this time — set when they get up (Config/Tripwire.trip
-- .getUpGraceSeconds). Without it, standing up inside the doorway you were tripped in can re-trip you
-- on a second wire before you have taken a step.
local immuneUntil: { [Types.PlayerId]: number } = {}
-- Set while a player is down so `tick` can tell the frame they get up from every frame after it, and
-- hand their movement back exactly once.
local prone: { [Types.PlayerId]: boolean } = {}
local latestCatch: Catch? = nil

local function config()
	return Config.Tripwire
end

--------------------------------------------------------------------------------
-- Building one wire
--------------------------------------------------------------------------------

local function strandPart(model: Model, from: Vector3, to: Vector3, thickness: number): BasePart?
	local delta = to - from
	local length = delta.Magnitude
	if length < 1e-3 then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = "Strand"
	part.Size = Vector3.new(thickness, thickness, length)
	part.CFrame = CFrame.lookAt(from + delta * 0.5, to)
	part.Anchored = true
	part.CanCollide = false
	-- See the file header: nothing in the game may raycast this into existence as terrain.
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = config().geometry.strandColor
	part.Material = config().geometry.strandMaterial
	part.Parent = model
	return part
end

-- Draw the strand between two anchors as a sagging line of segments, with a few knots hung off it.
-- Sag comes from `TripwireRules.sagAt` rather than from a curve invented here, so the drawn shape and
-- the rule stay one thing.
local function buildWire(anchorA: Vector3, anchorB: Vector3, seed: number): (Model, { BasePart })
	local geometry = config().geometry
	local model = Instance.new("Model")
	model.Name = "WickTripwire"

	local span = (anchorB - anchorA).Magnitude
	local rng = Random.new(seed)
	local segments = math.max(2, math.floor(geometry.segmentCount))
	local strands: { BasePart } = {}

	local function pointAt(t: number): Vector3
		local straight = anchorA:Lerp(anchorB, t)
		return straight - Vector3.yAxis * TripwireRules.sagAt(t, span)
	end

	local previous = pointAt(0)
	for index = 1, segments do
		local point = pointAt(index / segments)
		local part = strandPart(model, previous, point, geometry.strandThickness)
		if part ~= nil then
			table.insert(strands, part)
		end
		previous = point
	end

	-- KNOTS. The creature is named for them, and they are what stops the wire reading as a wire: a few
	-- small lumps at random points along the strand, which is also the only thing making it visible at
	-- the edge of a candle's reach.
	for index = 1, math.max(0, math.floor(geometry.knotCount)) do
		local t = (index - 0.5) / math.max(geometry.knotCount, 1) + rng:NextNumber(-0.06, 0.06)
		local knot = Instance.new("Part")
		knot.Name = "Knot"
		local size = geometry.knotSize * rng:NextNumber(0.7, 1.3)
		knot.Size = Vector3.new(size, size * 0.8, size)
		knot.CFrame = CFrame.new(pointAt(math.clamp(t, 0, 1)))
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		knot.Anchored = true
		knot.CanCollide = false
		knot.CanQuery = false
		knot.CanTouch = false
		knot.CastShadow = false
		knot.Color = geometry.strandColor
		knot.Material = geometry.strandMaterial
		knot.Parent = model
		table.insert(strands, knot)
	end

	model.PrimaryPart = strands[1]
	return model, strands
end

--------------------------------------------------------------------------------
-- Laying and clearing
--------------------------------------------------------------------------------

-- Is there already a wire across this opening? Asked by the creature before it walks somewhere to lay
-- one, and again by `lay` itself — the walk takes seconds, and another Knotwalker (or the same one
-- re-deciding) can have strung it in the meantime.
function TripwireService.hasWireNear(depth: number, position: Vector3, radius: number): boolean
	local wires = wiresByDepth[depth]
	if wires == nil then
		return false
	end
	for _, wire in wires do
		if wire.spent then
			continue
		end
		local delta = wire.center - position
		if Vector3.new(delta.X, 0, delta.Z).Magnitude <= radius then
			return true
		end
	end
	return false
end

function TripwireService.armedCount(depth: number): number
	local wires = wiresByDepth[depth]
	if wires == nil then
		return 0
	end
	local count = 0
	for _, wire in wires do
		if not wire.spent then
			count += 1
		end
	end
	return count
end

-- String one across a doorway. Returns false when the opening cannot be verified against built
-- Terrain — the same refusal every other placement in the game makes rather than seating geometry on
-- an analytic height it could not measure.
function TripwireService.lay(depth: number, opening: RoomNavigation.DoorwayOpening, seed: number): boolean
	if not config().enabled then
		return false
	end
	local geometry = config().geometry
	local half = opening.width * math.clamp(geometry.spanFraction, 0, 1) * 0.5
	local center = opening.center
	local endA = center - opening.lateralAxis * half
	local endB = center + opening.lateralAxis * half

	-- BOTH ENDS ARE MEASURED SEPARATELY. A doorway sits on the seam between two rooms' ground fields
	-- and the floor across an opening is rarely level, so one sample taken at the middle would hang
	-- one end of the wire in the air and bury the other.
	local groundA = SurfaceProbe.tryGroundY(center.Y, endA.X, endA.Z, 0)
	local groundB = SurfaceProbe.tryGroundY(center.Y, endB.X, endB.Z, 0)
	if groundA == nil or groundB == nil then
		return false
	end

	local anchorA = Vector3.new(endA.X, groundA + geometry.heightStuds, endA.Z)
	local anchorB = Vector3.new(endB.X, groundB + geometry.heightStuds, endB.Z)
	local model, strands = buildWire(anchorA, anchorB, seed)
	model.Parent = Workspace

	local wires = wiresByDepth[depth]
	if wires == nil then
		wires = {}
		wiresByDepth[depth] = wires
	end
	table.insert(wires, {
		depth = depth,
		model = model,
		strands = strands,
		anchorA = anchorA,
		anchorB = anchorB,
		center = (anchorA + anchorB) * 0.5,
		exposure = 0,
		spent = false,
		removeAt = nil,
		expiresAt = os.clock() + config().armedSeconds,
	})
	Telemetry.event("tripwire_laid", nil, { depth = depth })
	return true
end

-- Take a wire out of service. `charSeconds` of shrivelled strand first when it burned, because a
-- barrier that vanishes on the frame it is beaten never taught anyone that they beat it.
local function spend(wire: Wire, now: number, burned: boolean)
	if wire.spent then
		return
	end
	wire.spent = true
	if burned then
		wire.removeAt = now + config().burn.charSeconds
		for _, part in wire.strands do
			part.Color = Color3.fromRGB(28, 24, 20)
			part.Material = Enum.Material.Slate
		end
	else
		-- SPRUNG. The strand goes slack and drops to the floor, which is the read a player standing up
		-- gets for "that one is used".
		wire.removeAt = now + 0.75
		for _, part in wire.strands do
			part.CFrame = part.CFrame - Vector3.yAxis * config().geometry.heightStuds
		end
	end
end

--------------------------------------------------------------------------------
-- The catch
--------------------------------------------------------------------------------

local function isRunner(state: Types.PlayerRunState, depth: number): boolean
	return state.alive and not state.finished and state.snuffedAt == nil and state.depth == depth
end

local function trip(wire: Wire, playerId: Types.PlayerId, state: Types.PlayerRunState, speed: number, now: number)
	local trip_ = config().trip
	local seconds = TripwireRules.stunSeconds(speed)
	state.trippedUntil = now + seconds
	prone[playerId] = true
	MovementService.refresh(playerId)

	if trip_.waxDamage > 0 then
		WaxService.drainExternal(
			playerId,
			trip_.waxDamage,
			"DamageThreat" :: Types.WaxSource,
			"You went down in the dark and did not get up.",
			{ kind = "Hit", seconds = seconds },
			"Knotwalker"
		)
	end
	if trip_.consumedOnTrip then
		spend(wire, now, false)
	end

	-- THE NOISE IS THE POINT. A body hitting the floor is the loudest thing that player has done, and
	-- it is what brings the owner — and anything else with ears — to where they are lying. Routed
	-- through the ordinary sound field rather than told directly to the Knotwalker, so every eared
	-- creature on the floor gets the same honest event.
	NoiseService.emit("Landing", state.position, nil)

	latestCatch = { depth = wire.depth, playerId = playerId, position = state.position, at = now }

	-- Everyone sees the body go down; only the victim's own client plays the fall.
	Remotes.get("RunEvent"):FireAllClients("tripwireTrip", {
		playerId = playerId,
		position = state.position,
		depth = wire.depth,
		seconds = seconds,
	})
	Telemetry.event("tripwire_trip", playerId, { depth = wire.depth, speed = speed, seconds = seconds })
end

-- Every armed wire on this floor tested against one player's step.
local function testPlayer(playerId: Types.PlayerId, state: Types.PlayerRunState, now: number)
	local foot = CharacterService.basePosition(playerId)
	local last = previousFoot[playerId]
	previousFoot[playerId] = foot
	if last == nil or state.trippedUntil > now or now < (immuneUntil[playerId] or 0) then
		return
	end
	local wires = wiresByDepth[state.depth]
	if wires == nil then
		return
	end
	local speed = CharacterService.horizontalSpeed(playerId)
	local airborne = CharacterService.isAirborne(playerId)
	for _, wire in wires do
		if wire.spent then
			continue
		end
		if
			TripwireRules.trips({
				previousFoot = last,
				currentFoot = foot,
				anchorA = wire.anchorA,
				anchorB = wire.anchorB,
				speed = speed,
				airborne = airborne,
			})
		then
			trip(wire, playerId, state, speed, now)
			return
		end
	end
end

-- Light held at a wire, and the wire catching. The brightness bar is Logic/VineRules' own — see
-- TripwireRules.burns for why this must not be a second opinion about what "maximum brightness" is.
local function accumulateBurn(wire: Wire, now: number, dt: number)
	local held = false
	for _, state in PlayerState.all() do
		if not isRunner(state, wire.depth) then
			continue
		end
		if not TripwireRules.withinBurnRange(state.position, wire.center) then
			continue
		end
		if
			TripwireRules.burns(
				state.isLit,
				state.isCupping,
				state.burnRate,
				state.flareEndsAt > now,
				state.modifiers.maxBurnRate
			)
		then
			held = true
			break
		end
	end
	if not held then
		return
	end
	wire.exposure += dt
	if wire.exposure < config().burn.seconds then
		return
	end
	spend(wire, now, true)
	Telemetry.event("tripwire_burned", nil, { depth = wire.depth })
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function TripwireService.tick(dt: number)
	if not config().enabled then
		return
	end
	local now = os.clock()

	-- GETTING UP, first: a player whose stun lapsed this frame should be walking again before anything
	-- else this tick reads their speed.
	for playerId in prone do
		local state = PlayerState.get(playerId)
		if state == nil or state.trippedUntil <= now then
			prone[playerId] = nil
			immuneUntil[playerId] = now + config().trip.getUpGraceSeconds
			if state ~= nil then
				state.trippedUntil = 0
			end
			MovementService.refresh(playerId)
		end
	end

	for _, wires in wiresByDepth do
		for index = #wires, 1, -1 do
			local wire = wires[index]
			local removeAt = wire.removeAt
			if removeAt ~= nil and now >= removeAt then
				wire.model:Destroy()
				table.remove(wires, index)
				continue
			end
			if wire.spent then
				continue
			end
			if now >= wire.expiresAt then
				spend(wire, now, false)
				continue
			end
			accumulateBurn(wire, now, dt)
		end
	end

	for playerId, state in PlayerState.all() do
		if not state.alive or state.finished or state.snuffedAt ~= nil then
			previousFoot[playerId] = nil
			continue
		end
		if not CharacterService.hasIntactBody(playerId) then
			previousFoot[playerId] = nil
			continue
		end
		testPlayer(playerId, state, now)
	end
end

-- The most recent catch, or nil. CONSUMED BY READING: the Knotwalker that reacts to it takes it, so
-- one fall cannot recruit the same creature twice or be answered by a body on another floor a second
-- later. `depth` filters to the caller's own floor and leaves anybody else's catch in place.
function TripwireService.takeCatch(depth: number): Catch?
	local catch = latestCatch
	if catch == nil or catch.depth ~= depth then
		return nil
	end
	latestCatch = nil
	return catch
end

-- Is this player still on the floor, and how long do they have left? Read by the Knotwalker each tick
-- while it is standing over somebody.
function TripwireService.isProne(playerId: Types.PlayerId): boolean
	local state = PlayerState.get(playerId)
	return state ~= nil and state.trippedUntil > os.clock()
end

function TripwireService.clearDepth(depth: number)
	local wires = wiresByDepth[depth]
	if wires == nil then
		return
	end
	for _, wire in wires do
		wire.model:Destroy()
	end
	wiresByDepth[depth] = nil
	if latestCatch ~= nil and latestCatch.depth == depth then
		latestCatch = nil
	end
end

function TripwireService.reset()
	for depth in wiresByDepth do
		TripwireService.clearDepth(depth)
	end
	table.clear(wiresByDepth)
	table.clear(previousFoot)
	table.clear(immuneUntil)
	-- A player caught as the run ends must not stay pinned in the next one. Clearing the flag is not
	-- enough on its own: `MovementService.refresh` is what puts the speed back.
	for playerId in prone do
		local state = PlayerState.get(playerId)
		if state ~= nil then
			state.trippedUntil = 0
		end
		MovementService.refresh(playerId)
	end
	table.clear(prone)
	latestCatch = nil
end

return TripwireService
