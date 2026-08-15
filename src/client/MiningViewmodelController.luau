--!strict
-- Local-only mining tool presentation.
--
-- The coordinator tells this module when an authoritative stance opens/closes and when the player
-- begins a predicted swing. This module owns only the camera-space pickaxe, its target-aligned
-- motion, trail, and draw/stow fade. It never sends remotes and never decides strike outcomes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MiningViewmodelController = {}

local pickaxeModel: Model? = nil
local pickaxeWanted = false
local pickaxeFadeAlpha = 0

local stanceOpen = false
local engagedAt = 0
local engagedTarget: BasePart? = nil
local swingStartedAt = -math.huge
local swingAccuracy: string? = nil
local swingDepleted = false
local swingTarget: BasePart? = nil

-- THE PRIME, 0 at READY and 1 at fully cocked. Driven by the coordinator from the live sweep clock, so
-- the arm winds up in step with the marker the player is reading rather than on a clock of its own.
local primeAlpha = 0
-- What the prime at the instant of the CLICK left for the swing to do. A strike that began from a
-- half-cocked arm plays a half-length anticipation from where the arm actually was, so the animation
-- never rewinds itself: `raisedOffset` is only the start pose for a completely unprimed strike, which
-- is exactly what a click during the wind-up is.
local swingAnticipationSeconds = Config.Mining.pickaxe.anticipationSeconds
local swingStartOffset = Config.Mining.pickaxe.raisedOffset

local function toolPart(
	model: Model,
	className: "Part" | "WedgePart",
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material
): BasePart
	local created = Instance.new(className) :: BasePart
	created.Name = name
	created.Size = size
	created.CFrame = at
	created.Color = color
	created.Material = material
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = false
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = model
	return created
end

local function buildPickaxe(): Model
	local cfg = Config.Mining.pickaxe
	local model = Instance.new("Model")
	model.Name = "WickPickaxe"

	local handle =
		toolPart(model, "Part", "Handle", cfg.handleSize, CFrame.identity, cfg.handleColor, Enum.Material.Wood)
	local headY = cfg.handleSize.Y / 2 + cfg.headSize.Y * 0.15
	local headAt = CFrame.new(0, headY, 0)
	toolPart(model, "Part", "HeadEye", cfg.headSize, headAt, cfg.headColor, Enum.Material.Metal)

	local prongOffset = (cfg.headSize.X + cfg.prongSize.X) * 0.5 - 0.08
	local leftProng = toolPart(
		model,
		"WedgePart",
		"LeftProng",
		cfg.prongSize,
		headAt * CFrame.new(-prongOffset, 0, 0) * CFrame.Angles(0, math.rad(-90), 0),
		cfg.headEdgeColor,
		Enum.Material.Metal
	)
	local rightProng = toolPart(
		model,
		"WedgePart",
		"RightProng",
		cfg.prongSize,
		headAt * CFrame.new(prongOffset, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
		cfg.headEdgeColor,
		Enum.Material.Metal
	)
	toolPart(
		model,
		"Part",
		"Collar",
		cfg.collarSize,
		CFrame.new(0, cfg.handleSize.Y / 2 - cfg.collarSize.Y * 0.35, 0),
		cfg.headColor,
		Enum.Material.Metal
	)

	for index = 1, math.max(0, math.floor(cfg.gripCount)) do
		local y = -cfg.handleSize.Y / 2 + 0.18 + (index - 1) * cfg.gripSpacing
		local wrap = toolPart(
			model,
			"Part",
			"GripWrap",
			cfg.gripSize,
			CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(index * 18), 0),
			cfg.gripColor,
			Enum.Material.Fabric
		)
		wrap.Transparency = 0.05
	end

	local leftTrail = Instance.new("Attachment")
	leftTrail.Name = "TrailLeft"
	leftTrail.Position = Vector3.new(-cfg.prongSize.X * 0.35, 0, 0)
	leftTrail.Parent = leftProng
	local rightTrail = Instance.new("Attachment")
	rightTrail.Name = "TrailRight"
	rightTrail.Position = Vector3.new(cfg.prongSize.X * 0.35, 0, 0)
	rightTrail.Parent = rightProng
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = leftTrail
	trail.Attachment1 = rightTrail
	trail.Color = ColorSequence.new(cfg.trailColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.48),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.trailWidthScale),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.FaceCamera = true
	trail.Lifetime = cfg.trailLifetime
	trail.LightEmission = 0.4
	trail.Enabled = false
	trail.Parent = handle

	model.PrimaryPart = handle
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("WickBaseTransparency", descendant.Transparency)
			descendant.Transparency = 1
		end
	end
	return model
