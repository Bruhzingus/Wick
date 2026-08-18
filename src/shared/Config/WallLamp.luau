--!strict
-- THE WALL LAMPS — one burnt-out candle bracketed to the rock in every room of every floor, and one
-- crowned lamp in the room the floor ends in. Cold when the floor is built; lit one at a time, by
-- hand, by a player who chose to stop and do it.
--
-- WHAT THIS REPLACED, and why: the lamps used to be a cutscene. Every room had one, they were all
-- cold, and they all caught at once in a scripted sequence the instant somebody cashed out — an
-- ending nobody could reach until the run was already over. That made a floor's worth of fixtures
-- into set dressing for five seconds of results screen. They are now a VERB. Lighting one is
-- something a player does, mid-run, at a cost, for a reason.
--
-- THE REASON: A CAVE YOU CAN READ. A lit lamp is a room you have already been in. A party that
-- lights as it goes leaves a legible trail, and the member who fell behind can follow it instead of
-- guessing. Lighting the crowned lamp in the completion room answers the whole floor at once, which
-- is how somebody who reached the way down makes the cave survivable for the friends still in it.
--
-- THEY ARE REAL LIGHT AND THAT IS NOT FREE. Every lit lamp enters `server/LightSources` exactly like
-- a flame does: dark-hunters are pushed out of the space it covers and the Drawn are pulled toward
-- it. Lighting a room does not make it safe — it changes WHICH half of the taxonomy is a problem
-- there. That asymmetry is the entire cost model, and it is why lighting a lamp needs no wax price
-- tag: what you pay is the attention you just bought, plus the seconds you spent rooted in the open
-- paying for it.
--
-- THEY ARE CANDLES, DELIBERATELY. Every flame in this world is a candle: the one in your hands, the
-- one you relight a teammate with, the stubs on the dead. A gas fixture was a second kind of fire
-- with its own colour and its own fiction about its own fuel supply, and it made the one object a
-- player was supposed to walk toward look like it came from a different game. These are the same
-- wax, the same orange, burnt down and gone out long before anybody arrived.

export type WallLampVariant = "Room" | "Main"

-- What one lit lamp is worth to threat perception (`server/LightSources`). Deliberately expressed in
-- the SAME units as the candle's own light-field numbers (Config/Light: intensity 0.18-0.42, range
-- 10-30) rather than in a private scale, so a reader can answer "is this brighter than a player" by
-- comparing two numbers instead of by tracing two curves.
export type WallLampPerception = {
	intensity: number,
	range: number,
}

-- The visible output. `point` only resolves the fixture itself; `spot` is what actually reaches the
-- room. Split for the same reason the old fixture split them: buying room coverage out of one
-- spherical source at the flame produces a small sun, and the flame stops reading as a flame.
export type WallLampOutput = {
	pointRange: number,
	pointBrightness: number,
	spotRange: number,
	spotBrightness: number,
	spotAngle: number,
	perception: WallLampPerception,
}

export type WallLampGeometry = {
	-- The iron that holds it: a flat plate against the rock, a bracket arm out of it, and a pan under
	-- the candle to catch what runs off.
	plateWidth: number,
	plateHeight: number,
	plateThickness: number,
	armLength: number,
	armThickness: number,
	panRadius: number,
	panHeight: number,
	panLipHeight: number,
	-- The candle itself. Squat and fat — a pillar somebody expected to burn for a week, not a taper.
	pillarRadius: number,
	pillarHeight: number,
	-- The melted lip at the top, same silhouette cue the player's own candle carries.
	rimRadiusMultiplier: number,
	rimHeight: number,
	-- Cold wax that ran down the side and set there. Purely silhouette: at the edge of candle range
	-- these are the only thing distinguishing a candle from a bollard.
	dripCount: number,
	dripThickness: number,
	dripMaxLength: number,
	wickHeight: number,
	wickThickness: number,
	flameHeight: number,
}

