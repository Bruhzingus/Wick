--!strict
-- The Stone Gnawer's server brain: what it hears, when it commits, and what a charge hits.
--
-- IT IS THE CAVE LISTENER'S BIGGER BROTHER, and that is a deliberate relationship rather than a
-- coincidence of both being deaf-and-blind. The Listener (Config/Threats.Listener) is the mining
-- threat: very sharp ears, walks at 9.75, and is escaped by going quiet and moving away. This one is
-- LESS perceptive and vastly more dangerous once roused — it hears less of the floor, and answers
-- with a 26-stud-per-second straight line that crosses a room before you have finished turning.
--
-- WHAT IT HEARS, and why it does not use the ordinary hearing profile. Every other eared creature in
-- the game reads `NoiseService` events, which describe what the CAVE hears: mining, falling stone,
-- dynamite, sprinting, landing. The Gnawer reads those too — but it also reads player MOVEMENT
-- directly, which nothing else in the game does. That is the one perception this creature has that
-- the roster does not, and it is confined to this file precisely so it stays that way: routing
-- movement through NoiseService would hand every hearing row a permanent track on every moving
-- player and turn the Cave Listener from a mining threat into an unavoidable one, which
-- Config/Sound's own comments are explicit must never happen.
--
-- THE CHARGE CANNOT STEER. `desiredVelocity()` is handed straight to the mover as a velocity
-- override and pathfinding is suspended for its whole duration. This is the entire counter to the
-- creature — sidestep and it commits past you — and correcting it mid-flight destroys the encounter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local StoneGnawerModule = require(ReplicatedStorage.Shared.Enemies.StoneGnawer)
local EnemyVariantRules = require(ReplicatedStorage.Shared.Logic.EnemyVariantRules)
local SoundField = require(ReplicatedStorage.Shared.Logic.SoundField)
local PlayerState = require(script.Parent.Parent.PlayerState)
local NoiseService = require(script.Parent.Parent.NoiseService)
local WaxService = require(script.Parent.Parent.WaxService)
local DripstoneService = require(script.Parent.Parent.DripstoneService)
local EnemyRegistry = require(script.Parent.Parent.EnemyRegistry)
local EnemyMover = require(script.Parent.EnemyMover)
local EnemyAudio = require(script.Parent.EnemyAudio)
local EncounterHints = require(script.Parent.EncounterHints)

local StoneGnawerBehavior = {}
StoneGnawerBehavior.__index = StoneGnawerBehavior

-- Scales every hearing radius on this creature. The owner's brief is that it should be LESS
-- perceptive than the Cave Listener (hearingRadius 95) and cover more ground when it does commit;
-- the pack's own `hearSprint` is 42, and this trims the movement channel further so a player who
-- keeps their distance genuinely goes unnoticed.
local MOVEMENT_HEARING_SCALE = 0.85

export type Gnawer = typeof(setmetatable(
	{} :: {
		body: any,
		mover: EnemyMover.Mover,
		depth: number,
		variant: EnemyVariantRules.Variant,
		elder: boolean,
		-- Cached once from the REST pose at construction. See the same reasoning EnemyMover records
		-- for `rideHeight`: reading these from a live `GetExtentsSize()` every frame of a charge would
		-- sample a body the charge animation is actively posing, so the hit reach would breathe with
		-- the gait, and it is a full descendant walk repeated on the one creature whose whole design is
		-- a fast, frequent per-frame collision check.
		bodyReach: number,
		bodyRadius: number,
		registryEntry: any,
		destroyed: boolean,
		blastDamage: number,
		blastHitPoints: number,
		-- The last point it decided to charge at. Kept so a charge that is interrupted before it
		-- begins still faces the right way.
		heardAt: Vector3?,
		lastChargeCollideAt: number,
		-- The newest landing already answered. Noise events live in the field for their whole decay
		-- (1.5s for a landing), so without this the same thump re-targets the creature on every tick of
		-- that window and a single hop reads as somebody jumping continuously. Same guard, and the same
		-- reason, as `WaxGrubBehavior.lastStompAt`.
		lastLandingAt: number,
		-- The newest dripstone impact already answered, for the same reason `lastLandingAt` exists: the
		-- event sits in the field for five whole seconds and would otherwise re-commit the creature on
		-- every tick of that window.
		lastDripstoneAt: number,
		-- GRAZING. `home` is where it was placed, and it is the anchor everything below orbits: a Gnawer
		-- is a feature of a room, not a patrol, so it must never wander out of the room it was budgeted
		-- into. `wanderTarget` is the current grazing spot and is re-rolled on `nextWanderAt`.
		home: Vector3,
		rng: Random,
		wanderTarget: Vector3?,
		nextWanderAt: number,
		-- HUNTING. Where it felt something break, when it will give up on getting there, and the
		-- newest event already answered so one collapse is one trip.
		huntTarget: Vector3?,
		huntUntil: number,
		lastHuntNoiseAt: number,
		-- When it next works its nose. Re-rolled from this creature's own rng after every snuffle.
		nextSnuffleAt: number,
	},
	StoneGnawerBehavior
))

