--!strict
-- Lightweight authoritative threat representation. Detailed procedural bodies are client-built
-- from these presentation attributes; the server owns only position, AI, contact, and wax effects.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)
local Protocol = require(ReplicatedStorage.Shared.NewModelsAndObjects.ThreatVisualProtocol)

local ThreatVisualProxy = {}

export type Proxy = {
	model: Model,
	root: BasePart,
	upOffset: number,
	lastTargetPosition: Vector3?,
	lastIllumination: number,
	lastMode: Types.ThreatMode?,
	lastMoving: boolean?,
	attackPulses: number,
	nextAttackPulseAt: number,
	intentPulses: number,
}

-- A row's authored `visualStyle` names its body outright; anything without one falls back to its
-- category's silhouette, which is what keeps "a new threat is a new config row" true for rows that
-- do not need art of their own.
local STYLE_KINDS: { [string]: string } = {
	Bug = Protocol.kinds.ceilingFly,
	Listener = Protocol.kinds.listener,
	Knotwalker = Protocol.kinds.knotwalker,
	Calver = Protocol.kinds.calver,
}

local KIND_GROUND_OFFSET_KEYS: { [string]: string } = {
	[Protocol.kinds.ceilingFly] = "ceilingFly",
	[Protocol.kinds.moth] = "moth",
	[Protocol.kinds.listener] = "listener",
	[Protocol.kinds.knotwalker] = "knotwalker",
	[Protocol.kinds.calver] = "calver",
}

local function visualKind(def: Types.ThreatDef): string
	local style = def.visualStyle
	local mapped = if style ~= nil then STYLE_KINDS[style] else nil
	if mapped ~= nil then
		return mapped
	end
	if def.category == "Drawn" then
		return Protocol.kinds.moth
	end
	return Protocol.kinds.crawler
end

local function groundOffset(kind: string): number
	local offsets = Config.Threats.visuals.procedural.groundOffsets
	local key = KIND_GROUND_OFFSET_KEYS[kind]
	local offset = if key ~= nil then (offsets :: { [string]: number })[key] else nil
	return if offset ~= nil then offset else offsets.crawler
end

-- `familyId` selects the cave family's dressing for this body. Presentation only — see
-- ThreatVisualProtocol.attributes.familyVariant for exactly what a variant may and may not change.
function ThreatVisualProxy.build(def: Types.ThreatDef, familyId: string?): Proxy
	local kind = visualKind(def)
	local profile = CaveFamilyRules.resolve(familyId)
	local presentation = profile.presentation
	local model = Instance.new("Model")
	model.Name = "Threat_" .. def.id

	local root = Instance.new("Part")
	root.Name = "ThreatProxy"
	root.Size = Config.Threats.visuals.procedural.proxySize
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	model:SetAttribute(Protocol.attributes.kind, kind)
	-- THE FAMILY ID, not `presentation.threatVariantId`. This used to publish the latter — the string
	-- "Stone" / "Moss" / "Ice" — which the client then handed to `CaveFamilyRules.resolve`. Those are
	-- display labels, not ids: resolve matches against "STONE" / "MOSS" / "ICE", so every lookup missed
	-- and every threat in every cave silently got the free family's dressing. The variant string stays
	-- in the profile as the human-readable label it always was; what travels is the id that resolves.
	model:SetAttribute(Protocol.attributes.familyVariant, profile.id)
	model:SetAttribute(Protocol.attributes.familyTint, presentation.threatVariantTintStrength)
	model:SetAttribute(Protocol.attributes.mode, "Wander")
	model:SetAttribute(Protocol.attributes.illumination, 0)
	model:SetAttribute(Protocol.attributes.moving, false)
	model:SetAttribute(Protocol.attributes.attack, 0)
	model:SetAttribute(Protocol.attributes.intentSequence, 0)
	CollectionService:AddTag(model, Config.Feel.threatWarning.collectionTag)

	if Config.Feel.debug.showThreatLabels then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "DebugLabel"
		billboard.Size = UDim2.fromOffset(140, 26)
		billboard.StudsOffset = Vector3.new(0, 1.2, 0)
		billboard.MaxDistance = 90
		billboard.LightInfluence = 0
		billboard.AlwaysOnTop = false

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.TextTransparency = 0.25
		text.TextColor3 = if def.category == "DarkHunter"
			then Config.Threats.visuals.procedural.debugHunterColor
			else Config.Threats.visuals.procedural.debugDrawnColor
		text.Text = def.displayName
		text.Parent = billboard
		billboard.Parent = root
	end

	return {
		model = model,
		root = root,
		upOffset = groundOffset(kind),
		lastTargetPosition = nil,
		lastIllumination = -1,
		lastMode = nil,
		lastMoving = nil,
		attackPulses = 0,
		nextAttackPulseAt = 0,
		intentPulses = 0,
	}
