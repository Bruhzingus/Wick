--!strict
-- The Grub Queen: slow, unkillable by anything but dynamite, and the centre of her own encounter.
--
-- SHE IS A RESOURCE RACE, NOT A DAMAGE RACE. She cannot be worn down and cannot be interrupted. Six
-- sticks kill her; everything else in the chamber exists to make finding six sticks expensive. The
-- grubs are attrition, the two chained Longarms are pressure, and the wax and dynamite sitting on
-- opposite sides of the chamber are the choice — survive longer, or kill faster.
--
-- SHE CRAWLS, AND SHE IS HOPELESS AT IT ON PURPOSE. 1.8 studs a second against a player who walks at
-- 8; twenty-four degrees a second to turn a body twenty-eight studs long. She will never catch
-- anybody. What she does is take away standing still — the corner behind her used to be a place the
-- encounter stopped happening, and now it is a place she is slowly arriving at.
--
-- THE BITE IS THE ONLY THING SHE DOES QUICKLY, and it is the biggest hit in the game (0.8 of a full
-- candle). Two things make that fair and both are non-negotiable:
--   * IT ONLY LANDS IN FRONT OF HER, inside `biteArcDot`. Her flank and her whole abdomen are safe,
--     which is what makes her slow turn a real counter rather than a cosmetic one.
--   * THE CONTACT TEST IS TAKEN WHEN THE MANDIBLES SHUT, not when the animation starts. Half a
--     second of rear-back is the warning, and stepping out of the arc during it works. Resolving at
--     the windup instead would make the telegraph decorative, which is the same mistake the
--     Longarm's reveal exists to avoid.
--
-- SHE COUNTS STICKS, NOT DAMAGE. `DynamiteService` hands her a flat charge per detonation inside the
-- blast radius rather than a distance-scaled figure (see Config/GrubQueen for the full reasoning).
-- Nothing else in this file may reduce her health, and `damage()` is deliberately absent: the pack
-- module exposes `applyDynamite` instead of `damage` for exactly this reason.
--
-- THE VENT IS THE ONLY TIMER THE PLAYER GETS. It brightens as the next brood approaches, and that is
-- deliberately the whole of it — no UI meter, because reading the room is the skill being asked for.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local GrubQueenModule = require(ReplicatedStorage.Shared.Enemies.GrubQueen)
local EnemyVariantRules = require(ReplicatedStorage.Shared.Logic.EnemyVariantRules)
local QueenRegistry = require(script.Parent.Parent.QueenRegistry)
local ThreatService = require(script.Parent.Parent.ThreatService)
local NoiseService = require(script.Parent.Parent.NoiseService)
local PlayerState = require(script.Parent.Parent.PlayerState)
local WaxService = require(script.Parent.Parent.WaxService)
local SurfaceProbe = require(script.Parent.Parent.SurfaceProbe)
local EnemyMover = require(script.Parent.EnemyMover)
local EnemyAudio = require(script.Parent.EnemyAudio)
local EncounterHints = require(script.Parent.EncounterHints)

local GrubQueenBehavior = {}
GrubQueenBehavior.__index = GrubQueenBehavior

-- She never attacks directly — her brood and her chained Longarms do that, and both already carry
-- their own encounter hint. This is the substitute trigger: close enough to have plainly found her.
local SIGHTING_RADIUS = 55

