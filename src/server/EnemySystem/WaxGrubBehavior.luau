--!strict
-- One Wax Grub: where it crawls, what it latches onto, and what scares it off.
--
-- NO HUMANOID, NO PATHFINDING, DELIBERATELY. A brood is up to five bodies and the boss chamber runs a
-- brood alongside two Longarms, so five Humanoids and five `ComputeAsync` calls per brood is a cost
-- this creature does not earn: it crawls a few studs toward a point on the floor and never needs to
-- route around anything. It is steered directly and re-seated on measured Terrain every step, which
-- is also what keeps it glued to rough voxel ground that a naive lerp would bury it in or float it
-- over. If a grub ever needs to cross a room it should still not get a Humanoid — it should be
-- despawned and re-spawned with its brood.
--
-- TWO DEVIATIONS FROM THE PACK, both owner decisions recorded in Config/WaxGrub:
--   * IT FLEES FLARES, NOT BRIGHTNESS. The pack feeds `setIllumination` a continuous light reading;
--     this game already has four creatures that flee ambient light, so the grub is fed a spike (1)
--     only while a flare actually burns nearby and 0 otherwise. Same threshold, different input.
--   * IT FOLLOWS WAX TRAILS, slowly. The involuntary drip trail a lit player leaves
--     (server/DripTrailService) is wax on the floor, and a wax scavenger should want it. This is what
--     it does when no player is standing still to latch onto.
--
-- IT DRAINS THROUGH THE WAX SYSTEM, NOT FROM INSIDE THE MODULE. The pack writes a
-- `WaxDrainPerSecond` attribute and explicitly leaves application to the host; this reads that
-- attribute and spends it through `WaxService.drainExternal` like every other contact in the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local WaxGrubModule = require(ReplicatedStorage.Shared.Enemies.WaxGrub)
local EnemyVariantRules = require(ReplicatedStorage.Shared.Logic.EnemyVariantRules)
local PlayerState = require(script.Parent.Parent.PlayerState)
local WaxService = require(script.Parent.Parent.WaxService)
local DripTrailService = require(script.Parent.Parent.DripTrailService)
local NoiseService = require(script.Parent.Parent.NoiseService)
local SurfaceProbe = require(script.Parent.Parent.SurfaceProbe)
local EnemyRegistry = require(script.Parent.Parent.EnemyRegistry)
local EnemyAudio = require(script.Parent.EnemyAudio)
local EnemyMover = require(script.Parent.EnemyMover)
local EncounterHints = require(script.Parent.EncounterHints)

local WaxGrubBehavior = {}
WaxGrubBehavior.__index = WaxGrubBehavior

-- A player moving faster than this is "moving" and is ignored; slower and they are worth latching
-- onto. Well under run speed (16) so the grub only ever commits to somebody who has genuinely stopped.
local STILL_SPEED = 2.5
-- How far a grub will stray from the brood anchor it was spawned at. A brood is a place, not a patrol.
local WANDER_RADIUS = 14
local WANDER_REPICK_SECONDS = 3.2
local TRAIL_INTEREST_RADIUS = 26
-- Close enough to a wax drop to stop and start chewing it rather than keep crawling toward it.
-- Comfortably past `crawlToward`'s own stopping distance (0.4) so the approach always finishes
-- before the grub tries to eat.
local EAT_RANGE = 1.0

export type Grub = typeof(setmetatable(
	{} :: {
		body: any,
		depth: number,
		variant: EnemyVariantRules.Variant,
		home: Vector3,
		speed: number,
		-- Variant-and-elder multiplier for speeds the pack has never scaled (fleeSpeed,
		-- trailFollowSpeed). NOT for `speed` above, which is already variant-scaled by the pack.
		speedScale: number,
		-- How far the root sits above the rock, sampled once at spawn from the rest pose. See `seat`.
		rideHeight: number,
		-- Flat floor height for part-floored rooms, or nil in every real cave. See `seat`.
		fallbackGroundY: number?,
		registryEntry: any,
		destroyed: boolean,
		blastDamage: number,
		blastHitPoints: number,
		wanderTarget: Vector3?,
		nextWanderAt: number,
		-- The one wax drop currently being chewed, and when that bite finishes. Set only while the
		-- grub is parked over it (see EAT_RANGE) and cleared by any higher-priority interruption
		-- (stomp/flare flee, latching onto a player) so a resumed grub never claims to be mid-bite on
		-- a drop it is no longer standing over.
		eatingPoint: Types.TrailPoint?,
		eatEndsAt: number,
		latchedPlayerId: Types.PlayerId?,
		-- Landings still owed before THIS latch is shaken off. Rolled fresh on every latch (see
		-- `shakeStompsMin`/`Max`) and meaningless while unlatched, where one footfall is always enough.
		stompsToShake: number,
		rng: Random,
		-- `createdAt` of the most recent landing already answered, so one footfall scares this grub
		-- exactly once however many ticks the event stays in the field.
		lastStompAt: number,
		onDied: (() -> ())?,
	},
	WaxGrubBehavior
))