-- The crowned lamp, and only the parts that differ from a room lamp. Everything unlisted is the room
-- lamp's, scaled by `scale` — one fixture family, one manufacturer, one silhouette language.
export type MainLampGeometry = {
	scale: number,
	-- A beaten reflector plate behind the flame. The honest reason a real fixture has one (throw the
	-- light forward instead of into the wall) is also the reason this one reads as important.
	reflectorWidth: number,
	reflectorHeight: number,
	reflectorThickness: number,
	-- The crown: short iron uprights fanned around the pan, the one piece of pure ornament in the
	-- fixture set. It exists so the lamp that answers the floor is findable across a dark room.
	crownPoints: number,
	crownHeight: number,
	crownThickness: number,
	crownSpread: number,
	-- THE AURA. Two flat Neon discs behind the flame, dead at transparency 1 until the lamp catches.
	-- The one thing in the cave that is not simply fire, and the only licence taken with the "a
	-- candle is a candle" rule above: this lamp answers a whole floor, so it is allowed to look like
	-- it could.
	auraRadius: number,
	auraOuterMultiplier: number,
	auraTransparency: number,
	auraOuterTransparency: number,
	-- How far either side of resting transparency the aura breathes, and how long one breath takes.
	-- Rendered by `client/LampPresentation`; nothing on the server touches it.
	auraPulseAmplitude: number,
	auraPulseSeconds: number,
}

-- Lighting one, as a player action. The hold is the whole cost of a room lamp, so it is the number
-- that decides whether lighting the cave is a habit or a commitment.
export type WallLampInteraction = {
	promptRange: number,
	-- Slack added to `promptRange` when the server re-validates, matching the trust-boundary margins
	-- Config/Security owns everywhere else.
	positionToleranceStuds: number,
	roomHoldSeconds: number,
	mainHoldSeconds: number,
	-- How much early a client's completion may arrive before the server calls it forged. Covers one
	-- bad round trip and nothing more.
	holdGraceSeconds: number,
	-- A begun hold that never completes or cancels is dropped after this, so a disconnect mid-light
	-- cannot leave a candle leaning at a wall forever.
	holdExpirySeconds: number,
	-- How far the candle leans toward the lamp while lighting it, and how long the lean takes to
	-- reach full. Everybody on the floor sees this: it is the only outward sign of what you are doing.
	leanDegrees: number,
	leanRiseSeconds: number,
}

-- THE ANSWER. What the crowned lamp does to the rest of the floor when it catches.
export type WallLampCascade = {
	-- A held breath before the first room answers, so the cascade reads as caused by the crowned lamp
	-- rather than as part of the same flash.
	leadSeconds: number,
	-- Between rooms. Nearest first (`server/WallLampService` orders by distance from the crowned
	-- lamp), so what a listener hears is the light coming toward them or moving away.
	stepSeconds: number,
	-- The whole cascade is compressed to fit inside this no matter how large the floor is. A player is
	-- STILL PLAYING while this runs — it is a world event, not a cutscene — and an answer that takes
	-- half a minute stops being an answer.
	maximumSeconds: number,
}

