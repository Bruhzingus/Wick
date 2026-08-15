--!strict
-- Local-only world presentation for mining. This module renders seam proximity warmth, spatial
-- strike/break audio, and collision-neutral contact chips. It never decides accuracy, progress,
-- depletion, cargo, range, or which replicated event a client is allowed to present.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MiningVisualProtocol = require(ReplicatedStorage.Shared.MiningVisualProtocol)
local AudioCues = require(script.Parent.AudioCues)

local MiningWorldPresentation = {}

export type StrikePitches = {
	impact: number?,
	accent: number?,
}

type SeamGlow = {
	shells: { BasePart },
	alpha: number,
}

-- Local amber ember shells, one set per nearby deposit. The shell transparency remains coupled to
-- the replicated seam transparency, so authoritative wear is visible without client-owned state.
local seamGlows: { [Model]: SeamGlow } = {}

-- A paid helper can receive the shared world break and their private cargo result in either order.
-- The first path claims the physical transient; the other can still update its private HUD without
-- doubling the same break cue and debris burst.
local presentedBreaks: { [BasePart]: boolean } = {}

local function livePart(part: BasePart?): BasePart?
	if part ~= nil and part.Parent ~= nil then
		return part
	end
	return nil
end

local function presentationRoot(target: BasePart?, fallbackTarget: BasePart?): BasePart?
	return livePart(target) or livePart(fallbackTarget)
end

-- Build the local ember shells for one deposit's seams. They cast no light and cannot collide,
-- touch, or answer queries.
local function ensureGlow(model: Model): SeamGlow?
	local existing = seamGlows[model]
	if existing ~= nil then
		return existing
	end

	local glowCfg = Config.Mining.visual.glow
	local shells: { BasePart } = {}
	for _, child in model:GetChildren() do
		if not child:IsA("BasePart") or child.Name ~= "WaxSeam" then
			continue
		end

		local shell = Instance.new("Part")
		shell.Name = "WickSeamEmber"
		-- `thickness` is configured as an inset. Clamp every axis so an unusually thin authored
		-- seam can never collapse the cosmetic shell to a zero or negative size.
		local grown = child.Size + Vector3.one * glowCfg.thickness
		shell.Size = Vector3.new(math.max(grown.X, 0.05), math.max(grown.Y, 0.05), math.max(grown.Z, 0.05))
		shell.CFrame = child.CFrame
		shell.Color = glowCfg.color
		shell.Material = Enum.Material.Neon
		shell.Transparency = 1
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CastShadow = false
		shell.Parent = child
		table.insert(shells, shell)
	end

	if #shells == 0 then
		return nil
	end

	local glow: SeamGlow = {
		shells = shells,
		alpha = 0,
	}
	seamGlows[model] = glow
	return glow
end

local function destroyGlow(model: Model)
	local glow = seamGlows[model]
	if glow == nil then
		return
	end

	seamGlows[model] = nil
	for _, shell in glow.shells do
		shell:Destroy()
	end
end

-- Deliberately a slight warmth that rises only near an unspent seam, not a locator visible through
-- the cave. Deposits on another floor are ignored even if their replicated Instances still exist.
function MiningWorldPresentation.updateGlow(origin: Vector3?, currentDepth: number, dt: number)
	local glowCfg = Config.Mining.visual.glow
	local attributes = MiningVisualProtocol.attributes
	local seen: { [Model]: boolean } = {}

	if origin ~= nil then
		for _, tagged in CollectionService:GetTagged(MiningVisualProtocol.depositTag) do
			local model = tagged :: Model
			local root = model.PrimaryPart
			if root == nil or root:GetAttribute(attributes.depth) ~= currentDepth then
				continue
			end

			local distance = (root.Position - origin).Magnitude
			if root:GetAttribute(attributes.depleted) == true or distance > glowCfg.range then
				continue
			end

			local glow = ensureGlow(model)
			if glow == nil then
				continue
			end

			seen[model] = true
			local closeness =
				math.clamp((glowCfg.range - distance) / math.max(glowCfg.range - glowCfg.nearDistance, 0.01), 0, 1)
			local step = math.clamp(dt * glowCfg.fadePerSecond, 0, 1)
			glow.alpha += (closeness - glow.alpha) * step
			local transparency = 1 - glow.alpha * (1 - glowCfg.minTransparency)
			for _, shell in glow.shells do
				local seam = shell.Parent
				local remaining = if seam ~= nil and seam:IsA("BasePart") then 1 - seam.Transparency else 0
				shell.Transparency = 1 - (1 - transparency) * remaining
			end
		end
	end

	for model in seamGlows do
		if not seen[model] then
			destroyGlow(model)
		end
	end