local function config()
	return Config.WaxGrub
end

-- Seat the body on measured Terrain. The whole reason this creature can skip pathfinding is that it
-- only ever moves across open floor, and the only thing open floor asks of it is that it stays on
-- the actual voxels rather than on the analytic field they were written from.
--
-- THE RIDE HEIGHT IS MEASURED ONCE AND REMEMBERED. Reading `GetExtentsSize()` here every frame — the
-- obvious way to write this — samples a body that is being posed by an animation, so the extents
-- breathe as the grub undulates and the creature bobs up and down out of the floor in time with its
-- own crawl cycle. It is also a full descendant walk per grub per frame, which a brood cannot afford.
--
-- `position` is where the ROOT wants to be, so the ground under it is `rideHeight` below. Returns nil
-- when nothing was measured there; see `crawlToward` for why that is a refusal rather than a hold.
--
-- A POINT QUERY, NOT A FOOTPRINT ONE. `tryGroundY` with a sample radius also fires eight rays around
-- the centre and refuses unless all of them agree with the centre's tangent plane to within
-- `maxPeripheralDeltaStuds`. That is the question a permanent placement has to pass and the wrong one
-- to ask on every step of a crawl: it answers "no" exactly where the cave floor is lumpy, and a grub
-- that cannot resolve its next foothold does not travel. THIS IS THE STUCK GRUB — a body playing its
-- crawl animation on the spot, having been told there is no ground one stud ahead of it on ground it is
-- visibly standing on. EnemyMover.reseat and ThreatService both ask for the centre point alone.
local function seat(self: Grub, position: Vector3): Vector3?
	local measured = SurfaceProbe.tryGroundY(position.Y - self.rideHeight, position.X, position.Z, 0)
	if measured == nil then
		-- A FLAT PART FLOOR, if this floor registered one (EnemyService.setGroundFallback). Only the
		-- developer laboratory ever does; a real cave has none, and a miss there means the grub really
		-- is at the edge of the carved rock.
		local fallback = self.fallbackGroundY
		if fallback ~= nil then
			return Vector3.new(position.X, fallback + self.rideHeight, position.Z)
		end
		return nil
	end
	return Vector3.new(position.X, measured + self.rideHeight, position.Z)
end

-- A flare burning within reach, as the 0/1 spike this creature reads instead of ambient brightness.
local function flareNearby(self: Grub): number
	local origin = self.body.root.Position
	local now = os.clock()
	for _, state in PlayerState.all() do
		if state.depth ~= self.depth or not state.isLit or state.flareEndsAt <= now then
			continue
		end
		if (state.position - origin).Magnitude <= 34 then
			return 1
		end
	end
	return 0
end

-- The nearest player who has actually stopped, and how far away they are.
local function stillPlayerNear(self: Grub): (Types.PlayerId?, BasePart?, number)
	local origin = self.body.root.Position
	local bestId: Types.PlayerId? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = config().senseRange
	for playerId, state in PlayerState.all() do
		if state.depth ~= self.depth or not state.alive or state.finished or state.snuffedAt ~= nil then
			continue
		end
		if PlayerState.isThreatProtected(playerId) then
			continue
		end
		local player = Players:GetPlayerByUserId(playerId)
		local character = if player ~= nil then player.Character else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or not root:IsA("BasePart") then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		if Vector3.new(velocity.X, 0, velocity.Z).Magnitude > STILL_SPEED then
			continue
		end
		local distance = (root.Position - origin).Magnitude
		if distance < bestDistance then
			bestId = playerId
			bestRoot = root
			bestDistance = distance
		end
	end
	return bestId, bestRoot, bestDistance
end

