--!strict
-- Unlittius: the boss's brain, and the only thing in the game that decides whether one of his attacks
-- landed (Config/Unlittius, Logic/UnlittiusRules, shared/Enemies/Unlittius).
--
-- HE IS BOUND TO HIS SHRINE AND HE NEVER CHASES. There is no pathfinding in this file, no navmesh, no
-- Humanoid and no walk cycle, and — deliberately — no "approach" intent at all: `stepMovement` keeps
-- him inside an eleven-stud disc around his own dais and moves him for exactly two reasons. Somebody
-- has crowded him and a boulder needs room; or somebody has put a pillar between them, and he slides
-- until he has an angle again. Cover costs him a couple of seconds, not the fight.
--
-- He also STOPS DEAD the moment an attack commits, which is what keeps his telegraphs honest.
--
-- HE IS A CLOCK. Everything he does is a fixed timeline: an action is chosen, its start is stamped
-- against `workspace:GetServerTimeNow()`, and its authoritative beats — the dripstone snap, two
-- boulder releases, the summon, two rakes — are resolved when the elapsed time crosses them. Clients
-- read the same stamp and draw the same timeline, which is why nothing here has to be told twice.
--
-- EVERY HIT IS RE-TESTED AT ITS OWN BEAT, never at the windup. That is the entire fairness contract of
-- this fight, and it is the same one the Grub Queen's bite is built on: a telegraph that decides its
-- damage when it starts is not a telegraph, it is an announcement. A player who reads the floor
-- markers and moves, steps out of the rake, or gets behind cover before a boulder arrives takes
-- nothing — because the test happens then, against where they are then.
--
-- WHAT IS REUSED RATHER THAN REBUILT, because this encounter should not introduce a second version of
-- anything the cave already has:
--   * the falling stones are real `NewModelsAndObjects/UnstableDripstone` bodies driven through
--     `DripstoneVisualProtocol`, so the client's existing dripstone presentation animates the wobble,
--     the fall and the impact with no new code;
--   * damage is `WaxService.drainExternal`, in fractions of a candle, like every other hazard;
--   * knockback is `CharacterService.pushRunBody`, the same shove the cave already uses;
--   * summoned Gnawers are ordinary `StoneGnawer` bodies spawned through `EnemyService` by the
--     callback below — this file contains no Gnawer AI and must never grow any;
--   * impacts emit real `NoiseService` events, so everything on the floor that can hear reacts.
--
-- HE DOES NOT SPAWN THE CANDLES AND HE DOES NOT COUNT THEM. `UnlittiusEncounterService` owns the eight
-- candles and tells him the authoritative total through `candleLit`; all he does with it is recoil,
-- dim, and — at eight — stop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local UnlittiusModule = require(ReplicatedStorage.Shared.Enemies.Unlittius)
local UnlittiusRules = require(ReplicatedStorage.Shared.Logic.UnlittiusRules)
local UnlittiusVisualProtocol = require(ReplicatedStorage.Shared.UnlittiusVisualProtocol)
local DripstoneVisualProtocol = require(ReplicatedStorage.Shared.DripstoneVisualProtocol)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local UnstableDripstone = require(ReplicatedStorage.Shared.NewModelsAndObjects.UnstableDripstone)
local EnemyVariantRules = require(ReplicatedStorage.Shared.Logic.EnemyVariantRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CollectionService = game:GetService("CollectionService")

local UnlittiusRegistry = require(script.Parent.Parent.UnlittiusRegistry)
local PlayerState = require(script.Parent.Parent.PlayerState)
local WaxService = require(script.Parent.Parent.WaxService)
local CharacterService = require(script.Parent.Parent.CharacterService)
local NoiseService = require(script.Parent.Parent.NoiseService)
local ThreatService = require(script.Parent.Parent.ThreatService)
local SurfaceProbe = require(script.Parent.Parent.SurfaceProbe)
local Telemetry = require(script.Parent.Parent.Telemetry)
local EnemyAudio = require(script.Parent.EnemyAudio)
local EncounterHints = require(script.Parent.EncounterHints)

local UnlittiusBehavior = {}
UnlittiusBehavior.__index = UnlittiusBehavior

local Protocol = UnlittiusVisualProtocol

local function config()
	return Config.Unlittius
end

-- THE FALLING STONE HE PULLS OUT OF THE CEILING. Deliberately the cave's own `Lance`: this attack is
-- the room answering him rather than a bespoke projectile, so it should be made of the same rock the
-- player has been dodging since floor three, and it inherits that formation's whole presentation.
local DRIPSTONE_VARIANT = "Lance"

-- HOW WIDE HE IS, FOR THE PURPOSES OF NOT SHOOTING HIMSELF. Measured off the built rig rather than
-- guessed: his shoulders span 4.74 studs and his cape adds depth behind them, so 3.2 is a cylinder
-- comfortably outside the torso and inside the shoulder attachments at 3.4. A boulder path that stays
-- clear of this stays clear of him.
local BODY_CLEARANCE_RADIUS = 3.2

type Zone = {
	position: Vector3,
	impactAt: number,
	marker: BasePart,
	stone: Model?,
	resolved: boolean,
	-- When the spent stone is swept up. Carried on the zone rather than derived from the action's
	-- clock, because he has usually started something else by the time his last one lands.
	clearAt: number?,
}

type Projectile = {
	part: BasePart,
	origin: Vector3,
	direction: Vector3,
	position: Vector3,
	firedAt: number,
	travelled: number,
	-- One boulder may only ever hit a given player once. Without this a stone that clips a character
	-- across two frames bills them twice for one impact.
	hitPlayers: { [Types.PlayerId]: boolean },
}

export type Boss = typeof(setmetatable(
	{} :: {
		body: any,
		depth: number,
		variant: EnemyVariantRules.Variant,
		destroyed: boolean,
		registryEntry: any,
		-- Where he floats and what he is anchored over. `daisPosition` is the FLOOR under him, which is
		-- what every ground-seeking part of the fight measures from.
		daisPosition: Vector3,
		chamberRadius: number,
		fallbackGroundY: number?,
		-- The action timeline. `action` is one of `Protocol.actions`; `actionStartedAt` is server time.
		action: string,
		actionStartedAt: number,
		actionEndsAt: number,
		nextActionAt: number,
		recent: { UnlittiusRules.ActionId },
		-- Which authoritative beats of the current action have already fired. Cleared on every new
		-- action, and the reason a recoil cannot rewind a boulder that already left.
		firedBeats: { [string]: boolean },
		-- Live sub-objects.
		zones: { Zone },
		projectiles: { Projectile },
		-- The bodies he has called up and not yet lost. Held as references and pruned by looking, so the
		-- active cap is a fact about the world rather than a counter that can drift.
		summoned: { any },
		nextSummonAt: number,
		nextMeleeAt: number,
		meleeTarget: Types.PlayerId?,
		-- Levitation. `velocity` is eased rather than assigned (Logic/UnlittiusRules.stepVelocity) and
		-- `lateralSign` is the side he is currently circling on, held for `lateralHoldSeconds`.
		velocity: Vector3,
		lateralSign: number,
		lateralHoldUntil: number,
		-- Walks the impact variation set, so two stones landing a second apart are never the same
		-- recording twice.
		impactVariant: number,
		-- Paces the stone-shifting cue he makes while under way. A loop would drone under a stationary
		-- boss and cut out every time he stopped to attack.
		nextDriftSoundAt: number,
		-- Whether cover is currently between him and the nearest player, resampled four times a second
		-- rather than every frame. This is the only thing that makes him move at all.
		sightBlocked: boolean,
		nextSightCheckAt: number,
		-- HIS VOICE. `voiceBag` is a shuffled order of every utterance he has, emptied one at a time so
		-- all of them are heard before any repeats; `lastVoiceLine` stops a fresh bag from opening on
		-- the one the previous bag closed with.
		voiceBag: { number },
		lastVoiceLine: number?,
		nextVoiceAt: number,
		incantIndex: number,
		-- The built rig, kept so the voice can be emitted from his HEAD rather than his chest.
		rig: any,
		boulderTargets: { Types.PlayerId },
		-- Progress and completion.
		candlesLit: number,
		-- How many candles this chamber actually built. His dim curve divides by this rather than by
		-- the configured eight, so a seven-candle room still goes fully dark on its last one.
		candleTarget: number,
		banishing: boolean,
		banished: boolean,
		banishStartedAt: number,
		-- Where he was standing when the eighth candle landed. The unbind drags him home from here.
		banishFrom: Vector3,
		relief: Model?,
		ceilingHeight: number,
		awake: boolean,
		rng: Random,
		-- Set by `EnemyService.spawnUnlittius`. He asks; the service owns what a Gnawer is.
		onSummon: ((position: Vector3) -> any?)?,
		onBanished: (() -> ())?,
	},
	UnlittiusBehavior
))

--------------------------------------------------------------------------------
-- Players
--------------------------------------------------------------------------------

-- Everybody who counts as a participant this frame: alive, on his floor, not protected, not finished.
-- Every attack targets out of this list and nothing else — the encounter must never reach a player
-- who is dead, spectating, or standing in the developer laboratory's protected zone.
local function participants(self: Boss): { { id: Types.PlayerId, position: Vector3, distance: number } }
	local origin = self.body.root.Position
	local found: { { id: Types.PlayerId, position: Vector3, distance: number } } = {}
	for playerId, state in PlayerState.all() do
		if state.depth ~= self.depth or not state.alive or state.finished or state.snuffedAt ~= nil then
			continue
		end
		if PlayerState.isThreatProtected(playerId) then
			continue
		end
		table.insert(found, {
			id = playerId,
			position = state.position,
			distance = UnlittiusRules.flatDistance(state.position, origin),
		})
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	return found
end

-- Ground under a point, with the laboratory's flat-floor fallback. Same contract as the Queen's
-- `seat`: measure, or refuse — a marker placed on a height nothing measured is a marker inside rock.
local function groundY(self: Boss, position: Vector3): number?
	local measured = SurfaceProbe.tryGroundY(self.daisPosition.Y, position.X, position.Z, 0)
	if measured ~= nil then
		return measured
	end
	return self.fallbackGroundY
end

--------------------------------------------------------------------------------
-- Presentation contract
--------------------------------------------------------------------------------

local function publishAction(self: Boss, action: string, startedAt: number)
	local model = self.body.model
	local attributes = Protocol.boss.attributes
	model:SetAttribute(attributes.actionStartedAt, startedAt)
	model:SetAttribute(attributes.power, UnlittiusRules.power(self.candlesLit))
	model:SetAttribute(attributes.candlesLit, self.candlesLit)
	-- Action last, so its change signal observes a matching timestamp — the same ordering rule the
	-- dripstone's own state machine documents.
	model:SetAttribute(attributes.action, action)
end

-- One place where every action begins, so nothing can start an attack without stamping a clock, and
-- the body's animation state and the replicated action can never disagree.
local function beginAction(self: Boss, action: string, length: number, now: number)
	self.action = action
	self.actionStartedAt = now
	self.actionEndsAt = now + length
	table.clear(self.firedBeats)
	self.body:setState(action)
	publishAction(self, action, now)
	EnemyAudio.observe(self.body.model, "Unlittius", action)
end

-- Has this beat's time arrived, and has it not already fired? Every authoritative hit in the fight
-- goes through here, which is what makes "a beat fires exactly once" a property of the file rather
-- than of each attack remembering to check.
local function beat(self: Boss, name: string, at: number, now: number): boolean
	if self.firedBeats[name] then
		return false
	end
	if not UnlittiusRules.beatReached(now - self.actionStartedAt, at) then
		return false
	end
	self.firedBeats[name] = true
	return true
end

--------------------------------------------------------------------------------
-- DRIPSTONE
--------------------------------------------------------------------------------

local function clearZone(zone: Zone)
	if zone.marker.Parent ~= nil then
		zone.marker:Destroy()
	end
	local stone = zone.stone
	if stone ~= nil and stone.Parent ~= nil then
		stone:Destroy()
	end
end

-- The floor marker. A flat cracked disc rather than a decal so it needs no texture asset, no
-- SurfaceGui and no client to exist — a player who joins mid-telegraph sees the same warning as one
-- who was here for it.
local function buildMarker(self: Boss, position: Vector3, markedAt: number, impactAt: number): BasePart
	local dripstone = config().dripstone
	local marker = Instance.new("Part")
	marker.Name = "UnlittiusTelegraph"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.16, dripstone.impactRadius * 2, dripstone.impactRadius * 2)
	-- Lying flat: a Cylinder part's length runs along X, so it has to be tipped onto its face.
	marker.CFrame = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Material = Enum.Material.Neon
	marker.Color = config().body.runeColor
	marker.Transparency = 0.55
	marker:SetAttribute(Protocol.telegraph.attributes.markedAt, markedAt)
	marker:SetAttribute(Protocol.telegraph.attributes.impactAt, impactAt)
	marker:SetAttribute(Protocol.telegraph.attributes.radius, dripstone.impactRadius)
	CollectionService:AddTag(marker, Protocol.telegraph.tag)
	marker.Parent = self.body.model.Parent
	return marker
