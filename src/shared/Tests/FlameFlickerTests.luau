--!strict

local Harness = require(script.Parent.Harness)
local LightConfig = require(script.Parent.Parent.Config.Light)
local FlameFlicker = require(script.Parent.Parent.Logic.FlameFlicker)

local function expectFinite(value: number, label: string)
	Harness.expect(value == value, label .. " must not be NaN")
	Harness.expect(value > -math.huge and value < math.huge, label .. " must be finite")
end

local function expectBounded(sample: FlameFlicker.Sample, label: string)
	local flicker = LightConfig.rendering.flicker
	expectFinite(sample.brightnessMultiplier, label .. " brightness")
	expectFinite(sample.warmth, label .. " warmth")
	Harness.expect(
		sample.brightnessMultiplier >= flicker.minimumBrightnessMultiplier,
		label .. " brightness fell below the configured minimum"
	)
	Harness.expect(
		sample.brightnessMultiplier <= flicker.maximumBrightnessMultiplier,
		label .. " brightness exceeded the configured maximum"
	)
	Harness.expect(sample.warmth >= 0, label .. " warmth must not be negative")
	Harness.expect(sample.warmth <= flicker.maximumWarmthBlend, label .. " warmth exceeded its configured maximum")
end

local suite: Harness.Suite = {
	name = "FlameFlicker",
	tests = {
		Harness.test("rendering config defines a safe multi-band combustion signal", function()
			local flicker = LightConfig.rendering.flicker
			Harness.expect(flicker.ownerSeedModulo > 0, "owner seed modulo must permit safe modulo")
			Harness.expect(flicker.ownerSeedScale > 0, "owner seed scale must preserve owner phase variation")
			Harness.expect(
				flicker.minimumBrightnessMultiplier < 1 and flicker.maximumBrightnessMultiplier > 1,
				"flicker bounds must permit both dimming and brightening around the authoritative target"
			)
			Harness.expect(
				flicker.minimumBrightnessMultiplier < flicker.maximumBrightnessMultiplier,
				"flicker bounds must be ordered"
			)
			Harness.expect(flicker.minimumBrightnessMultiplier >= 0, "flicker cannot render negative light")
			Harness.expect(flicker.contextResponseSeconds > 0, "context changes must have a positive response time")
			Harness.expect(flicker.impactReleaseSeconds > 0, "impact flicker must have a positive release time")
			Harness.expect(flicker.loopSeconds > 0, "the bounded coherent-noise loop must have positive duration")
			Harness.expect(flicker.noiseScale > 0, "coherent noise normalization must remain positive")
			Harness.expect(#flicker.layers > 0, "at least one regular combustion layer is required")
			for index, layer in flicker.layers do
				Harness.expect(layer.frequencyHz > 0, string.format("layer %d frequency must be positive", index))
				Harness.expect(layer.amplitude > 0, string.format("layer %d amplitude must be positive", index))
			end
			Harness.expect(
				flicker.gutter.threshold >= 0 and flicker.gutter.threshold < 1,
				"gutter threshold must leave a reachable shaped interval"
			)
			Harness.expect(flicker.gutter.depth >= 0, "gutter depth cannot brighten the flame")
			for name, contextBand in
				{
					draft = flicker.draft,
					sprint = flicker.sprint,
					threat = flicker.threat,
				}
			do
				Harness.expect(contextBand.frequencyHz > 0, name .. " frequency must be positive")
				Harness.expect(contextBand.amplitude >= 0, name .. " amplitude cannot be negative")
			end
		end),

		Harness.test("identical inputs and the long loop seam reproduce the same sample", function()
			local context: FlameFlicker.Context = {
				draft = 0.35,
				sprint = 0.7,
				threat = 0.2,
			}
			local first = FlameFlicker.sample(17.375, 5521, context)
			local second = FlameFlicker.sample(17.375, 5521, context)

			Harness.equal(first.brightnessMultiplier, second.brightnessMultiplier)
			Harness.equal(first.warmth, second.warmth)

			local looped = FlameFlicker.sample(17.375 + LightConfig.rendering.flicker.loopSeconds, 5521, context)
			Harness.near(looped.brightnessMultiplier, first.brightnessMultiplier, 1e-10)
			Harness.near(looped.warmth, first.warmth, 1e-10)
		end),

		Harness.test("representative owners times and context combinations stay finite and bounded", function()
			local owners = { -999999, 0, 1, 104728, 104729, 2147483647 }
			local times = { -10, 0, 0.01, 1.25, 50, 1000, 100000, 1780000000 }
			local contexts: { FlameFlicker.Context } = {}
			for draft = 0, 1 do
				for sprint = 0, 1 do
					for threat = 0, 1 do
						table.insert(contexts, {
							draft = draft,
							sprint = sprint,
							threat = threat,
						})
					end
				end
			end
			table.insert(contexts, {
				draft = -1,
				sprint = 2,
				threat = 0.5,
			})

			for _, ownerUserId in owners do
				for _, timeSeconds in times do
					for contextIndex, context in contexts do
						expectBounded(
							FlameFlicker.sample(timeSeconds, ownerUserId, context),
							string.format("owner %d time %.3f context %d", ownerUserId, timeSeconds, contextIndex)
						)
					end
				end
			end
		end),

		Harness.test("signal varies over time and distinct owners do not share a phase", function()
			local context: FlameFlicker.Context = {
				draft = 0,
				sprint = 0,
				threat = 0,
			}
			-- Production samples Workspace:GetServerTimeNow(), so this must vary at Unix-epoch
			-- scale rather than silently quantizing to a constant coherent-noise coordinate.
			local epochTime = 1780000000
			local origin = FlameFlicker.sample(epochTime, 137, context)
			local timeVaries = false
			local ownerPhaseDiverges = false

			for index = 1, 240 do
				local timeSeconds = epochTime + index * 0.071
				local later = FlameFlicker.sample(timeSeconds, 137, context)
				local otherOwner = FlameFlicker.sample(timeSeconds, 9917, context)
				if math.abs(later.brightnessMultiplier - origin.brightnessMultiplier) > 1e-6 then
					timeVaries = true
				end
				if math.abs(later.brightnessMultiplier - otherOwner.brightnessMultiplier) > 1e-6 then
					ownerPhaseDiverges = true
				end
			end

			Harness.expect(timeVaries, "regular candle combustion must not become a constant light output")
			Harness.expect(ownerPhaseDiverges, "different candle owners must not flicker in lockstep")
		end),

		Harness.test("context blends clamp their inputs and remain bounded through transitions", function()
			local ownerUserId = 423
			local timeSeconds = 8.125
			local zero = FlameFlicker.sample(timeSeconds, ownerUserId, {
				draft = 0,
				sprint = 0,
				threat = 0,
			})
			local belowZero = FlameFlicker.sample(timeSeconds, ownerUserId, {
				draft = -4,
				sprint = -2,
				threat = -1,
			})
			Harness.equal(belowZero.brightnessMultiplier, zero.brightnessMultiplier)
			Harness.equal(belowZero.warmth, zero.warmth)

			local one = FlameFlicker.sample(timeSeconds, ownerUserId, {
				draft = 1,
				sprint = 1,
				threat = 1,
			})
			local aboveOne = FlameFlicker.sample(timeSeconds, ownerUserId, {
				draft = 3,
				sprint = 2,
				threat = 7,
			})
			Harness.equal(aboveOne.brightnessMultiplier, one.brightnessMultiplier)
			Harness.equal(aboveOne.warmth, one.warmth)

			for step = 0, 40 do
				local weight = step / 40
				expectBounded(
					FlameFlicker.sample(timeSeconds, ownerUserId, {
						draft = weight,
						sprint = weight,
						threat = weight,
					}),
					string.format("context transition %.3f", weight)
				)
			end

			local contextChangesOutput: { [string]: boolean } = {
				draft = false,
				sprint = false,
				threat = false,
			}
			local activeContexts: { [string]: FlameFlicker.Context } = {
				draft = { draft = 1, sprint = 0, threat = 0 },
				sprint = { draft = 0, sprint = 1, threat = 0 },
				threat = { draft = 0, sprint = 0, threat = 1 },
			}
			for index = 1, 180 do
				local sampleTime = 1780000000 + index * 0.083
				local baseline = FlameFlicker.sample(sampleTime, ownerUserId, {
					draft = 0,
					sprint = 0,
					threat = 0,
				})
				for name, activeContext in activeContexts do
					local contextual = FlameFlicker.sample(sampleTime, ownerUserId, activeContext)
					if math.abs(contextual.brightnessMultiplier - baseline.brightnessMultiplier) > 1e-6 then
						contextChangesOutput[name] = true
					end
				end
			end
			for name, changed in contextChangesOutput do
				Harness.expect(changed, name .. " context must materially affect rendered combustion")
			end
		end),

		Harness.test("dim combustion samples shift toward the configured warmer flame color", function()
			local flicker = LightConfig.rendering.flicker
			local foundDimSample = false
			local context: FlameFlicker.Context = {
				draft = 0,
				sprint = 0,
				threat = 0,
			}

			for ownerUserId = 1, 5 do
				for index = 0, 800 do
					local sample = FlameFlicker.sample(index * 0.037, ownerUserId * 103, context)
					if sample.brightnessMultiplier < 1 - 1e-6 then
						foundDimSample = true
						local brightnessLoss = 1 - sample.brightnessMultiplier
						local minimumWarmth =
							math.min(flicker.maximumWarmthBlend, brightnessLoss * flicker.warmthPerBrightnessLoss)
						Harness.expect(
							sample.warmth + 1e-6 >= minimumWarmth,
							"a dimming flame must receive the corresponding warm-color shift"
						)
					end
				end
			end

			Harness.expect(foundDimSample, "the configured signal must produce observable dim combustion samples")
		end),
	},
}

return suite
