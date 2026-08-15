--!strict
-- Renders session-local remains records into newly built floors, exposes their light to threat
-- perception, and performs atomic server-authoritative recovery through Interfaces/Remains.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local CargoRules = require(ReplicatedStorage.Shared.Logic.CargoRules)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local SurfaceRules = require(ReplicatedStorage.Shared.Logic.SurfaceRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local ExtractionService = require(script.Parent.ExtractionService)
local SurfaceProbe = require(script.Parent.SurfaceProbe)

local RemainsService = {}

type ActiveRemains = {
	id: number,
	ownerId: Types.PlayerId,
	depth: number,
	position: Vector3,
	intensity: number,
	range: number,
	part: BasePart,
}

local active: { [number]: ActiveRemains } = {}

local function destroyActive(id: number)
	local remains = active[id]
	if remains ~= nil then
		remains.part:Destroy()
		active[id] = nil
	end
end

local function eligibleRoomIndices(plan: Types.FloorPlan): { number }
	local flooded: { [number]: boolean } = {}
	for _, hazard in plan.hazards do
		if hazard.hazardId == "Water" then
			flooded[hazard.roomIndex] = true
		end
	end

	local indices: { number } = {}
	for index in plan.rooms do
		if index ~= plan.entryRoomIndex and index ~= plan.basinRoomIndex and not flooded[index] then
			table.insert(indices, index)
		end
	end
	if #indices == 0 then
		table.insert(indices, plan.entryRoomIndex)
	end
	return indices
end

-- Old and new plans share a floor plane but not necessarily topology. Choose the nearest safe room
-- in the new layout, then clamp the old local offset away from walls.
-- Returns the remapped position AND the room it was mapped into, because the caller needs that room's
-- ground field to seat the pile on the floor's actual relief.
local function remapPosition(oldPosition: Vector3, roomCenters: { Vector3 }, roomIndices: { number }): (Vector3, number)
	local nearestIndex = roomIndices[1]
	local nearestCenter = roomCenters[nearestIndex]
	local nearestDistance = math.huge
	for _, roomIndex in roomIndices do
		local center = roomCenters[roomIndex]
		local delta = Vector3.new(oldPosition.X - center.X, 0, oldPosition.Z - center.Z)
		if delta.Magnitude < nearestDistance then
			nearestDistance = delta.Magnitude
			nearestCenter = center
			nearestIndex = roomIndex
		end
	end

	local halfExtent = Config.Floors.geometry.cellSize * Config.Remains.placementInset / 2
	local localX = math.clamp(oldPosition.X - nearestCenter.X, -halfExtent, halfExtent)
	local localZ = math.clamp(oldPosition.Z - nearestCenter.Z, -halfExtent, halfExtent)
	return nearestCenter + Vector3.new(localX, Config.Remains.visualThickness / 2, localZ), nearestIndex
end

-- Rest remains on the real cave floor at their remapped spot, rather than the flat room level, so they
-- never float above or sink into the undulating ground.
--
-- `surface` is the room this pile landed in, when the caller knows it. It matters entirely for the
-- MISS case: the probe's own fallback used to be `position.Y`, which `remapPosition` derives from the
-- room CENTRE — the room's nominal level, with none of its ground relief. The cave floor swells toward
-- the walls, domes over planned mounds and dips into pools, so on any real floor that fallback was a
-- pile hanging in the air by however much relief was under it. The analytic field is the same one the
-- Terrain was carved from and is right to within a voxel everywhere.
local function groundedPosition(position: Vector3, surface: SurfaceProbe.RoomGroundSurface?): Vector3
	local half = Config.Remains.visualThickness / 2
	-- Where the floor is SUPPOSED to be, before asking where it actually got built.
	local plannedY = position.Y - half
	if surface ~= nil then
		plannedY = surface.center.Y
			+ GroundGeometry.offset(surface.groundField, position.X - surface.center.X, position.Z - surface.center.Z)
	end

	local params = RaycastParams.new()
	-- Terrain only, for the reason `server/SurfaceProbe` gives: the cave's dressing is collision-neutral
	-- scenery and none of it is ground. Resting a recoverable pile on a rock formation puts its prompt
	-- somewhere a player cannot reach it.
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local hit = workspace:Raycast(
		Vector3.new(position.X, plannedY + Config.Remains.groundProbeHeightAbove, position.Z),
		Vector3.new(0, -Config.Remains.groundProbeDepth, 0),
		params
	)
	-- Same surface test as every other ground probe: a downward-facing hit is a roof dip, not a floor.
	local grounded = hit ~= nil
		and SurfaceRules.isUpwardFacing(hit.Normal, Config.Floors.geometry.placementProbe.maxUpwardSlopeDegrees)
	local surfaceY = if grounded and hit ~= nil then hit.Position.Y else plannedY
	return Vector3.new(position.X, surfaceY + half, position.Z)
end

-- One prompt, two payloads. A pile left by a death holds wax AND the half of its owner's haul that
-- survived the fall; a pile left by a disconnect holds only cargo, locked to the owner until their
-- grace window lapses. Both are recovered here, in one hold of one prompt.
--
-- THE ORDER MATTERS: cargo is claimed before wax. A player at full wax should still be able to pick
-- up a haul, and returning early on the wax check would have silently made a full candle a reason to
-- leave money on the ground.
local function collect(player: Player, remains: ActiveRemains)
	if remains.part.Parent == nil then
		return
	end
	local state = PlayerState.get(player.UserId)
	if
		state == nil
		or not state.alive
		or state.finished
		or state.snuffedAt ~= nil
		or state.depth ~= remains.depth
		or (state.position - remains.position).Magnitude > Config.Remains.pickupRange
	then
		return
	end

	local now = os.clock()
	local recoveredGrams = 0

	-- CARGO. `claimCargo` enforces the owner lock and removes the grams from the record before
	-- returning them, so two prompts triggering on the same frame cannot both be paid — the second
	-- finds an empty record. Nothing here can duplicate cargo, because nothing here copies it.
	if Interfaces.Remains.cargoAvailableTo(remains.id, player.UserId, now) then
		local room = ExtractionService.carryRoom(player.UserId)
		if room <= 0 then
			Remotes.get("RunEvent"):FireClient(player, "message", { text = "You cannot carry any more Raw Wax." })
		else
			local claimed = Interfaces.Remains.claimCargo(remains.id, player.UserId, now, room)
			if claimed.total > 0 then
				local moved, leftover = ExtractionService.receive(player.UserId, claimed)
				recoveredGrams = moved
				-- Anything the bag would not take goes straight back onto the pile rather than being
				-- destroyed. `receive` only fails to move grams at the carry cap, so this is rare, but
				-- silently deleting them would be a leak in the one direction that costs a player.
				if leftover.total > 0 then
					local leftoverRecord = Interfaces.Remains.deposit({
						playerId = remains.ownerId,
						depth = remains.depth,
						position = remains.position,
						wax = 0,
						cargo = leftover,
						ownerLockUntil = 0,
					})
					-- Without this, the surplus would sit in Interfaces.Remains as a record with no
					-- rendered Instance — invisible and unreachable for the rest of the run, then
					-- silently stripped at teardown. That is a genuine loss of value nobody could see
					-- happen, indistinguishable from a bug rather than the "left for someone else" it
					-- is meant to be.
					RemainsService.spawnLive(leftoverRecord)
				end
			end
		end
	end

	-- WAX. Unchanged rules: you cannot relight from your own remains, and a full candle takes none.
	local recoveredWax = 0
	local remainingWax = 0
	local mayTakeWax = player.UserId ~= remains.ownerId or Config.Remains.ownerMayCollect
	if mayTakeWax and state.wax.current < state.wax.max then
		local capacity = state.wax.max - state.wax.current
		local record, waxLeft = Interfaces.Remains.claim(remains.id, capacity)
		if record ~= nil then
			recoveredWax = record.wax
			remainingWax = waxLeft
			state.wax = WaxAccounting.grant(state.wax, state.waxLedger, recoveredWax, "FoundWaxGain")
		end
	end

	if recoveredGrams > 0 and recoveredWax > 0 then
		Remotes.get("RunEvent"):FireClient(player, "message", {
			text = ("Recovered %s Raw Wax and %.0f%% wax."):format(
				CargoRules.formatGrams(recoveredGrams),
				recoveredWax / Config.Wax.maxWax * 100
			),
		})
	elseif recoveredGrams > 0 then
		Remotes.get("RunEvent"):FireClient(player, "message", {
			text = ("Recovered %s Raw Wax."):format(CargoRules.formatGrams(recoveredGrams)),
		})
	elseif recoveredWax > 0 then
		Remotes.get("RunEvent"):FireClient(player, "message", {
			text = if remainingWax > 0
				then ("Recovered %.0f%% wax; some remains."):format(recoveredWax / Config.Wax.maxWax * 100)
				else ("Recovered %.0f%% wax from another candle."):format(recoveredWax / Config.Wax.maxWax * 100),
		})
	elseif
		player.UserId ~= remains.ownerId and not Interfaces.Remains.cargoAvailableTo(remains.id, player.UserId, now)
	then
		-- The one case worth explaining rather than silently refusing: someone else's bag, still
		-- inside their reconnect window.
		Remotes.get("RunEvent"):FireClient(player, "message", {
			text = "This haul is still held for whoever dropped it.",
		})
	end

	-- The record removes itself once both payloads are gone; mirror that on the visual.
	if not Interfaces.Remains.cargoAvailableTo(remains.id, remains.ownerId, now) and remainingWax <= 0 then
		local stillThere = false
		for _, record in Interfaces.Remains.listForFloor(remains.depth) do
			if record.id == remains.id then
				stillThere = true
				break
			end
		end
		if not stillThere then
			destroyActive(remains.id)
		end
	end
end

-- Build the visible pool for one record at an already-resolved position. Shared by the floor-build
-- path (which remaps old positions into the new layout) and the live-drop path (which does not need
-- to, because the body fell on the floor that is standing right now).
local function render(record: Interfaces.RemainsRecord, position: Vector3, parent: Instance)
	local part = Instance.new("Part")
	part.Name = "Remains_" .. record.id
	part.Shape = Enum.PartType.Cylinder
	part.Size =
		Vector3.new(Config.Remains.visualThickness, Config.Remains.visualDiameter, Config.Remains.visualDiameter)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = Config.Remains.color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.Parent = parent

	local light = Instance.new("PointLight")
	light.Color = Config.Remains.color
	light.Brightness = Config.Remains.lightIntensity
	light.Range = Config.Remains.lightRange
	light.Shadows = false
	light.Parent = part

	local prompt = Instance.new("ProximityPrompt")
	-- A pile holding a haul says so, because walking to a friend's body to get their Raw Wax is a
	-- different decision from walking to a stranger's candle to top up, and the prompt is the only
	-- place the game can tell them apart before they commit to the hold.
	local hasCargo = record.cargo.total > 0
	prompt.ActionText = "Recover"
	prompt.ObjectText = if hasCargo
		then string.format("Remains · %s Raw Wax", CargoRules.formatGrams(record.cargo.total))
		else "Candle Remains"
	prompt.HoldDuration = Config.Remains.pickupHoldSeconds
	prompt.MaxActivationDistance = Config.Remains.pickupRange
	prompt.RequiresLineOfSight = true
	prompt.Parent = part

	local runtime: ActiveRemains = {
		id = record.id,
		ownerId = record.playerId,
		depth = record.depth,
		position = position,
		intensity = Config.Remains.lightIntensity,
		range = Config.Remains.lightRange,
		part = part,
	}
	active[record.id] = runtime
	prompt.Triggered:Connect(function(player: Player)
		collect(player, runtime)
	end)
	return runtime
end

-- The floor models currently standing, so a body dropped DURING a run can be rendered onto the floor
-- it fell on. Without this, remains only ever appeared when a floor was newly built — which was fine
-- while they were a gift to a future expedition, and is not fine now that half of a dead player's
-- haul is lying in one and their party is expected to go and get it.
local floorParents: { [number]: Instance } = {}
-- The ground fields of the floor currently standing, kept for the same reason `floorParents` is: a
-- pile dropped mid-run has to be seated on the floor's real relief, and only these describe it.
local floorSurfaces: { [number]: { [number]: SurfaceProbe.RoomGroundSurface } } = {}

-- Which room's ground field describes a point, for a body that fell wherever it fell. Nearest centre
-- rather than a containment test: the fields blend continuously into one another, so the nearest room
-- is right in the middle and harmless at a boundary, and a pile that lands in a doorway still gets a
-- field instead of nothing.
local function nearestSurface(depth: number, position: Vector3): SurfaceProbe.RoomGroundSurface?
	local surfaces = floorSurfaces[depth]
	if surfaces == nil then
		return nil
	end
	local nearest: SurfaceProbe.RoomGroundSurface? = nil
	local nearestDistance = math.huge
	for _, surface in surfaces do
		local delta = Vector3.new(position.X - surface.center.X, 0, position.Z - surface.center.Z)
		if delta.Magnitude < nearestDistance then
			nearestDistance = delta.Magnitude
			nearest = surface
		end
	end
	return nearest
end

function RemainsService.spawnFloor(
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: SurfaceProbe.RoomGroundSurface },
	parent: Instance
)
	floorParents[plan.depth] = parent
	floorSurfaces[plan.depth] = roomSurfaces
	local roomIndices = eligibleRoomIndices(plan)
	for _, record in Interfaces.Remains.listForFloor(plan.depth) do
		if active[record.id] ~= nil then
			continue
		end
		local remapped, roomIndex = remapPosition(record.position, roomCenters, roomIndices)
		render(record, groundedPosition(remapped, roomSurfaces[roomIndex]), parent)
	end
