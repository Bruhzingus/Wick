--!strict
-- Local-only dynamite presentation: the stick in your hands, and the three beats of throwing it.
--
-- The coordinator (client/DynamiteController) tells this module when a stick is drawn, how far the
-- wind-up has travelled, and when the throw was released. This module owns only the camera-space
-- stick, its poses, and the draw/stow fade. It never sends remotes, never reads the bag, and never
-- decides whether a throw was legal — a refused throw is corrected by the coordinator putting a
-- stick back in frame, not by anything here.
--
-- BUILT FROM `NewModelsAndObjects/Dynamite.buildStick`, deliberately, rather than from a bespoke
-- held-stick model. It is the same silhouette the player picks up off the floor and the same one
-- they watch land, so the thing in their hands is recognisably the thing they are about to throw.
--
-- WHY THE STICK VANISHES MID-ANIMATION. At the end of the release stroke the server's thrown charge
-- already exists and is flying, so from that instant there are two sticks unless this one goes. It
-- is hidden instantly rather than faded: a stick that dissolves out of your hand while an identical
-- one arcs away reads as a duplication bug, which is exactly what it would be.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DynamiteModel = require(ReplicatedStorage.Shared.NewModelsAndObjects.Dynamite)

local DynamiteViewmodelController = {}

local BASE_TRANSPARENCY_ATTRIBUTE = "WickBaseTransparency"

local stickModel: Model? = nil
-- Whether the coordinator wants a stick in frame at all. Drives the draw/stow fade; the throw
-- overrides it for its own short window (see `stickWanted`).
local held = false
local fadeAlpha = 0

-- The live wind-up, 0 (just pressed) to 1 (fully cocked), written every frame by the coordinator.
local windupAlpha = 0
-- The throw in flight. `throwFromAlpha` is where the wind-up had actually got to at the instant of
-- release, so the release stroke starts from the pose that was on screen rather than snapping to a
-- full cock the player never reached.
local throwStartedAt = -math.huge
local throwFromAlpha = 0
-- Whether this throw's one instant hide has already been applied. Starts true because there is no
-- throw in flight at startup, and a pending snap with `throwStartedAt` at -infinity would fire on
-- the first frame and blank a stick that was never thrown.
local releaseSnapped = true

local function viewmodelConfig()
	return Config.Dynamite.viewmodel
end

local function releaseEndsAt(): number
	return throwStartedAt + viewmodelConfig().releaseSeconds
end

local function throwEndsAt(): number
	local cfg = viewmodelConfig()
	return throwStartedAt + cfg.releaseSeconds + cfg.recoverSeconds
end

local function buildStick(): Model
	local cfg = viewmodelConfig()
	local model = Instance.new("Model")
	model.Name = "WickHeldDynamite"

	local root = Instance.new("Part")
	root.Name = "HeldRoot"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.CFrame = CFrame.identity
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	-- Centred on the root rather than standing on it: `buildStick` authors a stick upright with its
	-- base at the origin, and a pose CFrame that rotates about the base swings the whole stick through
	-- an arc instead of turning it in place.
	local length = Config.Dynamite.visual.stickLength * cfg.stickScale
	DynamiteModel.buildStick(model, CFrame.new(0, -length / 2, 0), cfg.stickScale)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- A viewmodel sits inside the camera's near plane; a shadow cast from there lands on nothing
			-- and costs a draw either way.
			descendant.CastShadow = false
			descendant:SetAttribute(BASE_TRANSPARENCY_ATTRIBUTE, descendant.Transparency)
			descendant.Transparency = 1
		end
	end
	return model
end

local function destroyStick()
	fadeAlpha = 0
	if stickModel ~= nil then
		stickModel:Destroy()
		stickModel = nil
	end
end

-- Whether a stick belongs in frame this instant. Through the whip it is true no matter what the
-- coordinator wants — the stick is mid-flight out of the hand and cannot be recalled — and from the
-- release onward it is the ordinary held state again, so a player with another stick draws a fresh
-- one across the recover while a player who threw their last one comes back empty.
local function stickWanted(now: number): boolean
	if now >= throwStartedAt and now < releaseEndsAt() then
		return true
	end
	return held
end

local function ensureStick()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	if stickModel == nil then
		local built = buildStick()
		built.Parent = camera
		stickModel = built
	elseif stickModel.Parent ~= camera then
		stickModel.Parent = camera
	end
end

