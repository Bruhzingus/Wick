-- StoneWardenSqueeze.lua
--
-- THE WARDEN COULD NOT GET THROUGH THE DOOR.
--
-- Config/Floors.geometry rolls every doorway on a floor between 8 and 13 studs tall and 8 and 45
-- wide. The Warden's authoritative root is 12 studs tall and 6 wide, and the pursuit asked
-- PathfindingService for an agent 12 studs tall. Both halves of that failed at once:
--
--   * PHYSICALLY, a 12-stud body does not pass under an 8-stud arch. It walked into the rock above
--     the opening and stopped.
--   * PLANNING-WISE, a 12-stud agent makes PathfindingService refuse to route through ANY opening
--     shorter than 12, so most of the doorways on a floor were not merely hard for it — they were
--     invisible, and `ComputeAsync` fell through to the direct-line fallback that walks into walls.
--
-- The encounter is built to be escaped rather than beaten (DESIGN §9), and that is a promise about
-- OUTRUNNING it, not about finding a short doorway and watching it give up. A player who learns that
-- a low arch stops it dead has been handed a way to ignore the whole set-piece.
--
-- So it folds. This module owns the authoritative root's SIZE — the one thing the animator is
-- forbidden to touch — probes the space in front of the body, and drives a single 0..1 blend that the
-- root shape and the pose both read. What the player sees is a mass dropping onto its knees, rolling
-- its shoulders in and grinding itself through an opening that is plainly too small for it.
--
-- WHAT THIS DOES NOT CHANGE. Contact still kills through the same Touched connection on the same
-- part, the stun still disarms it, and the crown is still the counter. The one cost the fold carries
-- is `walkSpeedMultiplier` while it is folded — the Warden pays time to pass a tight opening, which
-- is the same currency every other counter in this encounter deals in.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local StoneWardenSqueeze = {}
StoneWardenSqueeze.__index = StoneWardenSqueeze

-- Height the forward and lateral probes are cast from, above the ground the body is standing on. Off
-- the floor far enough to clear the lip of an eroded doorway sill, and well under the shortest arch.
local PROBE_FOOT_LIFT = 0.9

local function damp(current, target, seconds, dt)
	if seconds <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-dt / seconds))
end

function StoneWardenSqueeze.new(rig, config)
	local self = setmetatable({}, StoneWardenSqueeze)
	self.Rig = rig
	self.Config = config
	self.Enabled = false
	self.Blend = 0
	self.Folded = false
	self.ConstrictedUntil = 0
	self.NextProbeAt = 0
	self.LastGrindAt = -math.huge
	self.Destroyed = false
	-- Fired with a world position each time stone starts dragging on stone. The behaviour turns it
	-- into the broadcast grind cue; nothing here knows a client exists.
	self.OnGrind = nil
	-- Fired with the new fold state on the EDGE, not with the ramp. The pose runs its own smoothing
	-- off its own window (motion.squeezeBlendSeconds), which is deliberately shorter than the root's:
	-- the body starts ducking a beat before the hitbox shrinks, which is what a creature deciding to
	-- fold looks like, rather than a hitbox that changed and a pose that caught up.
	self.OnFold = nil

	self.HeartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if rig.model.Parent == nil then
			self:destroy()
			return
		end
		self:step(dt)
	end)

	return self
end

-- Only a walking Warden folds. Set false through the emergence (the root is anchored and being
-- placed by hand) and through a stun (the body is under rubble and owns its own silhouette).
function StoneWardenSqueeze:setEnabled(enabled)
	if self.Enabled == enabled then
		return
	end
	self.Enabled = enabled
	if not enabled then
		self.ConstrictedUntil = 0
	end
end

function StoneWardenSqueeze:blend()
	return self.Blend
end

function StoneWardenSqueeze:isFolded()
	return self.Folded
end

function StoneWardenSqueeze:_raycastParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Its own body, and every character in the world. A player standing in the mouth of a doorway is
	-- the single most likely thing to be in front of a pursuing Warden, and reading them as rock
	-- would make it fold in open floor every time it got close to somebody.
	local ignore: { Instance } = { self.Rig.model }
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignore, character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