export type WallLampConfig = {
	enabled: boolean,
	geometry: WallLampGeometry,
	main: MainLampGeometry,
	interaction: WallLampInteraction,
	cascade: WallLampCascade,
	roomOutput: WallLampOutput,
	mainOutput: WallLampOutput,
	-- Wax, cold and burnt. The pillar is family-neutral on purpose: it is the same wax the player is
	-- made of, and tinting it per cave would break that read.
	waxColor: Color3,
	waxLitColor: Color3,
	deadWickColor: Color3,
	litWickColor: Color3,
	flameCoreColor: Color3,
	flameTipColor: Color3,
	lightColor: Color3,
	auraColor: Color3,
	-- Installation. Every lamp is bolted to real Terrain, never floated in a room or stood on the
	-- floor: `server/FloorBuilder` probes the rendered rock across the fixture's full height and mounts
	-- just proud of the nearest real surface. No Terrain is carved, so a lamp can never produce a
	-- recessed pocket or an invented flat wall.
	installation: {
		projectionStuds: number,
		clearanceStuds: number,
		minimumFloorStuds: number,
		groundClearanceStuds: number,
		approachSampleStuds: number,
		fallbackInsetStuds: number,
		surfaceOutsetStuds: number,
		roomMountHeight: number,
		mainMountHeight: number,
	},
	-- Tag and attributes the client finds lamps by. The server never sends a lamp list: it tags the
	-- fixtures it builds and stamps their state, exactly as the water surfaces and the descent cage
	-- already do it, and every client reads the world instead of a replicated table.
	tag: string,
	depthAttribute: string,
	variantAttribute: string,
	litAttribute: string,
	restBrightnessAttribute: string,
	auraRestAttribute: string,
	auraTag: string,
	-- The catch. A small one for a room candle, the deeper fixture cue for the crowned lamp.
	roomIgniteCue: string,
	mainIgniteCue: string,
	-- The flare on catch: a hard spike that decays back to rest, never a fade-in. A light that eases
	-- up reads as somebody turning a dial; one that slams and settles reads as something catching.
	flareSeconds: number,
	flareBrightnessMultiplier: number,
}

