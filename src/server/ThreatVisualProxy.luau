--!strict
-- Lightweight authoritative threat representation. Detailed procedural bodies are client-built
-- from these presentation attributes; the server owns only position, AI, contact, and wax effects.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
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
}

local function visualKind(def: Types.ThreatDef): string
	if def.visualStyle == "Bug" then
		return Protocol.kinds.ceilingFly
	end
	if def.category == "Drawn" then
		return Protocol.kinds.moth
	end
	return Protocol.kinds.crawler
end

local function groundOffset(kind: string): number
	local offsets = Config.Threats.visuals.procedural.groundOffsets
	if kind == Protocol.kinds.ceilingFly then
		return offsets.ceilingFly
	elseif kind == Protocol.kinds.moth then
		return offsets.moth
	end
	return offsets.crawler
end

function ThreatVisualProxy.build(def: Types.ThreatDef): Proxy
	local kind = visualKind(def)
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
	model:SetAttribute(Protocol.attributes.mode, "Wander")
	model:SetAttribute(Protocol.attributes.illumination, 0)
	model:SetAttribute(Protocol.attributes.moving, false)
	model:SetAttribute(Protocol.attributes.attack, 0)
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
	}
end

-- One attack beat, paced so a continuously draining threat swings on a cadence instead of once per
-- damage tick. Cosmetic only: the swing follows the contact the server has already resolved, so a
-- dropped or late pulse never changes what the hit did.
function ThreatVisualProxy.signalAttack(proxy: Proxy, victimPlayerId: Types.PlayerId, now: number)
	if now < proxy.nextAttackPulseAt then
		return
	end
	proxy.nextAttackPulseAt = now + Config.Threats.visuals.procedural.attackPulseIntervalSeconds
	proxy.attackPulses += 1
	proxy.model:SetAttribute(Protocol.attributes.attackVictim, victimPlayerId)
	proxy.model:SetAttribute(Protocol.attributes.attack, proxy.attackPulses)
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
