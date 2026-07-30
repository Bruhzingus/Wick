--!strict
-- Pure rules for the ghost candle (DESIGN §7; values in Config/Spectator). Every decision the
-- spectator system makes that is not "move an Instance" lives here, so all of it is testable cold:
-- when a footfall is worth recording, how a trail ages out, which teammate the follow key selects
-- next, and when the server is allowed to pull a ghost back onto its target.
--
-- No Instances, no services, no clocks of its own — the caller passes the time in.

local Types = require(script.Parent.Parent.Types)

local SpectatorRules = {}

-- A player is a ghost the moment their run ends terminally. `finished` is the brazier exit: those
-- players are alive and gone, and never get a body down here.
function SpectatorRules.isGhost(alive: boolean, finished: boolean): boolean
	return not alive and not finished
end

-- Who a ghost may follow: anyone still actually playing this expedition. A SNUFFED teammate counts —
-- they are lying on the floor waiting for a relight, which is exactly where the party is and exactly
-- where a ghost wants to be watching.
function SpectatorRules.canFollow(alive: boolean, finished: boolean): boolean
	return alive and not finished
end

-- True when this runner has travelled far enough since their last recorded footfall. Distance rather
-- than time on purpose: a player standing still leaves one mark, not a growing pile of them.
function SpectatorRules.shouldSample(last: Vector3?, position: Vector3, intervalStuds: number): boolean
	if last == nil then
		return true
	end
	return (position - last).Magnitude >= math.max(intervalStuds, 0)
end

-- Drops samples that have outlived `lifetimeSeconds`, then trims the oldest until at most
-- `maxSamples` remain. Returns a new list; buffers are per-runner and small by construction.
function SpectatorRules.pruneSamples(
	samples: { Types.SpectatorSample },
	now: number,
	lifetimeSeconds: number,
	maxSamples: number
): { Types.SpectatorSample }
	local kept: { Types.SpectatorSample } = {}
	for _, sample in samples do
		if now - sample.at < lifetimeSeconds then
			table.insert(kept, sample)
		end
	end
	local limit = math.max(math.floor(maxSamples), 0)
	local excess = #kept - limit
	if excess > 0 then
		local trimmed: { Types.SpectatorSample } = {}
		for index = excess + 1, #kept do
			table.insert(trimmed, kept[index])
		end
		return trimmed
	end
	return kept
end

-- How strongly one footfall should still read, 1 at the moment it was left and falling to
-- `fadeFloor` as it ages out. Presentation-only, but it belongs here so the fade cannot drift
-- from the lifetime the server prunes by.
function SpectatorRules.trailAlpha(ageSeconds: number, lifetimeSeconds: number, fadeFloor: number): number
	if lifetimeSeconds <= 0 then
		return 0
	end
	local remaining = 1 - math.clamp(ageSeconds / lifetimeSeconds, 0, 1)
	local floor = math.clamp(fadeFloor, 0, 1)
	if remaining <= 0 then
		return 0
	end
	return floor + (1 - floor) * remaining
end

-- The follow key's whole behaviour: nil -> the first candidate, a candidate -> the next one, the
-- last candidate -> nil (roam free), and anything else -> the first candidate. Candidates are
-- sorted by id so the cycle is stable for every ghost regardless of table order.
function SpectatorRules.nextFollowTarget(candidates: { Types.PlayerId }, current: Types.PlayerId?): Types.PlayerId?
	local ordered = table.clone(candidates)
	table.sort(ordered)
	if #ordered == 0 then
		return nil
	end
	if current == nil then
		return ordered[1]
	end
	local index = table.find(ordered, current)
	if index == nil then
		return ordered[1]
	end
	if index >= #ordered then
		return nil
	end
	return ordered[index + 1]
end

-- Whether the server should pull a following ghost back onto its target. Three reasons, and the
-- first is the one this exists for: the party used a descent hole a ghost cannot use, so it is on a
-- floor that is finished and empty.
function SpectatorRules.needsReanchor(
	ghostPosition: Vector3?,
	ghostDepth: number,
	targetPosition: Vector3,
	targetDepth: number,
	maxDistance: number
): boolean
	if ghostDepth ~= targetDepth then
		return true
	end
	if ghostPosition == nil then
		return true
	end
	return (targetPosition - ghostPosition).Magnitude > math.max(maxDistance, 0)
end

-- Where a pulled ghost is placed: the target's own feet, lifted clear. Deliberately not offset
-- sideways — the target is standing there, so it is the only point on this floor the server knows is
-- standable, and a lateral nudge is how a ghost ends up inside rock.
function SpectatorRules.anchorPosition(targetPosition: Vector3, lift: number): Vector3
	return targetPosition + Vector3.new(0, math.max(lift, 0), 0)
end

-- Stable per-runner colour index into Config/Spectator.trail.ownerColors, so one teammate's path is
-- always the same colour to every ghost watching it.
function SpectatorRules.colorIndexFor(ownerId: Types.PlayerId, paletteSize: number): number
	if paletteSize <= 0 then
		return 0
	end
	return math.abs(ownerId) % paletteSize + 1
end

return SpectatorRules