end

local function setPickaxeVisible(visible: boolean)
	pickaxeWanted = visible
	if not visible then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	if pickaxeModel == nil then
		local built = buildPickaxe()
		built.Parent = camera
		pickaxeModel = built
	elseif pickaxeModel.Parent ~= camera then
		pickaxeModel.Parent = camera
	end
end

local function destroyPickaxe()
	pickaxeWanted = false
	pickaxeFadeAlpha = 0
	if pickaxeModel ~= nil then
		pickaxeModel:Destroy()
		pickaxeModel = nil
	end
end

local function updatePickaxeVisibility(dt: number)
	local built = pickaxeModel
	if built == nil then
		pickaxeFadeAlpha = 0
		return
	end
	local target = if pickaxeWanted then 1 else 0
	local seconds = if pickaxeWanted then Config.Mining.pickaxe.raiseSeconds else Config.Mining.qte.exitSeconds
	local step = math.clamp(dt / math.max(seconds, 0.01), 0, 1)
	pickaxeFadeAlpha += (target - pickaxeFadeAlpha) * step
	for _, descendant in built:GetDescendants() do
		if descendant:IsA("BasePart") then
			local baseTransparency = tonumber(descendant:GetAttribute("WickBaseTransparency")) or 0
			descendant.Transparency = 1 - pickaxeFadeAlpha * (1 - baseTransparency)
		end
	end
	if not pickaxeWanted and pickaxeFadeAlpha <= 0.015 then
		destroyPickaxe()
	end
end

-- The complete tool motion as a function of the local prediction clock. The impact pause, rebound,
-- and outcome-specific offsets make the tool feel as though it contacted mass instead of tracing a
-- generic cursor arc.
local function pickaxeOffset(now: number): CFrame
	local cfg = Config.Mining.pickaxe
	local sinceSwing = now - swingStartedAt
	local contactOffset = if swingDepleted
		then cfg.breakOffset
		elseif swingAccuracy == "Miss" then cfg.glanceOffset
		else cfg.strikeOffset
	local reboundOffset = if swingDepleted
		then contactOffset:Lerp(cfg.reboundOffset, 0.45)
		elseif swingAccuracy == "Perfect" then contactOffset:Lerp(cfg.reboundOffset, 0.68)
		elseif swingAccuracy == "Miss" then contactOffset:Lerp(cfg.reboundOffset, 0.82)
		else cfg.reboundOffset

	-- The anticipation beat is per-swing rather than a constant, because the prime may already have
	-- covered some or all of it. Everything downstream is measured off this, so a shortened wind-up
	-- moves the contact, the rebound and the recovery earlier as one piece.
	local anticipation = swingAnticipationSeconds
	if sinceSwing >= 0 then
		if sinceSwing < anticipation then
			local alpha = sinceSwing / math.max(anticipation, 0.01)
			return swingStartOffset:Lerp(cfg.anticipationOffset, 1 - (1 - alpha) * (1 - alpha))
		end
		if sinceSwing < anticipation + cfg.swingSeconds then
			local alpha = (sinceSwing - anticipation) / math.max(cfg.swingSeconds, 0.01)
			return cfg.anticipationOffset:Lerp(contactOffset, alpha * alpha * alpha)
		end
		if sinceSwing < anticipation + cfg.swingSeconds + cfg.impactSeconds then
			return contactOffset
		end
		if sinceSwing < anticipation + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds then
			local alpha = (sinceSwing - anticipation - cfg.swingSeconds - cfg.impactSeconds)
				/ math.max(cfg.reboundSeconds, 0.01)
			return contactOffset:Lerp(reboundOffset, 1 - (1 - alpha) * (1 - alpha))
		end
		local recoverStart = anticipation + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds
		if sinceSwing < recoverStart + cfg.recoverSeconds then
			local alpha = (sinceSwing - recoverStart) / math.max(cfg.recoverSeconds, 0.01)
			local target = if stanceOpen then cfg.raisedOffset else cfg.restOffset
			return reboundOffset:Lerp(target, 1 - (1 - alpha) * (1 - alpha))
		end
	end

	if not stanceOpen then
		return cfg.restOffset
	end

	local drawn = math.clamp((now - engagedAt) / math.max(cfg.raiseSeconds, 0.01), 0, 1)
	-- READY, then drifting back into the cocked pose as the marker travels. This is the slow half of
	-- the swing: the player is watching one continuous wind-up, and the click is what ends it.
	local held = cfg.restOffset:Lerp(cfg.raisedOffset, drawn):Lerp(cfg.anticipationOffset, primeAlpha)
	-- A cocked arm stops breathing. Damping the idle motion as the prime completes leaves the marker as
	-- the only thing moving while the read is happening.
	local steadiness = 1 - math.clamp(cfg.primeSteadiness, 0, 1) * primeAlpha
	local bob = math.sin((now / math.max(cfg.bobSeconds, 0.01)) * math.pi * 2) * cfg.bobStuds * steadiness
	local sway = math.sin((now / math.max(cfg.bobSeconds * 1.7, 0.01)) * math.pi * 2)
		* math.rad(cfg.swayDegrees)
		* steadiness
	return held * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, sway)