local function updateVisibility(dt: number, now: number)
	local wanted = stickWanted(now)
	if wanted then
		ensureStick()
	end
	local built = stickModel
	if built == nil then
		fadeAlpha = 0
		return
	end

	local cfg = viewmodelConfig()
	-- THE INSTANT IT LEAVES THE HAND, once, with no fade. Everything else about this module eases;
	-- this one transition must not, because the server's thrown charge is already in the air and a
	-- stick dissolving out of the hand beside it would read as one stick becoming two.
	if not releaseSnapped and now >= releaseEndsAt() then
		releaseSnapped = true
		fadeAlpha = 0
	else
		local target = if wanted then 1 else 0
		local seconds = if wanted then cfg.drawSeconds else cfg.stowSeconds
		local step = math.clamp(dt / math.max(seconds, 0.01), 0, 1)
		fadeAlpha += (target - fadeAlpha) * step
	end

	for _, descendant in built:GetDescendants() do
		if descendant:IsA("BasePart") then
			local base = tonumber(descendant:GetAttribute(BASE_TRANSPARENCY_ATTRIBUTE)) or 0
			descendant.Transparency = 1 - fadeAlpha * (1 - base)
		end
	end

	if not wanted and fadeAlpha <= 0.015 then
		destroyStick()
	end
end

-- The complete pose as a function of the local clock. Three beats during a throw — whip, then
-- recover — and a breathing held pose the rest of the time.
local function stickOffset(now: number): CFrame
	local cfg = viewmodelConfig()
	local cocked = cfg.heldOffset:Lerp(cfg.windupOffset, throwFromAlpha)

	if now >= throwStartedAt and now < throwEndsAt() then
		local sinceThrow = now - throwStartedAt
		if sinceThrow < cfg.releaseSeconds then
			-- THE WHIP. Cubic-in, so the stick accelerates out of the cock rather than sliding: a throw
			-- that travels at a constant rate has no moment of release in it.
			local alpha = math.clamp(sinceThrow / math.max(cfg.releaseSeconds, 0.01), 0, 1)
			local eased = alpha * alpha * alpha
			local spin = CFrame.Angles(math.rad(cfg.releaseSpinDegrees) * eased, 0, 0)
			return cocked:Lerp(cfg.releaseOffset, eased) * spin
		end
		-- THE RECOVER. The hand comes back empty and a fresh stick fades into it on the way — which is
		-- what makes carrying several read as a bag rather than as a respawning prop.
		local alpha = math.clamp((sinceThrow - cfg.releaseSeconds) / math.max(cfg.recoverSeconds, 0.01), 0, 1)
		return cfg.releaseOffset:Lerp(cfg.heldOffset, 1 - (1 - alpha) * (1 - alpha))
	end

	-- HELD, drifting back toward the cocked pose as the button is held down. The player is watching
	-- one continuous wind-up that they END by releasing, exactly as the pickaxe's prime works.
	local pose = cfg.heldOffset:Lerp(cfg.windupOffset, windupAlpha)
	local steadiness = 1 - math.clamp(cfg.windupSteadiness, 0, 1) * windupAlpha
	local bob = math.sin((now / math.max(cfg.bobSeconds, 0.01)) * math.pi * 2) * cfg.bobStuds * steadiness
	local sway = math.sin((now / math.max(cfg.bobSeconds * 1.6, 0.01)) * math.pi * 2)
		* math.rad(cfg.swayDegrees)
		* steadiness
	return pose * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, sway)
end

-- Draw a stick, or keep the one already in frame. Idempotent: called every time the coordinator
-- decides a stick belongs on screen, including on the far side of a throw.
function DynamiteViewmodelController.setHeld(wanted: boolean)
	held = wanted
	if not wanted then
		windupAlpha = 0
	end
end

function DynamiteViewmodelController.isHeld(): boolean
	return held
end

-- The live wind-up, 0..1. Ignored while a throw is in flight: the release owns the stick until it
-- finishes, and a coordinator still writing a stale alpha must not fight it for the pose.
function DynamiteViewmodelController.setWindup(alpha: number)
	if os.clock() < throwEndsAt() then
		return
	end
	windupAlpha = if alpha == alpha then math.clamp(alpha, 0, 1) else 0
end

-- `alpha` is how far the wind-up had travelled at the instant of release. Sampled by the coordinator
-- BEFORE it clears its own state, so the stroke begins from exactly the pose on screen.
function DynamiteViewmodelController.beginThrow(now: number, alpha: number)
	throwStartedAt = now
	throwFromAlpha = if alpha == alpha then math.clamp(alpha, 0, 1) else 0
	windupAlpha = 0
	releaseSnapped = false
end

-- When the stick leaves the hand. The coordinator has nothing to do at this instant — the server's
-- charge is already in the world — but the throw is not over, and `isThrowing` stays true until the
-- recover finishes so a second press cannot interrupt the animation halfway.
function DynamiteViewmodelController.isThrowing(): boolean
	return os.clock() < throwEndsAt()
end

function DynamiteViewmodelController.throwEndsAt(): number
	return throwEndsAt()
end

function DynamiteViewmodelController.update(dt: number, now: number)
	updateVisibility(dt, now)
	local built = stickModel
	local camera = Workspace.CurrentCamera
	if built == nil or camera == nil then
		return
	end
	built:PivotTo(camera.CFrame * stickOffset(now))
end

function DynamiteViewmodelController.destroy()
	held = false
	windupAlpha = 0
	throwStartedAt = -math.huge
	throwFromAlpha = 0
	releaseSnapped = true
	destroyStick()
end

return DynamiteViewmodelController
