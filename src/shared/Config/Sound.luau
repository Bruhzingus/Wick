--!strict
-- The sound field: what the cave can hear, and how loudly. The second perception field alongside
-- light (Config/Light + Logic/LightField), read through Logic/SoundField.
--
-- THREE RULES that keep this from becoming a second threat system:
--   1. Only DARK-HUNTERS listen. The Drawn are moth logic and stay deaf, so a noisy action never
--      pulls both families at once and the light/dark read is untouched. Ears are one optional
--      `hearing` field on a Config/Threats row (Types/Sound.HearingProfile).
--   2. Hearing is CURIOSITY, never acquisition. A heard noise makes a hunter walk to where the
--      sound was and look around. It does not tell it where you are now, does not make it faster,
--      and does not raise its damage. Being heard costs you a location.
--   3. Loudness SUMS and DECAYS. One noise is usually under the curiosity threshold; three
--      overlapping ones are not. "Repeated hits lure them" is not special-cased anywhere — it falls
--      out of adding decaying events together.
--
-- Adding an emitter is one row below plus one NoiseService.emit call at the site that already knows
-- the event happened.

export type NoiseDef = {
	-- Perceived strength at the source. Compare against hearing.curiosityThreshold below: a single
	-- clean pick strike (0.55) sits under a shallow crawler's threshold (0.8), so ONE swing is usually
	-- ignored and the second or third is what brings something. That threshold falls with depth
	-- (Config/Threats.DarkCrawler.depthScaling.hearing), so the same swing buys less silence deeper down.
	loudness: number,
	-- Studs to silence. Linear falloff, so a noise's reach is honest and readable.
	radius: number,
	-- Seconds for the event to decay to nothing. This is the overlap window that lets repeated
	-- strikes add up, so it must stay comfortably longer than the gap between them.
	decaySeconds: number,
}

export type SoundConfig = {
	enabled: boolean,
	-- Hard cap on live events, oldest dropped first. A runaway emitter degrades the field's
	-- resolution instead of the server's frame time.
	maxLiveEvents: number,
	-- Default running is a continuous state, not a moment, so it emits on a timer rather than on an event.
	-- Long enough that two consecutive footfall events barely overlap: running past something is a
	-- risk, but it must not be a louder version of mining.
	sprintEmitIntervalSeconds: number,
	emitters: { [string]: NoiseDef },
}

local Sound: SoundConfig = {
	enabled = true,
	maxLiveEvents = 96,
	sprintEmitIntervalSeconds = 1.1,
	emitters = {
		-- MINING. The clean strike is the quiet one: hitting the timing window is what buys you
		-- safety, and it is the only lever the player has over how exposed mining makes them.
		MineStrikeClean = {
			loudness = 0.55,
			radius = 46,
			decaySeconds = 3.2,
		},
		-- A fumbled swing is a scrape and a clatter rather than a clean bite — louder, further, and
		-- longer-lived, so a player who cannot hit the rail both takes more swings AND advertises
		-- each one harder. This is the entire skill-to-safety relationship in two rows.
		MineStrikeFumble = {
			loudness = 0.95,
			radius = 62,
			decaySeconds = 4,
		},
		-- The seam giving way. The loudest single thing mining produces, and it lands at the exact
		-- moment the player is free to leave — the reward and the consequence arrive together.
		MineBreak = {
			loudness = 1.25,
			radius = 74,
			decaySeconds = 4.5,
		},
		-- THE SIGNAL BELL (Config/LampNetwork.bell). Louder and further than a clean strike, because
		-- being heard is the entire point of ringing it — but shorter-lived than a seam breaking, so it
		-- is a moment the dark notices rather than a place it settles on.
		--
		-- THIS ROW IS THE DOWNSIDE. A bell that only reached teammates would be a free position readout
		-- in a game built on not knowing where anything is; feeding the same field a fumbled pickaxe
		-- feeds means the cave hears it too, and dark-hunters come to look. Lowering `loudness` or
		-- `radius` here is lowering the price of being found.
		SignalBell = {
			loudness = 1.05,
			radius = 64,
			decaySeconds = 2.4,
		},
		-- EXISTING WORLD EVENTS. Deliberately quiet relative to mining: they are the noise floor
		-- that mining stands out against, not competing attractions.
		--
		-- Default running. Per emit interval, not per second (NoiseService throttles it), and under every
		-- hearing threshold on its own — running past something is not automatically a mistake, but
		-- running past it repeatedly, or running while anything else is happening, can be.
		Sprint = {
			loudness = 0.3,
			radius = 30,
			decaySeconds = 1.6,
		},
		-- A dripstone crown hitting the floor. Genuinely loud, and already a moment the player is
		-- reeling from — this is the cheapest dread in the game and costs no new mechanic.
		DripstoneImpact = {
			loudness = 1.4,
			radius = 85,
			decaySeconds = 5,
		},
		-- A vine curtain going up. Burning through is already a loud, bright, expensive commitment
		-- by design; giving it a noise makes the "loud" part literal.
		VineBurn = {
			loudness = 0.85,
			radius = 55,
			decaySeconds = 4,
		},
	},
}

return Sound
