--!strict
-- Server authority for the four tools. Generic over ToolDef rows: behaviour is selected by the
-- row's data flags (togglesLit / held / burst / cast params), never by tool name. Owns decoys
-- and flare-burst lifetimes; exposes their light sources for threat perception.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local ToolRules = require(ReplicatedStorage.Shared.Logic.ToolRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local MovementService = require(script.Parent.MovementService)

local ToolService = {}

type Decoy = {
	position: Vector3,
	endsAt: number,
	attractsDrawn: boolean,
	intensity: number,
	range: number,
	part: BasePart,
}

local decoys: { Decoy } = {}

local function spawnDecoy(state: Types.PlayerRunState, def: Types.ToolDef, aim: Vector3, now: number)
	local castRange = def.castRange :: number -- Cast rows always define castRange
	local size = def.decoySize :: number
	local position = ToolRules.clampAim(state.position, aim, castRange)
	local waxType = Config.WaxTypes[state.waxTypeId]

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * size
	part.Color = Color3.fromRGB(255, 170, 60)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.Position = position + Vector3.new(0, size / 2, 0)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 100)
	light.Range = def.decoyRange :: number
	light.Brightness = def.decoyIntensity :: number
	light.Parent = part
	part.Parent = workspace

	table.insert(decoys, {
		position = part.Position,
		endsAt = now + def.duration,
		attractsDrawn = waxType.attractsDrawn, -- your wax: cold wax throws cold decoys
		intensity = def.decoyIntensity :: number,
		range = def.decoyRange :: number,
		part = part,
	})
end

local function activate(player: Player, state: Types.PlayerRunState, def: Types.ToolDef, aim: Vector3?, now: number)
	state.nextToolUse[def.id] = now + def.cooldown

	if def.togglesLit then
		if state.isLit then
			state.isLit = false
			state.unlitByChoice = true
			state.isCupping = false
		else
			state.isLit = true
			state.unlitByChoice = false
		end
		state.litChangedAt = now
		MovementService.refresh(player.UserId)
		return
	end

	if def.held then
		state.isCupping = not state.isCupping
		MovementService.refresh(player.UserId)
		return
	end

	-- Instant effects: charge, then apply whatever physical params the row declares.
	state.wax.current -= def.waxCost -- validated strictly above; can never hit zero here
	if def.burstIntensity ~= nil then
		state.flareEndsAt = now + def.duration
	end
	if def.castRange ~= nil then
		spawnDecoy(state, def, aim or state.position, now)
	end
end

function ToolService.init()
	Remotes.get("ToolUse").OnServerEvent:Connect(function(player: Player, toolId: unknown, aimPoint: unknown)
		if typeof(toolId) ~= "string" then
			return
		end
		local def = Config.Tools[toolId :: Types.ToolId]
		if def == nil then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil then
			return
		end
		local ok = ToolRules.validate(state, def, os.clock())
		if not ok then
			return
		end
		local aim: Vector3? = if typeof(aimPoint) == "Vector3" then aimPoint else nil
		activate(player, state, def, aim, os.clock())
	end)
end

-- Expire decoys and lapsed flare bursts.
function ToolService.tick()
	local now = os.clock()
	for index = #decoys, 1, -1 do
		if now >= decoys[index].endsAt then
			decoys[index].part:Destroy()
			table.remove(decoys, index)
		end
	end
	for _, state in PlayerState.all() do
		if state.flareEndsAt ~= 0 and now >= state.flareEndsAt then
			state.flareEndsAt = 0
		end
	end
end

-- Decoy contributions to the light field.
function ToolService.decoySources(): { Types.LightSource }
	local sources: { Types.LightSource } = {}
	for _, decoy in decoys do
		table.insert(sources, {
			kind = "Decoy" :: Types.LightSourceKind,
			position = decoy.position,
			intensity = decoy.intensity,
			range = decoy.range,
			attractsDrawn = decoy.attractsDrawn,
			ownerId = nil,
		})
	end
	return sources
end

function ToolService.reset()
	for _, decoy in decoys do
		decoy.part:Destroy()
	end
	table.clear(decoys)
end

return ToolService
