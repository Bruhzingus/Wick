--!strict
-- Renders the Descent Ladder's ride locally (Config/DescentLadder, FLOOR-FIXTURES-OVERHAUL). The
-- server owns who rides, when the ride starts, how far the cage goes and where the rider ends up;
-- every client reconstructs the same analytic descent before Roblox's camera step so replication
-- cadence cannot make it judder.
--
-- THIS IS THE ELEVATOR'S PATTERN, DELIBERATELY. `client/ElevatorController` already solved exactly
-- this problem for the lobby car — one timestamped curve, locally evaluated, with the server writing
-- only the final transform — and the cave's ladder is the same problem one floor at a time. Sharing
-- the approach also means both rides share ONE camera-offset writer (`CameraController`), so a
-- player who somehow had both running could never get two competing `Humanoid.CameraOffset` writes.
--
-- IT DECIDES NOTHING. It never selects a rider, never times a ride, never moves anybody's depth, and
-- never touches the hatch — the hatch is a server-written pose precisely so that every player in the
-- room sees the mouth covered at the same instant.
--
-- WHY THE RIDERS ARE PIVOTED HERE. The server keeps each rider's unanchored physical body under
-- server ownership inside the closed cage at the upper fixture, so this client's downwards transform
-- remains cosmetic. Every client carries that live in-cage pose down with the cage; the server's
-- authoritative teleport to the next floor lands the moment the ride does.
--
-- THE CAGE TAKES TWO (`Config.DescentLadder.riderCapacity`), so every rider here is a list entry
-- rather than a slot. Both riders' clients run this identically off the same broadcast timestamps,
-- which is what keeps a shared descent looking like one machine moving rather than two.
--
-- BOTH LEGS ARE VISIBLE. The downward curve lands in the successor's aligned entry room. Once riders
-- are clear, a second timestamped curve carries only the empty cage back to its upper fixture.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DescentElevatorRules = require(ReplicatedStorage.Shared.Logic.DescentElevatorRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local CameraController = require(script.Parent.CameraController)

local DescentLadderController = {}

-- One rider's body and stable height over the deck. Horizontal position and facing are read live
-- rather than captured, so a body cannot drift out of the cage or be forced into a fixed pose.
type RiderVisual = {
	model: Model,
	-- The rider's height over the deck stays fixed, while X/Z and facing are refreshed from the
	-- server-owned physical body each frame. That keeps ordinary in-cage movement and free look from
	-- being overwritten by the analytic ride renderer.
	verticalOffset: number,
}

type Ride = {
	cage: Model,
	cageRestPivot: CFrame,
	riderIds: { number },
	riders: { [number]: RiderVisual },
	startedAt: number,
	duration: number,
	distance: number,
	direction: "Down" | "Up",
	isLocalRider: boolean,
	-- The winch, parented to the cage so it travels down the shaft with it.
	winch: BasePart?,
}

local player = Players.LocalPlayer
-- KEYED BY FLOOR, NOT A SINGLE SLOT. A party of four splits across floors constantly, and two people
-- riding two different ladders inside the same few seconds is ordinary play — with one slot the
-- second departure would silently cancel the first, leaving one player's own descent with no camera
-- shudder and a body that stopped following the cage under it. Each floor has exactly one cage, so
-- depth is the natural key and a second ride at the same ladder can only ever be a replacement.
local rides: { [number]: Ride } = {}

-- A short-lived world anchor for a positional cue, the same disposable-emitter pattern
-- client/DynamiteController uses for the fuse and the blast.
local function playAt(cueName: string, position: Vector3, lifetimeSeconds: number): BasePart
	local anchor = Instance.new("Part")
	anchor.Name = "WickLadderAudioAnchor"
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = Workspace

	AudioCues.playAt(cueName, anchor)
	Debris:AddItem(anchor, math.max(lifetimeSeconds, 0.1))
	return anchor
end

local function clearRide(depth: number)
	local active = rides[depth]
	if active == nil then
		return
	end
	rides[depth] = nil
	local winch = active.winch
	if winch ~= nil then
		winch:Destroy()
	end
	if active.isLocalRider then
		CameraController.setElevatorOffset(Vector3.zero)
	end
end

local function clearAllRides()
	for depth in rides do
		clearRide(depth)
	end
end

-- Smoothstep: a winch eases off its brake, runs, and settles. The same curve the lobby car uses, so
-- both rides in this game accelerate the same way.
--
-- IT LIVES IN THE SHARED RULES, NOT HERE. The server inverts this exact curve to decide when the cage
-- has fallen clear of the mouth and the hatch may be thrown over it; a private copy on this side would
-- put a slab through the cage the first time either was retuned alone.
local rideEase = DescentElevatorRules.rideEase

local function captureRiders(active: Ride)
	for _, riderId in active.riderIds do
		local existing = active.riders[riderId]
		if existing ~= nil and existing.model.Parent ~= nil then
			continue
		end
		active.riders[riderId] = nil
		local rider = Players:GetPlayerByUserId(riderId)
		local character = if rider ~= nil then rider.Character else nil
		if character == nil or character.PrimaryPart == nil then
			continue
		end
		-- PLACED ON THE DECK, NOT WHEREVER THE BODY CURRENTLY LOOKS LIKE IT IS. Its initial horizontal
		-- slot is only a starting point: afterward we preserve live in-cage movement and facing. Height
		-- stays fixed because the cage's deck, not a sampled world position, owns it during the ride.
		local relative = active.cageRestPivot:ToObjectSpace(character:GetPivot())
		active.riders[riderId] = {
			model = character,
			verticalOffset = relative.Position.Y,
		}
	end
end

-- The cage has invisible server-side containment behind its visible open frame, plus the closed
-- front gate. Match that footprint in the local prediction so a rider can explore the deck without
-- appearing to cross a boundary before the authoritative collision catches them.
local function riderCageSpace(active: Ride, rider: RiderVisual): CFrame
	local current = active.cageRestPivot:ToObjectSpace(rider.model:GetPivot())
	local halfWidth = math.max(Config.DescentLadder.cageWidth / 2 - Config.Character.bodyRadius, 0)
	local halfDepth = math.max(Config.DescentLadder.cageDepth / 2 - Config.Character.bodyRadius, 0)
	local position = current.Position
	return CFrame.new(
		math.clamp(position.X, -halfWidth, halfWidth),
		rider.verticalOffset,
		math.clamp(position.Z, -halfDepth, halfDepth)
	) * (current - position)
end

local function applyShake(active: Ride, now: number)
	if not active.isLocalRider then
		return
	end
	local config = Config.DescentLadder
	-- Hardest at the top, easing as the cage settles: chain under load, then chain under control.
	local remaining = math.clamp((active.startedAt + active.duration - now) / active.duration, 0, 1)
	local amplitude = config.shakeStuds * (remaining * 0.5 + 0.5)
	local phase = now * config.shakeHz * math.pi * 2
	CameraController.setElevatorOffset(
		Vector3.new(math.sin(phase * 1.21) * amplitude, 0, math.cos(phase * 0.83) * amplitude * 0.6)
	)
end

local function renderOne(depth: number, active: Ride, now: number)
	if active.cage.Parent == nil then
		-- The floor retired, or the run ended, out from under a ride we were still drawing.
		clearRide(depth)
		return
	end

	local progress = math.clamp((now - active.startedAt) / active.duration, 0, 1)
	local eased = rideEase(progress)
	local offset = if active.direction == "Down" then -eased * active.distance else -(1 - eased) * active.distance
	local pivot = active.cageRestPivot * CFrame.new(0, offset, 0)
	active.cage:PivotTo(pivot)

	-- THE RIDERS ARE DROPPED FIRST, BEFORE THE FINAL FRAME IS DRAWN. The server lands the ride and
	-- teleports them onto the next floor on its own tick at exactly this timestamp; a client running a
	-- slow frame could otherwise evaluate `progress >= 1` a beat late and spend that beat dragging an
	-- already-arrived body back down a shaft it is no longer in.
	if progress >= 1 then
		-- The server writes the authoritative endpoint; nothing local is left to draw until a distinct
		-- return event begins the empty upward leg.
		playAt(Config.DescentLadder.audio.arriveCue, pivot.Position, 3)
		clearRide(depth)
		return
	end

	if active.direction == "Down" then
		captureRiders(active)
		for _, visual in active.riders do
			if visual.model.Parent ~= nil then
				visual.model:PivotTo(pivot * riderCageSpace(active, visual))
			end
		end
		applyShake(active, now)
	end
end

local function renderRides()
	if next(rides) == nil then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for depth, active in rides do
		renderOne(depth, active, now)
	end
end

function DescentLadderController.start()
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if typeof(kind) ~= "string" or typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: any }
		if kind == "descentRide" or kind == "descentReturn" then
			-- `any` is confined to this untyped RemoteEvent boundary; every field is validated here.
			local cage = data.cage
			local depth = tonumber(data.depth)
			local startedAt = tonumber(data.startedAt)
			local duration = tonumber(data.duration)
			local distance = tonumber(data.distance)
			local restPivot = data.restPivot
			local riderIds: { number } = {}
			if typeof(data.riderIds) == "table" then
				for _, rawId in data.riderIds do
					if typeof(rawId) == "number" and rawId > 0 and rawId % 1 == 0 then
						table.insert(riderIds, rawId)
					end
				end
			end
			if
				typeof(cage) ~= "Instance"
				or not cage:IsA("Model")
				or depth == nil
				or (kind == "descentRide" and #riderIds == 0)
				or startedAt == nil
				or duration == nil
				or duration <= 0
				or distance == nil
				or distance < 0
				or typeof(restPivot) ~= "CFrame"
			then
				return
			end

			-- Only this floor's own previous ride, if the cage somehow departed twice. Every other
			-- floor's ride is somebody else's descent and keeps drawing.
			clearRide(depth)
			local active: Ride = {
				cage = cage,
				cageRestPivot = restPivot,
				riderIds = riderIds,
				riders = {},
				startedAt = startedAt,
				duration = duration,
				distance = distance,
				direction = if kind == "descentRide" then "Down" else "Up",
				isLocalRider = kind == "descentRide" and table.find(riderIds, player.UserId) ~= nil,
				winch = nil,
			}
			if active.direction == "Down" then
				captureRiders(active)
			end

			-- The latch releasing, heard from wherever the listener is standing, and the winch itself
			-- parented to the cage so it descends with the thing making the noise.
			local startPosition = if active.direction == "Down"
				then restPivot.Position
				else (restPivot * CFrame.new(0, -distance, 0)).Position
			playAt(Config.DescentLadder.audio.departCue, startPosition, 3)
			local winch =
				playAt(Config.DescentLadder.audio.rideCue, startPosition, Config.DescentLadder.audio.rideEmitterSeconds)
			winch.Parent = cage
			active.winch = winch

			rides[depth] = active
		elseif kind == "floor" then
			-- OUR OWN ARRIVAL, and only ours: `floor` is fired to the player who moved and nobody else.
			-- It ends the ride this client was a passenger on; a teammate descending some other ladder
			-- is still descending and must keep being drawn.
			for depth, active in rides do
				if active.isLocalRider then
					clearRide(depth)
				end
			end
		elseif kind == "countdown" or kind == "runResolved" then
			-- A new expedition, or this one ending. Nothing in flight survives either.
			clearAllRides()
		end
	end)

	RunService:BindToRenderStep("WickDescentRide", Enum.RenderPriority.Camera.Value - 1, renderRides)
end

return DescentLadderController
