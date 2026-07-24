--!strict
-- Assembles the complete light field each tick: every lit flame (cup-dimmed, flare-boosted),
-- every decoy, every drip. Threat perception sees exactly this list and nothing else — which is
-- why every tool works: they all edit this list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local BrightnessMap = require(ReplicatedStorage.Shared.Logic.BrightnessMap)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local PlayerState = require(script.Parent.PlayerState)
local ToolService = require(script.Parent.ToolService)
local DripTrailService = require(script.Parent.DripTrailService)

local LightSources = {}

function LightSources.collect(now: number): { Types.LightSource }
	local sources: { Types.LightSource } = {}

	for playerId, state in PlayerState.all() do
		if not state.alive or state.finished or not state.isLit then
			continue
		end
		local waxType = Config.WaxTypes[state.waxTypeId]
		local cupMultiplier = 1
		if state.isCupping then
			cupMultiplier = Config.Tools.Cup.lightMultiplier :: number -- Cup rows always define this
		end
		local params = BrightnessMap.paramsFor(state.burnRate, waxType, cupMultiplier)
		local flamePosition = Vector3.new(
			state.position.X,
			CandleGeometry.flameCenterY(state.position.Y, state.currentHeight),
			state.position.Z
		)
		table.insert(sources, {
			kind = "Flame" :: Types.LightSourceKind,
			position = flamePosition,
			intensity = params.intensity,
			range = params.range,
			attractsDrawn = waxType.attractsDrawn,
			ownerId = playerId,
		})
		if state.flareEndsAt > now then
			local flare = Config.Tools.Flare
			table.insert(sources, {
				kind = "Flare" :: Types.LightSourceKind,
				position = flamePosition,
				intensity = flare.burstIntensity :: number, -- Flare rows always define burst params
				range = flare.burstRange :: number,
				attractsDrawn = waxType.attractsDrawn,
				ownerId = playerId,
			})
		end
	end

	for _, source in ToolService.decoySources() do
		table.insert(sources, source)
	end
	for _, source in DripTrailService.sources() do
		table.insert(sources, source)
	end
	return sources
end

return LightSources
