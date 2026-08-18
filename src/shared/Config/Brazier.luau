--!strict
-- Brazier / reward tuning (DESIGN §12).
-- Reward = waxDelivered * depthMultipliers[depth] * (1 + groupBonusPerPlayer * additionalPlayers)
--          * caveTierMultiplier * rewardPerWaxUnit. The tier multiplier comes from the selected
--          Config/CaveTiers row, not from this file. Expose the numbers: legible tension beats
--          mysterious tension. The preview shows this arithmetic live.
--
-- THE FIXTURE IS A BRAZIER AGAIN. It was briefly a Gas Lantern whose ignition also lit the whole
-- floor in a scripted sequence; that coupling is gone. Lighting the cave is now its own player verb
-- with its own fixtures (Config/WallLamp), and this object went back to being the one simple thing
-- it should always have been: a bowl of dead coals you set fire to when you are done. Every number
-- above this line is untouched by that change — the payout, the hold, the range and the tolerance are
-- what they have been since the fixture was one grey box.

-- What the object looks like. Sits in this file rather than in a fourth Config because the Brazier
-- has exactly one job and splitting its bowl from its payout would mean two files nobody can change
-- independently. `Config/Cauldron` and `Config/WallLamp` own the room's other two fixtures.
--
-- COLD UNTIL LIT, like every other lightable thing in this game: dead grey coals, no glow, no heat
-- shimmer. The bowl has been sitting here since whoever worked this cave last walked out of it.
export type BrazierFixtureConfig = {
	cairnRadius: number,
	cairnHeight: number,
	legCount: number,
	legHeight: number,
	legThickness: number,
	legSpread: number,
	bowlRadius: number,
	bowlDepth: number,
	bowlWallThickness: number,
	rimHeight: number,
	rimOverhang: number,
	coalCount: number,
	coalRadius: number,
	coalColor: Color3,
	coalLitColor: Color3,
	emberColor: Color3,
	flameCount: number,
	flameHeight: number,
	flameCoreColor: Color3,
	flameTipColor: Color3,
	lightColor: Color3,
	lightRange: number,
	lightBrightness: number,
	-- Studs above the bowl's rim that the commit prompt hangs at.
	promptHeight: number,
	igniteCue: string,
	restBrightnessAttribute: string,
	-- The catch: a hard spike that decays back to rest, never a fade-in.
	flareSeconds: number,
	flareBrightnessMultiplier: number,
	-- THE ANSWERING IGNITIONS, and the brazier is the only fixture that gets them. The same cue,
	-- delayed, quieter, lower and played from anchors well out in the dark, so what the ear reports is
	-- "that sound again, further away". It says the cave keeps going somewhere you cannot see and
	-- deliberately does not claim to represent any particular room.
	--
	-- THE WALL LAMPS MUST NEVER HAVE THESE. A cascade already plays one real cue per room from the
	-- room it actually happened in; giving each of those a pair of distant fakes as well would turn a
	-- legible sequence into a dozen overlapping delayed copies of itself.
	echoCount: number,
	echoDelaySeconds: number,
	echoSpacingSeconds: number,
	echoDistanceStuds: number,
	echoLevelFalloff: number,
	echoPitchFalloff: number,
}

export type BrazierConfig = {
	depthMultipliers: { number },
	groupBonusPerPlayer: number,
	rewardPerWaxUnit: number,
	promptRange: number,
	groupRadius: number,
	positionToleranceStuds: number,
	commitHoldSeconds: number,
	previewUpdateSeconds: number,
	-- Seconds after a group commit before the shared prompt is offered again. Just long enough for
	-- every member's own payout task to have finished; nothing waits on a camera beat any more.
	groupPromptResetSeconds: number,
	fixture: BrazierFixtureConfig,
}

local Brazier: BrazierConfig = {
	-- Depth multiplier by floor (index = floor number). DESIGN §12 examples: floor2 ~1.5, floor4 ~3, floor6 ~5.
	-- Steeper curve = stronger pull to push deeper = higher risk/reward.
	depthMultipliers = { 1.0, 1.5, 2.2, 3.0, 4.0, 5.0, 6.5, 8.0, 10.0, 12.5 },
	-- Bonus per ADDITIONAL player at the same brazier (DESIGN §12: 0.25). A multiplier, not a split pot —
	-- nobody's share shrinks when someone else arrives. Higher = more reason to wait for the party.
	groupBonusPerPlayer = 0.25,
	-- Scalar from delivered wax units to payout currency. Higher = more generous economy.
	rewardPerWaxUnit = 1000,
	-- Studs at which the commit prompt and live preview appear.
	promptRange = 10,
	-- Slack added to promptRange when re-validating a player is still close enough server-side
	-- (matches the trust-boundary margins Config/Security owns).
	positionToleranceStuds = 2,
	-- Studs within which another alive, unfinished player counts toward the group bonus at commit.
	groupRadius = 12,
	-- Seconds the commit prompt must be held. Guards against accidentally ending your run.
	commitHoldSeconds = 1,
	-- Seconds between preview refreshes for players standing at the brazier.
	previewUpdateSeconds = 0.25,
	groupPromptResetSeconds = 2,

	fixture = {
		-- A low cairn of stacked rock under it, the same move the Cauldron makes: the fixture was
		-- INSTALLED by somebody, and a bowl standing on bare cave floor reads as spawned.
		cairnRadius = 1.5,
		cairnHeight = 0.42,
		-- Three legs, not four. Three cannot rock on uneven rock and it is why real tripods have three.
		legCount = 3,
		legHeight = 1.5,
		legThickness = 0.19,
		-- Degrees the legs splay from vertical.
		legSpread = 13,
		bowlRadius = 1.16,
		bowlDepth = 0.58,
		bowlWallThickness = 0.14,
		rimHeight = 0.17,
		rimOverhang = 0.1,
		-- Loose fuel heaped in the bowl. Enough pieces to read as a heap from above and few enough that
		-- the silhouette stays a bowl.
		coalCount = 7,
		coalRadius = 0.29,
		coalColor = Color3.fromRGB(44, 41, 39),
		coalLitColor = Color3.fromRGB(96, 44, 22),
		-- Only the embers are Neon, and only once lit: what glows is the fuel, never the iron.
		emberColor = Color3.fromRGB(255, 122, 44),
		-- Three tongues rather than the candle's two-piece flame. A bowl fire is wider than it is tall
		-- and one ball on top of a heap of coals reads as a lightbulb.
		flameCount = 3,
		flameHeight = 0.92,
		flameCoreColor = Color3.fromRGB(255, 218, 148),
		flameTipColor = Color3.fromRGB(255, 138, 48),
		lightColor = Color3.fromRGB(255, 148, 66),
		-- THE BRIGHTEST FIXTURE IN THE GAME, and allowed to be: it only ever burns after somebody's run
		-- has already ended at it. It is not light the player gets to use.
		lightRange = 34,
		lightBrightness = 1.5,
		promptHeight = 1.15,
		igniteCue = "LanternIgnite",
		restBrightnessAttribute = "WickLampRestBrightness",
		flareSeconds = 0.55,
		-- Enough to read as a catch without throwing the amber back toward white on pale rock.
		flareBrightnessMultiplier = 1.75,
		echoCount = 2,
		echoDelaySeconds = 0.42,
		echoSpacingSeconds = 0.5,
		echoDistanceStuds = 46,
		echoLevelFalloff = 0.45,
		echoPitchFalloff = 0.88,
	},
}

return Brazier
