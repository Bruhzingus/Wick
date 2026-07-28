--!strict
-- Sound-domain types. The cave's SECOND perception field, alongside the light field.
--
-- The light field answers "how bright is it here"; the sound field answers "what did I just hear
-- over there". They are deliberately separate: light is continuous and owned by whoever is burning,
-- while noise is a set of discrete, decaying events that outlive the action that made them. A threat
-- that hears something walks to WHERE THE NOISE WAS, never to where the player currently is — being
-- heard costs you a location, not your life.
--
-- Like LightSource, every emitter produces the same row shape and every listener reads it through
-- Logic/SoundField. Adding an emitter is one Config/Sound row; adding a listener is one `hearing`
-- field on a threat definition. Neither ever means a branch in the brain.

-- Which world event made a noise. Open string alias: the emitter pool grows by Config/Sound rows.
export type NoiseKind = string

-- One thing that was heard. Emitted by the server, expired by the server, read by the pure field.
export type NoiseEvent = {
	kind: NoiseKind,
	position: Vector3,
	-- Perceived strength at the source. Falls off linearly to zero at `radius` and decays to zero
	-- over `decaySeconds`, so a single tap fades while repeated taps overlap and SUM.
	loudness: number,
	radius: number,
	decaySeconds: number,
	createdAt: number, -- os.clock()
	-- Who caused it, when a player did. Never used to target that player directly; it exists so a
	-- noise made inside a protected room can be filtered exactly like a light source or trail point.
	ownerId: number?,
}

-- One threat row's ears. Absent = deaf, which is the default for every existing threat.
export type HearingProfile = {
	-- Multiplies perceived loudness. The magnitude knob, mirroring |lightResponse|.
	sensitivity: number,
	-- Summed perceived loudness that has to be exceeded before curiosity wins. THE reason a single
	-- strike is usually ignored and a third one is not: overlapping events add together.
	curiosityThreshold: number,
	-- How far away a noise can still pull it. Independent of detectionRadius, which stays the
	-- sight/light range: something can be heard from further off than it can be seen.
	hearingRadius: number,
	-- How long it commits to a noise once it decides to go and look. Real prey still interrupts.
	investigateSeconds: number,
	-- Fraction of full speed used while walking to a noise. Below a hunt: curious, not alerted.
	investigateSpeedFraction: number,
}

return {}