export type Queen = typeof(setmetatable(
	{} :: {
		body: any,
		depth: number,
		variant: EnemyVariantRules.Variant,
		registryEntry: any,
		destroyed: boolean,
		dead: boolean,
		onBirth: ((CFrame) -> ())?,
		onDeath: (() -> ())?,
		-- Where she started and how far from it she will follow anybody. Defaults to her spawn and the
		-- configured chamber radius, so a Queen nobody leashed still cannot wander a floor.
		homePosition: Vector3,
		leashRadius: number,
		-- How far her root sits above the rock, measured off the built body once. She is CFrame-driven,
		-- so nothing else is going to keep her on the floor.
		rideHeight: number,
		-- The flat ground height to fall back to where there is no Terrain to probe. Only the developer
		-- laboratory ever registers one; see EnemyService.setGroundFallback.
		fallbackGroundY: number?,
		nextBiteAt: number,
		-- Set while a bite is in the air: who it was aimed at, and when the mandibles shut. Resolved
		-- from the step loop rather than on a timer of its own so the contact test happens on a frame
		-- where the player's position is current.
		bitePendingFor: Types.PlayerId?,
		biteContactAt: number,
	},
	GrubQueenBehavior
))

local function config()
	return Config.GrubQueen
end

-- The nearest player she is willing to follow: alive, on her floor, inside `pursuitRadius`, and not
-- under threat protection. Distance is FLAT — her root rides above the rock and a player's does not,
-- and a bite range measured as a diagonal would shrink or grow with the floor under them.
local function nearestPlayer(self: Queen): (Types.PlayerId?, Vector3?, number)
	local origin = self.body.root.Position
	local bestId: Types.PlayerId? = nil
	local bestPosition: Vector3? = nil
	local bestDistance = config().pursuitRadius
	for playerId, state in PlayerState.all() do
		if state.depth ~= self.depth or not state.alive or state.finished or state.snuffedAt ~= nil then
			continue
		end
		if PlayerState.isThreatProtected(playerId) then
			continue
		end
		local offset = state.position - origin
		local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if distance < bestDistance then
			bestId = playerId
			bestPosition = state.position
			bestDistance = distance
		end
	end
	return bestId, bestPosition, bestDistance
end

-- Whether a point is inside the arc her head can actually reach. Anything outside it is standing at
-- her flank or behind her, which is exactly where the fight wants a player to learn to be.
local function inBiteArc(self: Queen, target: Vector3): boolean
	local root = self.body.root
	local offset = target - root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.01 then
		return true
	end
	local facing = root.CFrame.LookVector
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if flatFacing.Magnitude < 0.01 then
		return false
	end
	return flatFacing.Unit:Dot(flat.Unit) >= config().biteArcDot
end

-- Ground under a proposed position, with the laboratory's flat-floor fallback. Mirrors the Wax Grub's
-- `seat` exactly: she is the other CFrame-driven body, so she has the same job to do and the same
-- reason to refuse rather than guess.
local function seat(self: Queen, position: Vector3): Vector3?
	local measured = SurfaceProbe.tryGroundY(position.Y - self.rideHeight, position.X, position.Z, 0)
	if measured ~= nil then
		return Vector3.new(position.X, measured + self.rideHeight, position.Z)
	end
	local fallback = self.fallbackGroundY
	if fallback ~= nil then
		return Vector3.new(position.X, fallback + self.rideHeight, position.Z)
	end
	return nil
end

