--!strict
-- The involuntary drip trail (DESIGN §8): emits points as lit players move, expires them, and
-- serves them to threat perception both as breadcrumbs (hunters) and tiny light sources (drawn).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)

local DripTrailService = {}

type Drip = {
	point: Types.TrailPoint,
	attractsDrawn: boolean,
	part: BasePart,
}

local trails: { [Types.PlayerId]: { Drip } } = {}
local lastEmitAt: { [Types.PlayerId]: Vector3 } = {}

local function emit(state: Types.PlayerRunState, now: number)
	local cfg = Config.DripTrail
	local waxType = Config.WaxTypes[state.waxTypeId]

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * cfg.dripPartSize
	part.Color = Color3.fromRGB(255, 200, 120)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.Position = state.position + Vector3.new(0, cfg.dripPartSize / 2, 0)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = cfg.pointRange
	light.Brightness = cfg.pointIntensity
	light.Parent = part
	part.Parent = workspace

	local playerTrail = trails[state.playerId]
	if playerTrail == nil then
		playerTrail = {}
		trails[state.playerId] = playerTrail
	end
	table.insert(playerTrail, {
		point = { position = part.Position, ownerId = state.playerId, createdAt = now },
		attractsDrawn = waxType.attractsDrawn,
		part = part,
	})
	if #playerTrail > cfg.maxPointsPerPlayer then
		playerTrail[1].part:Destroy()
		table.remove(playerTrail, 1)
	end
	lastEmitAt[state.playerId] = state.position
end

function DripTrailService.tick()
	local now = os.clock()
	local cfg = Config.DripTrail

	for playerId, state in PlayerState.all() do
		if state.alive and not state.finished and state.isLit and state.modifiers.hasDripTrail then
			local last = lastEmitAt[playerId]
			if last == nil or (state.position - last).Magnitude >= cfg.emitIntervalStuds then
				emit(state, now)
			end
		end
	end

	for _, playerTrail in trails do
		for index = #playerTrail, 1, -1 do
			if now - playerTrail[index].point.createdAt >= cfg.pointLifetimeSeconds then
				playerTrail[index].part:Destroy()
				table.remove(playerTrail, index)
			end
		end
	end
end

-- All live trail points, flattened, for hunter pathing.
function DripTrailService.getTrail(): { Types.TrailPoint }
	local points: { Types.TrailPoint } = {}
	for _, playerTrail in trails do
		for _, drip in playerTrail do
			table.insert(points, drip.point)
		end
	end
	return points
end

-- Trail contributions to the light field (tiny by config).
function DripTrailService.sources(): { Types.LightSource }
	local cfg = Config.DripTrail
	local sources: { Types.LightSource } = {}
	for _, playerTrail in trails do
		for _, drip in playerTrail do
			table.insert(sources, {
				kind = "Drip" :: Types.LightSourceKind,
				position = drip.point.position,
				intensity = cfg.pointIntensity,
				range = cfg.pointRange,
				attractsDrawn = drip.attractsDrawn,
				ownerId = drip.point.ownerId,
			})
		end
	end
	return sources
end

function DripTrailService.clear(playerId: Types.PlayerId)
	local playerTrail = trails[playerId]
	if playerTrail ~= nil then
		for _, drip in playerTrail do
			drip.part:Destroy()
		end
		trails[playerId] = nil
	end
	lastEmitAt[playerId] = nil
end

function DripTrailService.reset()
	for playerId in trails do
		DripTrailService.clear(playerId)
	end
end

return DripTrailService