local function config()
	return Config.StoneGnawer
end

-- Everything in the cave's own sound field, folded into the pack's `hearNoise(loudness, position)`
-- contract.
--
-- PERCEIVED loudness, not authored loudness: `SoundField.contributionOf` applies the event's distance
-- falloff and its time decay, which is the same figure every other eared creature in the game reasons
-- about. Reading the raw `loudness` field instead would make a pick strike across the floor as loud
-- as one at the creature's feet.
--
-- NO DEPTH FILTER IS NEEDED and none is applied. Noise events carry no depth, but floors sit 96 studs
-- apart (Config/Floors.geometry.floorGap) and this creature's own hearing tops out at 42 studs
-- (Config/StoneGnawer.hearSprint), so the pack's distance check inside `hearNoise` isolates it to its
-- own floor for free. That is worth stating rather than leaving to be rediscovered: if either number
-- ever changes such that the reach exceeds the gap, a Gnawer starts charging at the floor above.
local function feedCaveNoises(self: Gnawer, now: number)
	local listenAt = self.body.root.Position
	for _, event in NoiseService.events() do
		local contribution = SoundField.contributionOf(event, listenAt, now)
		if contribution <= 0 then
			continue
		end
		-- Normalized against a sprint (Config/StoneGnawer.sprintReferenceLoudness), which is what makes
		-- this creature's hearing radius scale with how loud the thing it heard actually was.
		local loudness = math.clamp(contribution / math.max(config().sprintReferenceLoudness, 1e-6), 0, 1)
		if loudness <= 0.05 then
			continue
		end
		self.body:hearNoise(loudness, event.position)
	end
end

-- LANDINGS, ON THIS CREATURE'S OWN REACH RATHER THAN THE FIELD'S.
--
-- The same shape as `feedPlayerMovement` above and for the same reason: the shared sound field cannot
-- express "this one creature hears this one event from further away". A landing's emitter dies at 30
-- studs, and that radius is holding up the Cave Listener's contract — widening it to suit the Gnawer
-- would make jumping summon Listeners across the room (Config/Sound.emitters.Landing says so
-- explicitly). So the reach is read from `hearLanding` and measured against the event's own position,
-- which is exactly what `WaxGrubBehavior.stompedThisTick` already does with the same event.
--
-- FULL LOUDNESS INSIDE THAT REACH. A body hitting rock is not a graded sound to this creature — it is
-- the thing that makes it lift its head — so anything within `hearLanding` commits it as hard as a
-- sprint at its shoulder does. The distance check IS the falloff.
--
-- Fed AFTER the cave noises so a landing wins the tick it happens on: `hearNoise` keeps the last
-- target it is handed, and the loudest, most recent thing should be what it charges.
local function feedLandings(self: Gnawer)
	local listenAt = self.body.root.Position
	local reach = config().hearLanding
	if reach <= 0 then
		return
	end
	for _, event in NoiseService.events() do
		if event.kind ~= "Landing" or event.createdAt <= self.lastLandingAt then
			continue
		end
		if (event.position - listenAt).Magnitude <= reach then
			self.lastLandingAt = event.createdAt
			-- `hearAt`, not `hearNoise`: this reach is THIS creature's and has already been applied, and
			-- `hearNoise` would silently re-gate it at `hearSprint` — which is why a per-kind reach has
			-- to go through the other door. See the note on `StoneGnawer.hearAt`.
			self.body:hearAt(event.position)
		end
	end
