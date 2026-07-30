--!strict
-- THE GHOST CANDLE — what a terminally dead player becomes for the rest of the expedition
-- (DESIGN §7: "you become a wisp… death doesn't mean sitting out"; §21 Q8 asks what exactly it can
-- do). This file is the whole answer, as numbers.
--
-- THE SHAPE OF THE ANSWER IS SUBTRACTION, NOT A NEW SYSTEM. A ghost is the candle you were with
-- every verb removed: it cannot mine, carry, ring, sacrifice, relight, or be perceived, and the
-- three things it keeps are all deliberately weak.
--
--   * A BODY that walks. It is translucent so nobody mistakes it for a live candle, and it walks
--     rather than flies so it can never scout a room the party has not reached. Rock still stops it.
--   * A LIGHT that is almost nothing (`light`). It is the "slightly useful" the design asks for and
--     it fades out entirely after `light.fadeAfterSeconds`, so being dead is never a lighting
--     strategy. It is cosmetic in the strictest sense: server/LightSources never collects it, so no
--     threat in the game can see it, be drawn to it, or be repelled by it.
--   * A TRAIL of its teammates' footfalls (`trail`), visible to ghosts and to nobody else. This is
--     the only sense a ghost has. In a cave it cannot light, the trail is how it finds the party —
--     which is why the samples come from the SERVER's own sampled positions and are replicated only
--     to players who are actually dead.
--
-- FOLLOWING (`follow`) exists because the party descends and a ghost cannot use the descent hole.
-- A ghost that lost its party would otherwise be stranded alone on a finished floor for the rest of
-- the run, which is the one failure state this whole system exists to prevent.

export type SpectatorBodyConfig = {
	height: number,
	transparency: number,
	waxColor: Color3,
	rimColor: Color3,
	wickColor: Color3,
	flameColor: Color3,
	flameTransparency: number,
	walkSpeed: number,
	hopPower: number,
}

export type SpectatorLightConfig = {
	range: number,
	brightness: number,
	fadeAfterSeconds: number,
}

export type SpectatorFollowConfig = {
	autoFollowOnDeath: boolean,
	graceSeconds: number,
	anchorLift: number,
	reanchorDistance: number,
	reanchorCooldownSeconds: number,
}

export type SpectatorTrailConfig = {
	sampleIntervalStuds: number,
	maxSamplesPerRunner: number,
	lifetimeSeconds: number,
	sendHz: number,
	markerWidth: number,
	markerThickness: number,
	markerLift: number,
	markerTransparency: number,
	markerFadeFloor: number,
	freshMarkerSeconds: number,
	freshMarkerWidthMultiplier: number,
	ownerColors: { Color3 },
}

export type SpectatorHudConfig = {
	enabled: boolean,
	displayOrder: number,
	position: UDim2,
	size: UDim2,
	touchSize: UDim2,
	maxTextSize: number,
	backgroundTransparency: number,
	followingFormat: string,
	freeRoamText: string,
	noTargetText: string,
	hintFormat: string,
}

export type SpectatorConfig = {
	body: SpectatorBodyConfig,
	light: SpectatorLightConfig,
	follow: SpectatorFollowConfig,
	trail: SpectatorTrailConfig,
	hud: SpectatorHudConfig,
}

