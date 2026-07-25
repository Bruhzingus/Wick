--!strict
-- Builds and animates detailed threat bodies locally around server-owned invisible proxies.
-- Local bodies never participate in collision, queries, contact, AI, or wax decisions.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local AudioCues = require(script.Parent.AudioCues)
local CaveMoth = require(ReplicatedStorage.Shared.NewModelsAndObjects.CaveMoth)
local CeilingFly = require(ReplicatedStorage.Shared.NewModelsAndObjects.CeilingFly)
local DarkCrawler = require(ReplicatedStorage.Shared.NewModelsAndObjects.DarkCrawler)
local Protocol = require(ReplicatedStorage.Shared.NewModelsAndObjects.ThreatVisualProtocol)

local ThreatVisualController = {}

type Visual = {
	model: Model,
	root: BasePart,
	update: (dt: number, mode: string, illumination: number, moving: boolean, targetPosition: Vector3?) -> (),
	destroy: () -> (),
}

type Entry = {
	proxy: Model,
	kind: string,
	visual: Visual?,
	nextBuzzAt: number,
}

local entries: { [Model]: Entry } = {}
local visualsFolder: Folder? = nil
local rng = Random.new()

local function presentationOnly(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

local function activityForMode(mode: string): number
	local activity = Config.Threats.visuals.procedural.activity
	if mode == "Seek" then
		return activity.seek
	elseif mode == "Stalk" then
		return activity.stalk
	elseif mode == "Flee" then
		return activity.flee
	end
	return activity.wander
end

local function crawlerVisual(parent: Instance): Visual
	local crawler = DarkCrawler.build(parent)
	presentationOnly(crawler.model)
	return {
		model = crawler.model,
		root = crawler.root,
		update = function(dt, mode, illumination, moving, targetPosition)
			crawler:setIllumination(illumination)
			crawler:setAware(activityForMode(mode))
			crawler:setMoving(moving)
			crawler:lookAt(targetPosition)
			crawler:step(dt)
		end,
		destroy = function()
			crawler:destroy()
		end,
	}
end

local function mothVisual(parent: Instance): Visual
	local moth = CaveMoth.build(parent)
	moth:setTarget(nil)
	presentationOnly(moth.model)
	return {
		model = moth.model,
		root = moth.root,
		update = function(dt, mode, illumination, _moving, _targetPosition)
			moth:setPressure(activityForMode(mode))
			moth:setIllumination(illumination)
			moth:step(dt)
		end,
		destroy = function()
			moth:destroy()
		end,
	}
end

local function ceilingFlyVisual(parent: Instance): Visual
	local fly = CeilingFly.build(parent)
	fly:setFlying(true)
	presentationOnly(fly.model)
	return {
		model = fly.model,
		root = fly.root,
		update = function(dt, mode, illumination, _moving, _targetPosition)
			fly:setAlert(activityForMode(mode))
			fly:setIllumination(illumination)
			fly:step(dt)
		end,
		destroy = function()
			fly:destroy()
		end,
	}
end

local function buildVisual(kind: string, parent: Instance): Visual?
	if kind == Protocol.kinds.crawler then
		return crawlerVisual(parent)
	elseif kind == Protocol.kinds.moth then
		return mothVisual(parent)
	elseif kind == Protocol.kinds.ceilingFly then
		return ceilingFlyVisual(parent)
	end
	return nil
end

local function removeProxy(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local entry = entries[instance]
	if entry == nil then
		return
	end
	entries[instance] = nil
	if entry.visual ~= nil then
		entry.visual.destroy()
	end
end

local function addProxy(instance: Instance)
	if not instance:IsA("Model") or entries[instance] ~= nil then
		return
	end
	local kind = instance:GetAttribute(Protocol.attributes.kind)
	local parent = visualsFolder
	if type(kind) ~= "string" or parent == nil then
		return
	end
	entries[instance] = {
		proxy = instance,
		kind = kind,
		visual = nil,
		nextBuzzAt = os.clock() + rng:NextNumber(
			Config.Threats.visuals.procedural.ceilingFlyBuzz.minIntervalSeconds,
			Config.Threats.visuals.procedural.ceilingFlyBuzz.maxIntervalSeconds
		),
	}
end

local function flyBuzzIsAudible(cameraPosition: Vector3, proxyRoot: BasePart, parent: Folder): boolean
	local buzz = Config.Threats.visuals.procedural.ceilingFlyBuzz
	local offset = proxyRoot.Position - cameraPosition
	local distance = offset.Magnitude
	if distance > buzz.audibleDistance then
		return false
	end
	if distance <= buzz.occlusionEndpointInset then
		return true
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { parent }
	-- This check models cave-wall occlusion, not bodies. Exclude every replicated character so a
	-- teammate crossing the line cannot make the same authoritative fly go silent for one client.
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(exclude, character)
		end
	end
	raycastParams.FilterDescendantsInstances = exclude
	-- Stop just before the roof-mounted root. Terrain immediately behind/around the fly is not an
	-- occluder; walls and cave bends along the rest of the path still correctly muffle its buzz.
	local occlusionRay = offset.Unit * (distance - buzz.occlusionEndpointInset)
	return Workspace:Raycast(cameraPosition, occlusionRay, raycastParams) == nil
end

local function updateFlyBuzz(entry: Entry, proxyRoot: BasePart, cameraPosition: Vector3, parent: Folder, now: number)
	if entry.kind ~= Protocol.kinds.ceilingFly or now < entry.nextBuzzAt then
		return
	end
	local buzz = Config.Threats.visuals.procedural.ceilingFlyBuzz
	if flyBuzzIsAudible(cameraPosition, proxyRoot, parent) then
		AudioCues.playAt(buzz.cueName, proxyRoot)
		entry.nextBuzzAt = now + rng:NextNumber(buzz.minIntervalSeconds, buzz.maxIntervalSeconds)
	else
		entry.nextBuzzAt = now + buzz.outOfRangeRetrySeconds
	end
end

local function render(dt: number)
	local camera = Workspace.CurrentCamera
	local parent = visualsFolder
	if camera == nil or parent == nil then
		return
	end

	local renderConfig = Config.Threats.visuals.procedural
	local boundedDt = math.min(dt, renderConfig.maxAnimationDeltaSeconds)
	local now = os.clock()
	for proxy, entry in entries do
		local proxyRoot = proxy.PrimaryPart
		if proxyRoot == nil or not proxy:IsDescendantOf(Workspace) then
			continue
		end

		local cullLimit = renderConfig.cullDistance + if entry.visual ~= nil then renderConfig.cullHysteresis else 0
		local withinRange = (camera.CFrame.Position - proxyRoot.Position).Magnitude <= cullLimit
		updateFlyBuzz(entry, proxyRoot, camera.CFrame.Position, parent, now)
		if not withinRange then
			if entry.visual ~= nil then
				entry.visual.destroy()
				entry.visual = nil
			end
			continue
		end

		local visual = entry.visual
		if visual == nil then
			visual = buildVisual(entry.kind, parent)
			if visual == nil then
				continue
			end
			visual.model.Name = "Visual_" .. proxy.Name
			entry.visual = visual
		end

		visual.root.CFrame = proxyRoot.CFrame
		local mode = proxy:GetAttribute(Protocol.attributes.mode)
		local illumination = proxy:GetAttribute(Protocol.attributes.illumination)
		local moving = proxy:GetAttribute(Protocol.attributes.moving)
		local targetPosition = proxy:GetAttribute(Protocol.attributes.targetPosition)
		visual.update(
			boundedDt,
			if type(mode) == "string" then mode else "Wander",
			if type(illumination) == "number" then illumination else 0,
			if type(moving) == "boolean" then moving else false,
			if typeof(targetPosition) == "Vector3" then targetPosition else nil
		)
	end
end

function ThreatVisualController.start()
	local folder = Instance.new("Folder")
	folder.Name = "WickThreatVisuals"
	folder.Parent = Workspace
	visualsFolder = folder

	local tag = Config.Feel.threatWarning.collectionTag
	for _, instance in CollectionService:GetTagged(tag) do
		addProxy(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(addProxy)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeProxy)
	RunService.RenderStepped:Connect(render)
end

return ThreatVisualController