end

-- FALLING STONE, ON ITS OWN REACH. Same shape as `feedLandings` and for the same structural reason:
-- the pack's `hearNoise` caps every reaction at `hearSprint` no matter how loud the thing was, so
-- without this a dripstone column coming down 60 studs away — which the cave's own field carries at
-- full perceived loudness — was simply discarded, and a collapse committed this creature from no
-- further than a footstep did.
--
-- FULL LOUDNESS INSIDE THE REACH, exactly as a landing gets. Rock breaking is not a graded sound to
-- an eyeless thing that hunts by vibration; the distance check IS the falloff.
local function feedDripstone(self: Gnawer)
	local reach = config().hearDripstone
	if reach <= 0 then
		return
	end
	local listenAt = self.body.root.Position
	for _, event in NoiseService.events() do
		if event.kind ~= "DripstoneImpact" or event.createdAt <= self.lastDripstoneAt then
			continue
		end
		if (event.position - listenAt).Magnitude <= reach then
			self.lastDripstoneAt = event.createdAt
			-- Through `hearAt` so the 72 studs above survives contact with the pack's 42-stud generic
			-- cap, which is the whole reason this creature can be called sensitive to falling stone.
			self.body:hearAt(event.position)
		end
	end
end

-- THE HUNT CHANNEL: the cave breaking somewhere it cannot charge at.
--
-- This deliberately reads the RAW EVENT rather than `SoundField.contributionOf`, and that is the only
-- place in the game that does. The field answers "how loud is this here", which is a question about
-- air — and a dripstone impact stops being audible at 85 studs by that measure. What this creature
-- has that nothing else does is a jaw on the floor: it feels a column come down through the rock long
-- after the sound of it has stopped mattering. So the test is geometric, and the loudness question is
-- not asked at all.
--
-- ONLY WHAT IT COULD NOT ALREADY ANSWER. Anything inside its direct reach has already been fed to
-- `hearNoise` above and has either roused it or been ignored on its merits; hunting is exclusively
-- for the band beyond that. Without this the two channels would fight over the same event every tick
-- — one trying to charge at it, the other trying to walk to it.
local function feedHuntNoises(self: Gnawer, now: number)
	local settings = config()
	local state = self.body.state
	-- Only a calm creature goes looking. Mid-charge, mid-stagger or hurt, it has a more pressing
	-- problem than something that fell over in the next room.
	if state ~= "eat" and state ~= "move" and state ~= "listen" and state ~= "hunt" then
		return
	end
	local listenAt = self.body.root.Position
	for _, event in NoiseService.events() do
		if not settings.huntKinds[event.kind] or event.createdAt <= self.lastHuntNoiseAt then
			continue
		end
		local offset = event.position - listenAt
		-- VERTICAL BAND FIRST. Floors stack 96 studs apart and `huntRadius` is 150, so without this a
		-- Gnawer hunts a collapse on the floor above and walks to the point directly beneath it.
		if math.abs(offset.Y) > settings.huntVerticalBand then
			continue
		end
		local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		local directReach = if event.kind == "DripstoneImpact" then settings.hearDripstone else settings.hearSprint
		if distance <= directReach or distance > settings.huntRadius then
			continue
		end
		self.lastHuntNoiseAt = event.createdAt
		self.huntTarget = event.position
		self.huntUntil = now + settings.huntSeconds
	end
end

-- THE MOVEMENT CHANNEL, which is this creature's alone. Players in this game are always at run speed
-- (server/MovementService starts every body at Config.Movement.runSpeed), so in practice a moving
-- player is a sprinting player and a still player is silent — exactly the two poles the pack asks
-- for. The measured speed is used rather than the movement mode so that anything which SLOWS a
-- player (a fold, a hazard, deep water) genuinely makes them quieter.
local function feedPlayerMovement(self: Gnawer)
	local reference = math.max(Config.Movement.runSpeed, 0.001)
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
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local loudness = math.clamp(speed / reference, 0, 1) * MOVEMENT_HEARING_SCALE
		if loudness <= 0.05 then
			continue
		end
		self.body:hearNoise(loudness, root.Position)
	end
