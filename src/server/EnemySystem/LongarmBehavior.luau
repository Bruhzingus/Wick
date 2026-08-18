--!strict
-- The Longarm's server brain: who it is walking at, when it strikes, and what a grab costs.
--
-- THE REVEAL IS THE WHOLE CREATURE. It stands with its arms folded alongside its legs and reads as a
-- tall biped on two thick limbs until it strikes, at which point half of each limb peels away to nine
-- studs of reach. Everything below serves that: it is slow (4.5), it is silent until it commits (no
-- idle or locomotion cue exists for it anywhere), and the only thing that scares it is a flare.
--
-- THREE RULES THAT ARE NOT TUNING AND MUST NOT BE "IMPROVED":
--   * The 6-second ignore window after a grab. In a game with no combat, a grab that can immediately
--     re-grab is unrecoverable, and the window is the player's chance to get out.
--   * Flare is the ONLY thing that repels it. Ordinary candle brightness never reaches 0.78.
--   * A decoy outranks every player. It is the only proactive tool the player has against this
--     creature, and an implementation that "sensibly" preferred a nearby player would delete the
--     reason the item exists.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local LongarmModule = require(ReplicatedStorage.Shared.Enemies.Longarm)
local EnemyVariantRules = require(ReplicatedStorage.Shared.Logic.EnemyVariantRules)
local PlayerState = require(script.Parent.Parent.PlayerState)
local WaxService = require(script.Parent.Parent.WaxService)
local MovementService = require(script.Parent.Parent.MovementService)
local ToolService = require(script.Parent.Parent.ToolService)
local EnemyRegistry = require(script.Parent.Parent.EnemyRegistry)
local EnemyMover = require(script.Parent.EnemyMover)
local EnemyAudio = require(script.Parent.EnemyAudio)
local EncounterHints = require(script.Parent.EncounterHints)

local LongarmBehavior = {}
LongarmBehavior.__index = LongarmBehavior

-- How far it will look for something to walk toward. Beyond this it simply stands, which is the
-- state a player is supposed to walk past without ever knowing it was there.
local AWARENESS_RADIUS = 60

-- THE STOOP. This creature stands 11.8 studs and the cave's openings roll 8 to 13 (Config/Floors), so
-- it does not fit through its own world standing up. It folds — see the STOOPING block in
-- shared/Enemies/Longarm — and everything below is the decision of WHEN.
--
-- LOOK AHEAD, NOT UP. The probe is taken at a point in front of the body, because a creature that
-- discovers the lintel once it is already under it has folded a fold too late and shoulders into rock
-- instead. Four studs is about one stride at its speed of 4.5.
local STOOP_LOOKAHEAD_STUDS = 4
-- Headroom it wants above the standing silhouette before it will straighten back up. Without a margin
-- the creature stands, immediately re-probes the same marginal ceiling, folds, and jitters between the
-- two poses every few frames.
local STOOP_CLEARANCE_MARGIN = 1.2
local RISE_CLEARANCE_MARGIN = 2.4
-- One ray this often while it is travelling, rather than one per frame per body. The gap it is
-- looking for is metres wide and it moves at 4.5 studs a second, so this samples the same doorway
-- several times over on the approach.
local CLEARANCE_PROBE_INTERVAL = 0.2

export type Longarm = typeof(setmetatable(
	{} :: {
		body: any,
		mover: EnemyMover.Mover,
		depth: number,
		variant: EnemyVariantRules.Variant,
		elder: boolean,
		homePosition: Vector3,
		leashRadius: number,
		registryEntry: any,
		destroyed: boolean,
		blastDamage: number,
		blastHitPoints: number,
		heldPlayerId: Types.PlayerId?,
		nextStrikeAt: number,
		-- The stoop, in studs, measured off the built body once: how tall it stands, how tall it is
		-- folded, and where its pelvis rides in each. See the STOOP block above.
		standingHeight: number,
		stoopHeight: number,
		stoopRide: number,
		colliderStanding: { size: Vector3, offset: CFrame }?,
		stooped: boolean,
		nextClearanceAt: number,
		clearance: number,
	},
	LongarmBehavior
))