end

function MiningWorldPresentation.clearGlow()
	for model in seamGlows do
		destroyGlow(model)
	end
end

-- The rock is the emitter. If replication has already removed both possible seam roots, retain the
-- cue as a non-spatial local beat rather than dropping confirmed presentation entirely.
function MiningWorldPresentation.playAtSeam(
	cueName: string,
	pitchMultiplier: number?,
	target: BasePart?,
	fallbackTarget: BasePart?
): boolean
	local root = presentationRoot(target, fallbackTarget)
	if root ~= nil then
		return AudioCues.playAt(cueName, root, pitchMultiplier)
	end
	return AudioCues.play(cueName, pitchMultiplier)
end

-- A handful of short-lived local stone/wax chips sells physical contact. Wax-coloured chips are
-- emitted only when the authoritative result says this strike actually released a wax shard.
local function emitImpactDebris(root: BasePart, accuracy: string, shardWax: boolean?)
	local feedback = Config.Mining.feedback
	local rng = Random.new(math.floor(Workspace:GetServerTimeNow() * 1000) % 2147483647)
	local surface = root.CFrame:PointToWorldSpace(Vector3.new(0, root.Size.Y * 0.08, -root.Size.Z * 0.52))
	-- The exposed seam is built on local -Z, which is the root's LookVector in world space.
	local outward = root.CFrame.LookVector
	local count = math.max(0, math.floor(feedback.impactDebrisCount))
	if accuracy == "Miss" then
		count = math.max(2, math.floor(count * 0.55))
	end

	for index = 1, count do
		local size = rng:NextNumber(feedback.impactDebrisSizeMin, feedback.impactDebrisSizeMax)
		local chip = Instance.new("Part")
		chip.Name = "WickMineChip"
		chip.Size = Vector3.new(size * rng:NextNumber(0.7, 1.4), size, size * rng:NextNumber(0.7, 1.4))
		local surfaceScatter = root.CFrame.RightVector * rng:NextNumber(-0.45, 0.45)
			+ root.CFrame.UpVector * rng:NextNumber(-0.2, 0.45)
		chip.CFrame = CFrame.new(surface + surfaceScatter)
			* CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi))
		local isWax = shardWax == true and index % 3 == 0
		chip.Color = if isWax then Config.Mining.visual.waxDeepColor else Config.Mining.visual.rockAccent
		chip.Material = if isWax then Enum.Material.SmoothPlastic else Enum.Material.Slate
		chip.Anchored = false
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CanTouch = false
		chip.CastShadow = false
		chip.Parent = Workspace
		chip.AssemblyLinearVelocity = outward
				* rng:NextNumber(feedback.impactDebrisSpeed * 0.55, feedback.impactDebrisSpeed)
			+ root.CFrame.RightVector * rng:NextNumber(
				-feedback.impactDebrisSpeed * 0.45,
				feedback.impactDebrisSpeed * 0.45
			)
			+ Vector3.yAxis * rng:NextNumber(feedback.impactDebrisUpSpeed * 0.45, feedback.impactDebrisUpSpeed)
		chip.AssemblyAngularVelocity =
			Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
		Debris:AddItem(chip, feedback.impactDebrisLifetime)
	end
end