end

-- A charge in flight, resolved against the world every frame: first anything it runs into, then
-- anybody it runs over.
local function stepCharge(self: Gnawer, now: number)
	local velocity = self.body:desiredVelocity()
	if velocity == nil then
		if self.mover:isOverridden() then
			self.mover:setVelocityOverride(nil)
		end
		return
	end

	-- `desiredVelocity()` is built from `StoneGnawer.Config.chargeSpeed`, which the pack never scales
	-- by variant — unlike `body.speed`, this needs the FULL multiplier applied here, once.
	local speedMultiplier = EnemyVariantRules.speedMultiplier(self.variant, self.elder)
	self.mover:setVelocityOverride(velocity * speedMultiplier)

	local root = self.body.root
	local direction = Vector3.new(velocity.X, 0, velocity.Z)
	if direction.Magnitude < 0.01 then
		return
	end

	-- WHAT IT RUNS INTO. Spherecast rather than a ray so a shoulder clipping a column counts, and
	-- throttled so one impact cannot fire the stagger twice in consecutive frames.
	if now - self.lastChargeCollideAt > 0.5 then
		local hit = EnemyMover.chargeObstruction(root.Position, direction.Unit * self.bodyReach, self.bodyRadius)
		if hit ~= nil then
			self.lastChargeCollideAt = now
			self.body:onChargeCollide()
			self.mover:setVelocityOverride(nil)
			-- SMASHING THE ROOM IS WORTH THE SMALL EFFORT (pack CLAUDE.md §4): a charge that ends
			-- against a formation should bring it down. This is the same hazard call the Calver's
			-- ceiling strike makes, so a Gnawer wrecking the room reuses a system that already exists
			-- rather than inventing destruction.
			DripstoneService.triggerNearest(self.depth, hit.Position, self.bodyReach + 6)
			NoiseService.emit("DripstoneImpact", hit.Position, nil)
			EnemyAudio.play(self.body.model, "GnawerImpact")
			return
		end
	end

	-- WHO IT RUNS OVER. The charge is the only thing this creature does that touches a player, and it
	-- costs wax through the same channel every other threat uses — never Humanoid damage, because
	-- players in this game have no health pool worth the name.
	for playerId, state in PlayerState.all() do
		if state.depth ~= self.depth or not state.alive or state.finished or state.snuffedAt ~= nil then
			continue
		end
		if PlayerState.isThreatProtected(playerId) then
			continue
		end
		local delta = state.position - root.Position
		if Vector3.new(delta.X, 0, delta.Z).Magnitude > self.bodyReach then
			continue
		end
		if now - self.lastChargeCollideAt <= 0.5 then
			continue
		end
		self.lastChargeCollideAt = now
		WaxService.drainExternal(
			playerId,
			config().chargeDamage,
			"DamageThreat" :: Types.WaxSource,
			"The Stone Gnawer ran you down.",
			{ kind = "Hit", seconds = config().chargeLockSeconds },
			"StoneGnawer"
		)
		EncounterHints.announce(playerId, "StoneGnawer")
		self.body:onChargeCollide()
		self.mover:setVelocityOverride(nil)
		break
	end
end

