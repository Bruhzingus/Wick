--!strict
-- THE GAS LANTERN — the fixture a run is cashed out at (DESIGN §12), and the only flame in this game
-- a player does not have to carry.
--
-- THIS FILE OWNS THE FIXTURE, NEVER THE REWARD. `Config/Brazier` still owns the payout arithmetic,
-- the prompt range, the hold time and the tolerance the server re-validates against; every one of
-- those numbers is untouched by this overhaul. What lives here is what the object looks like, what
-- happens the instant it catches, and how long that lasts.
--
-- "GAS, NOT WAX" IS FICTION AND NOT A MECHANIC. The lantern is fed by its own supply, so lighting it
-- does not draw on the candle in the player's hands — but it never did. The reward formula READS how
-- much Raw Wax that player is carrying; the lamp is not fuelled by it. Nothing in this file may be
-- implemented as "the fixture is now free to use", because it was never paid for.
--
-- COLD UNTIL LIT. Every surface below is dead — unlit glass, dark wick, no glow — for the same
-- reason a blast door is inert until it is blown and Frozen Wax is a dull block until it thaws: the
-- ignition has to be worth watching, and a fixture that is already glowing has spent that.
--
-- THE FLAME IS NOT CANDLE-ORANGE AND NOT DESCENT-BLUE. Candle-orange belongs to the flame the player
-- carries, everywhere, always; the cold blue that used to mark the way down was retired with the
-- descent beacon and reads hostile. A gas flame is the honest third answer and needs no new hue in
-- the palette: a pale blue-white core with warm tips, which is what burning gas actually looks like.

export type LanternChainReactionConfig = {
	flareSeconds: number,
	flareBrightnessMultiplier: number,
	echoCount: number,
	echoDelaySeconds: number,
	echoSpacingSeconds: number,
	echoDistanceStuds: number,
	echoLevelFalloff: number,
	echoPitchFalloff: number,
}

-- THE CAVE-WIDE LAMP NETWORK: one cold fixture mounted to a real Terrain wall in every room, then lit
-- in a floor-wide sequence when somebody commits.
--
-- THEY ARE THE ONLY OTHER THING ON A FLOOR THAT CAN BE LIT. Before them a floor had exactly one
-- lightable fixture (this lantern) and one always-on work lamp on the ladder, so the moment a run
-- ended had nowhere to go: the lamp caught and the results card was already on screen. These exist to
-- give that moment enough room to read before the card arrives.
--
-- THEY ARE NOT A TRAVEL SEQUENCE. DESIGN §404 and GAME-BRIEF §736 both retired the return-to-surface
-- ride; the run still ends exactly where the player is standing. The network answers through the
-- rooms they actually explored, and then the card comes.
export type LanternNetworkConfig = {
	enabled: boolean,
	-- Fraction of the Gas Lantern's own head size. Larger than the original floor lamps so their
	-- silhouettes carry during the short free-look window before the results card.
	scale: number,
	-- Every lamp and the Gas Lantern are attached to clear cave walls, never placed as floor posts.
	projectionStuds: number,
	-- Random wall relief is not built inside this padding around the fixture.
	installationClearanceStuds: number,
	installationMinimumFloorStuds: number,
	installationGroundClearanceStuds: number,
	installationApproachSampleStuds: number,
	installationFallbackInsetStuds: number,
	installationSurfaceOutsetStuds: number,
	mainMountHeight: number,
	lampMountHeight: number,
	postHeight: number,
	lightRange: number,
	lightBrightness: number,
	roomLightRange: number,
	roomLightBrightness: number,
	roomLightAngle: number,
	-- THE BEAT. A held breath after the Gas Lantern catches, one lamp per step, then a completed-cave
	-- hold. A last or unanimous group extraction keeps normal first-person camera control for exactly
	-- `freeLookSeconds`; early individual extraction gets its results immediately.
	leadSeconds: number,
	stepSeconds: number,
	settleSeconds: number,
	freeLookSeconds: number,
}

export type LanternConfig = {
	postHeight: number,
	postThickness: number,
	baseRadius: number,
	baseHeight: number,
	housingWidth: number,
	housingHeight: number,
	glassInset: number,
	glassColor: Color3,
	glassTransparency: number,
	glassLitTransparency: number,
	capOverhang: number,
	valveLength: number,
	deadWickColor: Color3,
	flameCoreColor: Color3,
	flameTipColor: Color3,
	flameHeight: number,
	lightColor: Color3,
	lightRange: number,
	lightBrightness: number,
	roomLightRange: number,
	roomLightBrightness: number,
	roomLightAngle: number,
	depthChain: {
		enabled: boolean,
		linkHeight: number,
		linkThickness: number,
		maxLinks: number,
		floorsPerLink: number,
	},
	chainReaction: LanternChainReactionConfig,
	network: LanternNetworkConfig,
	igniteCue: string,
	-- Written onto every lamp light this file builds, carrying the brightness that lamp is supposed to
	-- settle back to. The ignition flare reads it rather than assuming the Gas Lantern's own value,
	-- which is what lets a dimmer network lamp flare and settle without being left burning at the big
	-- fixture's output.
	restBrightnessAttribute: string,
}

