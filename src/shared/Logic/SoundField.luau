--!strict
-- Pure: the sound field. Given a list of decaying noise events, answers "how loud is it here" and
-- "is there anything here worth walking over to look at". Every listener routes through this, the
-- same way every light-based perception routes through LightField.
--
-- The two falloffs are deliberately both linear and both honest:
--   * DISTANCE — full loudness at the source, zero at the event's radius.
--   * TIME     — full loudness when it happens, zero at the end of its decay window.
-- Multiply them and events SUM. That product is the whole design: one strike fades before it
-- matters, three strikes in a row overlap and add, and nothing anywhere needs an `if mining` branch
-- to produce "repeated hits lure them".

local Types = require(script.Parent.Parent.Types)
local SoundConfig = require(script.Parent.Parent.Config.Sound)

local SoundField = {}

-- Has this event finished decaying? The server uses this to expire; the field uses it to skip.
function SoundField.isExpired(event: Types.NoiseEvent, now: number): boolean
	return event.decaySeconds <= 0 or now - event.createdAt >= event.decaySeconds
end

-- How much of this event is left, 1 at the instant it happened down to 0 at the end of its window.
function SoundField.remainingFraction(event: Types.NoiseEvent, now: number): number
	if event.decaySeconds <= 0 then
		return 0
	end
	local age = now - event.createdAt
	if age < 0 then
		-- A clock that has not reached the event yet still hears it at full strength rather than
		-- above it; loudness is never allowed to exceed the configured row.
		return 1
	end
	return math.clamp(1 - age / event.decaySeconds, 0, 1)
end

-- Contribution of ONE event at a position: distance falloff x time decay.
function SoundField.contributionOf(event: Types.NoiseEvent, position: Vector3, now: number): number
	if event.radius <= 0 or event.loudness <= 0 then
		return 0
	end
	local distance = (event.position - position).Magnitude
	if distance >= event.radius then
		return 0
	end
	return event.loudness * (1 - distance / event.radius) * SoundField.remainingFraction(event, now)
end

-- Total perceived loudness at a position. Events ADD — this is what makes repetition matter.
function SoundField.loudnessAt(position: Vector3, events: { Types.NoiseEvent }, now: number): number
	local total = 0
	for _, event in events do
		total += SoundField.contributionOf(event, position, now)
	end
	return total
end

export type Audible = {
	position: Vector3, -- WHERE THE SOUND WAS. Never where a player currently is.
	loudness: number, -- summed perceived loudness that crossed the threshold
}

-- Does this listener want to go and look, and at what?
--
-- The returned position is the loudness-weighted centre of everything it can currently hear, not
-- the single loudest event: a player striking the same seam repeatedly is walked toward as one
-- place rather than as a series of near-identical points. Returns nil when the summed loudness is
-- under the profile's curiosity threshold, which is the common case for any single noise.
function SoundField.audibleFor(
	position: Vector3,
	events: { Types.NoiseEvent },
	now: number,
	profile: Types.HearingProfile
): Audible?
	if not SoundConfig.enabled or profile.sensitivity <= 0 then
		return nil
	end

	local total = 0
	local weighted = Vector3.zero
	for _, event in events do
		-- hearingRadius is the listener's own gate, applied before the event's falloff: a quiet
		-- noise far away is not merely faint, it is out of earshot entirely.
		if (event.position - position).Magnitude > profile.hearingRadius then
			continue
		end
		local contribution = SoundField.contributionOf(event, position, now) * profile.sensitivity
		if contribution <= 0 then
			continue
		end
		total += contribution
		weighted += event.position * contribution
	end

	if total <= 0 or total < profile.curiosityThreshold then
		return nil
	end
	return {
		position = weighted / total,
		loudness = total,
	}
end

-- Build one event from its Config/Sound row. The single place a NoiseKind becomes a NoiseEvent, so
-- an emitter site never has to know the tuning it is emitting.
function SoundField.eventFor(kind: Types.NoiseKind, position: Vector3, now: number, ownerId: number?): Types.NoiseEvent?
	local def = SoundConfig.emitters[kind]
	if not SoundConfig.enabled or def == nil then
		return nil
	end
	return {
		kind = kind,
		position = position,
		loudness = def.loudness,
		radius = def.radius,
		decaySeconds = def.decaySeconds,
		createdAt = now,
		ownerId = ownerId,
	}
end

return SoundField