-- Where it goes when it is NOT charging. Deliberately almost nowhere: this creature eats in one
-- place and listens from it, and the charge is the only travel it does. Wandering it around the room
-- would erase the thing that makes it fair — that a player can learn where it is and route around it.
-- SETTLE BACK TO GRAZING. The pack brain has no route out of `listen`: every timeout in
-- Enemies/StoneGnawer.step (charge, stagger, hurt) lands there and nothing ever returns it to `eat`,
-- so the FIRST noise a Gnawer ever heard promoted it to a permanently alert statue for the rest of the
-- run. That cost the encounter its whole reset: the eat loop is how a player finds the creature and
-- reads the room as dangerous, and a Gnawer that has been disturbed once was silent and motionless
-- forever after.
--
-- Fixed HERE rather than in the pack module because the pack module is vendored and its `Config` is a
-- separate copy of these numbers; this is the integration layer and it already reads the game's own
-- Config/StoneGnawer.
--
-- `hearNoise` re-promotes it to `listen` from `eat` the instant anything is audible again, so the only
-- way this fires is a genuinely quiet stretch — which is exactly the "not fighting anyone for a couple
-- of seconds" this is meant to represent.
local function stepSettle(self: Gnawer)
	if self.body.state ~= "listen" then
		return
	end
	if self.body.stateT < config().grazeSettleSeconds then
		return
	end
	self.heardAt = nil
	self.body:setState("eat")
end

-- WALK TO IT. Returns true while the hunt owns the body, in which case grazing must keep its hands
-- off the destination.
--
-- IT DOES NOT CHARGE AT THE NOISE, and that is the point of the whole state. A charge is 26 studs a
-- second in a straight line at something it can hear RIGHT NOW; this is a walk toward a place where
-- something happened, with its head up the whole way. If anything makes a noise it can actually reach
-- while it is walking, `hearNoise` promotes it to `listen` on its own and the hunt is dropped below —
-- which is how a player who set the noise off and then stayed near it gets found.
--
-- ARRIVING ENDS IN `listen`, NOT IN `eat`. It got there, it has its head up, and it is now standing
-- in the room with whatever caused it — the existing `grazeSettleSeconds` timer is what eventually
-- puts its head back down if nothing else happens, so the reset is the one the player already knows.
local function stepHunt(self: Gnawer, now: number): boolean
	local target = self.huntTarget
	if target == nil then
		return false
	end

	local state = self.body.state
	-- ANYTHING IT FOUND ON THE WAY OUTRANKS THE TRIP. `hearNoise` promotes it to `listen` the moment
	-- something audible is genuinely in reach, and `listen` is one step from a charge — so `listen`,
	-- `warn`, `charge` and every damage beat all drop the hunt here. It has something better.
	if state ~= "eat" and state ~= "move" and state ~= "hunt" then
		self.huntTarget = nil
		return false
	end

	if now >= self.huntUntil then
		-- Gave up. Whatever it was, it is not there any more, and standing around where the noise was
		-- is not this creature's behaviour — it goes back to its own patch.
		self.huntTarget = nil
		self.mover:setDestination(nil)
		self.body:setState("eat")
		return false
	end

	local root = self.body.root.Position
	local flat = Vector3.new(target.X - root.X, 0, target.Z - root.Z)
	if flat.Magnitude <= config().huntArriveRadius then
		self.huntTarget = nil
		self.mover:setDestination(nil)
		self.body:setState("listen")
		return true
	end

	if state ~= "hunt" then
		self.body:setState("hunt")
		-- First snuffle comes almost immediately, but not on the same frame as the `GnawerHunt` cue the
		-- state change just fired: the two would stack into one noise and the entry beat would be lost
		-- inside it. Jittered like the rest, because two Gnawers roused by the SAME detonation start
		-- hunting on the same frame — so a fixed first delay is the one moment they are guaranteed to
		-- snuffle in unison, which is exactly the tell that there is a timer behind this.
		self.nextSnuffleAt = now + 0.45 + self.rng:NextNumber() * 0.5
	end

	-- WORKING ITS NOSE AS IT GOES. A hunting Gnawer is the only creature in the game that travels while
	-- making a sound it chose to make, and this is that sound — irregular on purpose, because a fixed
	-- cadence reads as a machine and the thing this is imitating is an animal casting for a scent.
	-- Rolled from the creature's own rng so two of them never fall into step.
	if now >= self.nextSnuffleAt then
		local settings = config()
		self.nextSnuffleAt = now + settings.snuffleSeconds + self.rng:NextNumber() * settings.snuffleJitterSeconds
		EnemyAudio.play(self.body.model, "GnawerSnuffle")
	end

	self.mover:setDestination(target)
	return true