local function accentCue(accuracy: string): string?
	if accuracy == "Perfect" then
		return "MineStrikePerfect"
	elseif accuracy == "Good" then
		return "MineStrikeClean"
	end
	-- A miss keeps the common heavy pick/rock impact and communicates the glance through the sideways
	-- viewmodel path, red HUD response, zero payout, and louder server-owned cave noise. It deliberately
	-- has no accent: the old accent was an airy gas hiss, so an opening miss sounded like the wax itself
	-- made a cartoon noise instead of like steel glancing off stone.
	return nil
end

-- Present one server-confirmed strike. `pitches` lets the local striker retain the slight impact
-- variation and Perfect-streak ladder; nearby clients omit it and hear the authored base layers.
function MiningWorldPresentation.presentStrike(
	target: BasePart?,
	accuracy: string,
	shardWax: boolean?,
	pitches: StrikePitches?,
	fallbackTarget: BasePart?
)
	local impactPitch = if pitches ~= nil then pitches.impact else nil
	local accentPitch = if pitches ~= nil then pitches.accent else nil
	MiningWorldPresentation.playAtSeam("MineStrikeImpact", impactPitch, target, fallbackTarget)
	local accent = accentCue(accuracy)
	if accent ~= nil then
		MiningWorldPresentation.playAtSeam(accent, accentPitch, target, fallbackTarget)
	end

	local root = presentationRoot(target, fallbackTarget)
	if root ~= nil then
		emitImpactDebris(root, accuracy, shardWax)
	end
end

local function claimBreakPresentation(target: BasePart?): boolean
	if target == nil then
		return true
	end
	if presentedBreaks[target] == true then
		return false
	end
	presentedBreaks[target] = true
	return true
end

-- Shared mineImpact and private depletion messages may race. Returning false means this root's
-- physical break transient was already shown; private reward/cargo UI should still proceed.
function MiningWorldPresentation.presentBreak(
	target: BasePart?,
	accuracy: string,
	shardWax: boolean?,
	fallbackTarget: BasePart?
): boolean
	local root = presentationRoot(target, fallbackTarget)
	-- Claim by Instance identity even if replication removed its parent between the two messages.
	-- A destroyed root can still be the common key that prevents two non-spatial break fallbacks.
	if not claimBreakPresentation(target or fallbackTarget) then
		return false
	end

	-- Preserve the steel/stone body on the final contact, then let rubble own the payoff. The
	-- ordinary grade accent is intentionally omitted so completion does not stack every cue.
	MiningWorldPresentation.playAtSeam("MineStrikeImpact", nil, target, fallbackTarget)
	MiningWorldPresentation.playAtSeam("MineBreak", nil, target, fallbackTarget)
	if root ~= nil then
		emitImpactDebris(root, accuracy, shardWax)
	end
	return true
end

function MiningWorldPresentation.clearBreakClaims()
	table.clear(presentedBreaks)
end

-- The fuse has been lit somewhere the player can see or hear. One sharp cue on the rock; the climbing
-- hiss above is already handling the three seconds themselves, so this is the transition and not the
-- state.
function MiningWorldPresentation.presentPrimed(target: BasePart?)
	MiningWorldPresentation.playAtSeam("SeamCrackle", nil, target, nil)
end

-- THE BLAST. Deliberately more debris than any break in the game and no wax in it: what leaves the
-- rock is the rock. The cue's own roll-off carries it far past the radius that hurt anybody, which is
-- correct — the whole floor should know, because in about a second the whole floor is coming.
function MiningWorldPresentation.presentExplosion(target: BasePart?)
	MiningWorldPresentation.playAtSeam("SeamExplosion", nil, target, nil)
	local root = presentationRoot(target, nil)
	if root ~= nil then
		-- Twice, because the burst is authored for a pickaxe bite and this is not one. A deposit already
		-- destroyed by the time the event arrives still gets its noise; there is simply no rock left to
		-- throw.
		emitImpactDebris(root, "Perfect", false)
		emitImpactDebris(root, "Perfect", false)
	end
end

function MiningWorldPresentation.destroy()
	MiningWorldPresentation.clearGlow()
	MiningWorldPresentation.clearBreakClaims()
end

return MiningWorldPresentation
