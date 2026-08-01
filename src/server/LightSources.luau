--!strict
-- Assembles the complete light field each tick: every lit flame (cup-dimmed, flare-boosted),
-- every decoy and every remains pool. Threats see exactly this list — which is
-- why every tool works: they all edit this list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local BrightnessMap = require(ReplicatedStorage.Shared.Logic.BrightnessMap)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local PlayerState = require(script.Parent.PlayerState)
local ToolService = require(script.Parent.ToolService)
local RemainsService = require(script.Parent.RemainsService)
local MossFireService = require(script.Parent.MossFireService)

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
		local lightMultiplier =
			DripstoneRules.lightMultiplier(now, state.lightSuppressedUntil, state.lightSuppressionMultiplier)
		local flamePosition = Vector3.new(
			state.position.X,
			CandleGeometry.flameCenterY(state.position.Y, state.currentHeight),
			state.position.Z
		)
		table.insert(sources, {
			kind = "Flame" :: Types.LightSourceKind,
			position = flamePosition,
			intensity = params.intensity * lightMultiplier,
			range = params.range * lightMultiplier,
			attractsDrawn = waxType.attractsDrawn,
			repelsDarkHunters = true,
			forcesDarkHunterRetreat = false,
			ownerId = playerId,
		})
		if state.flareEndsAt > now then
			local flare = Config.Tools.Flare
			table.insert(sources, {
				kind = "Flare" :: Types.LightSourceKind,
				position = flamePosition,
				intensity = (flare.burstIntensity :: number) * lightMultiplier, -- Flare rows always define burst params
				range = (flare.burstRange :: number) * lightMultiplier,
				attractsDrawn = waxType.attractsDrawn,
				repelsDarkHunters = true,
				forcesDarkHunterRetreat = true,
				ownerId = playerId,
			})
		end
	end

	for _, source in ToolService.decoySources() do
		table.insert(sources, source)
	end
	for _, source in RemainsService.sources() do
		table.insert(sources, source)
	end
	-- Burning vegetation joins the SAME list as everything else, which is the whole point: a fire is
	-- read by threats exactly as any other light is, with no special case anywhere in perception. It
	-- attracts Drawn and affects ordinary dark-hunter logic, and it can never force the panic retreat
	-- that only a real Flare causes (see MossFireService.sources).
	for _, source in MossFireService.sources() do
		table.insert(sources, source)
	end
	return sources
end

return LightSources