local function config()
	return Config.Longarm
end

-- The nearest live decoy flame on this floor, or nil. Asks ToolService what is actually burning
-- rather than scanning the workspace, so a decoy that has already expired cannot lure anything.
local function nearestDecoy(self: Longarm): BasePart?
	local best: BasePart? = nil
	local bestDistance = config().decoyInterest
	for _, decoy in ToolService.decoysAtDepth(self.depth) do
		if decoy.Parent == nil then
			continue
		end
		local distance = (decoy.Position - self.body.root.Position).Magnitude
		if distance < bestDistance then
			best = decoy
			bestDistance = distance
		end
	end
	return best
end

-- The player it is currently interested in: nearest targetable one inside its awareness, ignoring
-- anybody it is still in the grace window for.
--
-- DISTANCE IS FLAT, and on this creature that is not a detail. Its pelvis rides 7.4 studs up while a
-- player's root sits about 3, so a straight-line distance carries 4.4 studs of pure height that has
-- nothing to do with whether the arm can touch them: measured that way, a reach of 9 only ever
-- reaches 7.9 along the ground, and the band a player has to learn would move depending on how the
-- floor happened to slope. The arm swings out and DOWN — see the strike track, which lands 2.5 studs
-- below the pelvis, at chest height — so the question the reach bands are asking is a flat one.
local function nearestPlayer(self: Longarm): (Types.PlayerId?, Vector3?, number)
	if self.body:isIgnoring() then
		return nil, nil, math.huge
	end
	local origin = self.body.root.Position
	local bestId: Types.PlayerId? = nil
	local bestPosition: Vector3? = nil
	local bestDistance = AWARENESS_RADIUS
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

-- FLARE, AND NOTHING ELSE. Fed the same way ThreatService decides a ceiling ambusher is repelled:
-- a flare is a discrete state on the player, not a brightness reading, so this reports 1 when one is
-- burning nearby and 0 otherwise rather than sampling the light field. Ordinary candle brightness
-- must never approach `flareThreshold` or the creature would be repelled by simply being looked at.
local function strongestFlare(self: Longarm): number
	local origin = self.body.root.Position
	local now = os.clock()
	for playerId, state in PlayerState.all() do
		if state.depth ~= self.depth or not state.isLit or state.flareEndsAt <= now then
			continue
		end
		if (state.position - origin).Magnitude <= AWARENESS_RADIUS then
			local _ = playerId
			return 1
		end
	end
	return 0
end

function LongarmBehavior.new(cframe: CFrame, depth: number, familyId: string?, seed: number?): Longarm
	local variant = EnemyVariantRules.variantForFamily(familyId)
	local body = LongarmModule.new(cframe, variant, seed)
	local model = body.model
	local elder = model:GetAttribute("Elder") == true

	-- The stoop measurements are authored at build scale; `BodyScale` carries BODY_SCALE and the elder
	-- bonus together (EnemyKit.finish), so one multiplication gives this body's real numbers.
	local bodyScale = model:GetAttribute("BodyScale")
	local scale = if typeof(bodyScale) == "number" then bodyScale else 1
	local stoopHeight = LongarmModule.Stance.stoopHeight * scale
	local stoopRide = LongarmModule.Stance.stoopRide * scale

	-- `body.speed` is ALREADY variant-scaled (Longarm.new: `Config.speed * stats.speed`), so only the
	-- elder factor belongs here — see EnemyVariantRules.elderSpeedMultiplier.
	--
	-- ROUTED AT ITS FOLDED HEIGHT, NOT ITS STANDING ONE. Every doorway on the floor is shorter than
	-- this creature, and a mover that cannot compute a route holds rather than guessing — so asked at
	-- its standing height it would never leave the room it spawned in. See EnemyMover.attach.
	local mover =
		EnemyMover.attach(model, body.root, body.speed * EnemyVariantRules.elderSpeedMultiplier(elder), stoopHeight)

	local self: Longarm = setmetatable({
		body = body,
		mover = mover,
		depth = depth,
		variant = variant,
		elder = elder,
		homePosition = cframe.Position,
		leashRadius = math.huge,
		registryEntry = nil,
		destroyed = false,
		blastDamage = 0,
		blastHitPoints = config().blast.hitPoints,
		heldPlayerId = nil,
		nextStrikeAt = 0,
		standingHeight = LongarmModule.Stance.standHeight * scale,
		stoopHeight = stoopHeight,
		stoopRide = stoopRide,
		colliderStanding = nil,
		stooped = false,
		nextClearanceAt = 0,
		-- Assume open cave until the first probe says otherwise: a body that spawned believing it was
		-- under a lintel would fold on its first step for no reason the player can see.
		clearance = math.huge,
	}, LongarmBehavior)

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
	return self