end

-- WANDER WHILE GRAZING. This used to clear the destination and nothing else, so a Gnawer stood exactly
-- where it spawned for the entire floor.
--
-- TWO STATES, NOT ONE. `eat` is parked and chewing; `move` is walking to the next grazing spot. The
-- pack ships a full four-legged walk cycle (Enemies/StoneGnawer, `T.move`) that nothing ever played,
-- because before grazing existed this creature never travelled under its own decision — it only ever
-- charged. Driving the whole wander from `eat` would have walked the body across the floor with its
-- head down mid-chew, which is the animation equivalent of moonwalking.
--
-- Movement is confined to those two: `listen` is the held breath before a charge and must read as
-- stillness, and every other state either drives the body itself (charge, stagger) or is a death beat.
local function stepIdleMovement(self: Gnawer, now: number, hunting: boolean)
	if self.mover:isOverridden() then
		return
	end
	-- A HUNT OWNS THE DESTINATION. Grazing would otherwise clear it on the very next line and re-roll a
	-- wander target inside `grazeRadius`, which is the one thing that would keep this creature pinned
	-- to its own patch when the whole point is that it has left it.
	if hunting then
		return
	end
	local state = self.body.state
	if state ~= "eat" and state ~= "move" then
		self.mover:setDestination(nil)
		self.wanderTarget = nil
		return
	end

	local settings = config()
	if now >= self.nextWanderAt or self.wanderTarget == nil then
		-- The pause between grazing spots is deliberately long and jittered: this creature is meant to
		-- read as head-down and preoccupied, and a steady repick rate looks like patrolling.
		self.nextWanderAt = now + settings.grazePauseSeconds + self.rng:NextNumber() * settings.grazePauseJitterSeconds
		local angle = self.rng:NextNumber() * math.pi * 2
		local radius = self.rng:NextNumber() * settings.grazeRadius
		self.wanderTarget = self.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end

	local target = self.wanderTarget
	if target == nil then
		return
	end
	local root = self.body.root.Position
	local flat = Vector3.new(target.X - root.X, 0, target.Z - root.Z)
	if flat.Magnitude < 1.5 then
		-- Arrived. Head back down and chew until the next repick rather than jittering on the spot.
		self.mover:setDestination(nil)
		if state ~= "eat" then
			self.body:setState("eat")
		end
		return
	end
	if state ~= "move" then
		self.body:setState("move")
	end
	self.mover:setDestination(target)
end

function StoneGnawerBehavior.new(cframe: CFrame, depth: number, familyId: string?, seed: number?): Gnawer?
	local variant = EnemyVariantRules.variantForFamily(familyId)
	local body = StoneGnawerModule.new(cframe, variant, seed)
	local model = body.model

	local elder = model:GetAttribute("Elder") == true
	-- `body.speed` is ALREADY variant-scaled (StoneGnawer.new: `Config.walkSpeed * stats.speed`), so
	-- only the elder factor belongs here — see EnemyVariantRules.elderSpeedMultiplier.
	local mover = EnemyMover.attach(model, body.root, body.speed * EnemyVariantRules.elderSpeedMultiplier(elder))

	-- Measured once, from the rest pose, before a single frame of animation has run.
	local restExtents = model:GetExtentsSize()
	local bodyReach = math.max(restExtents.Z, restExtents.X) * 0.5 + 1.5
	local bodyRadius = restExtents.Y * 0.3

	local self: Gnawer = setmetatable({
		body = body,
		mover = mover,
		depth = depth,
		variant = variant,
		elder = elder,
		bodyReach = bodyReach,
		bodyRadius = bodyRadius,
		registryEntry = nil,
		destroyed = false,
		blastDamage = 0,
		blastHitPoints = config().blast.hitPoints,
		heardAt = nil,
		lastChargeCollideAt = 0,
		lastLandingAt = 0,
		lastDripstoneAt = 0,
		home = cframe.Position,
		rng = Random.new(seed or 0),
		wanderTarget = nil,
		nextWanderAt = 0,
		huntTarget = nil,
		huntUntil = 0,
		lastHuntNoiseAt = 0,
		nextSnuffleAt = 0,
	}, StoneGnawerBehavior)

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

	EnemyAudio.attachLoop(model, "GnawerEat")
	return self