end

local function swingEndsAt(): number
	local cfg = Config.Mining.pickaxe
	return swingStartedAt
		+ swingAnticipationSeconds
		+ cfg.swingSeconds
		+ cfg.impactSeconds
		+ cfg.reboundSeconds
		+ cfg.recoverSeconds
end

local function pickaxeAimAdjustment(camera: Camera, now: number, activeTarget: BasePart?): CFrame
	local cfg = Config.Mining.pickaxe
	local target = if now < swingEndsAt() then swingTarget else engagedTarget or activeTarget
	if target == nil or target.Parent == nil then
		return CFrame.identity
	end
	local viewportPoint, visible = camera:WorldToViewportPoint(target.Position)
	local viewport = camera.ViewportSize
	if not visible or viewportPoint.Z <= 0 or viewport.X <= 0 or viewport.Y <= 0 then
		return CFrame.identity
	end

	local screenX = math.clamp((viewportPoint.X / viewport.X - 0.5) * 2, -1, 1)
	local screenY = math.clamp((viewportPoint.Y / viewport.Y - 0.5) * 2, -1, 1)
	local adjustment = CFrame.new(screenX * cfg.aimScreenOffsetStuds.X, -screenY * cfg.aimScreenOffsetStuds.Y, 0)
		* CFrame.Angles(math.rad(-screenY * cfg.aimPitchDegrees), math.rad(-screenX * cfg.aimYawDegrees), 0)

	-- The prime leans the tool toward the seam as it cocks, so the aim weight rises with the wind-up
	-- rather than snapping on at the click. Held to the idle fraction's own range until the strike.
	local idle = if stanceOpen then cfg.idleAimFraction + (1 - cfg.idleAimFraction) * primeAlpha * 0.5 else 0
	local anticipation = swingAnticipationSeconds
	local elapsed = now - swingStartedAt
	local weight = idle
	if elapsed >= 0 then
		if elapsed < anticipation then
			local alpha = elapsed / math.max(anticipation, 0.01)
			weight = idle + (1 - idle) * alpha * alpha
		elseif elapsed < anticipation + cfg.swingSeconds + cfg.impactSeconds then
			weight = 1
		elseif elapsed < anticipation + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds then
			local alpha = (elapsed - anticipation - cfg.swingSeconds - cfg.impactSeconds)
				/ math.max(cfg.reboundSeconds, 0.01)
			weight = 1 + (0.45 - 1) * alpha
		elseif elapsed < swingEndsAt() - swingStartedAt then
			local recoverStart = anticipation + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds
			local alpha = (elapsed - recoverStart) / math.max(cfg.recoverSeconds, 0.01)
			weight = 0.45 + (idle - 0.45) * alpha
		end
	end
	return CFrame.new():Lerp(adjustment, math.clamp(weight, 0, 1))
