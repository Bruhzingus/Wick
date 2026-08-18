--!strict
-- Assembles the complete light field each tick: every lit flame (cup-dimmed, flare-boosted),
-- every decoy and every remains pool. Threats see exactly this list — which is
-- why every tool works: they all edit this list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local BrightnessMap = require(ReplicatedStorage.Shared.Logic.BrightnessMap)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local CandleModifiers = require(ReplicatedStorage.Shared.Logic.CandleModifiers)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local PlayerState = require(script.Parent.PlayerState)
local ToolService = require(script.Parent.ToolService)
local RemainsService = require(script.Parent.RemainsService)
local MossFireService = require(script.Parent.MossFireService)
local WallLampService = require(script.Parent.WallLampService)

local LightSources = {}

function LightSources.collect(now: number): { Types.LightSource }
	local sources: { Types.LightSource } = {}

	for playerId, state in PlayerState.all() do
		if not state.alive or state.finished or not state.isLit then
			continue
		end
		local cupMultiplier = 1
		if state.isCupping then
			cupMultiplier = Config.Tools.Cup.lightMultiplier :: number -- Cup rows always define this
		end
		-- The SAME derived profile the player's own light is rendered from, so a BrightWax stack is
		-- seen by the Drawn exactly as far as it is seen by the player carrying it.
		local candle = CandleModifiers.profile(state.candle, state.isCupping)
		local params = BrightnessMap.paramsFor(state.burnRate, candle, cupMultiplier)
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
			attractsDrawn = candle.attractsDrawn,
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
				attractsDrawn = candle.attractsDrawn,
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
	-- THE WALL LAMPS A PLAYER LIT BY HAND (Config/WallLamp). They join the SAME list for the same
	-- reason burning vegetation does, and it is the entire reason lighting a cave means anything: a
	-- lit lamp is read by threats exactly as any other light is, so a lit room pushes dark-hunters out
	-- and pulls the Drawn in with no special case anywhere in perception.
	--
	-- Unlike every other entry in this list, a lamp has no owner and never moves or goes out — see
	-- Logic/WallLampRules.lightSource, which is also where the refusal to let one force a Flare's
	-- panic retreat lives.
	for _, source in WallLampService.sources() do
		table.insert(sources, source)
	end
	return sources
end

return LightSources
