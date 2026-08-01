-- StoneWardenBehavior.lua
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WardenRegistry = require(script.Parent.Parent:WaitForChild("WardenRegistry"))
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.Parent:WaitForChild("PlayerState"))
local DeathService = require(script.Parent.Parent:WaitForChild("DeathService"))

local StoneWardenBehavior = {}
StoneWardenBehavior.__index = StoneWardenBehavior

-- parent is optional and defaults to workspace; ServerInit passes the owning floor's model so
-- the dormant pile / active warden are destroyed automatically when that floor is torn down.
-- depth is the floor number this warden belongs to; hazards on that floor (unstable dripstone)
-- look the golem up by it through WardenRegistry.
function StoneWardenBehavior.new(spawnCFrame, relicPart, parent: Instance?, depth: number?)
	local self = setmetatable({}, StoneWardenBehavior)
	self.SpawnCFrame = spawnCFrame
	self.RelicPart = relicPart
	self.Depth = depth or 1
	self.State = "DORMANT"
	self.PauseTimer = 0
	self.IsPaused = false
	self.StunnedUntil = 0
	self.RegistryEntry = nil

	local ModelModule = require(script.Parent:WaitForChild("StoneWardenModel"))
	local modelParent = parent or workspace

	self.DormantModel = ModelModule.buildDormantPile(spawnCFrame)
	self.DormantModel.Parent = modelParent

	self.ActiveModel = ModelModule.buildActiveWarden(spawnCFrame)
	self.ActiveModel.Parent = modelParent
	-- Remembered from the model rather than hardcoded, so the stun restores whatever pace
	-- StoneWardenModel actually built it with.
	local builtHumanoid = self.ActiveModel:FindFirstChildOfClass("Humanoid")
	self.BaseWalkSpeed = builtHumanoid and builtHumanoid.WalkSpeed or 8

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
	self.ActiveModel.PrimaryPart.Anchored = true
	self.ActiveModel.PrimaryPart.CanCollide = false

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
	self.ActiveModel.PrimaryPart.Touched:Connect(function(hit)
		if self.State == "ACTIVE" and not self:IsStunned() then
			local character = hit:FindFirstAncestorOfClass("Model")
			if character == nil then
				return
			end
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local player = Players:GetPlayerFromCharacter(character)
				local state = player and PlayerState.get(player.UserId) or nil
				if state ~= nil and state.alive and not state.finished and state.depth == self.Depth then
					DeathService.kill(player.UserId, "Snuffed", "The Stone Warden crushed your flame.")
				end
			end
		end
	end)

	-- Relic Touch Logic
	self.RelicPart.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if character and character:FindFirstChildOfClass("Humanoid") and self.State == "DORMANT" then
			self:Activate()
			self.RelicPart:Destroy()
		end
	end)

	task.spawn(function()
		self:_updateLoop()
	end)

	return self
end

function StoneWardenBehavior:Activate()
	if self.State ~= "DORMANT" then
		return
	end
	self.State = "EMERGING"
	print("The wall breathes. The Stone-Warden is emerging.")

	self.ActiveModel.PrimaryPart.CanCollide = true
	self.ActiveModel.PrimaryPart.Anchored = false

	-- Force server ownership so it doesn't stutter
	self.ActiveModel.PrimaryPart:SetNetworkOwner(nil)

	local duration = Config.StoneWarden.emergenceSeconds
	local startTime = tick()

	while tick() - startTime < duration do
		local progress = (tick() - startTime) / duration
		for _, part in ipairs(self.DormantModel:GetDescendants()) do
			if part:IsA("BasePart") then
				local original = self.DormantTransparency[part] or 0
				part.Transparency = original + (1 - original) * progress
			end
		end
		for _, part in ipairs(self.ActiveModel:GetDescendants()) do
			if part:IsA("BasePart") then
				local original = self.ActiveTransparency[part] or 0
				part.Transparency = 1 - (1 - original) * progress
			end
		end
		-- Rise from ground using PivotTo
		self.ActiveModel:PivotTo(self.SpawnCFrame * CFrame.new(0, 6 - (15 * (1 - progress)), 0))
		task.wait(0.1)
	end

	self.DormantModel:Destroy()
	self.State = "ACTIVE"

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
	})
end

function StoneWardenBehavior:IsStunned()
	return tick() < self.StunnedUntil
end

-- Root the golem where it stands. Overlapping strikes extend the window; they never shorten it.
function StoneWardenBehavior:Stun(seconds)
	if self.State ~= "ACTIVE" then
		return
	end
	self.StunnedUntil = math.max(self.StunnedUntil, tick() + math.max(seconds or 0, 0))
	self.IsPaused = false
	local humanoid = self.ActiveModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(self.ActiveModel.PrimaryPart.Position)
	end
	if self.RubbleEmitter then
		self.RubbleEmitter.Enabled = true
	end
end

function StoneWardenBehavior:_releaseStun()
	local humanoid = self.ActiveModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = self.BaseWalkSpeed
	end
	if self.RubbleEmitter then
		self.RubbleEmitter.Enabled = false
	end
end

function StoneWardenBehavior:_updateLoop()
	local stunHeld = false
	while true do
		task.wait(Config.StoneWarden.pathRefreshSeconds)
		-- RunOrchestrator destroys the whole floor model between runs. Stop the loop with it,
		-- and take the warden back out of the hazard registry on the way out.
		if self.ActiveModel.Parent == nil then
			if self.RegistryEntry ~= nil then
				WardenRegistry.unregister(self.RegistryEntry)
				self.RegistryEntry = nil
			end
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
				self:_trackNearestPlayer()
			end
		end
	end
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
		local targetRoot = nearestPlayer.HumanoidRootPart
		local velocity = targetRoot.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		-- Pause Logic: If player is basically not moving
		if horizontalSpeed < 2 then
			if not self.IsPaused then
				self.IsPaused = true
				self.PauseTimer = tick()
				self.ActiveModel.Humanoid:MoveTo(self.ActiveModel.PrimaryPart.Position) -- Stop
			end

			-- Resume after 3 seconds of player standing still
			if tick() - self.PauseTimer > Config.StoneWarden.stationaryPauseSeconds then
				self.IsPaused = false
			else
				return -- Stay paused
			end
		else
			self.IsPaused = false
		end

		-- Pathfinding Logic
		local path = PathfindingService:CreatePath({
			AgentRadius = 3.0,
			AgentHeight = 12.0,
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
			-- Fallback to direct movement if pathing fails
			self.ActiveModel.Humanoid:MoveTo(targetRoot.Position)
		end
	end
end

return StoneWardenBehavior