end

-- THE COLLIDER HAS TO FOLD TOO. It is the only part of the body that answers to physics, and at full
-- height it reaches well above the head — so a creature that folded its visible geometry and kept its
-- standing collider would fold beautifully and then shoulder into the rock above the doorway anyway.
-- Squashed to the folded silhouette and dropped to sit on it, restored exactly on the way back up.
local function setColliderStance(self: Longarm, stooped: boolean)
	local collider = self.body.model:FindFirstChild("Collider")
	if collider == nil or not collider:IsA("BasePart") then
		return
	end
	local weld = collider:FindFirstChildOfClass("Weld")
	if weld == nil then
		return
	end
	if self.colliderStanding == nil then
		self.colliderStanding = { size = collider.Size, offset = weld.C0 }
	end
	local standing = self.colliderStanding
	if standing == nil then
		return
	end
	if not stooped then
		collider.Size = standing.size
		weld.C0 = standing.offset
		return
	end
	-- Tall enough to still be a body worth colliding with, short enough to clear the tightest opening
	-- the folded silhouette fits through, and re-centred on the folded pelvis rather than the standing
	-- one — the whole volume has to come down with the creature, not just shrink in place.
	local height = math.max(self.stoopHeight * 0.8, 1)
	collider.Size = Vector3.new(standing.size.X, height, standing.size.Z)
	weld.C0 = CFrame.new(standing.offset.Position.X, height * 0.5 - self.stoopRide, standing.offset.Position.Z)
end

-- Fold or straighten the physics volume. The body owns the animation; this owns the part of the stoop
-- the animation cannot express, and it flips at the ENDS of the fold — the collider is invisible, and
-- a creature is only ever in the doorway once the fold has finished.
local function setStooped(self: Longarm, stooped: boolean)
	if self.stooped == stooped then
		return
	end
	self.stooped = stooped
	setColliderStance(self, stooped)
end

-- WHERE THE PELVIS SHOULD BE RIGHT NOW, tracked continuously across the fold rather than snapped at
-- either end of it. Snapping is the visible failure in both directions: drop the ride the instant the
-- fold starts and the creature spends half a second with its legs inside the rock, drop it only when
-- the fold ends and it spends the same half-second folding in mid-air with its feet off the floor.
--
-- `foldSeconds` and `riseSeconds` come from the pack module rather than from `Config.Longarm` on
-- purpose: they are the lengths of `T.fold` and `T.rise` themselves, and a game-side copy that drifted
-- from the tracks would put the pelvis somewhere the pose does not agree with.
local function stanceRide(self: Longarm): number
	local standing = self.mover:standingRide()
	local state = self.body.state
	if state == "stoop" then
		return self.stoopRide
	elseif state == "fold" then
		local k = math.clamp(self.body.stateT / LongarmModule.Config.foldSeconds, 0, 1)
		return standing + (self.stoopRide - standing) * k
	elseif state == "rise" then
		local k = math.clamp(self.body.stateT / LongarmModule.Config.riseSeconds, 0, 1)
		return self.stoopRide + (standing - self.stoopRide) * k
	end
	return standing
end