end

function MiningViewmodelController.engage(now: number, target: BasePart?)
	stanceOpen = true
	engagedAt = now
	engagedTarget = target
	swingStartedAt = -math.huge
	swingAccuracy = nil
	swingDepleted = false
	swingTarget = target
	primeAlpha = 0
end

function MiningViewmodelController.disengage()
	stanceOpen = false
	engagedTarget = nil
	primeAlpha = 0
end

-- `prime` is how far the wind-up had already travelled at the moment of the click, 0..1. It decides
-- both where the down-stroke starts from and how much anticipation is left to play: a fully primed
-- arm has none, and swings immediately. Omitted or zero reproduces the original animation exactly.
function MiningViewmodelController.beginStrike(now: number, target: BasePart?, prime: number?)
	local cfg = Config.Mining.pickaxe
	local resolved = if prime ~= nil and prime == prime then math.clamp(prime, 0, 1) else 0
	swingStartedAt = now
	swingAccuracy = nil
	swingDepleted = false
	swingTarget = target
	swingAnticipationSeconds = cfg.anticipationSeconds * (1 - resolved)
	swingStartOffset = cfg.raisedOffset:Lerp(cfg.anticipationOffset, resolved)
	-- The held pose is now the swing's business. Clearing it stops the idle branch from fighting the
	-- strike for a frame if the two are ever evaluated in the same tick.
	primeAlpha = 0
end

function MiningViewmodelController.resolveStrike(accuracy: string, depleted: boolean)
	swingAccuracy = accuracy
	swingDepleted = depleted
end

function MiningViewmodelController.markDepleted()
	swingDepleted = true
end

function MiningViewmodelController.impactTime(): number
	return swingStartedAt + swingAnticipationSeconds + Config.Mining.pickaxe.swingSeconds
end

function MiningViewmodelController.swingEndsAt(): number
	return swingEndsAt()
end

-- `prime` is the live wind-up, 0..1, supplied by the coordinator from the sweep clock. It is ignored
-- while a strike is in flight — the swing owns the tool until it finishes.
function MiningViewmodelController.update(
	dt: number,
	now: number,
	visibleWanted: boolean,
	activeTarget: BasePart?,
	prime: number?
)
	setPickaxeVisible(visibleWanted or now < swingEndsAt())
	updatePickaxeVisibility(dt)

	if now >= swingEndsAt() then
		primeAlpha = if prime ~= nil and prime == prime then math.clamp(prime, 0, 1) else 0
	end

	local camera = Workspace.CurrentCamera
	local built = pickaxeModel
	if built == nil or camera == nil then
		return
	end
	local cfg = Config.Mining.pickaxe
	built:PivotTo(camera.CFrame * pickaxeAimAdjustment(camera, now, activeTarget) * pickaxeOffset(now))
	local trail = built:FindFirstChild("SwingTrail", true)
	if trail ~= nil and trail:IsA("Trail") then
		-- The trail belongs to the FAST half only. Measured off this swing's own anticipation so a
		-- primed strike still streaks from just before contact rather than from the moment of the click.
		local sinceSwing = now - swingStartedAt
		trail.Enabled = sinceSwing >= swingAnticipationSeconds * 0.45
			and sinceSwing <= swingAnticipationSeconds + cfg.swingSeconds + cfg.impactSeconds
	end
end

function MiningViewmodelController.destroy()
	stanceOpen = false
	engagedTarget = nil
	swingStartedAt = -math.huge
	swingTarget = nil
	swingAccuracy = nil
	swingDepleted = false
	primeAlpha = 0
	swingAnticipationSeconds = Config.Mining.pickaxe.anticipationSeconds
	swingStartOffset = Config.Mining.pickaxe.raisedOffset
	destroyPickaxe()
end

return MiningViewmodelController