-- A FOOT COMING DOWN ON THIS GRUB.
--
-- Read out of the noise field rather than pushed in by whatever detects landings, which is what keeps
-- this creature from creating a dependency cycle: `DripTrailService` already emits a `Landing` event
-- at the exact moment a foot meets the floor, observed server-side from the Humanoid's own floor
-- material, so a client cannot claim to have stomped anything. The grub simply listens for one close
-- enough to be standing on it.
--
-- IT IS SCARED, NEVER KILLED. The player has no attack, and a grub that died to a footstep would make
-- the whole brood meaningless. What one landing BUYS depends on whether it is already latched — see
-- `stomped` below.
--
-- THIS ONLY WORKS BECAUSE A LATCHED GRUB DOES NOT COLLIDE (Enemies/WaxGrub.latchTo). The event is a
-- transition into grounded, and a collidable body riding under the player's boots is a floor that
-- follows them into the air: the Humanoid never reports Air, so the landing never happens and the
-- one counter to this creature is unreachable exactly while it is being used on you.
local function stompedThisTick(self: Grub): boolean
	local origin = self.body.root.Position
	local radius = config().stompRadius
	for _, event in NoiseService.events() do
		if event.kind ~= "Landing" or event.createdAt <= self.lastStompAt then
			continue
		end
		if (event.position - origin).Magnitude <= radius then
			self.lastStompAt = event.createdAt
			return true
		end
	end
	return false
end

-- The nearest wax drop on the floor. This is the grub's ambient purpose and the reason it reads as a
-- scavenger rather than as a small aggressive animal. Returns the whole point, not just its
-- position, because `eatingPoint` needs the (ownerId, createdAt) pair to remove exactly this drop
-- from the trail once it is eaten (DripTrailService.consume).
local function nearestTrailPoint(self: Grub): Types.TrailPoint?
	local origin = self.body.root.Position
	local best: Types.TrailPoint? = nil
	local bestDistance = TRAIL_INTEREST_RADIUS
	for _, point in DripTrailService.getTrail() do
		local distance = (point.position - origin).Magnitude
		if distance < bestDistance then
			best = point
			bestDistance = distance
		end
	end
	return best
end

-- `fallbackGroundY` is the flat floor height to crawl on when no Terrain can be measured. Supplied
-- only for part-floored rooms (the developer laboratory); nil everywhere else.
function WaxGrubBehavior.new(
	cframe: CFrame,
	depth: number,
	familyId: string?,
	seed: number?,
	fallbackGroundY: number?
): Grub
	local variant = EnemyVariantRules.variantForFamily(familyId)
	local body = WaxGrubModule.new(cframe, variant, seed)
	local model = body.model
	local elder = model:GetAttribute("Elder") == true

	-- THE ROOT IS ANCHORED. NOTHING ELSE IS, AND THAT DISTINCTION IS LOAD-BEARING.
	--
	-- This body is moved by writing the root's CFrame rather than by physics, so the root has to be
	-- anchored — an unanchored grub with no Humanoid would just fall over and slide. Every OTHER part
	-- must stay unanchored, because the grub is a Motor6D chain: `EnemyKit.finish` unanchors the whole
	-- model precisely so those joints can pose the segments, and a Motor6D cannot move a part that is
	-- anchored.
	--
	-- ANCHORING EVERY PART IS WHAT MAKES A GRUB RENDER AS ONE BOX. The segments are all created at the
	-- origin and only ever placed by their joints, so freezing the joints leaves eleven parts stacked
	-- inside each other, which `PivotTo` then carries around as a single cube. Worth spelling out
	-- because the broken version looks deliberate: it is one line, it reads as tidy, and the model it
	-- produces is a plausible-looking solid.
	--
	-- The unanchored parts are jointed to the anchored root, so they form one kinematic assembly that
	-- follows it exactly — which is the behaviour the anchor-everything version was reaching for.
	body.root.Anchored = true

	local self: Grub = setmetatable({
		body = body,
		depth = depth,
		variant = variant,
		home = cframe.Position,
		-- `body.speed` is ALREADY variant-scaled (WaxGrub.new: `Config.speed * stats.speed`), so only
		-- the elder factor belongs here — see EnemyVariantRules.elderSpeedMultiplier for why the
		-- obvious `speedMultiplier(variant, elder)` would apply the variant term a second time.
		speed = body.speed * EnemyVariantRules.elderSpeedMultiplier(elder),
		-- The variant-and-elder factor for values the PACK has never scaled — fleeSpeed and
		-- trailFollowSpeed are both this game's own numbers (Config/WaxGrub), so unlike `speed` above
		-- they need the full multiplier, once, applied where they are used below.
		speedScale = EnemyVariantRules.speedMultiplier(variant, elder),
		-- Measured from the REST pose, before a single frame of animation has run, and by the same
		-- function the Humanoid-driven bodies use so a grub sits on the rock exactly the way they do.
		rideHeight = EnemyMover.measureRideHeight(model, body.root),
		fallbackGroundY = fallbackGroundY,
		registryEntry = nil,
		destroyed = false,
		blastDamage = 0,
		blastHitPoints = config().blast.hitPoints,
		wanderTarget = nil,
		nextWanderAt = 0,
		eatingPoint = nil,
		eatEndsAt = 0,
		latchedPlayerId = nil,
		stompsToShake = 0,
		rng = Random.new(seed or os.clock() * 1000),
		lastStompAt = 0,
		onDied = nil,
	}, WaxGrubBehavior)

	-- SEAT IT ONCE, HERE. The spawner resolves a GROUND POINT (EnemyService.groundedCFrame) and
	-- `WaxGrubModule.new` pivots the model onto it, which puts the root — not the underside — on the
	-- rock and leaves the grub embedded in the floor until it happens to crawl. `seat` is asked for the
	-- root height that corresponds to that same ground point.
	local spawnSeat = seat(self, body.root.Position + Vector3.yAxis * self.rideHeight)
	if spawnSeat ~= nil then
		body.root.CFrame = CFrame.new(spawnSeat) * (body.root.CFrame - body.root.Position)
	end

	self.registryEntry = EnemyRegistry.register({
		depth = depth,
		position = function(): Vector3?
			if self.destroyed or model.Parent == nil or body.root.Parent == nil then
				return nil
			end
			return body.root.Position
		end,
		blast = function(damage: number): boolean
			return self:blast(damage)
		end,
	})

	EnemyAudio.attachLoop(model, "GrubIdle")
	return self
