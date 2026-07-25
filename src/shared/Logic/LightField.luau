--!strict
-- Pure: the light field. Given a list of sources, answers "how bright is it here" and
-- "what is the strongest attractor near this point". All threat perception routes through this.

local Types = require(script.Parent.Parent.Types)

local LightField = {}

-- Contribution of one source at a position: linear falloff to zero at range.
function LightField.contributionOf(source: Types.LightSource, position: Vector3): number
	if source.range <= 0 then
		return 0
	end
	local distance = (source.position - position).Magnitude
	return math.max(0, source.intensity * (1 - distance / source.range))
end

-- Total light level at a position.
function LightField.intensityAt(position: Vector3, sources: { Types.LightSource }): number
	local total = 0
	for _, source in sources do
		total += LightField.contributionOf(source, position)
	end
	return total
end

-- DESIGN gives Cast a deliberately asymmetric perception rule: its decoy pulls Drawn but is
-- useless against dark-hunters. Filtering source data here keeps ThreatBrain generic.
function LightField.sourcesForDarkHunters(sources: { Types.LightSource }): { Types.LightSource }
	local perceived: { Types.LightSource } = {}
	for _, source in sources do
		if source.repelsDarkHunters then
			table.insert(perceived, source)
		end
	end
	return perceived
end

-- The single strongest source, judged from `position`, within `radius` of it.
-- requireAttractsDrawn: true when asking on behalf of the drawn (cold-wax sources are invisible to them).
function LightField.strongestSourceNear(
	position: Vector3,
	sources: { Types.LightSource },
	radius: number,
	requireAttractsDrawn: boolean
): Types.LightSource?
	local best: Types.LightSource? = nil
	local bestScore = 0
	for _, source in sources do
		if requireAttractsDrawn and not source.attractsDrawn then
			continue
		end
		if (source.position - position).Magnitude > radius then
			continue
		end
		-- Judge by perceived brightness at the asker, not raw intensity: a dim source up close
		-- can out-pull a bright one far away.
		local score = LightField.contributionOf(source, position)
		if score > bestScore then
			bestScore = score
			best = source
		end
	end
	return best
end

return LightField