local WallLamp: WallLampConfig = {
	-- MASTER ROLLBACK. False builds no lamps at all: no fixtures, no prompts, no cascade, and nothing
	-- in the light field. A floor without them is exactly the floor that shipped before them.
	enabled = true,

	geometry = {
		plateWidth = 0.86,
		plateHeight = 1.05,
		plateThickness = 0.14,
		-- How far the candle stands off the rock. Long enough that the bracket is legible as a bracket
		-- from the side; short enough that a player cannot walk between the candle and the wall.
		armLength = 0.74,
		armThickness = 0.13,
		panRadius = 0.46,
		panHeight = 0.1,
		panLipHeight = 0.11,
		-- FAT. A 0.3-radius pillar at 1.6 studs reads as a candle from across a room; a taper reads as
		-- a stick. The player's own candle is the same proportion for the same reason.
		pillarRadius = 0.3,
		pillarHeight = 1.6,
		rimRadiusMultiplier = 1.12,
		rimHeight = 0.14,
		-- Three runs, not a symmetric ring: wax runs where the draught took it.
		dripCount = 3,
		dripThickness = 0.11,
		dripMaxLength = 0.72,
		wickHeight = 0.2,
		wickThickness = 0.07,
		flameHeight = 0.44,
	},

	main = {
		-- Half again as big in every dimension. Enough that the crowned lamp is obviously the same
		-- object as the room lamps and obviously not one of them.
		scale = 1.5,
		reflectorWidth = 1.5,
		reflectorHeight = 1.7,
		reflectorThickness = 0.1,
		crownPoints = 7,
		crownHeight = 0.5,
		crownThickness = 0.09,
		-- Degrees the outermost crown points fan away from vertical.
		crownSpread = 34,
		auraRadius = 1.15,
		auraOuterMultiplier = 1.75,
		-- Faint. The aura is a halo behind a flame, never a second light source — these are Neon, which
		-- in this engine means self-illuminating pixels and NOT illumination, so they light nothing.
		auraTransparency = 0.72,
		auraOuterTransparency = 0.9,
		auraPulseAmplitude = 0.07,
		auraPulseSeconds = 3.4,
	},

	interaction = {
		promptRange = 9,
		positionToleranceStuds = 2,
		-- TWO SECONDS IS THE PRICE OF A ROOM. Long enough that you have to decide to do it and long
		-- enough for something to walk in on you; short enough that lighting your way through a floor
		-- is not a chore. Rooted the whole time, and any movement input cancels it.
		roomHoldSeconds = 2,
		-- The crowned lamp answers a whole floor, so it asks for longer. It is also, by construction,
		-- lit in the room that holds the Cauldron, the Brazier and the way down — the one place on the
		-- floor where standing still for three seconds is a real decision.
		mainHoldSeconds = 3,
		holdGraceSeconds = 0.25,
		holdExpirySeconds = 12,
		-- The candle bows to touch its flame to a dead wick. It is a literal reading of the action and
		-- it costs no animation data: the rig is four welded parts and this pivots all of them together
		-- about the candle's base (`server/CharacterService.applyLean`).
		leanDegrees = 26,
		leanRiseSeconds = 0.35,
	},

	cascade = {
		leadSeconds = 0.5,
		stepSeconds = 0.5,
		-- Eight seconds for the largest floor. A cascade the player is walking around during must be
		-- over before they have left the room they started it in.
		maximumSeconds = 8,
	},

	-- ONE ROOM LAMP LIGHTS ITS CORNER, NOT THE ROOM. Deliberately below the candle's own maximum reach
	-- (Config/Light: 30 studs at full dial): a lit lamp tells you where you have been and gives you
	-- something to walk toward, and you still work by the flame in your hands. The cave staying dark is
	-- the game; a fixture in every room that each lit a whole chamber would end it one hold at a time.
	roomOutput = {
		pointRange = 12,
		pointBrightness = 0.34,
		spotRange = 26,
		spotBrightness = 0.85,
		spotAngle = 130,
		-- Perception sits close to what the fixture visibly throws, and below a full-dial candle. A lamp
		-- that pushed hunters further than it lit would be a safety the player could not see the edge of.
		perception = {
			intensity = 0.2,
			range = 22,
		},
	},

	-- The crowned lamp is the exception it has earned: it is lit once per floor, by hand, in the room
	-- the floor ends in. It still is not a floodlight — it is the brightest thing in the cave and the
	-- cave is still a cave.
	mainOutput = {
		pointRange = 17,
		pointBrightness = 0.5,
		spotRange = 46,
		spotBrightness = 1.2,
		spotAngle = 150,
		perception = {
			intensity = 0.4,
			range = 40,
		},
	},

	-- The same dirty tallow the player is made of, gone cold.
	waxColor = Color3.fromRGB(214, 201, 172),
	-- Lit wax glows slightly from within where the flame has softened the top. A small shift; the
	-- pillar is never a light source.
	waxLitColor = Color3.fromRGB(232, 214, 176),
	-- BURNT OUT. Charcoal, not black: a wick that has been lit before and gone out, which is the whole
	-- story the cold fixture has to tell.
	deadWickColor = Color3.fromRGB(38, 34, 31),
	litWickColor = Color3.fromRGB(96, 62, 38),
	-- CANDLE-ORANGE, the same fire as everything else in this world.
	flameCoreColor = Color3.fromRGB(255, 226, 160),
	flameTipColor = Color3.fromRGB(255, 152, 62),
	lightColor = Color3.fromRGB(255, 164, 84),
	-- The aura leans cooler than the flame so it reads as around the fire rather than as more of it.
	auraColor = Color3.fromRGB(255, 198, 138),

	installation = {
		projectionStuds = 1.1,
		clearanceStuds = 1.25,
		minimumFloorStuds = 4,
		groundClearanceStuds = 0.75,
		approachSampleStuds = 4,
		fallbackInsetStuds = 9,
		surfaceOutsetStuds = 0.2,
		-- Mounted at the height a person would actually reach to light one, which is also roughly the
		-- height of the flame the player is carrying. The two flames meet level, and the lean does the
		-- rest.
		roomMountHeight = 2.2,
		mainMountHeight = 2.35,
	},

	tag = "WickWallLamp",
	depthAttribute = "WickLampDepth",
	variantAttribute = "WickLampVariant",
	litAttribute = "WickLampLit",
	restBrightnessAttribute = "WickLampRestBrightness",
	auraRestAttribute = "WickLampAuraRest",
	auraTag = "WickWallLampAura",

	roomIgniteCue = "LampIgnite",
	mainIgniteCue = "LanternIgnite",
	flareSeconds = 0.5,
	flareBrightnessMultiplier = 1.7,
}

return WallLamp
