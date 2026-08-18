--!strict
-- The involuntary drip trail (DESIGN §8): emits points as lit players move, expires them, and
-- serves them to dark-hunter perception as geometric breadcrumbs. Drops never emit light.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)
local NoiseService = require(script.Parent.NoiseService)
local CharacterService = require(script.Parent.CharacterService)

local DripTrailService = {}

type Drip = {
	point: Types.TrailPoint,
	part: BasePart,
}

local trails: { [Types.PlayerId]: { Drip } } = {}
local lastEmitAt: { [Types.PlayerId]: Vector3 } = {}
-- Last tick's grounded read per player. The only thing needed to turn a polled state into the
-- discrete event the sound field wants: airborne last tick and grounded this tick is a landing.
local wasAirborne: { [Types.PlayerId]: boolean } = {}
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
		-- Footfalls are the OTHER involuntary evidence movement leaves, so they live beside the drip
		-- trail rather than in a service of their own. Deliberately independent of the drip-trail
		-- sacrifice and of being lit: giving up your trail hides your wax, never your footsteps, and
		-- running in the dark is still running.
		if state.alive and not state.finished and state.movementMode == "Run" then
			NoiseService.emitThrottled("Sprint", state.position, playerId, Config.Sound.sprintEmitIntervalSeconds)
		end
		-- LANDING. A discrete moment rather than a state, so it emits on the transition and needs no
		-- throttle: you cannot land twice without leaving the ground in between. Server-observed
		-- (CharacterService.isAirborne reads the Humanoid's own floor material), so a client cannot
		-- claim to be silently airborne, and a body that stops existing mid-jump simply never lands.
		local airborne = state.alive and not state.finished and CharacterService.isAirborne(playerId)
		if wasAirborne[playerId] and not airborne then
			-- THIS EVENT IS ALSO THE STOMP. A Wax Grub reads the noise field for landings near it and
			-- is scared off by one (server/EnemySystem/WaxGrubBehavior) — nothing extra is emitted for
			-- it and this file knows nothing about creatures. Worth stating because it looks like a
			-- pure audio/perception line and is load-bearing for a gameplay interaction.
			NoiseService.emit("Landing", state.position, playerId)
		end
		wasAirborne[playerId] = airborne
		if state.alive and not state.finished and state.isLit and state.modifiers.hasDripTrail then
			local last = lastEmitAt[playerId]
			local interval = cfg.emitIntervalStuds
			if state.movementMode == "Run" then
				interval *= cfg.sprintIntervalMultiplier
			end
			if last == nil or (state.position - last).Magnitude >= interval then
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

-- Removes one specific drip, if it is still there. Called when a Wax Grub finishes chewing through
-- it (server/EnemySystem/WaxGrubBehavior). This races against the drip's own `pointLifetimeSeconds`
-- expiry and against other grubs converging on the same point; both are harmless, whichever side
-- gets there first wins and the other simply finds nothing left to remove.
function DripTrailService.consume(ownerId: Types.PlayerId, createdAt: number): boolean
	local playerTrail = trails[ownerId]
	if playerTrail == nil then
		return false
	end
	for index, drip in playerTrail do
		if drip.point.createdAt == createdAt then
			drip.part:Destroy()
			table.remove(playerTrail, index)
			return true
		end
	end
	return false
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
	wasAirborne[playerId] = nil
end

function DripTrailService.reset()
	for playerId in trails do
		DripTrailService.clear(playerId)
	end
end

return DripTrailService