end

-- One attack beat, paced so a continuously draining threat swings on a cadence instead of once per
-- damage tick. Cosmetic only: the swing follows the contact the server has already resolved, so a
-- dropped or late pulse never changes what the hit did.
function ThreatVisualProxy.signalAttack(
	proxy: Proxy,
	victimPlayerId: Types.PlayerId,
	now: number,
	pulseIntervalSeconds: number?
)
	if now < proxy.nextAttackPulseAt then
		return
	end
	proxy.nextAttackPulseAt = now
		+ (pulseIntervalSeconds or Config.Threats.visuals.procedural.attackPulseIntervalSeconds)
	proxy.attackPulses += 1
	proxy.model:SetAttribute(Protocol.attributes.attackVictim, victimPlayerId)
	proxy.model:SetAttribute(Protocol.attributes.attack, proxy.attackPulses)
end

-- A pre-effect presentation signal, currently and deliberately only for Calver's ceiling hammer.
-- The server timestamp lets every client reconstruct the same point in the motion even when the
-- attribute packet arrives late. It carries no gameplay result and never replaces the confirmed-hit
-- pulse above.
function ThreatVisualProxy.signalIntent(proxy: Proxy, serverStartedAt: number, actionId: string)
	proxy.intentPulses += 1
	proxy.model:SetAttribute(Protocol.attributes.intentStartedAt, serverStartedAt)
	proxy.model:SetAttribute(Protocol.attributes.intentAction, actionId)
	-- Sequence is written last so a client observing it also observes the matching timestamp/action.
	proxy.model:SetAttribute(Protocol.attributes.intentSequence, proxy.intentPulses)
end

function ThreatVisualProxy.sync(
	proxy: Proxy,
	mode: Types.ThreatMode,
	targetPosition: Vector3?,
	illumination: number,
	moving: boolean
)
	local attributes = Protocol.attributes
	if proxy.lastMode ~= mode then
		proxy.lastMode = mode
		proxy.model:SetAttribute(attributes.mode, mode)
	end
	if proxy.lastMoving ~= moving then
		proxy.lastMoving = moving
		proxy.model:SetAttribute(attributes.moving, moving)
	end

	local step = Config.Threats.visuals.procedural.illuminationStep
	local quantizedIllumination = math.clamp(math.round(illumination / step) * step, 0, 1)
	if quantizedIllumination ~= proxy.lastIllumination then
		proxy.lastIllumination = quantizedIllumination
		proxy.model:SetAttribute(attributes.illumination, quantizedIllumination)
	end

	local previousTarget = proxy.lastTargetPosition
	local targetChanged = if targetPosition == nil
		then previousTarget ~= nil
		else previousTarget == nil
			or (targetPosition - (previousTarget :: Vector3)).Magnitude
				>= Config.Threats.visuals.procedural.targetReplicationDistance
	if targetChanged then
		proxy.lastTargetPosition = targetPosition
		proxy.model:SetAttribute(attributes.targetPosition, targetPosition)
	end
end

return ThreatVisualProxy