-- The rock above the point it is about to walk into, sampled from the floor rather than from the
-- creature. Throttled: see CLEARANCE_PROBE_INTERVAL.
local function sampleClearance(self: Longarm, now: number)
	if now < self.nextClearanceAt then
		return
	end
	self.nextClearanceAt = now + CLEARANCE_PROBE_INTERVAL
	local root = self.body.root
	local facing = root.CFrame.LookVector
	local ahead = Vector3.new(facing.X, 0, facing.Z)
	if ahead.Magnitude > 0.01 then
		ahead = ahead.Unit * STOOP_LOOKAHEAD_STUDS
	else
		ahead = Vector3.zero
	end
	-- Measured from the floor the creature is standing on, not from its hips: the question is how tall
	-- the opening is, and `rideHeight` is exactly how far the floor is below the root.
	local floorY = root.Position.Y - self.mover.rideHeight
	local from = Vector3.new(root.Position.X + ahead.X, floorY, root.Position.Z + ahead.Z)
	self.clearance = EnemyMover.overheadClearance(from, self.standingHeight + RISE_CLEARANCE_MARGIN + 4)
end

-- Whether the body should be folded right now, given what the last probe found. Two different
-- thresholds on purpose — see STOOP_CLEARANCE_MARGIN.
local function wantsStoop(self: Longarm): boolean
	if self.stooped then
		return self.clearance < self.standingHeight + RISE_CLEARANCE_MARGIN
	end
	return self.clearance < self.standingHeight + STOOP_CLEARANCE_MARGIN
end

-- Drive the fold from a locomotion state, and report whether the body is currently in one of the
-- stoop states — in which case the caller must NOT overwrite it with `move`.
local function updateStoop(self: Longarm, now: number): boolean
	sampleClearance(self, now)
	local state = self.body.state
	local folded = self.body:isStooping()
	if wantsStoop(self) then
		-- Either not folded at all, or halfway back up and turning into the opening it just left —
		-- which is what a creature circling a doorway does. Fold from wherever the body has got to.
		if not folded or state == "rise" then
			self.body:setState("fold")
		end
		setStooped(self, self.body.state == "stoop")
		self.mover:setRideHeight(stanceRide(self))
		return true
	end
	if folded then
		if state ~= "rise" then
			self.body:setState("rise")
		end
		setStooped(self, false)
		self.mover:setRideHeight(stanceRide(self))
		return true
	end
	-- Standing, and standing at exactly the height it was built at — the rise hands over to `move` on
	-- whichever frame crosses `riseSeconds`, which is rarely the frame the lerp reached the top on.
	self.mover:setRideHeight(self.mover:standingRide())
	return false
end

-- Walk toward a point. Every ordinary locomotion branch goes through here so the stoop is decided in
-- exactly one place: if the body is folding, folded, or standing back up, that state OWNS the rig and
-- must not be overwritten with `move` — which is precisely the bug a second call site would introduce.
local function travelTo(self: Longarm, destination: Vector3, now: number)
	self.mover:setDestination(destination)
	if not updateStoop(self, now) then
		self.body:setState("move")
	end
	self.mover:step(now)
end

-- Chains this Longarm to a patrol area. Used by the boss encounter, whose two guards must stay in
-- the chamber rather than following a fleeing player out of it.
function LongarmBehavior.setLeash(self: Longarm, center: Vector3, radius: number)
	self.homePosition = center
	self.leashRadius = radius
end

function LongarmBehavior.blast(self: Longarm, damage: number): boolean
	if self.destroyed then
		return false
	end
	self.blastDamage += math.max(damage, 0)
	if self.blastDamage >= self.blastHitPoints then
		self:releaseHeld()
		self.body:damage(self.body.health)
		return true
	end
	self.body:damage(0)
	return false
end

-- Let go of whoever is being held and hand their movement back. Safe to call when nothing is held.
function LongarmBehavior.releaseHeld(self: Longarm)
	local playerId = self.heldPlayerId
	if playerId == nil then
		return
	end
	self.heldPlayerId = nil
	local state = PlayerState.get(playerId)
	if state ~= nil then
		state.isHeldByEnemy = false
	end
	MovementService.refresh(playerId)
end