-- Turn toward a point at `turnDegreesPerSecond`, and report whether she is now pointed at it closely
-- enough to be worth crawling forward. A body this long that strafed toward a target without coming
-- about first would read as sliding rather than crawling.
local function turnToward(self: Queen, target: Vector3, dt: number): boolean
	local root = self.body.root
	local offset = target - root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.5 then
		return false
	end
	local desired = flat.Unit
	local facing = root.CFrame.LookVector
	local current = Vector3.new(facing.X, 0, facing.Z)
	if current.Magnitude < 0.01 then
		return false
	end
	current = current.Unit
	-- Yaw arithmetic rather than vector cross products: wrapping the difference into (-pi, pi] is what
	-- stops a body this size from taking the long way round a 181-degree turn.
	local currentYaw = math.atan2(current.X, current.Z)
	local desiredYaw = math.atan2(desired.X, desired.Z)
	local difference = (desiredYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi
	local step = math.rad(config().turnDegreesPerSecond) * dt
	local yaw = currentYaw + math.clamp(difference, -step, step)
	local turned = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	root.CFrame = CFrame.lookAt(root.Position, root.Position + turned)
	-- Only crawl once she is roughly pointed the right way, using the same threshold as the bite arc:
	-- she advances on exactly the ground she could bite on, and turns on the spot everywhere else.
	return math.abs(difference) <= math.acos(config().biteArcDot)
end

-- One crawl step. Refuses rather than grinds: rock ahead or no measured floor both mean she turns in
-- place this frame instead of pushing into it, which on a body with no pathfinding is the difference
-- between a slow menace and a Queen vibrating against a stalagmite.
local function crawlToward(self: Queen, target: Vector3, dt: number): boolean
	local root = self.body.root
	local origin = root.Position
	local delta = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	local distance = delta.Magnitude
	-- She stops short of the target rather than climbing onto it: her mandibles are what she wants in
	-- range, and those are already seven studs in front of her root.
	if distance <= config().biteRange * 0.8 then
		return false
	end
	local direction = delta.Unit
	local stepDistance = math.min(config().crawlSpeed * dt, distance)
	-- ROCK AHEAD? A SPHERE, BECAUSE SHE IS FOUR STUDS WIDE and a thin ray would thread gaps she
	-- cannot fit through. Every number here is measured off the built body rather than picked:
	--
	--   radius 1.8   — her thorax is 4.0 across, so this is very slightly narrower than she is. It
	--                  cannot be her true half-width: her root rides 2.36 studs above her lowest
	--                  point, so a sphere of 2.4 clips the FLOOR on every step and she never moves
	--                  anywhere at all. Erring narrow makes her occasionally start into a gap she
	--                  has to back out of; erring wide makes her furniture.
	--   lift 0.5     — puts the sphere's underside 1.06 studs clear of the rock she is standing on,
	--                  which is more than voxel seams and stalagmite bases ever disagree by.
	--   reach 6.0    — her head is 4.66 studs in front of her root and her mandibles reach 7.6, so a
	--                  probe that only looked as far as her next step would let her put her face
	--                  through a wall before anything noticed.
	local probeOrigin = origin + Vector3.new(0, 0.5, 0)
	if EnemyMover.chargeObstruction(probeOrigin, direction * (stepDistance + 6.0), 1.8) ~= nil then
		return false
	end
	local next_ = seat(self, origin + direction * stepDistance)
	if next_ == nil then
		return false
	end
	root.CFrame = CFrame.lookAt(next_, next_ + root.CFrame.LookVector)
	return true
end

-- The first player to come within sight of her on this floor, announced once per player ever.
local function announceToNearbyPlayers(self: Queen)
	local origin = self.body.root.Position
	for playerId, state in PlayerState.all() do
		if state.depth ~= self.depth or not state.alive or state.finished then
			continue
		end
		if (state.position - origin).Magnitude <= SIGHTING_RADIUS then
			EncounterHints.announce(playerId, "GrubQueen")
		end
	end
end

function GrubQueenBehavior.new(cframe: CFrame, depth: number, familyId: string?, seed: number?): Queen
	local variant = EnemyVariantRules.variantForFamily(familyId)
	local body = GrubQueenModule.new(cframe, variant, seed)
	local model = body.model

	-- ANCHORED AND IMMOBILE, BUT ONLY AT THE ROOT. She needs no Humanoid, no mover and no pathfinding —
	-- the pack is explicit that she is the one body the host does not have to move — and anchoring the
	-- root is what keeps a forty-times-mass grub from being shoved around by her own brood.
	--
	-- HER SEGMENTS MUST STAY UNANCHORED. She is a Motor6D chain like every other body in the pack, and
	-- her whole presence is the peristaltic wave travelling down it; anchoring the segments would
	-- freeze those joints and collapse her nine-segment body into a single stack of parts at the
	-- origin. See WaxGrubBehavior for the same trap written out at length.
	body.root.Anchored = true

	local self: Queen = setmetatable({
		body = body,
		depth = depth,
		variant = variant,
		registryEntry = nil,
		destroyed = false,
		dead = false,
		onBirth = nil,
		onDeath = nil,
		homePosition = cframe.Position,
		leashRadius = config().leashRadius,
		-- Measured the same way every other pack body's is, so she stands on the rock rather than in
		-- it. She is CFrame-driven, so this is the only thing holding her up.
		rideHeight = EnemyMover.measureRideHeight(model, body.root),
		fallbackGroundY = nil,
		nextBiteAt = 0,
		bitePendingFor = nil,
		biteContactAt = 0,
	}, GrubQueenBehavior)

	-- THE CALL. Every 26 seconds she alerts the room, which is the encounter's pressure valve: if the
	-- player is doing well, this is what breaks the stalemate. Routed through the systems the cave
	-- already has — a real noise event and a real threat alert — rather than a bespoke summon, so
	-- anything on the floor that can hear reacts the way it always does.
	body.onCall = function()
		local position = body.root.Position
		NoiseService.emit("DripstoneImpact", position, nil)
		ThreatService.alertAll(depth, position, 150, 12)
		EnemyAudio.play(model, "QueenCall")
	end

	body.onBirth = function(birthCFrame: CFrame)
		local spawner = self.onBirth
		if spawner ~= nil then
			spawner(birthCFrame)
		end
	end

	body.onDeath = function()
		self.dead = true
		local finish = self.onDeath
		if finish ~= nil then
			finish()
		end
	end

	self.registryEntry = QueenRegistry.register({
		depth = depth,
		position = function(): Vector3?
			if self.destroyed or model.Parent == nil or body.root.Parent == nil then
				return nil
			end
			return body.root.Position
		end,
		applyDynamite = function(charges: number): boolean
			if self.destroyed or self.dead then
				return false
			end
			body:applyDynamite(charges)
			return self.dead
		end,
	})

	EnemyAudio.attachLoop(model, "QueenChurn")
	body:start()
	return self
end

-- Chain her to a chamber, exactly as the two Longarm guards are chained (BossEncounterService). The
-- default is her spawn point and the configured radius, so this only ever narrows or re-centres it.
function GrubQueenBehavior.setLeash(self: Queen, center: Vector3, radius: number)
	self.homePosition = center
	self.leashRadius = radius
end

-- The flat floor height to use where there is no Terrain, for the developer laboratory. Handed down
-- by `EnemyService.spawnQueen` for the same reason the Wax Grub takes one: she is CFrame-driven, so
-- without it every crawl step in the lab measures no ground and she never moves.
function GrubQueenBehavior.setGroundFallback(self: Queen, y: number?)
	self.fallbackGroundY = y
end

-- One of her brood died. She caps live grubs at 14, so this is what lets the cap breathe.
function GrubQueenBehavior.grubDied(self: Queen)
	if self.destroyed then
		return
	end
	self.body:grubDied()
end

function GrubQueenBehavior.isDead(self: Queen): boolean
	return self.dead
end

-- THE MANDIBLES SHUT. Everything is re-read here rather than remembered from the windup: whether the
-- target still exists, whether they are still in range, and whether they are still in the arc. A
-- player who stepped aside during the rear-back takes nothing, which is the whole contract of a
-- telegraph.
local function resolveBite(self: Queen)
	local playerId = self.bitePendingFor
	self.bitePendingFor = nil
	if playerId == nil then
		return
	end
	local state = PlayerState.get(playerId)
	if state == nil or state.depth ~= self.depth or not state.alive or state.finished then
		return
	end
	local offset = state.position - self.body.root.Position
	local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if distance > config().biteRange or not inBiteArc(self, state.position) then
		return
	end
	EncounterHints.announce(playerId, "GrubQueen")
	WaxService.drainExternal(
		playerId,
		config().biteDamage,
		"DamageThreat" :: Types.WaxSource,
		"The Queen had you in her mandibles.",
		{ kind = "Hit", seconds = 1.6 },
		"GrubQueen"
	)
end

-- Bite, crawl, or hold. In that order, and only ever one of them: she is far too heavy to be doing
-- two things at once, and a Queen who slid forward through her own bite would lose the telegraph.
local function pursue(self: Queen, dt: number, now: number)
	-- `crawl` is a state she must be taken OUT of as deliberately as she is put into it: it is the
	-- fast peristaltic wave, and a Queen playing it while stationary reads as a treadmill.
	local function settle(travelling: boolean)
		if self.body:isTravelling() then
			self.body:setState(if travelling then "crawl" else "idle")
		end
	end

	local targetId, targetPosition, distance = nearestPlayer(self)
	if targetId == nil or targetPosition == nil then
		settle(false)
		return
	end

	-- CLOSE ENOUGH AND IN FRONT OF HER. The arc test is here as well as at contact so she does not
	-- even begin a bite at somebody standing at her flank — the windup should mean something is about
	-- to happen to YOU, not that something is happening somewhere.
	if distance <= config().biteRange and now >= self.nextBiteAt and inBiteArc(self, targetPosition) then
		if self.body:bite() then
			self.nextBiteAt = now + config().biteInterval
			self.bitePendingFor = targetId
			self.biteContactAt = now + GrubQueenModule.Config.biteContactSeconds
			return
		end
	end

	if not self.body:isTravelling() then
		return
	end

	-- LEASHED TO HER CHAMBER. She turns to watch a player she will not follow, which is the same
	-- answer the Longarm guards give and reads as interest rather than as a broken pursuit.
	local fromHome = targetPosition - self.homePosition
	if Vector3.new(fromHome.X, 0, fromHome.Z).Magnitude > self.leashRadius then
		turnToward(self, targetPosition, dt)
		settle(false)
		return
	end

	local aimed = turnToward(self, targetPosition, dt)
	settle(aimed and crawlToward(self, targetPosition, dt))
end

function GrubQueenBehavior.step(self: Queen, dt: number, now: number)
	if self.destroyed then
		return
	end
	local model = self.body.model
	if model.Parent == nil then
		self:destroy()
		return
	end
	-- Her own movement state is already set before the comparison below, so this pass is belt-and-braces
	-- for her rather than a fix — but it keeps all four creatures on one observation rule.
	EnemyAudio.observe(model, "Queen", self.body.state)

	local previousState = self.body.state
	self.body:step(dt)
	if self.body.state ~= previousState then
		EnemyAudio.observe(model, "Queen", self.body.state)
	end

	if not self.dead and self.body.state ~= "death" then
		if self.bitePendingFor ~= nil and now >= self.biteContactAt then
			resolveBite(self)
		end
		pursue(self, dt, now)
	end
	announceToNearbyPlayers(self)
end

function GrubQueenBehavior.destroy(self: Queen)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.registryEntry ~= nil then
		QueenRegistry.unregister(self.registryEntry)
		self.registryEntry = nil
	end
	EnemyAudio.stopAll(self.body.model)
	self.body.onBirth = nil
	self.body.onCall = nil
	self.body.onDeath = nil
	self.body:destroy()
end

-- Read by RunOrchestrator's descent guard: the ladder refuses a rider while she is alive
-- (Config/GrubQueen.requiresKillToDescend). Deliberately a query on the registry rather than on this
-- object, so the orchestrator never has to hold a reference to an encounter.
function GrubQueenBehavior.aliveAtDepth(depth: number): boolean
	return QueenRegistry.aliveAtDepth(depth)
end

-- Config is read for the brood cap and intervals by the pack module itself; this reference keeps the
-- dependency explicit for anybody retuning the encounter.
function GrubQueenBehavior.broodCap(): number
	return config().maxLiveGrubs
end

return GrubQueenBehavior
