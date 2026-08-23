-- StoneWardenBehavior.lua
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local WardenRegistry = require(script.Parent.Parent:WaitForChild("WardenRegistry"))
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.Parent:WaitForChild("PlayerState"))
local DeathService = require(script.Parent.Parent:WaitForChild("DeathService"))
local DripstoneService = require(script.Parent.Parent:WaitForChild("DripstoneService"))
local StoneWardenAnimator = require(script.Parent:WaitForChild("StoneWardenAnimator"))
local StoneWardenSqueeze = require(script.Parent:WaitForChild("StoneWardenSqueeze"))

local StoneWardenBehavior = {}
StoneWardenBehavior.__index = StoneWardenBehavior

local function smoothstep(value)
	local x = math.clamp(value, 0, 1)
	return x * x * (3 - 2 * x)
end

-- parent is optional and defaults to workspace; ServerInit passes the owning floor's model so
-- the dormant pile / active warden are destroyed automatically when that floor is torn down.
-- depth is the floor number this warden belongs to; hazards on that floor (unstable dripstone)
-- look the golem up by it through WardenRegistry.
-- `displayName` is what this cave calls its Warden — Stone Warden, Moss Warden, Ice Warden
-- (Logic/CaveFamilyRules.wardenDisplayName). It reaches only the death line: the encounter itself is
-- one system with one config id in every family, and only the name and the rock differ.
function StoneWardenBehavior.new(
	spawnCFrame,
	waxPieces: { BasePart },
	collapsePositions: { Vector3 },
	parent: Instance?,
	depth: number?,
	displayName: string?
)
	local self = setmetatable({}, StoneWardenBehavior)
	self.SpawnCFrame = spawnCFrame
	self.WaxPieces = waxPieces
	self.CollapsePositions = collapsePositions
	self.CollectedPieces = {}
	self.PiecesRemaining = #waxPieces
	local waxOrigin = Vector3.zero
	for _, piece in waxPieces do
		waxOrigin += piece.Position
	end
	self.WaxOrigin = if #waxPieces > 0 then waxOrigin / #waxPieces else spawnCFrame.Position
	self.Depth = depth or 1
	self.DisplayName = displayName or "Stone Warden"
	self.State = "DORMANT"
	self.PauseTimer = 0
	self.IsPaused = false
	-- The listening beat is one-shot per stationary episode (see _trackNearestPlayer): spent when the
	-- pause runs out, re-armed only when the tracked player moves again or a different one becomes
	-- the nearest target.
	self.PauseSpent = false
	self.PauseTarget = nil
	self.StunnedUntil = 0
	self.RegistryEntry = nil
	self.Destroyed = false
	self.LastContactAt = {}
	-- DYNAMITE (Config/Dynamite.threat). Accumulated blast damage in "sticks at point blank", and the
	-- clock on the limp a surviving blast leaves behind. Both start clean and neither ever heals: the
	-- Warden is the one thing in the cave a party might genuinely try to wear down across a floor.
	self.BlastDamage = 0
	self.SlowUntil = 0

	local ModelModule = require(script.Parent:WaitForChild("StoneWardenModel"))
	local modelParent = parent or workspace

	self.DormantModel, self.DormantDust = ModelModule.buildDormantPile(spawnCFrame)
	self.DormantModel.Parent = modelParent

	self.ActiveRig = ModelModule.buildActiveWarden(spawnCFrame)
	self.ActiveModel = self.ActiveRig.model
	self.ActiveModel.Parent = modelParent
	CollectionService:AddTag(self.ActiveModel, Config.Diagnostics.wardenTag)
	self.Animator = StoneWardenAnimator.new(
		self.ActiveRig,
		Config.StoneWarden.motion,
		Config.StoneWarden.emergenceSeconds,
		Config.StoneWarden.emergenceStages,
		Config.StoneWarden.squeeze
	)
	-- Owns the authoritative root's SIZE (see StoneWardenSqueeze's header for why the encounter needs
	-- one). Left disabled until the body is standing clear and walking under its own physics.
	self.Squeeze = StoneWardenSqueeze.new(self.ActiveRig, Config.StoneWarden.squeeze)
	self.Squeeze.OnGrind = function(position)
		Remotes.get("RunEvent"):FireAllClients("wardenSqueeze", { position = position, depth = self.Depth })
	end
	self.Squeeze.OnFold = function(folded)
		self.Animator:setSqueeze(if folded then 1 else 0)
	end
	-- One sole landing, straight off the gait the player is watching. Presentation only: the payload
	-- carries a position and a weight, and no client may do anything with it but shake and make noise.
	self.Animator.OnFootPlant = function(side, position, strength)
		if self.Destroyed or self.State ~= "ACTIVE" then
			return
		end
		local dust = if side == "Left" then self.ActiveRig.footDust.left else self.ActiveRig.footDust.right
		if dust ~= nil and dust.Parent ~= nil then
			dust:Emit(math.floor(6 + strength * 10))
		end
		Remotes.get("RunEvent"):FireAllClients("wardenStep", {
			position = position,
			strength = strength,
			side = side,
			depth = self.Depth,
		})
	end
	-- Remembered from the model rather than hardcoded, so the stun restores whatever pace
	-- StoneWardenModel actually built it with.
	local builtHumanoid = self.ActiveRig.humanoid
	self.BaseWalkSpeed = builtHumanoid and builtHumanoid.WalkSpeed or Config.StoneWarden.walkSpeed

	-- Preserve intentional invisible roots while cross-fading only the visible stones.
	self.ActiveTransparency = {}
	for _, part in ipairs(self.ActiveModel:GetDescendants()) do
		if part:IsA("BasePart") then
			self.ActiveTransparency[part] = part.Transparency
			part.Transparency = 1
		end
	end
	self.DormantTransparency = {}
	for _, part in ipairs(self.DormantModel:GetDescendants()) do
		if part:IsA("BasePart") then
			self.DormantTransparency[part] = part.Transparency
		end
	end
	self.ActiveRig.root.Anchored = true
	self.ActiveRig.root.CanCollide = false

	-- Buried-in-rubble cue for the stun. Created disabled; only the stun turns it on, so a walking
	-- warden looks exactly as it did before.
	local rubble = Instance.new("ParticleEmitter")
	rubble.Name = "WardenRubble"
	rubble.Enabled = false
	rubble.Rate = 22
	rubble.Lifetime = NumberRange.new(0.6, 1.4)
	rubble.Speed = NumberRange.new(1, 4)
	rubble.SpreadAngle = Vector2.new(50, 50)
	rubble.Size = NumberSequence.new(0.8)
	rubble.Transparency = NumberSequence.new(0.35)
	rubble.Color = ColorSequence.new(Color3.fromRGB(74, 71, 66), Color3.fromRGB(40, 40, 44))
	rubble.Acceleration = Vector3.new(0, -22, 0)
	rubble.Parent = self.ActiveModel.PrimaryPart
	self.RubbleEmitter = rubble

	-- Kill Logic. A stunned warden is inert: it cannot walk and it cannot kill on contact, which is
	-- the whole reason to lead one under a fractured ceiling.
	self.TouchConnection = self.ActiveModel.PrimaryPart.Touched:Connect(function(hit)
		if not self.Destroyed and self.State == "ACTIVE" and not self:IsStunned() then
			local character = hit:FindFirstAncestorOfClass("Model")
			if character == nil then
				return
			end
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local player = Players:GetPlayerFromCharacter(character)
				local state = player and PlayerState.get(player.UserId) or nil
				if
					state ~= nil
					and state.alive
					and not state.finished
					and state.depth == self.Depth
					and not PlayerState.isThreatProtected(player.UserId)
				then
					local now = tick()
					local previous = self.LastContactAt[player.UserId] or -math.huge
					if now - previous < Config.StoneWarden.motion.contactRepeatCooldownSeconds then
						return
					end
					-- Death remains the first side effect of confirmed contact. Follow-through and audio are
					-- post-contact presentation; neither can introduce a warning or delay the kill.
					DeathService.kill(
						player.UserId,
						"Snuffed",
						"The " .. self.DisplayName .. " crushed your flame.",
						"StoneWarden"
					)
					self.LastContactAt[player.UserId] = now
					pcall(self.Animator.signalContact, self.Animator)
					Remotes.get("RunEvent"):FireAllClients("wardenAttack", {
						position = self.ActiveModel.PrimaryPart.Position,
						victimId = player.UserId,
					})
				end
			end
		end
	end)

	-- Three deliberate pickups replace the old proximity trigger. The server still validates the
	-- player and distance because a prompt is an interaction surface, not gameplay authority.
	for _, piece in waxPieces do
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "WardenWaxPrompt"
		prompt.ActionText = Config.StoneWarden.pickupActionText
		prompt.ObjectText = Config.StoneWarden.pickupObjectText
		prompt.MaxActivationDistance = Config.StoneWarden.pickupRange
		prompt.HoldDuration = Config.StoneWarden.pickupHoldSeconds
		prompt.RequiresLineOfSight = true
		prompt.Parent = piece
		prompt.Triggered:Connect(function(player)
			self:_collectWax(player, piece)
		end)
	end

	task.spawn(function()
		self:_updateLoop()
	end)

	return self