end

-- Render a record that was just deposited into a live floor. Called the moment a player dies or drops
-- out, so the pile exists in the world while the people who could reach it are still standing there.
function RemainsService.spawnLive(record: Interfaces.RemainsRecord?)
	if record == nil or active[record.id] ~= nil then
		return
	end
	local parent = floorParents[record.depth]
	if parent == nil then
		return
	end
	render(record, groundedPosition(record.position, nearestSurface(record.depth, record.position)), parent)
end

function RemainsService.sources(): { Types.LightSource }
	local sources: { Types.LightSource } = {}
	for _, remains in active do
		table.insert(sources, {
			kind = "Remains" :: Types.LightSourceKind,
			position = remains.position,
			intensity = remains.intensity,
			range = remains.range,
			attractsDrawn = true,
			repelsDarkHunters = true,
			forcesDarkHunterRetreat = false,
			ownerId = nil,
		})
	end
	return sources
end

-- Retire only this floor's live render state. Interfaces.Remains is the session-persistent record
-- authority and intentionally survives so a later expedition can remap the pile into its rebuilt
-- floor; deleting that record here would destroy recoverable wax/cargo.
function RemainsService.clearDepth(depth: number)
	floorParents[depth] = nil
	floorSurfaces[depth] = nil
	for id, remains in active do
		if remains.depth == depth then
			remains.part:Destroy()
			active[id] = nil
		end
	end
end

-- Removes this run's Instances only. Interface storage intentionally survives for the next run (its
-- cargo does not — RunOrchestrator strips that separately).
function RemainsService.reset()
	for _, remains in active do
		remains.part:Destroy()
	end
	table.clear(active)
	table.clear(floorParents)
	table.clear(floorSurfaces)
end

return RemainsService