-- Resolves an attack once a reveal has played out in full. Distance is measured fresh by the
-- caller each time — never the distance from when the reveal began, so a player who broke range
-- or ducked a decoy during the telegraph is rewarded for reacting to it rather than having a stale
-- distance decide their fate.
local function resolveStrike(self: Longarm, targetId: Types.PlayerId, distance: number, now: number)
	self.nextStrikeAt = now + 1.2
	local result = self.body:attackAt(distance)
	if result == "none" then
		return
	end
	EncounterHints.announce(targetId, "Longarm")

	if result == "graze" then
		-- THE TEACHING MOMENT, and the body is already playing the slash for it (`attackAt` picks the
		-- animation from the same distance this reads). Getting clipped at the edge of a reach you did
		-- not know existed is how a player learns this creature's real range, and it costs wax without
		-- taking the run — the wide, readable arc is what makes the lesson land instead of just hurting.
		WaxService.drainExternal(
			targetId,
			config().grazeDamage,
			"DamageThreat" :: Types.WaxSource,
			"The Longarm's reach caught you.",
			{ kind = "Hit", seconds = 1.2 },
			"Longarm"
		)
		return
	end

	-- GRAB. Holds for `holdSeconds`, drains, then drops and ignores for `ignoreSeconds`.
	local player = Players:GetPlayerByUserId(targetId)
	local character = if player ~= nil then player.Character else nil
	if character == nil then
		return
	end
	self.body:grab(character)
	self.heldPlayerId = targetId
	local heldState = PlayerState.get(targetId)
	if heldState ~= nil then
		heldState.isHeldByEnemy = true
	end
	MovementService.refresh(targetId)
	WaxService.drainExternal(
		targetId,
		config().grabDamage,
		"DamageThreat" :: Types.WaxSource,
		"The Longarm had hold of you.",
		{ kind = "Hit", seconds = config().holdSeconds },
		"Longarm"
	)
end