local Lantern: LanternConfig = {
	-- The stand. A candle is four studs tall, so the lamp head sits at roughly eye height: the flame
	-- you are walking toward is level with the flame you are carrying, which is the whole comparison
	-- the moment is about.
	postHeight = 3.1,
	postThickness = 0.32,
	baseRadius = 1.05,
	baseHeight = 0.34,
	-- The lamp head. Squat and square — four panes and a cap, not a globe.
	housingWidth = 1.15,
	housingHeight = 1.35,
	-- How far the glass sits inside the frame. Small; the frame has to read as holding the panes.
	glassInset = 0.08,
	-- Dark green-grey glass, the colour cold lamp glass actually is. Never clear: clear glass in an
	-- unlit cave is invisible, and the panes are the point of the silhouette.
	glassColor = Color3.fromRGB(52, 62, 60),
	glassTransparency = 0.42,
	-- Lit glass goes CLEARER, not brighter: what you see through it is the flame behind it, so the
	-- glass itself never becomes the light.
	glassLitTransparency = 0.16,
	capOverhang = 0.22,
	valveLength = 0.5,
	deadWickColor = Color3.fromRGB(28, 26, 24),
	-- THE GAS READ: a hot pale core with warm tips. Two parts, not a gradient — this game builds
	-- flames out of a small number of hard-edged pieces (see the candle's own flame) and a soft
	-- gradient here would be the one flame in the world that was drawn differently.
	flameCoreColor = Color3.fromRGB(196, 226, 255),
	flameTipColor = Color3.fromRGB(255, 168, 82),
	flameHeight = 0.62,
	-- WHAT THE LIT LANTERN THROWS. This is a deliberate exception to "the candle is the only light":
	-- it is the payoff of finishing a floor. Strong amber keeps ice and wet rock warm instead of
	-- bleaching them white when the network catches.
	lightColor = Color3.fromRGB(255, 158, 72),
	-- The PointLight only resolves the glass and mounting hardware. A broad, restrained SpotLight is
	-- added when FloorBuilder mounts the fixture and carries the useful illumination into the room;
	-- separating the two avoids buying room coverage with one sun-like hotspot at the flame.
	lightRange = 11,
	lightBrightness = 0.42,
	roomLightRange = 68,
	roomLightBrightness = 1.6,
	roomLightAngle = 150,
	-- THE DEPTH CHAIN: a physical run of links hanging from the lantern's post whose length is how
	-- deep this run has already reached. Computed from the floor's own global depth at build time, so
	-- it never depends on an older floor still existing — floors are torn down two deep behind the
	-- party and this must survive that.
	depthChain = {
		enabled = true,
		linkHeight = 0.24,
		linkThickness = 0.11,
		-- Caps the run so a very deep expedition does not hang a chain through the floor.
		maxLinks = 14,
		floorsPerLink = 1,
	},
	-- THE CHAIN REACTION: one shot, fired the moment a player commits, and carrying no state at all.
	-- It says "this keeps going somewhere you cannot see" and deliberately does not claim to
	-- represent any particular floor, lamp or route.
	chainReaction = {
		-- The catch. A hard flare that decays back to the lantern's steady output, never a fade-in.
		flareSeconds = 0.55,
		-- Enough to read as a catch without clipping the amber throw back toward white on pale rock.
		flareBrightnessMultiplier = 1.75,
		-- The answering ignitions. Quieter, lower and further away each time — the same cue as the
		-- lantern's own, played from anchors placed out in the dark.
		echoCount = 2,
		echoDelaySeconds = 0.42,
		echoSpacingSeconds = 0.5,
		echoDistanceStuds = 46,
		echoLevelFalloff = 0.45,
		echoPitchFalloff = 0.88,
	},
	-- THE FLOOR-WIDE NETWORK. Every room gets exactly one visible wall fixture. In the completion room
	-- that fixture is the interactive Gas Lantern itself, so no decorative companion is added.
	network = {
		enabled = true,
		scale = 1.05,
		projectionStuds = 1.35,
		installationClearanceStuds = 1.25,
		-- The cave floor rises into a berm and the visible wall is not the generator's nominal flat plane.
		-- Sample the ground, then raycast the lamp's complete height into Terrain and mount just in front
		-- of the closest real surface. Fallback inset is only used if Terrain produces no valid hit.
		installationMinimumFloorStuds = 4,
		installationGroundClearanceStuds = 0.75,
		installationApproachSampleStuds = 4,
		installationFallbackInsetStuds = 9,
		installationSurfaceOutsetStuds = 0.2,
		mainMountHeight = 0.55,
		lampMountHeight = 0.85,
		postHeight = 1.7,
		-- A small point glow makes the lamp itself readable. The wide, lower-intensity forward beam does
		-- the room lighting without enlarging the flame or throwing full-strength light into the wall.
		lightRange = 9,
		lightBrightness = 0.32,
		roomLightRange = 68,
		roomLightBrightness = 1.45,
		roomLightAngle = 150,
		-- `stepSeconds` is a maximum. BrazierService compresses it when a larger floor needs every lamp
		-- to catch inside the same five-second free-look window.
		leadSeconds = 0.55,
		stepSeconds = 0.72,
		settleSeconds = 1.1,
		freeLookSeconds = 5,
	},
	igniteCue = "LanternIgnite",
	restBrightnessAttribute = "WickLampRestBrightness",
}

return Lantern