local Spectator: SpectatorConfig = {
	body = {
		-- Fixed height (studs), between Config/Character's zero-wax and full-wax bodies. A ghost does
		-- not shrink: the shrink rule is the living wax meter made visible, and there is no meter left.
		height = 2.6,
		-- How see-through the wax reads. Higher = fainter. Anything below ~0.4 starts to read as a
		-- living candle at distance, which is the one misread that matters in a dark corridor.
		transparency = 0.62,
		waxColor = Color3.fromRGB(196, 206, 220),
		rimColor = Color3.fromRGB(214, 222, 234),
		wickColor = Color3.fromRGB(72, 78, 90),
		-- Cold, not warm: the one colour cue that says this flame is not fuel.
		flameColor = Color3.fromRGB(150, 194, 255),
		flameTransparency = 0.55,
		-- Studs/s. Faster than a living walk (Config/Movement.walkSpeed = 8) so a ghost can keep up
		-- with the party on foot, slower than a sprint so it still has to follow rather than lead.
		walkSpeed = 14,
		-- Terrain recovery only, same job as the living hop: clear a seam or a small swell.
		hopPower = 30,
	},
	light = {
		-- CANNOT LIGHT THE CAVE, BY CONSTRUCTION. Roughly a tenth of a living candle's reach: enough
		-- to see your own wax and the stone at your feet, never enough to read a room.
		range = 6,
		brightness = 0.35,
		-- Seconds after death before the glow is gone for good (the old wisp's "goes still and dark",
		-- kept as going DARK only — the body keeps walking, because a spectator that cannot move is
		-- not spectating). Shorter = dying costs the party its faint extra lamp sooner.
		fadeAfterSeconds = 120,
	},
	follow = {
		-- Ghosts start attached to a living teammate. Without this, the first thing a newly dead
		-- player has to do is find one in the dark, which is exactly the state the trail exists to fix.
		autoFollowOnDeath = true,
		-- Seconds a fresh ghost is left standing over its own remains before following can snap it
		-- away. The pile it just dropped is information the party needs, and the owner should see
		-- where it landed.
		graceSeconds = 4,
		-- Studs the ghost is lifted when it is re-anchored onto its target. Deliberately a lift and
		-- not a lateral offset: the target's own feet are the only point on the floor the server
		-- KNOWS is standable, so a sideways nudge is the one way to put a ghost inside rock.
		anchorLift = 0.5,
		-- How far a ghost may drift from its target before the server pulls it back. Generous: this
		-- is a leash for getting lost or left on a finished floor, not a tether that yanks.
		reanchorDistance = 90,
		-- Minimum seconds between two pulls, so a ghost that walks the boundary is not teleported
		-- every frame.
		reanchorCooldownSeconds = 2,
	},
	trail = {
		-- Studs a living runner must travel before their next footfall is recorded. Lower = a denser,
		-- easier-to-read path and more samples to replicate.
		sampleIntervalStuds = 4,
		-- Cap per runner, oldest dropped first. With four runners this bounds the whole system at
		-- 4 × this many local marker parts on the spectating client.
		maxSamplesPerRunner = 48,
		-- Seconds a footfall stays visible to ghosts. This is the memory of the system: long enough
		-- to follow a party that is a room ahead, short enough that a floor does not fill with lines.
		lifetimeSeconds = 45,
		-- Trail replication rate to each ghost. Only new samples are sent, so this is a latency knob
		-- rather than a bandwidth one.
		sendHz = 4,
		-- One footfall mark: a thin disc laid flat on the ground.
		markerWidth = 0.9,
		markerThickness = 0.08,
		markerLift = 0.06,
		-- Transparency of the freshest mark; it fades to invisible across `lifetimeSeconds`.
		markerTransparency = 0.25,
		-- Floor on the fade curve, so the oldest visible marks are faint rather than gone.
		markerFadeFloor = 0.08,
		-- The newest mark of each runner is drawn larger — the read is "they are THERE", and it is the
		-- one piece of live information a ghost gets.
		freshMarkerSeconds = 2.5,
		freshMarkerWidthMultiplier = 1.8,
		-- One colour per runner, picked by userId so two teammates' paths never merge into one line.
		ownerColors = {
			Color3.fromRGB(150, 194, 255),
			Color3.fromRGB(168, 255, 214),
			Color3.fromRGB(255, 196, 150),
			Color3.fromRGB(226, 170, 255),
		},
	},
	hud = {
		enabled = true,
		displayOrder = 7,
		position = UDim2.fromScale(0.5, 0.09),
		size = UDim2.fromScale(0.44, 0.052),
		-- Touch has no follow key, so the readout carries the button and needs the room for it.
		touchSize = UDim2.fromScale(0.52, 0.13),
		maxTextSize = 20,
		backgroundTransparency = 0.32,
		-- %s is the followed teammate's name.
		followingFormat = "GHOST · following %s",
		freeRoamText = "GHOST · roaming free",
		noTargetText = "GHOST · no one is left down here",
		-- %s is the follow key's label.
		hintFormat = "[%s] follow the next candle · their footfalls are all you can see",
	},
}

return Spectator