end

function WaxGrubBehavior.blast(self: Grub, damage: number): boolean
	if self.destroyed then
		return false
	end
	self.blastDamage += math.max(damage, 0)
	if self.blastDamage >= self.blastHitPoints then
		self.body:damage(self.body.health)
		return true
	end
	self.body:stomp()
	return false
end

-- A player's foot landed on this grub. It is SCARED, never killed: the player has no attack, and a
-- grub that dies to a footstep makes the whole brood meaningless.
function WaxGrubBehavior.stomp(self: Grub)
	if self.destroyed then
		return
	end
	self.stompsToShake = 0
	self.body:stomp()
end

-- ONE LANDING, ROUTED BY WHETHER IT IS ALREADY ON YOU.
--
-- A grub on the floor scatters from a single footfall — that is the "route around a brood" gesture
-- and it is unchanged. A grub that has LATCHED is the only fight this game gives the player, so it
-- costs the rolled `stompsToShake` landings and flinches for each one that is not the last. Rolled
-- per latch rather than per grub so the same creature is not always the same number of stomps.
local function stomped(self: Grub)
	if self.latchedPlayerId == nil then
		self:stomp()
		return
	end
	self.stompsToShake -= 1
	if self.stompsToShake <= 0 then
		self:stomp()
	else
		self.body:flinch()
	end
end

-- THE NUDGE THAT SAYS "STOMP". The one-shot teaching line (EncounterHints -> Feel.itemHints) fires
-- once per player ever, so a returning player who gets latched on floor 9 would otherwise have
-- nothing on screen at the moment it matters. Rate-limited per player across every grub, so a brood
-- landing on somebody one after another says this once and not five times. Keyed by user id and
-- never pruned: one number per player who has ever been latched on this server.
local nextHintAt: { [Types.PlayerId]: number } = {}

local function nudgeStomp(playerId: Types.PlayerId, now: number)
	if now < (nextHintAt[playerId] or 0) then
		return
	end
	nextHintAt[playerId] = now + config().shakeHintCooldownSeconds
	local player = Players:GetPlayerByUserId(playerId)
	if player ~= nil then
		Remotes.get("RunEvent")
			:FireClient(player, "message", { text = "A Wax Grub has latched on, jump on it to scare it off!" })
	end
end

function WaxGrubBehavior.isLatched(self: Grub): boolean
	return self.latchedPlayerId ~= nil
end

local function unlatch(self: Grub)
	if self.latchedPlayerId == nil then
		return
	end
	self.latchedPlayerId = nil
	self.body:unlatch()