end

function StoneWardenBehavior:_collectWax(player, piece)
	if self.Destroyed or self.State ~= "DORMANT" or self.CollectedPieces[piece] or piece.Parent == nil then
		return
	end
	local state = PlayerState.get(player.UserId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") or nil
	if
		state == nil
		or not state.alive
		or state.finished
		or state.snuffedAt ~= nil
		or state.depth ~= self.Depth
		or root == nil
		or (root.Position - piece.Position).Magnitude
			> Config.StoneWarden.pickupRange + Config.StoneWarden.pickupValidationSlack
	then
		return
	end

	self.CollectedPieces[piece] = true
	self.PiecesRemaining -= 1
	piece:Destroy()
	if self.PiecesRemaining <= 0 then
		self:Activate()
	end
end

function StoneWardenBehavior:Activate()
	if self.Destroyed or self.State ~= "DORMANT" then
		return
	end
	self.State = "EMERGING"
	print("The wall breathes. The Stone-Warden is emerging.")

	for _, piece in self.WaxPieces do
		if piece.Parent ~= nil then
			piece:Destroy()
		end
	end
	local triggeredDripstones = 0
	for _, position in self.CollapsePositions do
		if DripstoneService.triggerNearest(self.Depth, position, Config.StoneWarden.collapseTriggerRadius) then
			triggeredDripstones += 1
		end
	end
	Remotes.get("RunEvent"):FireAllClients("wardenCollapse", {
		position = self.WaxOrigin,
		depth = self.Depth,
		triggeredDripstones = triggeredDripstones,
	})

	local emergence = Config.StoneWarden.emergence
	local stages = Config.StoneWarden.emergenceStages
	local duration = Config.StoneWarden.emergenceSeconds
	local standHeight = Config.StoneWarden.squeeze.standingHeight / 2
	local startTime = tick()
	self.Animator:beginEmergence(startTime)

	-- FOUR BEATS, NOT ONE SLIDE. What this replaced eased a crouch out linearly over four seconds
	-- while cross-fading two models at the same constant rate, and the result read as an object being
	-- moved rather than as a thing standing up: the outcrop was already half transparent before it had
	-- visibly done anything, so the reveal happened during the least interesting second of it.
	--
	-- Now the wall strains and sheds dust while nothing has moved yet; one arm breaks the seal and
	-- takes the floor; the body climbs up over that arm as the outcrop finally dissolves behind it; and
	-- it reaches full height on a bellow. Each beat is broadcast so the client can shake and sound the
	-- room at the moment the body does the thing, rather than once at the start.
	local beat = 0
	local BEATS = {
		{ at = stages.tremorFraction, id = "tremor" },
		{ at = stages.breachFraction, id = "breach" },
		{ at = stages.riseFraction, id = "rise" },
		{ at = stages.roarFraction, id = "roar" },
	}

	-- IT STAYS ANCHORED THROUGH THE EMERGENCE. The body starts pushed back inside solid rock, and an
	-- unanchored assembly there spends the whole animation being shoved out by the wall it is supposed
	-- to be walking out of, fighting every PivotTo. Physics takes over once it is standing clear.
	while tick() - startTime < duration do
		if self.Destroyed or self.ActiveModel.Parent == nil then
			return
		end
		local progress = (tick() - startTime) / duration

		while beat < #BEATS and progress >= BEATS[beat + 1].at do
			beat += 1
			self:_emergenceBeat(BEATS[beat].id)
		end

		-- The two bodies swap over the BREACH, not over the whole animation: both of them are moving
		-- during that window, which is the only time a cross-fade is hard to catch.
		local swap = smoothstep(
			math.clamp(
				(progress - stages.tremorFraction * 0.8)
					/ math.max(0.001, stages.riseFraction - stages.tremorFraction * 0.8),
				0,
				1
			)
		)
		for _, part in ipairs(self.DormantModel:GetDescendants()) do
			if part:IsA("BasePart") then
				local original = self.DormantTransparency[part] or 0
				part.Transparency = original + (1 - original) * swap
			end
		end
		for _, part in ipairs(self.ActiveModel:GetDescendants()) do
			if part:IsA("BasePart") then
				local original = self.ActiveTransparency[part] or 0
				part.Transparency = 1 - (1 - original) * swap
			end
		end
		-- OUT OF THE WALL, not up out of the floor. Local +Z is into the stone (see StoneWardenModel),
		-- so the body starts a body's depth back inside it and low, then steps forward and stands as
		-- the outcrop it was cross-fades away. Held still through the tremor and eased across the
		-- breach and rise, so the translation lands on the beats the pose is already playing.
		local emerged = smoothstep(
			math.clamp(
				(progress - stages.tremorFraction) / math.max(0.001, stages.riseFraction - stages.tremorFraction),
				0,
				1
			)
		)
		local remaining = 1 - emerged
		self.ActiveModel:PivotTo(
			self.SpawnCFrame * CFrame.new(0, standHeight - emergence.rise * remaining, emergence.wallDepth * remaining)
		)
		RunService.Heartbeat:Wait()
	end
	-- A run can end during those four seconds, which takes the whole floor model with it. Handing an
	-- orphaned root to SetNetworkOwner throws; the update loop is already watching for the teardown.
	local activeRoot = self.ActiveModel.PrimaryPart
	if activeRoot == nil or activeRoot.Parent == nil then
		return
	end
	self.ActiveModel:PivotTo(self.SpawnCFrame * CFrame.new(0, standHeight, 0))

	activeRoot.CanCollide = true
	activeRoot.Anchored = false
	-- Force server ownership so it doesn't stutter
	activeRoot:SetNetworkOwner(nil)

	self.DormantModel:Destroy()
	self.DormantDust = nil
	self.State = "ACTIVE"
	self.Animator:setActive()
	-- Only now: the root is unanchored, under physics, and its size is the squeeze's to change.
	self.Squeeze:setEnabled(true)
	-- The tag clients read every frame to place the floor tremor. Deliberately NOT the diagnostics tag
	-- the constructor adds: that one exists so a developer overlay can count bodies and is free to be
	-- removed with the overlay, and the ground shaking under a player is part of the encounter.
	--
	-- Added HERE rather than at construction because the active body is built at the same moment as
	-- the dormant pile and spends the whole pre-wake floor sitting invisible inside it. Tagged early,
	-- a player would feel the floor shake standing next to an outcrop that has not moved yet — which
	-- gives the set-piece away exactly as surely as leaving the eyes lit would.
	CollectionService:AddTag(self.ActiveModel, Config.StoneWarden.presence.tag)

	-- Only a walking warden is worth dropping a ceiling on, so it enters the hazard registry here
	-- rather than at construction. _updateLoop removes it again when the floor is torn down.
	self.RegistryEntry = WardenRegistry.register({
		depth = self.Depth,
		position = function()
			local root = self.ActiveModel and self.ActiveModel.PrimaryPart
			if root == nil or root.Parent == nil then
				return nil
			end
			return root.Position
		end,
		stun = function(seconds)
			self:Stun(seconds)
		end,
		blast = function(damage)
			return self:Blast(damage)
		end,
	})
end

-- One beat of the wake. Everything here is presentation: dust off the wall, the eyes catching, and a
-- broadcast so the client can shake the floor and sound the room at the moment the body moves. None
-- of it advances the emergence, and skipping one entirely (a torn-down floor, a dropped remote) leaves
-- the encounter in exactly the same state at the end of the four seconds.
function StoneWardenBehavior:_emergenceBeat(id: string)
	local stages = Config.StoneWarden.emergenceStages
	local position = self.ActiveModel.PrimaryPart and self.ActiveModel.PrimaryPart.Position or self.SpawnCFrame.Position

	if id == "tremor" then
		if self.DormantDust ~= nil and self.DormantDust.Parent ~= nil then
			self.DormantDust.Rate = stages.dustRate
			self.DormantDust.Enabled = true
		end
	elseif id == "breach" then
		if self.DormantDust ~= nil and self.DormantDust.Parent ~= nil then
			self.DormantDust:Emit(stages.burstParticles)
		end
	elseif id == "rise" then
		-- The eyes catch as the head clears the rock. They are the only lights on the body and they
		-- have spent the whole floor disabled inside an outcrop, because a light is not a BasePart and
		-- the transparency cross-fade could never have hidden one.
		for _, light in self.ActiveRig.eyeLights do
			if light.Parent ~= nil then
				light.Enabled = true
			end
		end
		if self.DormantDust ~= nil and self.DormantDust.Parent ~= nil then
			self.DormantDust.Enabled = false
		end
	elseif id == "roar" then
		local shoulderDust = self.ActiveRig.shoulderDust
		if shoulderDust ~= nil and shoulderDust.Parent ~= nil then
			shoulderDust:Emit(stages.burstParticles)
		end
	end

	Remotes.get("RunEvent"):FireAllClients("wardenBeat", {
		beat = id,
		position = position,
		depth = self.Depth,
	})
end

function StoneWardenBehavior:IsStunned()
	return tick() < self.StunnedUntil
end

-- Root the golem where it stands. Overlapping strikes extend the window; they never shorten it.
function StoneWardenBehavior:Stun(seconds)
	if self.Destroyed or self.State ~= "ACTIVE" then
		return
	end
	self.StunnedUntil = math.max(self.StunnedUntil, tick() + math.max(seconds or 0, 0))
	self.Animator:setStunnedUntil(self.StunnedUntil)
	self.IsPaused = false
	local humanoid = self.ActiveModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(self.ActiveModel.PrimaryPart.Position)
	end
	if self.RubbleEmitter then
		self.RubbleEmitter.Enabled = true
	end
	-- The squeeze is deliberately NOT disabled here. The animator already refuses to draw the fold
	-- while stunned (a body under a fallen crown owns its whole silhouette), but the ROOT has to keep
	-- whatever size the space it is standing in allows: a Warden crowned halfway through an arch that
	-- grew back to twelve studs would be a collidable body inside solid rock, and it would be shoved
	-- out of the doorway by the wall the moment the stun released it.
end

-- The pace it should be walking at right now: its built speed, reduced while a blast limp is still
-- running and again while it is folded through an opening. Read rather than assumed so releasing a
-- stun cannot silently undo a slow that outlives it.
--
-- The fold's cost is the only thing StoneWardenSqueeze takes off the Warden, and it is worth stating
-- what it is replacing: before it, a tight doorway did not slow the pursuit down, it ENDED it.
function StoneWardenBehavior:_effectiveWalkSpeed()
	local speed = self.BaseWalkSpeed
	if tick() < self.SlowUntil then
		speed *= Config.Dynamite.threat.wardenSlowMultiplier
	end
	if self.Squeeze ~= nil and self.Squeeze:isFolded() then
		speed *= Config.StoneWarden.squeeze.walkSpeedMultiplier
	end
	return speed
end

-- Write the pace only when it actually changed. Every source above expires on its own clock, so an
-- edge-per-source scheme needed one flag per source and silently kept the last one that wrote when a
-- second overlapped it.
function StoneWardenBehavior:_syncWalkSpeed()
	local humanoid = self.ActiveModel:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	local desired = self:_effectiveWalkSpeed()
	if math.abs(humanoid.WalkSpeed - desired) > 0.01 then
		humanoid.WalkSpeed = desired
	end
end

-- A STICK OF DYNAMITE, ON THE ONE THING IN THE CAVE THAT IS NOT A THREAT ROW.
--
-- DESIGN §9 promises the Warden has exactly ONE counter — leading it under a falling crown — and this
-- does not break that promise: `wardenHitPoints` is three sticks at point blank, which is more than
-- the carry cap and vastly more than a run will ever be holding at once. What a stick actually buys is
-- a stun and then a limp, which is the same currency the crown deals in (time to get away) at a much
-- worse exchange rate. Killing one is theoretically reachable and practically absurd, which is the
-- correct shape for an encounter built to be escaped rather than beaten.
--
-- Returns true if this was the blast that finished it.
function StoneWardenBehavior:Blast(damage)
	if self.Destroyed or self.State ~= "ACTIVE" then
		return false
	end
	local incoming = math.max(damage or 0, 0)
	if incoming <= 0 then
		return false
	end
	self.BlastDamage = self.BlastDamage + incoming
	if self.BlastDamage >= Config.Dynamite.threat.wardenHitPoints then
		self:Destroy()
		return true
	end
	self.SlowUntil = math.max(self.SlowUntil, tick() + Config.Dynamite.threat.wardenSlowSeconds)
	-- Routed through the ordinary stun so the rubble cue, the animator's sag and the disarmed kill
	-- contact all behave exactly as they do under a crown. A blast is a smaller crown, not a new state.
	self:Stun(Config.Dynamite.threat.wardenStunSeconds)
	return false
end

function StoneWardenBehavior:_releaseStun()
	local humanoid = self.ActiveModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = self:_effectiveWalkSpeed()
	end
	if self.RubbleEmitter then
		self.RubbleEmitter.Enabled = false
	end
end

function StoneWardenBehavior:_updateLoop()
	local stunHeld = false
	while true do
		task.wait(Config.StoneWarden.pathRefreshSeconds)
		if self.Destroyed then
			break
		end
		-- RunOrchestrator destroys the whole floor model between runs. Stop the loop with it,
		-- and take the warden back out of the hazard registry on the way out.
		if self.ActiveModel.Parent == nil then
			self:Destroy()
			break
		end
		if self.State == "ACTIVE" then
			if self:IsStunned() then
				stunHeld = true
			else
				if stunHeld then
					stunHeld = false
					self:_releaseStun()
				end
				-- Both the blast limp and the fold outlive the events that started them, so the pace is
				-- re-derived every tick rather than written on an edge. Without this a Warden blasted
				-- once would keep the reduced speed for the rest of the floor, because nothing else
				-- ever wrote WalkSpeed again.
				self:_syncWalkSpeed()
				self:_trackNearestPlayer()
			end
		end
	end
end

-- Immediate, idempotent teardown for an individually-owned encounter. Ordinary floors still get
-- this for free when their parent model disappears; developer rooms can call it directly without
-- resetting the registry or disturbing another player's Warden.
function StoneWardenBehavior:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.State = "DESTROYED"
	if self.TouchConnection ~= nil then
		self.TouchConnection:Disconnect()
		self.TouchConnection = nil
	end
	if self.RegistryEntry ~= nil then
		WardenRegistry.unregister(self.RegistryEntry)
		self.RegistryEntry = nil
	end
	if self.Animator ~= nil then
		self.Animator.OnFootPlant = nil
		self.Animator:destroy()
	end
	if self.Squeeze ~= nil then
		self.Squeeze:destroy()
	end
	for _, piece in self.WaxPieces do
		if piece.Parent ~= nil then
			piece:Destroy()
		end
	end
	if self.DormantModel ~= nil and self.DormantModel.Parent ~= nil then
		self.DormantModel:Destroy()
	end
	if self.ActiveModel ~= nil and self.ActiveModel.Parent ~= nil then
		self.ActiveModel:Destroy()
	end
	table.clear(self.LastContactAt)
end

function StoneWardenBehavior:_trackNearestPlayer()
	local nearestPlayer = nil
	local shortestDistance = math.huge
	local wardenPos = self.ActiveModel.PrimaryPart.Position

	for _, player in ipairs(Players:GetPlayers()) do
		local state = PlayerState.get(player.UserId)
		local char = player.Character
		if
			state ~= nil
			and state.alive
			and not state.finished
			and state.snuffedAt == nil
			and state.depth == self.Depth
			and not PlayerState.isThreatProtected(player.UserId)
			and char
			and char:FindFirstChild("HumanoidRootPart")
			and char:FindFirstChild("Humanoid")
			and char.Humanoid.Health > 0
		then
			local dist = (char.HumanoidRootPart.Position - wardenPos).Magnitude
			if dist < shortestDistance then
				shortestDistance = dist
				nearestPlayer = char
			end
		end
	end

	if nearestPlayer then
		self.Animator:setNearTarget(shortestDistance)
		local targetRoot = nearestPlayer.HumanoidRootPart
		local velocity = targetRoot.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		-- THE LISTENING BEAT, ONCE PER STOP — not a halt that lasts as long as you hold still.
		--
		-- A player who stops moving buys `stationaryPauseSeconds` of stillness out of the Warden, and
		-- then it comes on regardless. What this replaced re-armed the pause on the very next refresh:
		-- clearing `IsPaused` fell straight through to one MoveTo, and 0.3 s later the player was still
		-- stationary and `IsPaused` was false again, so it stopped itself and started another three
		-- second wait. The pursuit was a two-stud lurch every three seconds — a Warden that only walked
		-- while you did, which is not what the beat is for and read as a broken golem.
		--
		-- The pause is therefore spent per stationary episode and only re-armed by the player actually
		-- moving again (or by a different player becoming the nearest target).
		if nearestPlayer ~= self.PauseTarget then
			self.PauseTarget = nearestPlayer
			self.IsPaused = false
			self.PauseSpent = false
		end
		if horizontalSpeed < 2 then
			if not self.PauseSpent then
				if not self.IsPaused then
					self.IsPaused = true
					self.PauseTimer = tick()
					self.ActiveModel.Humanoid:MoveTo(self.ActiveModel.PrimaryPart.Position) -- Stop
				end

				if tick() - self.PauseTimer > Config.StoneWarden.stationaryPauseSeconds then
					self.IsPaused = false
					self.PauseSpent = true
				else
					return -- Stay paused
				end
			end
		else
			self.IsPaused = false
			self.PauseSpent = false
		end

		-- Pathfinding Logic.
		--
		-- SIZED TO THE FOLDED BODY, NOT THE STANDING ONE. This asked for a 12-stud agent, which is the
		-- Warden's standing height — and PathfindingService refuses to route an agent through anything
		-- shorter than it is. Config/Floors rolls doorways between 8 and 13 studs tall, so most of the
		-- openings on a floor were not merely awkward for the pursuit, they did not exist for it: every
		-- ComputeAsync through one failed and fell through to the direct-line fallback below, which
		-- walks a twelve-stud body into the rock above the arch and leaves it there.
		--
		-- The agent is now the body it can actually make itself into (StoneWardenSqueeze). Planning a
		-- route through an opening it has to fold for is correct: folding is what it does when it gets
		-- there, and the probe that decides that reads the real cave rather than this plan.
		local squeeze = Config.StoneWarden.squeeze
		local path = PathfindingService:CreatePath({
			AgentRadius = squeeze.agentRadius,
			AgentHeight = squeeze.agentHeight,
			AgentCanJump = false,
			WaypointSpacing = 4,
		})

		local success = pcall(function()
			path:ComputeAsync(self.ActiveModel.PrimaryPart.Position, targetRoot.Position)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			if #waypoints > 1 then
				self.ActiveModel.Humanoid:MoveTo(waypoints[2].Position)
			end
		else
			-- Structural rock is a harder boundary than pursuit. Hold here and let the next refresh retry;
			-- direct movement on a failed route is exactly how a Warden walks into a cave wall.
			self.ActiveModel.Humanoid:MoveTo(self.ActiveModel.PrimaryPart.Position)
		end
	else
		self.Animator:setNearTarget(nil)
		-- No one left to listen for. The next player to come into range gets a fresh listening beat.
		self.PauseTarget = nil
		self.IsPaused = false
		self.PauseSpent = false
	end
end

return StoneWardenBehavior
