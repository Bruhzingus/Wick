--!strict
-- The involuntary drip trail (DESIGN §8): emits points as lit players move, expires them, and
-- serves them to dark-hunter perception as geometric breadcrumbs. Drops never emit light.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)

local DripTrailService = {}

type Drip = {
	point: Types.TrailPoint,
	part: BasePart,
}

local trails: { [Types.PlayerId]: { Drip } } = {}
local lastEmitAt: { [Types.PlayerId]: Vector3 } = {}
local rng = Random.new()
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- Cylinder axis X -> vertical

local function emit(state: Types.PlayerRunState, now: number)
	local cfg = Config.DripTrail
	local scale = 1 + rng:NextNumber(-cfg.dripSizeJitter, cfg.dripSizeJitter)
	local width = cfg.dripPartSize * scale
	local height = width * cfg.dripFlattening
	local offset = Vector3.new(
		rng:NextNumber(-cfg.dripPositionJitter, cfg.dripPositionJitter),
		0,
		rng:NextNumber(-cfg.dripPositionJitter, cfg.dripPositionJitter)
	)

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, width, width * rng:NextNumber(1 - cfg.dripAspectJitter, 1 + cfg.dripAspectJitter))
	part.Color = cfg.dripColor
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(state.position + offset + Vector3.new(0, height / 2, 0))
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		* UPRIGHT
	part.Parent = workspace

	local playerTrail = trails[state.playerId]
	if playerTrail == nil then
		playerTrail = {}
		trails[state.playerId] = playerTrail
	end
	table.insert(playerTrail, {
		point = { position = part.Position, ownerId = state.playerId, createdAt = now },
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