end

-- Is there rock between the grub and where it wants to be? One short ray, only ever a stud or two
-- long because a crawl step is tiny.
--
-- THIS IS THE WHOLE OF ITS COLLISION, and deliberately so. The body is anchored and driven by CFrame,
-- which is the right trade for a creature this small and this numerous — it needs no ragdoll, no
-- knockback and no physics solver, and five unanchored bodies per brood shoving each other around a
-- cave floor would cost more than the creature is worth. What anchoring loses is the free answer to
-- "may I move here", so this buys that back for one raycast per grub per frame and nothing else.
local function blocked(from: Vector3, direction: Vector3, distance: number): boolean
	local floors = workspace:FindFirstChild("WickFloors")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if floors ~= nil then { workspace.Terrain, floors } else { workspace.Terrain }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	-- Cast from body height rather than from the floor: a ray along the ground clips every bump on a
	-- voxel surface and would report the cave itself as an obstruction on every step.
	local origin = from + Vector3.new(0, 0.9, 0)
	return workspace:Raycast(origin, direction * (distance + 0.6), params) ~= nil
end

-- Crawl one step toward a point, staying on measured ground and turning to face travel.
local function crawlToward(self: Grub, target: Vector3, dt: number, speed: number)
	local root = self.body.root
	local origin = root.Position
	local delta = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	local distance = delta.Magnitude
	if distance < 0.4 then
		return
	end
	local direction = delta.Unit
	local stepDistance = math.min(speed * dt, distance)
	if blocked(origin, direction, stepDistance) then
		-- Rock. Give up on this target and roll a new one next tick rather than grinding into the
		-- wall: a grub has no pathfinding and none of its destinations are important enough to route
		-- to. Turning to face the obstruction keeps it from reading as frozen.
		self.wanderTarget = nil
		self.nextWanderAt = 0
		root.CFrame = CFrame.lookAt(origin, origin + direction)
		return
	end
	local nextPosition = seat(self, origin + direction * stepDistance)
	if nextPosition == nil then
		-- NO MEASURED GROUND AHEAD, which is the edge of the carved rock. Treated exactly like running
		-- into a wall rather than by holding position: holding leaves the grub crawling on the spot
		-- against the same dead heading until the wander timer happens to expire, and re-rolling the
		-- target now sends it somewhere that does have a floor on the very next tick.
		self.wanderTarget = nil
		self.nextWanderAt = 0
		root.CFrame = CFrame.lookAt(origin, origin + direction)
		return
	end
	root.CFrame = CFrame.lookAt(nextPosition, nextPosition + direction)
end