end

-- Dynamite. Two point-blank sticks (Config/StoneGnawer.blast), and a non-lethal one lands it in its
-- own stagger — the same beat as hitting a wall mid-charge, which is a reaction the player has
-- already been taught to read on this creature.
function StoneGnawerBehavior.blast(self: Gnawer, damage: number): boolean
	if self.destroyed then
		return false
	end
	self.blastDamage += math.max(damage, 0)
	if self.blastDamage >= self.blastHitPoints then
		self.body:damage(self.body.health)
		return true
	end
	self.mover:setVelocityOverride(nil)
	self.body:setState("stagger")
	return false
end

function StoneGnawerBehavior.step(self: Gnawer, dt: number, now: number)
	if self.destroyed then
		return
	end
	local model = self.body.model
	if model.Parent == nil then
		self:destroy()
		return
	end

	-- Catches the grazing `eat`/`move` swap, which `stepIdleMovement` performs at the END of the frame.
	-- Its hearing-driven and timeout-driven states were already caught below; these were not.
	EnemyAudio.observe(model, "Gnawer", self.body.state)

	local previousState = self.body.state
	if previousState ~= "death" then
		feedCaveNoises(self, now)
		feedPlayerMovement(self)
		-- Landings and falling stone LAST, and in that order, because `hearNoise` keeps the most recent
		-- target it is handed on a tick: a stomp out-argues the footfalls around it, and rock coming
		-- down out-argues everything. It is the one sound this creature is built around.
		feedLandings(self)
		feedDripstone(self)
		-- The other channel entirely, and it acts on nothing the three above could reach — see its own
		-- comment. Run after them so a noise close enough to charge at has already claimed the tick.
		feedHuntNoises(self, now)
	end

	self.body:step(dt)
	local state = self.body.state

	if state ~= previousState then
		EnemyAudio.observe(model, "Gnawer", state)
	end

	if state == "death" then
		self.mover:setVelocityOverride(nil)
		self.mover:setDestination(nil)
		-- The animation is a real beat and is allowed to finish before the body goes.
		if self.body.stateT > 2.2 then
			self:destroy()
		end
		return
	end

	-- THE WIND-UP IS WHERE IT AIMS, and it keeps aiming for the whole of it. `body.chargeDir` is re-aimed
	-- every frame at the most recent noise while in `warn` and frozen only by the launch
	-- (Enemies/StoneGnawer.step), so reading it here per frame is what turns the body to track — the
	-- telegraph now points where the charge will actually go rather than where the player used to be.
	--
	-- It has to get there through the Humanoid, because the snap-to-heading the pack module would
	-- otherwise do is a teleport that drops a Humanoid body through its own footing
	-- (Enemies/StoneGnawer.beginCharge). The Humanoid's own turn rate is also what visually paces the
	-- tracking, and is why the aim is rate-limited to roughly match it.
	if state == "warn" then
		self.mover:setFacing(self.body.chargeDir)
	else
		self.mover:setFacing(nil)
	end

	stepCharge(self, now)
	-- Settle BEFORE movement so a Gnawer that returns to grazing this frame starts walking on the same
	-- frame rather than standing still for one more tick.
	stepSettle(self)
	-- The hunt runs between them: after `stepSettle`, which is what returns a creature that has finished
	-- listening to its patch, and before grazing, which must not touch the destination while a hunt owns
	-- it. A hunt that has just arrived reports `true` for this frame so nothing overwrites the `listen`
	-- it ended on.
	local hunting = stepHunt(self, now)
	stepIdleMovement(self, now, hunting)
	self.mover:step(now)
end

function StoneGnawerBehavior.destroy(self: Gnawer)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.registryEntry ~= nil then
		EnemyRegistry.unregister(self.registryEntry)
		self.registryEntry = nil
	end
	EnemyAudio.stopAll(self.body.model)
	self.mover:destroy()
	self.body:destroy()
end

return StoneGnawerBehavior