-- Is the space the body is about to walk into too small for it standing up? Answered from the CAVE
-- rather than from the floor plan on purpose: the plan knows where doorways are, but a Warden is also
-- stopped by a collapsed formation, a boulder pinch or a low shelf, and none of those are doorways.
function StoneWardenSqueeze:_probeConstricted(): boolean
	local config = self.Config
	local root = self.Rig.root
	local cframe = root.CFrame
	local look = cframe.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return false
	end
	local forward = flat.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local groundY = root.Position.Y - root.Size.Y / 2
	local params = self:_raycastParams()

	-- Measured against the STANDING body in every case, including while already folded: the question
	-- is always "could it stand up here", never "does it still fit as it is". Asking the second one
	-- would let it stand up inside an arch the moment the fold made it fit.
	local ceilingReach = config.standingHeight + config.heightClearance - PROBE_FOOT_LIFT
	local halfNeeded = config.standingWidth / 2 + config.widthClearance
	local eyeLine = Vector3.new(0, PROBE_FOOT_LIFT, 0)
	local origin = Vector3.new(root.Position.X, groundY, root.Position.Z) + eyeLine

	for _, distance in config.probeDistances do
		local sample = origin + forward * distance
		-- Do not ask about a place the body cannot reach. Without this, a Warden standing a few studs
		-- from any wall would sample INSIDE that wall and fold in the middle of an open room.
		if distance > 0.5 then
			local blocked = workspace:Raycast(origin, forward * distance, params)
			if blocked ~= nil and blocked.Distance < distance - 0.5 then
				continue
			end
		end

		local ceiling = workspace:Raycast(sample, Vector3.new(0, ceilingReach, 0), params)
		if ceiling ~= nil then
			return true
		end

		local waist = sample + Vector3.new(0, config.standingHeight * 0.45 - PROBE_FOOT_LIFT, 0)
		local leftWall = workspace:Raycast(waist, -right * halfNeeded, params)
		if leftWall ~= nil and workspace:Raycast(waist, right * halfNeeded, params) ~= nil then
			return true
		end
	end
	return false
end

-- The root actually changes shape here, and the body's SOLES have to stay on the cave while it does.
-- A Humanoid keeps the bottom of its root on the ground, so a root that loses height keeps its centre
-- and lifts its feet off the floor; the compensating drop below is what turns that into a crouch
-- instead of a hover followed by a fall.
function StoneWardenSqueeze:_applyRootShape(blend)
	local config = self.Config
	local root = self.Rig.root
	if root.Anchored or root.Parent == nil then
		return
	end
	local height = config.standingHeight + (config.squeezedHeight - config.standingHeight) * blend
	local width = config.standingWidth + (config.squeezedWidth - config.standingWidth) * blend
	if math.abs(height - root.Size.Y) < 0.01 and math.abs(width - root.Size.X) < 0.01 then
		return
	end
	local bottom = root.Position.Y - root.Size.Y / 2
	local rotation = root.CFrame - root.CFrame.Position
	root.Size = Vector3.new(width, height, root.Size.Z)
	root.CFrame = CFrame.new(root.Position.X, bottom + height / 2, root.Position.Z) * rotation
end

function StoneWardenSqueeze:step(dt)
	if self.Destroyed then
		return
	end
	local config = self.Config
	local now = tick()

	if self.Enabled and config.enabled then
		if now >= self.NextProbeAt then
			self.NextProbeAt = now + config.probeSeconds
			if self:_probeConstricted() then
				-- Held past the last clear reading rather than released on it. The probe looks AHEAD, so
				-- the moment the opening stops being in front of the body it is around the body — and
				-- standing up there is standing up inside the arch.
				self.ConstrictedUntil = now + config.releaseGraceSeconds
			end
		end
	end

	local folded = self.Enabled and config.enabled and now < self.ConstrictedUntil
	if folded ~= self.Folded then
		self.Folded = folded
		if self.OnFold ~= nil then
			self.OnFold(folded)
		end
		if folded and self.OnGrind ~= nil and now - self.LastGrindAt >= config.grindCueSeconds then
			self.LastGrindAt = now
			local ok, err = pcall(self.OnGrind, self.Rig.root.Position)
			if not ok then
				warn("[WICK WARDEN] squeeze presentation failed: " .. tostring(err))
			end
		end
	end

	local target = if folded then 1 else 0
	local window = if folded then config.enterSeconds else config.exitSeconds
	self.Blend = damp(self.Blend, target, window, math.min(math.max(dt, 0), 1 / 20))
	if self.Blend < 0.002 then
		self.Blend = 0
	elseif self.Blend > 0.998 then
		self.Blend = 1
	end

	self:_applyRootShape(self.Blend)

	local dust = self.Rig.shoulderDust
	if dust ~= nil then
		local shedding = self.Blend > 0.15
		if dust.Enabled ~= shedding then
			dust.Enabled = shedding
		end
		if shedding then
			dust.Rate = config.dustRate * self.Blend
		end
	end
end

function StoneWardenSqueeze:destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.OnGrind = nil
	self.OnFold = nil
	if self.HeartbeatConnection ~= nil then
		self.HeartbeatConnection:Disconnect()
		self.HeartbeatConnection = nil
	end
	local dust = self.Rig.shoulderDust
	if dust ~= nil and dust.Parent ~= nil then
		dust.Enabled = false
	end
end

return StoneWardenSqueeze