end

-- CHOOSE THE ZONES AT THE START OF THE TELEGRAPH, not at the snap. They are placed around the
-- players' CURRENT positions by the pure rules, marked immediately, and then never move again —
-- which is what makes walking out of one work.
local function startDripstone(self: Boss, now: number)
	local people = participants(self)
	if #people == 0 then
		return
	end
	local targets: { Vector3 } = {}
	for _, person in people do
		table.insert(targets, person.position)
	end
	local rolls: { number } = {}
	for _ = 1, 32 do
		table.insert(rolls, self.rng:NextNumber())
	end
	local zoneCount = UnlittiusRules.dripstoneZoneCount(#people)
	-- WHEN THE STONE ACTUALLY LANDS, computed once and in ONE CLOCK. The marker goes up now, the snap
	-- detaches the stone at 1.62s, and the stone then falls for as long as the shared dripstone rules
	-- say a fall from that height takes — so the impact is the sum, and everything downstream (the
	-- marker's replicated `impactAt`, the client's fall animation, and the server's own damage test)
	-- reads that one number in `workspace:GetServerTimeNow()` space.
	--
	-- MIXING `os.clock()` IN HERE IS A REAL BUG AND WAS ONE: the client draws from server time, so a
	-- landing stamped in server-uptime lands on a floor nobody was warned about.
	local fallSeconds = DripstoneRules.fallDuration(config().dripstone.ceilingClearance)
	local landsAt = self.actionStartedAt + config().timings.dripstoneSnapAt + fallSeconds

	for _, position in UnlittiusRules.dripstoneZones(targets, zoneCount, rolls, self.daisPosition, self.chamberRadius) do
		local floorY = groundY(self, position)
		if floorY == nil then
			continue
		end
		local seated = Vector3.new(position.X, floorY, position.Z)
		table.insert(self.zones, {
			position = seated,
			impactAt = landsAt,
			marker = buildMarker(self, seated, now, landsAt),
			stone = nil,
			resolved = false,
			clearAt = nil,
		})
	end
end

-- THE SNAP. Every marked zone drops its stone at once. The stone is a real unstable dripstone body
-- entering at `Falling` — the client's existing controller animates the fall from the same
-- timestamp — and the damage is resolved when it lands, not now.
local function releaseDripstone(self: Boss)
	local dripstone = config().dripstone
	local parent = self.body.model.Parent
	for _, zone in self.zones do
		if zone.stone ~= nil then
			continue
		end
		local variant = DripstoneRules.variantById(DRIPSTONE_VARIANT)
		if variant == nil or parent == nil then
			continue
		end
		local anchor = CFrame.new(zone.position + Vector3.new(0, dripstone.ceilingClearance, 0))
		local stone = UnstableDripstone.build(parent, anchor, variant, self.rng:NextInteger(1, 2 ^ 30))
		stone:SetAttribute(DripstoneVisualProtocol.attributes.restCFrame, anchor)
		stone:SetAttribute(DripstoneVisualProtocol.attributes.impactPosition, zone.position)
		stone:SetAttribute(DripstoneVisualProtocol.attributes.fallDistance, dripstone.ceilingClearance)
		stone:SetAttribute(DripstoneVisualProtocol.attributes.variantId, DRIPSTONE_VARIANT)
		stone:SetAttribute(DripstoneVisualProtocol.attributes.depth, self.depth)
		stone:SetAttribute(DripstoneVisualProtocol.attributes.stateStartedAt, workspace:GetServerTimeNow())
		stone:SetAttribute(DripstoneVisualProtocol.attributes.state, DripstoneVisualProtocol.states.falling)
		-- NOT REGISTERED WITH `DripstoneService`. That service owns formations the FLOOR planted, which
		-- are triggered by walking under them and warned by their own wobble. These are his: chosen,
		-- timed and resolved here, and registering them would hand a second owner the same stone.
		CollectionService:AddTag(stone, DripstoneVisualProtocol.tag)
		zone.stone = stone
		if zone.marker.Parent ~= nil then
			zone.marker.Transparency = 0.3
		end
	end
	NoiseService.emit("DripstoneImpact", self.body.root.Position, nil)
	-- THE SNAP IS HIS, so it comes from his hands; each STONE then announces itself from where it is
	-- actually falling, which is the only way a player can tell which marker is about to resolve.
	EnemyAudio.playAt(self.body:chestPosition(), "UnlittiusDripstoneSnap")
	for _, zone in self.zones do
		if zone.stone ~= nil and not zone.resolved then
			EnemyAudio.playAt(
				zone.position + Vector3.new(0, config().dripstone.ceilingClearance * 0.6, 0),
				"UnlittiusDripstoneFall"
			)
		end
	end
end

-- ONE STONE LANDS. The test is taken here and only here, against where players are at this instant.
local function resolveZone(self: Boss, zone: Zone)
	local dripstone = config().dripstone
	zone.resolved = true
	local hitPlayerIds: { number } = {}
	for _, person in participants(self) do
		if UnlittiusRules.flatDistance(person.position, zone.position) > dripstone.impactRadius then
			continue
		end
		table.insert(hitPlayerIds, person.id)
		EncounterHints.announce(person.id, "Unlittius")
		local state = PlayerState.get(person.id)
		local maximum = if state ~= nil then state.wax.max else 1
		WaxService.drainExternal(
			person.id,
			maximum * dripstone.damage,
			"DamageDripstone" :: Types.WaxSource,
			"The ceiling came down where you were standing.",
			nil,
			"Unlittius"
		)
	end

	local stone = zone.stone
	if stone ~= nil and stone.Parent ~= nil then
		local rest = stone:GetAttribute(DripstoneVisualProtocol.attributes.restCFrame)
		if typeof(rest) == "CFrame" then
			stone:PivotTo(CFrame.new(0, -dripstone.ceilingClearance, 0) * rest)
		end
		stone:SetAttribute(DripstoneVisualProtocol.attributes.stateStartedAt, workspace:GetServerTimeNow())
		stone:SetAttribute(DripstoneVisualProtocol.attributes.state, DripstoneVisualProtocol.states.spent)
	end
	if zone.marker.Parent ~= nil then
		zone.marker:Destroy()
	end

	NoiseService.emit("DripstoneImpact", zone.position, nil)
	-- The same broadcast the cave's own formations make, so the client plays the same impact dust,
	-- debris, camera shake and audio it already has for a dripstone landing.
	Remotes.get("RunEvent"):FireAllClients("dripstoneImpact", {
		position = zone.position,
		depth = self.depth,
		variantId = DRIPSTONE_VARIANT,
		hitPlayerIds = hitPlayerIds,
	})
end

-- How long a landed stone stays on the floor before it is swept up. Long enough to read as debris
-- from the attack that just happened; short enough that eight candles' worth of volleys never turn
-- the chamber into an obstacle course the encounter was not designed around.
local SPENT_STONE_SECONDS = 6

local function stepZones(self: Boss, now: number)
	for index = #self.zones, 1, -1 do
		local zone = self.zones[index]
		if zone.stone ~= nil and not zone.resolved and now >= zone.impactAt then
			resolveZone(self, zone)
			zone.clearAt = now + SPENT_STONE_SECONDS
		end
		local clearAt = zone.clearAt
		if clearAt ~= nil and now >= clearAt then
			clearZone(zone)
			table.remove(self.zones, index)
		end
	end
end

--------------------------------------------------------------------------------
-- BOULDER BURST
--------------------------------------------------------------------------------

local function buildBoulderPart(self: Boss, origin: CFrame, conjuredAt: number): BasePart
	local boulder = config().boulder
	local part = Instance.new("Part")
	part.Name = "UnlittiusBoulder"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * boulder.radius * 2
	part.CFrame = origin
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Material = Enum.Material.Slate
	part.Color = Color3.fromRGB(72, 66, 60)
	part:SetAttribute(Protocol.boulder.attributes.conjuredAt, conjuredAt)
	part:SetAttribute(Protocol.boulder.attributes.radius, boulder.radius)
	CollectionService:AddTag(part, Protocol.boulder.tag)
	part.Parent = self.body.model.Parent
	return part
end

-- FIRE ONE. THE PACKAGE'S HARDEST REQUIREMENT ON THIS ATTACK IS THAT A CONJURED STONE NEVER PASSES
-- THROUGH HIS TORSO, and there are three separate mechanisms here holding that up:
--
--   1. THE ORIGIN IS AN ATTACHMENT OUTBOARD OF A SHOULDER, read off the live rig, so the stone never
--      begins inside him and the muzzle moves with him while he drifts.
--   2. THE SHOULDER IS CHOSEN FROM WHERE THE TARGET IS (`UnlittiusRules.boulderSide`), not from which
--      shot number this is. This is the fix for the real bug: firing the left stone at somebody
--      standing to his right sends it straight across his own chest. Picking the near shoulder makes
--      the flight path DIVERGE from his body for every target angle instead of crossing it.
--   3. THE RESULT IS VERIFIED before it is committed (`boulderPathClears`). If the chosen side somehow
--      still grazes him — a target almost exactly on his centreline, where neither shoulder is clearly
--      nearer — the other shoulder is used instead. This costs one vector comparison and removes the
--      whole class of failure rather than the instances of it.
--
-- `preferredSide` is what the animation just played (left stone first, right second), so the swap only
-- ever happens when the geometry demands it and the two shots normally still read as left-then-right.
local function fireBoulder(self: Boss, preferredSide: number, targetId: Types.PlayerId?, now: number)
	local boulder = config().boulder
	local anchor = self.body.anchorCFrame
	local aimAt: Vector3
	if targetId ~= nil then
		local state = PlayerState.get(targetId)
		if state ~= nil then
			local velocity = Vector3.zero
			local root = CharacterService.rootPart(targetId)
			if root ~= nil then
				velocity = root.AssemblyLinearVelocity
			end
			-- Aimed at the CHEST rather than the feet: a stone aimed at the ground in front of somebody
			-- passes under them, and this one is four studs across.
			aimAt = UnlittiusRules.leadTarget(state.position + Vector3.new(0, 2.2, 0), velocity)
		else
			aimAt = anchor.Position + anchor.LookVector * 20
		end
	else
		aimAt = anchor.Position + anchor.LookVector * 20
	end

	-- The near shoulder, then a clearance check, then the far one only if the near one fails.
	local side = UnlittiusRules.boulderSide(anchor.Position, anchor.LookVector, aimAt)
	local origin = self.body:boulderOrigin(side)
	if
		not UnlittiusRules.boulderPathClears(
			origin.Position,
			aimAt - origin.Position,
			self.body:chestPosition(),
			BODY_CLEARANCE_RADIUS,
			boulder.maxDistance
		)
	then
		side = -side
		origin = self.body:boulderOrigin(side)
	end
	local _ = preferredSide

	local part = buildBoulderPart(self, origin, now)
	local direction = UnlittiusRules.boulderDirection(origin.Position, aimAt)
	part:SetAttribute(Protocol.boulder.attributes.origin, origin.Position)
	part:SetAttribute(Protocol.boulder.attributes.direction, direction)
	part:SetAttribute(Protocol.boulder.attributes.speed, boulder.speed)
	part:SetAttribute(Protocol.boulder.attributes.firedAt, now)

	table.insert(self.projectiles, {
		part = part,
		origin = origin.Position,
		direction = direction,
		position = origin.Position,
		firedAt = now,
		travelled = 0,
		hitPlayers = {},
	})
	-- FROM THE SHOULDER IT LEFT. Two stones fire a quarter-second apart from opposite sides of him,
	-- and hearing them come from one point would delete the only cue that they are two.
	EnemyAudio.playAt(origin.Position, "UnlittiusBoulderFire")
end

local function destroyProjectile(self: Boss, index: number)
	local projectile = self.projectiles[index]
	if projectile.part.Parent ~= nil then
		projectile.part:Destroy()
	end
	table.remove(self.projectiles, index)
end

local function boulderImpact(self: Boss, projectile: Projectile, position: Vector3)
	NoiseService.emit("DripstoneImpact", position, nil)
	-- AT THE IMPACT, AND NEVER THE SAME RECORDING TWICE RUNNING. A burst is two stones landing within
	-- a second of each other, so an unvaried impact is immediately audible as one clip played twice.
	self.impactVariant += 1
	EnemyAudio.playVariantAt(position, "UnlittiusBoulderImpact", 3, self.impactVariant)
	Remotes.get("RunEvent"):FireAllClients("unlittiusBoulderImpact", {
		position = position,
		depth = self.depth,
	})
	local _ = projectile
end

-- ADVANCE EVERY LIVE STONE ONE STEP AND ASK WHETHER IT HIT SOMETHING. A spherecast from the previous
-- position to the next one rather than a position test: at 42 studs a second a stone crosses most of
-- a body between two frames, and a point test would let it pass through people.
local function stepProjectiles(self: Boss, dt: number)
	local boulder = config().boulder
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { self.body.model }
	parameters.IgnoreWater = true

	for index = #self.projectiles, 1, -1 do
		local projectile = self.projectiles[index]
		if projectile.part.Parent == nil then
			table.remove(self.projectiles, index)
			continue
		end
		local step = boulder.speed * dt
		local nextPosition = projectile.position + projectile.direction * step

		-- PLAYERS FIRST, and by distance to the swept segment rather than by a physics query: a
		-- character is a collection of parts owned by its own client, and the server's own record of
		-- where somebody is (`PlayerState`) is the only position this game trusts for damage anywhere.
		local hitSomebody = false
		for _, person in participants(self) do
			if projectile.hitPlayers[person.id] then
				continue
			end
			local chest = person.position + Vector3.new(0, 2.2, 0)
			local toChest = chest - projectile.position
			local along = math.clamp(toChest:Dot(projectile.direction), 0, step)
			local closest = projectile.position + projectile.direction * along
			if (chest - closest).Magnitude > boulder.radius + 1.8 then
				continue
			end
			projectile.hitPlayers[person.id] = true
			hitSomebody = true
			EncounterHints.announce(person.id, "Unlittius")
			local state = PlayerState.get(person.id)
			local maximum = if state ~= nil then state.wax.max else 1
			WaxService.drainExternal(
				person.id,
				maximum * boulder.damage,
				"DamageThreat" :: Types.WaxSource,
				"A conjured boulder caught you.",
				{ kind = "Hit", seconds = 1.2 },
				"Unlittius"
			)
			CharacterService.pushRunBody(person.id, projectile.direction, boulder.knockback)
		end
		if hitSomebody then
			boulderImpact(self, projectile, projectile.position)
			destroyProjectile(self, index)
			continue
		end

		-- THEN THE CAVE. Terrain and built geometry stop a boulder; his own body cannot, because it is
		-- filtered out — a stone that clipped the shoulder it was conjured beside would die on frame one.
		local result =
			workspace:Spherecast(projectile.position, boulder.radius, projectile.direction * step, parameters)
		if result ~= nil then
			boulderImpact(self, projectile, result.Position)
			destroyProjectile(self, index)
			continue
		end

		projectile.position = nextPosition
		projectile.travelled += step
		projectile.part.CFrame = CFrame.new(nextPosition)
		if projectile.travelled >= boulder.maxDistance then
			boulderImpact(self, projectile, nextPosition)
			destroyProjectile(self, index)
		end
	end
end

-- WHO EACH SHOT IS FOR, decided once when the burst begins and delegated to the pure rules so the
-- minimum-engagement geometry (see `UnlittiusRules.boulderTargets`) is enforced in one place and can
-- be swept in a test rather than discovered in a playtest.
local function chooseBoulderTargets(self: Boss)
	table.clear(self.boulderTargets)
	local candidates: { UnlittiusRules.BoulderCandidate } = {}
	for _, person in participants(self) do
		table.insert(candidates, { id = person.id, distance = person.distance })
	end
	for _, id in UnlittiusRules.boulderTargets(candidates) do
		table.insert(self.boulderTargets, id)
	end
end

--------------------------------------------------------------------------------
-- MELEE
--------------------------------------------------------------------------------

-- ONE RAKE. Reach and arc are tested from his root against the server's own record of where people
-- are, and the swipe is resolved for every player in the arc — a rake is a sweep, not a single
-- target — but only ONCE per player per swipe.
local function resolveRake(self: Boss, secondSwipe: boolean)
	local melee = config().melee
	local root = self.body.root
	local facing = self.body.anchorCFrame.LookVector
	local hit = 0
	for _, person in participants(self) do
		if person.distance > melee.reach then
			continue
		end
		if not UnlittiusRules.insideArc(root.Position, facing, person.position, melee.arcDot) then
			continue
		end
		hit += 1
		EncounterHints.announce(person.id, "Unlittius")
		local state = PlayerState.get(person.id)
		local maximum = if state ~= nil then state.wax.max else 1
		WaxService.drainExternal(
			person.id,
			maximum * melee.damagePerSwipe,
			"DamageThreat" :: Types.WaxSource,
			"His talons opened you up over the dais.",
			-- An impact SPAN rather than a standalone hit: the two rakes are a quarter of a second
			-- apart, so a Candle Sleeve should pay for the pair once rather than twice.
			{ kind = "Hit", seconds = 0.6 },
			"Unlittius"
		)
		if secondSwipe then
			local away = person.position - root.Position
			local flat = Vector3.new(away.X, 0, away.Z)
			if flat.Magnitude > 0.01 then
				CharacterService.pushRunBody(person.id, flat.Unit, melee.knockbackSecondSwipe)
			end
		end
	end
	-- FROM THE CLAW THAT SWUNG. The two rakes are 0.26s apart from opposite hands, so they get both a
	-- different position and a different recording.
	EnemyAudio.playVariantAt(
		self.body:meleeTrace(if secondSwipe then 1 else -1).Position,
		"UnlittiusMeleeSwipe",
		2,
		if secondSwipe then 1 else 0
	)
	if hit > 0 then
		Remotes.get("RunEvent"):FireAllClients("unlittiusRake", {
			position = self.body:meleeTrace(if secondSwipe then 1 else -1).Position,
			depth = self.depth,
			second = secondSwipe,
		})
	end
end

--------------------------------------------------------------------------------
-- THE DIRECTOR
--------------------------------------------------------------------------------

-- HOW MANY OF HIS GNAWERS ARE STILL STANDING, by looking rather than by counting. Every behaviour in
-- the pack sets `destroyed` when its body goes, so pruning the list is the whole implementation — and
-- it cannot drift the way a decrementing counter can when a floor is retired underneath him, when a
-- Gnawer is cleared by the laboratory's REMOVE ALL, or when one dies to something that never told him.
local function pruneSummoned(self: Boss): number
	for index = #self.summoned, 1, -1 do
		local gnawer = self.summoned[index]
		if gnawer == nil or gnawer.destroyed then
			table.remove(self.summoned, index)
		end
	end
	return #self.summoned
end

--------------------------------------------------------------------------------
-- MOVEMENT
--------------------------------------------------------------------------------

-- HE DRIFTS. This is the whole of his locomotion and there is deliberately nothing else: no
-- pathfinding, no navmesh, no Humanoid, no walk cycle. He picks a direction from
-- `UnlittiusRules.driftIntent`, eases his velocity toward it, and is clamped inside the chamber.
--
-- HE STOPS DEAD ONCE AN ATTACK HAS COMMITTED (`movement.freezeDuringAttacks`). That is a fairness
-- rule rather than a stylistic one: the dripstone markers are placed relative to where players are
-- when the telegraph starts, and the rake's arc is tested against his facing at contact. A boss who
-- kept sliding through his own windup would make every one of those a lie — so the moment he begins
-- anything but an idle, the velocity is bled off and he holds station until it ends.
-- CAN HE SEE THEM? The one question his whole mobility exists to answer, and the only raycast in the
-- encounter that is not a projectile.
--
-- Cast from his chest to theirs, ignoring his own body and every character: what we are asking about
-- is COVER — a pillar, a fallen stone, a formation — not whether a teammate is standing in the way.
-- Nothing here decides damage; a blocked shot is still resolved by the projectile's own spherecast.
local function hasLineOfSight(self: Boss, target: Vector3): boolean
	local origin = self.body:chestPosition()
	local delta = (target + Vector3.new(0, 2.2, 0)) - origin
	if delta.Magnitude < 0.01 then
		return true
	end
	-- EXCLUDE HIS OWN BODY AND EVERY CHARACTER. Bodies are parented straight into `workspace` in this
	-- game rather than into a folder, so the list is built from the players themselves — otherwise a
	-- teammate standing between them would read as cover and he would sidestep away from a shot he
	-- actually had.
	local ignore: { Instance } = { self.body.model }
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignore, character)
		end
	end
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = ignore
	parameters.IgnoreWater = true
	return workspace:Raycast(origin, delta, parameters) == nil
end

local function stepMovement(self: Boss, dt: number, now: number)
	local movement = config().movement
	local committed = movement.freezeDuringAttacks and self.action ~= Protocol.actions.idle

	local people = participants(self)
	local nearest = people[1]
	-- LINE OF SIGHT IS SAMPLED, NOT TESTED EVERY FRAME. A raycast per frame per boss is affordable but
	-- pointless: cover does not appear and disappear at 60Hz, and re-deciding four times a second is
	-- what stops him twitching between "I can see you" and "I cannot" on the edge of a pillar.
	if nearest ~= nil and now >= self.nextSightCheckAt then
		self.nextSightCheckAt = now + 0.25
		self.sightBlocked = not hasLineOfSight(self, nearest.position)
	elseif nearest == nil then
		self.sightBlocked = false
	end

	local intent: UnlittiusRules.DriftIntent = if committed
		then "Hold"
		else UnlittiusRules.driftIntent({
			nearestDistance = if nearest ~= nil then nearest.distance else nil,
			hasLineOfSight = not self.sightBlocked,
			distanceFromHome = UnlittiusRules.flatDistance(self.body.anchorCFrame.Position, self.daisPosition),
		})

	-- WHICH WAY HE CIRCLES IS HELD, not re-rolled per frame: a sign that flipped every tick would read
	-- as a body vibrating rather than as one choosing a side.
	if now >= self.lateralHoldUntil then
		self.lateralHoldUntil = now + movement.lateralHoldSeconds
		self.lateralSign = if self.rng:NextNumber() < 0.5 then -1 else 1
	end

	local origin = self.body.anchorCFrame.Position
	local direction = UnlittiusRules.driftDirection(
		intent,
		origin,
		if nearest ~= nil then nearest.position else nil,
		self.daisPosition,
		self.lateralSign
	)
	local desired = direction * UnlittiusRules.driftSpeed(intent)
	self.velocity = UnlittiusRules.stepVelocity(self.velocity, desired, dt)
	self.body:setTravel(self.velocity)

	-- HIM MOVING, HEARD. A body this size being carried across a room should not be silent, and in a
	-- chamber lit by candles it is often the only way to place him. Emitted periodically while he is
	-- genuinely under way rather than as a loop: his speed varies constantly, and a fixed bed would
	-- either drone under a stationary boss or cut out every time he stopped to attack.
	if self.velocity.Magnitude > movement.driftSpeed * 0.5 and now >= self.nextDriftSoundAt then
		self.nextDriftSoundAt = now + 2.2 + self.rng:NextNumber() * 1.4
		EnemyAudio.playAt(self.body.root.Position, "UnlittiusDrift")
	end

	if self.velocity.Magnitude > 1e-4 then
		self.body:moveBy(self.velocity * dt)
		-- INSIDE THE ROOM, ALWAYS. Clamped against the chamber he was actually built in rather than
		-- against an assumed radius, and the velocity is killed on contact so he settles against the
		-- limit instead of grinding along it for the rest of the fight.
		local clamped, corrected =
			UnlittiusRules.clampToChamber(self.body.anchorCFrame.Position, self.daisPosition, self.chamberRadius)
		if corrected then
			self.body:setPosition(clamped)
			self.velocity = Vector3.zero
			self.lateralHoldUntil = 0
		end
	end

	-- HE WATCHES WHOEVER IS NEAREST, whatever he is doing. Turning is not suppressed during an attack
	-- the way translation is: a rake that could not track at all would be trivially side-stepped, and
	-- the turn is slow enough (`turnDegreesPerSecond`) that getting behind him still works.
	if nearest ~= nil then
		self.body:faceToward(nearest.position, dt, movement.turnDegreesPerSecond)
	end
end

--------------------------------------------------------------------------------
-- HIS VOICE
--------------------------------------------------------------------------------

-- HE MUTTERS. Between attacks, from his head, in a language nobody speaks.
--
-- THE BAG IS THE WHOLE TRICK. Twelve utterances are shuffled into an order and emptied one at a time;
-- when it runs out a fresh bag is shuffled that cannot open on the line the last one closed with. A
-- player therefore hears all twelve before any of them comes round again, which is the difference
-- between a boss who talks and a boss with a sound effect on a timer.
--
-- FROM HIS HEAD, NOT HIS CHEST. The rune is where his power is; the voice is where his face is, and
-- in a chamber this dark being able to hear roughly where he is looking is worth the extra attachment.
local function speak(self: Boss, now: number)
	local voice = config().voice
	if #self.voiceBag == 0 then
		self.voiceBag = UnlittiusRules.shuffledVoiceBag(self.rng, self.lastVoiceLine)
	end
	local line = table.remove(self.voiceBag, 1)
	if line == nil then
		return
	end
	self.lastVoiceLine = line
	self.nextVoiceAt = now + UnlittiusRules.nextVoiceDelay(self.rng:NextNumber())

	local head = self.rig ~= nil and self.rig.attachments.HeadFX or nil
	local from = if head ~= nil then head.WorldPosition else self.body:chestPosition()
	EnemyAudio.playAt(
		from,
		"UnlittiusVoice" .. line,
		UnlittiusRules.voicePitch(self.candlesLit, self.candleTarget),
		UnlittiusRules.voiceGain(self.candlesLit, self.candleTarget)
	)
	local _ = voice
end

-- THE ONE TIME HE IS NOT MUTTERING BUT CASTING. Played on the summon's held pose, where the words and
-- the arms-up silhouette land together — the only moment in the fight the language is doing something
-- rather than just being overheard.
local function incant(self: Boss)
	local count = math.max(math.floor(config().voice.incantationCount), 1)
	self.incantIndex = self.incantIndex % count + 1
	local head = self.rig ~= nil and self.rig.attachments.HeadFX or nil
	local from = if head ~= nil then head.WorldPosition else self.body:chestPosition()
	EnemyAudio.playAt(
		from,
		"UnlittiusIncant" .. self.incantIndex,
		UnlittiusRules.voicePitch(self.candlesLit, self.candleTarget),
		nil
	)
	-- The incantation counts as him having spoken: he must not mutter over the back half of his own
	-- ritual.
	self.nextVoiceAt = workspace:GetServerTimeNow() + UnlittiusRules.nextVoiceDelay(self.rng:NextNumber())
end

local function rememberAction(self: Boss, action: UnlittiusRules.ActionId)
	table.insert(self.recent, 1, action)
	while #self.recent > 4 do
		table.remove(self.recent)
	end
end

local function selectAction(self: Boss, now: number)
	local people = participants(self)
	if #people == 0 then
		-- Nobody in the room. He waits — and does not bank up actions to fire the moment somebody
		-- walks back in, which is what a scheduler that kept running would do.
		self.nextActionAt = now + 1.0
		return
	end

	local melee = config().melee
	local nearest = people[1]
	local meleeCandidate = nearest.distance <= melee.triggerRadius
		and UnlittiusRules.insideArc(
			self.body.root.Position,
			self.body.anchorCFrame.LookVector,
			nearest.position,
			-- A wider gate than the rake's own arc: he TURNS toward whoever is under him before he
			-- swings, so the decision only has to know somebody is close, not that they are already
			-- lined up.
			-0.2
		)

	local action = UnlittiusRules.chooseAction({
		meleeCandidate = meleeCandidate,
		meleeReady = now >= self.nextMeleeAt,
		summonEligible = UnlittiusRules.summonEligible(pruneSummoned(self), now, self.nextSummonAt),
		candlesLit = self.candlesLit,
		recent = self.recent,
		roll = self.rng:NextNumber(),
	})

	local timings = config().timings
	if action == "Melee" then
		self.meleeTarget = nearest.id
		self.nextMeleeAt = now + melee.cooldownSeconds
		beginAction(self, Protocol.actions.melee, timings.meleeLength, now)
	elseif action == "BoulderBurst" then
		chooseBoulderTargets(self)
		beginAction(self, Protocol.actions.boulder, timings.boulderLength, now)
	elseif action == "SummonGnawers" then
		self.nextSummonAt = now + config().summon.cooldownSeconds
		beginAction(self, Protocol.actions.summon, timings.summonLength, now)
	else
		beginAction(self, Protocol.actions.dripstone, timings.dripstoneLength, now)
		startDripstone(self, now)
	end
	rememberAction(self, action)
end

-- The authoritative beats of whatever he is doing, resolved in timeline order.
local function stepAction(self: Boss, now: number)
	local timings = config().timings
	local action = self.action

	if action == Protocol.actions.dripstone then
		if beat(self, "snap", timings.dripstoneSnapAt, now) then
			releaseDripstone(self)
		end
	elseif action == Protocol.actions.boulder then
		if beat(self, "conjure", timings.boulderConjureAt, now) then
			-- BOTH SHOULDERS, because both stones are assembling out there at once.
			for _, conjureSide in { -1, 1 } do
				EnemyAudio.playAt(self.body:boulderOrigin(conjureSide).Position, "UnlittiusBoulderConjure")
			end
		end
		if beat(self, "fire1", timings.boulderFire1At, now) then
			fireBoulder(self, -1, self.boulderTargets[1], now)
		end
		if beat(self, "fire2", timings.boulderFire2At, now) then
			fireBoulder(self, 1, self.boulderTargets[2] or self.boulderTargets[1], now)
		end
	elseif action == Protocol.actions.summon then
		if beat(self, "charge", 0.25, now) then
			EnemyAudio.playAt(self.body:chestPosition(), "UnlittiusSummonRise")
		end
		-- THE WORDS, on the way into the held pose rather than at the start of the wind-up: the arms are
		-- already up and the language arrives with the shape.
		if beat(self, "incant", 0.9, now) then
			incant(self)
		end
		if beat(self, "spawn", timings.summonSpawnAt, now) then
			local spawner = self.onSummon
			local wanted = UnlittiusRules.summonCount(#participants(self), pruneSummoned(self))
			if spawner ~= nil then
				for index = 1, wanted do
					local point = UnlittiusRules.summonPoint(self.daisPosition, index, wanted, self.rng:NextNumber())
					local floorY = groundY(self, point)
					if floorY == nil then
						continue
					end
					local gnawer = spawner(Vector3.new(point.X, floorY, point.Z))
					if gnawer ~= nil then
						table.insert(self.summoned, gnawer)
						local arrival = Vector3.new(point.X, floorY, point.Z)
						-- THE FLOOR OPENING, AT THE PLACE IT OPENS. One per arrival rather than one for the
						-- summon: two Gnawers surfacing on opposite sides of the chamber are two events.
						EnemyAudio.playAt(arrival, "UnlittiusGnawerSpawn")
						Remotes.get("RunEvent"):FireAllClients("unlittiusSummon", {
							position = arrival,
							depth = self.depth,
						})
					end
				end
			end
			-- The ritual is loud, and it is the one action of his that should pull the rest of the
			-- floor toward the chamber.
			NoiseService.emit("DripstoneImpact", self.body.root.Position, nil)
			ThreatService.alertAll(self.depth, self.body.root.Position, 120, 10)
		end
	elseif action == Protocol.actions.melee then
		if beat(self, "windup", 0.08, now) then
			EnemyAudio.playAt(self.body:meleeTrace(-1).Position, "UnlittiusMeleeWindup")
		end
		if beat(self, "hit1", timings.meleeHit1At, now) then
			resolveRake(self, false)
		end
		if beat(self, "hit2", timings.meleeHit2At, now) then
			resolveRake(self, true)
		end
	end
end

--------------------------------------------------------------------------------
-- BANISH
--------------------------------------------------------------------------------

-- WHERE THE CEILING IS, over his own shrine. The banish's last two beats belong to the rock rather
-- than to him — he is being pressed into it — so they are emitted from up there, which is also where
-- the relief ends up and where a player will be looking.
local function ceilingPoint(self: Boss): Vector3
	return Vector3.new(
		self.daisPosition.X,
		self.daisPosition.Y + self.ceilingHeight - config().banish.ceilingInset,
		self.daisPosition.Z
	)
end

-- SWAP THE LIVE RIG FOR THE ANCHORED RELIEF. The animated body is destroyed rather than parked in the
-- ceiling: an idle Motor6D chain the engine keeps solving for the rest of the run, inside rock nobody
-- will look at again, is a cost with no return. The relief is built from the same proportions
-- (`Enemies/Unlittius.relief`) so the swap has nothing to line up.
local function swapToRelief(self: Boss)
	if self.relief ~= nil then
		return
	end
	local parent = self.body.model.Parent
	if parent == nil then
		return
	end
	local relief = UnlittiusModule.relief(self.variant, self.depth * 7919)
	-- Face down, at the ceiling, over the dais he was pulled off.
	local ceiling = ceilingPoint(self)
	relief:PivotTo(
		CFrame.new(ceiling)
			* CFrame.Angles(0, math.atan2(self.body.anchorCFrame.LookVector.X, self.body.anchorCFrame.LookVector.Z), 0)
	)
	relief.Parent = parent
	self.relief = relief

	for _, part in self.body.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 1
		end
	end
	self.body.rig.runeLight.Enabled = false
	Remotes.get("RunEvent"):FireAllClients("unlittiusRelief", {
		position = Vector3.new(self.daisPosition.X, ceiling, self.daisPosition.Z),
		depth = self.depth,
	})
	EnemyAudio.playAt(ceilingPoint(self), "UnlittiusBanishSeal")
end

local function stepBanish(self: Boss, now: number)
	local banish = config().banish
	local elapsed = now - self.banishStartedAt
	local progress = math.clamp(elapsed / math.max(banish.completeAt, 0.001), 0, 1)

	-- HE IS PULLED BACK OVER HIS OWN SHRINE BEFORE HE IS PULLED UP. Necessary rather than decorative
	-- now that he drifts: the eighth candle can land while he is anywhere in the chamber, and a relief
	-- that appeared in the ceiling over a random patch of floor would read as a bug rather than as the
	-- end of a ritual. It also gives the unbind something to be — the room taking hold of him and
	-- dragging him home — during a beat that was otherwise just a rune flickering.
	if elapsed < banish.unbindSeconds then
		local home = Vector3.new(self.daisPosition.X, self.body.anchorCFrame.Position.Y, self.daisPosition.Z)
		local eased = math.clamp(elapsed / math.max(banish.unbindSeconds, 0.001), 0, 1)
		-- Smoothstep, so the drag starts gently and arrives without a snap.
		local blend = eased * eased * (3 - 2 * eased)
		self.body:setPosition(self.banishFrom:Lerp(home, blend))
	elseif not self.firedBeats.homed then
		self.firedBeats.homed = true
		self.body:setPosition(Vector3.new(self.daisPosition.X, self.body.anchorCFrame.Position.Y, self.daisPosition.Z))
	end
	-- How far he has to travel: from his float height to the ceiling, less the depth he ends up
	-- embedded at. Measured off the chamber rather than assumed, so a shorter room still works.
	local rise = math.max(self.ceilingHeight - config().body.hoverHeight - banish.ceilingInset, 0)
	self.body:applyBanish(progress, rise)

	if beat(self, "unbind", 0, now) then
		EnemyAudio.playAt(self.body:chestPosition(), "UnlittiusBanishUnbind")
	end
	-- THE CRY. From his head, at full pitch and full volume regardless of how dim the candles have left
	-- him: everything else he says fades as he is put out, and this one deliberately does not. It is the
	-- last thing he has and he spends all of it.
	if beat(self, "cry", banish.cryAt, now) then
		local head = self.rig ~= nil and self.rig.attachments.HeadFX or nil
		EnemyAudio.playAt(if head ~= nil then head.WorldPosition else self.body:chestPosition(), "UnlittiusBanishCry")
	end
	-- THE LAST WORD, cut off by the seal a moment later. Emitted from the CEILING he is already inside
	-- rather than from his body, so it arrives from where the stone is closing over him.
	if beat(self, "lastWord", banish.lastWordAt, now) then
		EnemyAudio.playAt(ceilingPoint(self), "UnlittiusLastWord")
	end
	if beat(self, "pull", banish.unbindSeconds, now) then
		EnemyAudio.playAt(self.body.root.Position, "UnlittiusBanishRise")
	end
	if beat(self, "embed", banish.alignSeconds, now) then
		-- FROM THE CEILING, not from him. He is being pressed into rock above the chamber and the scrape
		-- belongs to the rock; a player looking up should hear it where they are looking.
		EnemyAudio.playAt(ceilingPoint(self), "UnlittiusBanishEmbed")
	end
	if beat(self, "swap", banish.reliefSwapAt, now) then
		swapToRelief(self)
	end
	if not self.banished and elapsed >= banish.completeAt then
		self.banished = true
		self.body.model:SetAttribute(Protocol.boss.attributes.action, Protocol.actions.banish)
		local finished = self.onBanished
		if finished ~= nil then
			finished()
		end
		Telemetry.event("unlittius_banished", nil, { depth = self.depth })
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function UnlittiusBehavior.new(
	cframe: CFrame,
	depth: number,
	familyId: string?,
	seed: number?,
	chamberRadius: number?,
	ceilingHeight: number?
): Boss
	local variant = EnemyVariantRules.variantForFamily(familyId)
	-- The CFrame handed in is the DAIS: the floor he is anchored over. He floats above it, and every
	-- ground-seeking part of the fight measures from the dais rather than from him.
	local dais = cframe.Position
	local floating = CFrame.new(dais + Vector3.new(0, config().body.hoverHeight, 0)) * (cframe - dais)
	local body = UnlittiusModule.new(floating, variant, seed)
	body.root.Anchored = true

	local self: Boss = setmetatable({
		body = body,
		depth = depth,
		variant = variant,
		destroyed = false,
		registryEntry = nil,
		daisPosition = dais,
		chamberRadius = chamberRadius or 30,
		fallbackGroundY = nil,
		action = Protocol.actions.idle,
		actionStartedAt = 0,
		actionEndsAt = 0,
		nextActionAt = 0,
		recent = {},
		firedBeats = {},
		zones = {},
		projectiles = {},
		summoned = {},
		nextSummonAt = 0,
		nextMeleeAt = 0,
		meleeTarget = nil,
		velocity = Vector3.zero,
		lateralSign = 1,
		lateralHoldUntil = 0,
		impactVariant = 0,
		nextDriftSoundAt = 0,
		sightBlocked = false,
		nextSightCheckAt = 0,
		voiceBag = {},
		lastVoiceLine = nil,
		-- He does not speak the moment he is built: the first mutter lands a few seconds after somebody
		-- has actually walked in on him.
		nextVoiceAt = 0,
		incantIndex = 0,
		rig = body.rig,
		boulderTargets = {},
		candlesLit = 0,
		candleTarget = config().encounter.candleCount,
		banishing = false,
		banished = false,
		banishStartedAt = 0,
		banishFrom = Vector3.zero,
		relief = nil,
		ceilingHeight = ceilingHeight or 40,
		awake = false,
		rng = Random.new(seed or 1),
		onSummon = nil,
		onBanished = nil,
	}, UnlittiusBehavior)

	local model = body.model
	model:SetAttribute(Protocol.boss.attributes.depth, depth)
	model:SetAttribute(Protocol.boss.attributes.candlesLit, 0)
	model:SetAttribute(Protocol.boss.attributes.power, 1)
	model:SetAttribute(Protocol.boss.attributes.action, Protocol.actions.idle)
	CollectionService:AddTag(model, Protocol.boss.tag)
	body:setPower(0, UnlittiusRules.runeBrightness(0))

	self.registryEntry = UnlittiusRegistry.register({
		depth = depth,
		position = function(): Vector3?
			if self.destroyed or model.Parent == nil then
				return nil
			end
			return body.root.Position
		end,
		candleLit = function(candlesLit: number)
			self:candleLit(candlesLit)
		end,
		banish = function()
			self:beginBanish()
		end,
		banished = function(): boolean
			return self.banished
		end,
	})

	EnemyAudio.attachLoop(model, "UnlittiusTension")
	return self
end

-- The flat floor height to use where there is no Terrain, for the developer laboratory. Same escape
-- hatch the Queen and the Wax Grub take, and for the same reason: every ground probe in this file
-- would otherwise refuse in a room built out of Parts.
function UnlittiusBehavior.setGroundFallback(self: Boss, y: number?)
	self.fallbackGroundY = y
end

-- How many candles the encounter actually seated. Handed down so his dim steps match the shrine that
-- was really built rather than the one the config describes.
function UnlittiusBehavior.setCandleTarget(self: Boss, total: number)
	self.candleTarget = math.max(math.floor(total), 1)
end

function UnlittiusBehavior.setChamber(self: Boss, radius: number, ceilingHeight: number)
	self.chamberRadius = radius
	self.ceilingHeight = ceilingHeight
end

-- A CANDLE CAUGHT. The single most important entry point in the encounter, and the only thing that
-- ever changes how the fight is going.
--
-- IT TAKES THE TOTAL, NOT AN INCREMENT. Two players finishing their holds on the same frame produce
-- two calls with counts 7 and 8, in whatever order the service resolved them; taking a maximum means
-- the second one cannot dim him back up, cannot replay a recoil he is already playing, and cannot
-- start a second banish.
function UnlittiusBehavior.candleLit(self: Boss, candlesLit: number)
	if self.destroyed or self.banishing then
		return
	end
	if candlesLit <= self.candlesLit then
		return
	end
	self.candlesLit = candlesLit
	self.body:setPower(candlesLit, UnlittiusRules.runeBrightness(candlesLit, self.candleTarget))

	local now = workspace:GetServerTimeNow()
	-- THE RECOIL TAKES PRIORITY OVER EVERYTHING EXCEPT THE BANISH, and it always plays: a candle that
	-- did not visibly hurt him is a candle the player cannot tell counted.
	--
	-- WHAT IT DOES NOT DO IS REWIND. Beats that already fired stay fired — a boulder in the air stays
	-- in the air, a rake that landed stays landed — because `beginAction` only clears the record of
	-- which beats are PENDING. `canInterruptFor` is consulted purely to decide whether the rest of the
	-- action was still cancellable, which is a fact worth recording rather than acting on differently:
	-- either way the recoil starts now, and either way nothing that already happened is undone.
	local wasInterruptible = UnlittiusRules.canInterruptFor(self.action, now - self.actionStartedAt)
	beginAction(self, Protocol.actions.recoil, config().timings.recoilLength, now)
	-- Downtime after a recoil is short: the recoil IS the pause, and a boss who then stood still for
	-- three more seconds would make lighting a candle a way to turn the fight off.
	self.nextActionAt = now + config().timings.recoilLength + 0.4
	-- THE WOUND AND WHAT IT COSTS HIM. The recoil walks three recordings so eight candles never sound
	-- like one clip eight times, and the rune fade under it is pitched a little lower on each candle,
	-- so the set descends across the fight instead of repeating.
	EnemyAudio.playVariantAt(self.body:chestPosition(), "UnlittiusRecoil", 3, candlesLit)
	EnemyAudio.playAt(self.body:chestPosition(), "UnlittiusRuneDim")
	Remotes.get("RunEvent"):FireAllClients("unlittiusCandle", {
		depth = self.depth,
		candlesLit = candlesLit,
		total = config().encounter.candleCount,
		position = self.body:chestPosition(),
	})
	Telemetry.event(
		"unlittius_candle",
		nil,
		{ depth = self.depth, candlesLit = candlesLit, interruptedAttack = not wasInterruptible }
	)
end

-- THE EIGHTH CANDLE. Everything stops: no scheduling, no live stones, no boulders in the air. A
-- projectile that was already travelling is deleted rather than allowed to land, because the fight is
-- over and a player killed by a stone thrown by a banished god is a bug however defensible the
-- timeline is.
function UnlittiusBehavior.beginBanish(self: Boss)
	if self.destroyed or self.banishing then
		return
	end
	self.banishing = true
	self.banishStartedAt = workspace:GetServerTimeNow()
	self.banishFrom = self.body.anchorCFrame.Position
	self.velocity = Vector3.zero
	self.body:setTravel(Vector3.zero)
	table.clear(self.firedBeats)
	for index = #self.projectiles, 1, -1 do
		destroyProjectile(self, index)
	end
	for index = #self.zones, 1, -1 do
		clearZone(self.zones[index])
		table.remove(self.zones, index)
	end
	self.body:setState(Protocol.actions.banish)
	self.action = Protocol.actions.banish
	self.actionStartedAt = self.banishStartedAt
	self.body.model:SetAttribute(Protocol.boss.attributes.banishStartedAt, self.banishStartedAt)
	publishAction(self, Protocol.actions.banish, self.banishStartedAt)
	EnemyAudio.stopAll(self.body.model)
	EnemyAudio.playAt(self.body:chestPosition(), "UnlittiusBanishUnbind")
end

function UnlittiusBehavior.isBanished(self: Boss): boolean
	return self.banished
end

-- How many of his summoned Gnawers are still alive. Exposed for the developer laboratory's readout
-- and for anyone tuning `Config.Unlittius.summon.activeCap` against what the room actually holds.
function UnlittiusBehavior.liveGnawers(self: Boss): number
	return pruneSummoned(self)
end

local function announceToNearbyPlayers(self: Boss)
	local origin = self.body.root.Position
	local radius = config().encounter.sightingRadius
	for playerId, state in PlayerState.all() do
		if state.depth ~= self.depth or not state.alive or state.finished then
			continue
		end
		if (state.position - origin).Magnitude <= radius then
			EncounterHints.announce(playerId, "Unlittius")
			self.awake = true
		end
	end
end

function UnlittiusBehavior.step(self: Boss, dt: number, _now: number)
	if self.destroyed then
		return
	end
	local model = self.body.model
	if model.Parent == nil then
		self:destroy()
		return
	end
	-- SERVER TIME, NOT `os.clock()`. Every timeline in this encounter is shared with clients through
	-- replicated timestamps, and `workspace:GetServerTimeNow()` is the only clock both ends agree on.
	local now = workspace:GetServerTimeNow()

	self.body:step(dt)
	stepZones(self, now)

	if self.banishing then
		stepBanish(self, now)
		return
	end

	stepProjectiles(self, dt)
	announceToNearbyPlayers(self)

	-- HE MOVES. Drift, turn, and the chamber clamp — all of it suppressed the moment an attack commits.
	stepMovement(self, dt, now)

	stepAction(self, now)

	-- HE MUTTERS BETWEEN ATTACKS. Gated on being awake, idle and a couple of seconds clear of whatever
	-- he last did, so the language is something you overhear in the gaps rather than something shouted
	-- over a boulder.
	if self.awake and now >= self.nextVoiceAt and UnlittiusRules.canSpeak(self.action, now - self.actionStartedAt) then
		if self.nextVoiceAt == 0 then
			-- First sighting: wait a beat rather than greeting them the instant they cross the threshold.
			self.nextVoiceAt = now + UnlittiusRules.nextVoiceDelay(self.rng:NextNumber())
		else
			speak(self, now)
		end
	end

	if now >= self.actionEndsAt and self.action ~= Protocol.actions.idle then
		beginAction(self, Protocol.actions.idle, config().timings.idleLength, now)
		if self.nextActionAt < now then
			self.nextActionAt = now + UnlittiusRules.downtimeSeconds(self.candlesLit, self.rng:NextNumber())
		end
	end

	-- THE OPENING DELAY IS ARMED WHEN HE WAKES, NOT CHECKED AFTERWARDS, and that ordering is the whole
	-- of this. It used to be the `else` of the branch below — but `nextActionAt` starts at 0 and `now`
	-- is `GetServerTimeNow`, which is never anywhere near 0, so the first branch always matched first
	-- and the second was dead code. He opened with an attack on the same frame he noticed anybody,
	-- which is exactly the beat `director.openingDelaySeconds` exists to buy: a moment to look at him
	-- before the room starts moving.
	if self.awake and self.nextActionAt == 0 then
		self.nextActionAt = now + config().director.openingDelaySeconds
	elseif self.awake and self.action == Protocol.actions.idle and now >= self.nextActionAt then
		selectAction(self, now)
	end
end

function UnlittiusBehavior.destroy(self: Boss)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.registryEntry ~= nil then
		UnlittiusRegistry.unregister(self.registryEntry)
		self.registryEntry = nil
	end
	for index = #self.projectiles, 1, -1 do
		destroyProjectile(self, index)
	end
	for index = #self.zones, 1, -1 do
		clearZone(self.zones[index])
		table.remove(self.zones, index)
	end
	-- THE RELIEF OUTLIVES HIM ONLY WHILE THE FLOOR DOES. On a standing floor it is the proof he was
	-- banished into that ceiling and nothing removes it; but `destroy` is only ever called when the
	-- floor is being retired, and a carving left in a folder whose room no longer exists is a leak that
	-- accumulates one relief per boss floor for the rest of the session.
	local relief = self.relief
	if relief ~= nil and relief.Parent ~= nil then
		relief:Destroy()
	end
	self.relief = nil
	EnemyAudio.stopAll(self.body.model)
	self.onSummon = nil
	self.onBanished = nil
	self.body:destroy()
end

-- Read by RunOrchestrator's descent guard through the registry, never through an object reference.
function UnlittiusBehavior.activeAtDepth(depth: number): boolean
	return UnlittiusRegistry.activeAtDepth(depth)
end

return UnlittiusBehavior