function WaxGrubBehavior.step(self: Grub, dt: number, now: number)
	if self.destroyed then
		return
	end
	local model = self.body.model
	if model.Parent == nil then
		self:destroy()
		return
	end

	-- Catches `attack`, `eat` and the wander states, all of which are set late in the previous frame and
	-- so were invisible to the comparison below. See EnemyAudio.observe.
	EnemyAudio.observe(model, "Grub", self.body.state)

	local previousState = self.body.state
	if previousState ~= "death" then
		self.body:setIllumination(flareNearby(self))
		if stompedThisTick(self) then
			stomped(self)
		end
	end

	self.body:step(dt)
	local state = self.body.state
	if state ~= previousState then
		EnemyAudio.observe(model, "Grub", state)
	end

	if state == "death" then
		unlatch(self)
		self.eatingPoint = nil
		if self.body.stateT > 1.6 then
			self:destroy()
		end
		return
	end

	-- FLEEING. Straight away from home-ish, fast, and never latched.
	if state == "flee" then
		unlatch(self)
		self.eatingPoint = nil
		local origin = self.body.root.Position
		local away = origin - self.home
		local flat = Vector3.new(away.X, 0, away.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
		crawlToward(self, origin + direction * 6, dt, config().fleeSpeed * self.speedScale)
		return
	end

	-- LATCHED. Ride the player and bill them for it.
	local latchedId = self.latchedPlayerId
	if latchedId ~= nil then
		local latchedState = PlayerState.get(latchedId)
		local player = Players:GetPlayerByUserId(latchedId)
		local character = if player ~= nil then player.Character else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if
			latchedState == nil
			or root == nil
			or not root:IsA("BasePart")
			or not latchedState.alive
			or latchedState.finished
			or latchedState.snuffedAt ~= nil
			or latchedState.depth ~= self.depth
		then
			unlatch(self)
		else
			-- Read from the model attribute, exactly as the pack intends: the creature declares its
			-- appetite and the wax system is the only thing that spends it.
			local perSecond = tonumber(model:GetAttribute("WaxDrainPerSecond")) or 0
			if perSecond > 0 then
				WaxService.drainExternal(
					latchedId,
					perSecond * dt,
					"DamageThreat" :: Types.WaxSource,
					"A wax grub is feeding on your candle.",
					{ kind = "Continuous", seconds = dt },
					"WaxGrub"
				)
			end
			local anchorPoint = root.Position - Vector3.new(0, 1.4, 0)
			self.body.root.CFrame = CFrame.lookAt(anchorPoint, root.Position)
			return
		end
	end

	-- LATCH ON. Only onto somebody who has actually stopped, and only from touching distance.
	local stillId, stillRoot, stillDistance = stillPlayerNear(self)
	if stillId ~= nil and stillRoot ~= nil and stillDistance <= config().attackRange then
		self.eatingPoint = nil
		self.latchedPlayerId = stillId
		self.stompsToShake = self.rng:NextInteger(config().shakeStompsMin, config().shakeStompsMax)
		self.body:latchTo(stillRoot)
		self.body:setState("attack")
		EncounterHints.announce(stillId, "WaxGrub")
		nudgeStomp(stillId, now)
		return
	end

	-- WALK TO SOMEBODY WHO HAS STOPPED, if one is in sense range.
	if stillId ~= nil and stillRoot ~= nil then
		self.eatingPoint = nil
		self.body:setState("move")
		crawlToward(self, stillRoot.Position, dt, self.speed)
		return
	end

	-- EATING. Locked onto one specific wax drop and chewing through it — committed for the whole
	-- bite so a grub reads as consuming something rather than merely standing near it.
	if self.eatingPoint ~= nil then
		if now >= self.eatEndsAt then
			DripTrailService.consume(self.eatingPoint.ownerId, self.eatingPoint.createdAt)
			self.eatingPoint = nil
			-- One tick of "idle" between bites, deliberately: WaxGrubModule.setState no-ops on a
			-- same-state call, so without this a grub eating two drops back to back would never
			-- re-enter "eat" and the munching cue (EnemyAudio: Grub.eat) would only ever fire once.
			self.body:setState("idle")
		else
			self.body:setState("eat")
		end
		return
	end

	-- FOLLOW THE WAX, THEN EAT IT. Slower than a chase: this is scavenging, not hunting. Once close
	-- enough to a drop, stop and commit to the bite above instead of grazing past it.
	local trailPoint = nearestTrailPoint(self)
	if trailPoint ~= nil then
		local origin = self.body.root.Position
		local flat = Vector3.new(trailPoint.position.X - origin.X, 0, trailPoint.position.Z - origin.Z)
		if flat.Magnitude <= EAT_RANGE then
			self.eatingPoint = trailPoint
			self.eatEndsAt = now + config().eatSeconds
			self.body:setState("eat")
			return
		end
		self.body:setState("move")
		crawlToward(self, trailPoint.position, dt, config().trailFollowSpeed * self.speedScale)
		return
	end

	-- WANDER around the brood anchor. Never far: a brood is a place.
	if now >= self.nextWanderAt or self.wanderTarget == nil then
		self.nextWanderAt = now + WANDER_REPICK_SECONDS
		local angle = self.rng:NextNumber() * math.pi * 2
		local radius = self.rng:NextNumber() * WANDER_RADIUS
		self.wanderTarget = self.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end
	local target = self.wanderTarget
	if target ~= nil then
		local flat = Vector3.new(target.X - self.body.root.Position.X, 0, target.Z - self.body.root.Position.Z)
		if flat.Magnitude < 1.2 then
			self.body:setState("idle")
		else
			self.body:setState("move")
			crawlToward(self, target, dt, self.speed)
		end
	end
end

function WaxGrubBehavior.destroy(self: Grub)
	if self.destroyed then
		return
	end
	self.destroyed = true
	unlatch(self)
	if self.registryEntry ~= nil then
		EnemyRegistry.unregister(self.registryEntry)
		self.registryEntry = nil
	end
	EnemyAudio.stopAll(self.body.model)
	self.body:destroy()
	local died = self.onDied
	if died ~= nil then
		self.onDied = nil
		died()
	end
end

return WaxGrubBehavior