function LongarmBehavior.step(self: Longarm, dt: number, now: number)
	if self.destroyed then
		return
	end
	local model = self.body.model
	if model.Parent == nil then
		self:destroy()
		return
	end

	-- Catches anything this creature decided LATE in the previous frame — a strike, a slash, a grab, a
	-- reveal. All four are set after the comparison below, so without this pass they were never seen.
	EnemyAudio.observe(model, "Longarm", self.body.state)

	local previousState = self.body.state
	if previousState ~= "death" then
		self.body:setIllumination(strongestFlare(self))
	end

	self.body:step(dt)
	local state = self.body.state
	if state ~= previousState then
		EnemyAudio.observe(model, "Longarm", state)
		-- The pack releases its own victim on the hold timer; mirror that into movement control the
		-- instant the state actually changes rather than on our own clock.
		if previousState == "hold" and state ~= "hold" then
			self:releaseHeld()
		end
	end

	if state == "death" then
		self:releaseHeld()
		self.mover:setDestination(nil)
		if self.body.stateT > 2.2 then
			self:destroy()
		end
		return
	end

	-- FLEEING IGNORES ITS NORMAL TARGET, at `fleeSpeed`, exactly as the pack requires. It runs
	-- directly away from whatever repelled it rather than pathing, because a flare is a panic and a
	-- creature that calmly routed around furniture while fleeing would not read as afraid.
	--
	-- IT ALSO DOES NOT STOOP WHILE IT PANICS. `flee` is a state of its own with its own animation and
	-- its own five-second timer, and folding would replace both — the creature would duck a doorway and
	-- come out the far side no longer afraid, which is the one thing a flare is supposed to buy. So a
	-- fleeing Longarm that runs at an opening too small for it presses against the rock until the panic
	-- expires, and it flees away from the player rather than through the doorway they came from, so
	-- that is a corner it has to be driven into rather than one it finds on its own.
	if state == "flee" then
		local _, awayFrom = nearestPlayer(self)
		local origin = self.body.root.Position
		local direction = if awayFrom ~= nil then (origin - awayFrom) else (origin - self.homePosition)
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude > 0.1 then
			self.mover:setDestination(origin + flat.Unit * 24)
		end
		-- `fleeSpeed` is raw pack config the constructor never touches (unlike `body.speed`), so this
		-- one wants the FULL multiplier — and the body's ACTUAL elder status, not a hardcoded `false`.
		-- An elder Longarm is meant to be 10% slower everywhere, fleeing included.
		self.mover:setSpeed(config().fleeSpeed * EnemyVariantRules.speedMultiplier(self.variant, self.elder))
		self.mover:step(now)
		return
	end

	-- COMMITTED. Both attacks plant the body for their whole length — the slash because the arc IS the
	-- tell and a creature that walked through its own swing would erase it, the thrust because it ends
	-- holding somebody.
	if state == "hold" or state == "strike" or state == "slash" then
		self.mover:setDestination(nil)
		self.mover:step(now)
		return
	end

	-- REVEALING. The whole design of this creature: arms unfold from the folded-leg disguise to the
	-- full 9-stud reach, and it is the player's ONLY warning — no idle sound, no locomotion cue,
	-- nothing before this. `revealSeconds` must play out in full and never shorten (pack CLAUDE.md
	-- §9), and the creature holds its ground while it does: closing distance during its own tell
	-- would erase the half-second the reveal is supposed to buy the player.
	if state == "reveal" then
		self.mover:setDestination(nil)
		self.mover:step(now)
		if self.body.stateT < config().revealSeconds then
			return
		end
		local targetId, _, distance = nearestPlayer(self)
		if targetId ~= nil and distance <= config().reachMax then
			resolveStrike(self, targetId, distance, now)
		else
			-- The target broke range or line of sight during the telegraph. Stand down rather than
			-- hold "revealed" forever waiting for a strike that was never going to land.
			self.nextStrikeAt = now + 1.2
			self.body:setState("idle")
		end
		return
	end

	self.mover:setSpeed(self.body.speed)

	-- A DECOY OUTRANKS EVERY PLAYER. This is the whole reason decoy candles exist as an item.
	local decoy = nearestDecoy(self)
	if decoy ~= nil then
		self.body:setDecoy(decoy)
		if (decoy.Position - self.body.root.Position).Magnitude <= config().reachGrab then
			self.body:consumeDecoy()
		end
		travelTo(self, decoy.Position, now)
		return
	end
	self.body:setDecoy(nil)

	local targetId, targetPosition, distance = nearestPlayer(self)
	if targetId == nil or targetPosition == nil then
		self.mover:setDestination(nil)
		-- STANDING STILL DOES NOT MEAN STANDING UP. A creature that lost its target while folded under
		-- a doorway would otherwise straighten into the rock above it, so the stoop still gets the
		-- decision; only when it is genuinely clear does `idle` win.
		if not updateStoop(self, now) then
			self.body:setState("idle")
		end
		self.mover:step(now)
		return
	end

	-- Chained guards never leave their chamber, however tempting the target.
	local leashed = (targetPosition - self.homePosition).Magnitude > self.leashRadius
	if leashed then
		travelTo(self, self.homePosition, now)
		return
	end

	-- CLOSE ENOUGH TO COMMIT. Begin the reveal rather than striking outright — see the `state ==
	-- "reveal"` branch above for why the telegraph cannot be skipped.
	--
	-- NOT WHILE IT IS FOLDED, though. The reveal is the creature standing to its full height and
	-- unfolding, and it cannot do that under the doorway it is currently squeezing through — it would
	-- rise straight into the rock. It keeps closing instead, which means the seconds it spends in an
	-- opening are seconds the player is safe from it. That is a fair trade for a nine-stud reach.
	if now >= self.nextStrikeAt and distance <= config().reachMax and not self.body:isStooping() then
		self.mover:setDestination(nil)
		self.body:setState("reveal")
		self.mover:step(now)
		return
	end

	travelTo(self, targetPosition, now)
end

function LongarmBehavior.destroy(self: Longarm)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:releaseHeld()
	if self.registryEntry ~= nil then
		EnemyRegistry.unregister(self.registryEntry)
		self.registryEntry = nil
	end
	EnemyAudio.stopAll(self.body.model)
	self.mover:destroy()
	self.body:destroy()
end

return LongarmBehavior
