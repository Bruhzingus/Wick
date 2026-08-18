--!strict
-- THE WORK LAMP — the enclosed glass lamp hanging off the descent headframe, and the last surviving
-- piece of the Gas Lantern.
--
-- WHAT THIS FILE USED TO BE. It owned a whole Gas Lantern: a glass-and-iron fixture on a post that
-- was the object a run ended at, plus a floor-wide network of smaller copies of itself that all
-- caught in a scripted sequence when somebody cashed out, plus the timings of the camera beat that
-- sequence played under. All of that is gone. Extraction is a Brazier again (`Config/Brazier`), and
-- lighting the cave is a player action performed on burnt-out wall candles (`Config/WallLamp`).
--
-- WHY THE WORK LAMP SURVIVED AND THE REST DID NOT. It is not a fixture anybody interacts with, it has
-- no state, and nothing reads it: it is a lamp somebody hung over a machine so they could see to
-- work it, and it has been burning since before the player arrived. That made it the one piece of
-- the gas-lit language with an honest reason to exist — the headframe is machinery, and machinery
-- gets a work light. The rest of the cave is lit by candles, which is what everything else in this
-- world burns.
--
-- IT IS NOT A LIGHT SOURCE IN THE RULES SENSE. Its `PointLight` is invisible to `server/LightSources`
-- — the perception field is assembled from server-owned flames, flares, decoys, remains and lit wall
-- lamps, never by scanning the world for lights — so it cannot change what any threat sees, what any
-- threat is drawn to, or how far a player can be perceived from. It is pure visual information:
-- something in the dark that says a machine is over here.

export type LanternConfig = {
	-- The lamp head. Squat and square — four panes and a cap, not a globe.
	housingWidth: number,
	housingHeight: number,
	capOverhang: number,
	-- Dark green-grey glass, the colour cold lamp glass actually is. This one is always burning, so it
	-- is always drawn at the lit transparency; the cold value is kept because it is what defines the
	-- colour the panes tint toward.
	glassColor: Color3,
	glassLitTransparency: number,
	flameHeight: number,
	flameCoreColor: Color3,
	flameTipColor: Color3,
	lightColor: Color3,
	-- Written onto the light this file builds, carrying the brightness it is supposed to settle back
	-- to. Shared with `Config/WallLamp` and `Config/Brazier` so `client/LampPresentation` can flare any
	-- lamp in the game without knowing which kind it is.
	restBrightnessAttribute: string,
}

local Lantern: LanternConfig = {
	housingWidth = 1.15,
	housingHeight = 1.35,
	capOverhang = 0.22,
	glassColor = Color3.fromRGB(52, 62, 60),
	-- Lit glass is CLEAR, not bright: what you see through it is the flame behind it, so the glass
	-- itself never becomes the light.
	glassLitTransparency = 0.16,
	flameHeight = 0.62,
	-- The gas read: a hot pale core with warm tips. Retained for this lamp alone — it is the one
	-- fixture in the cave that is not a candle, and the difference is the point of it.
	flameCoreColor = Color3.fromRGB(196, 226, 255),
	flameTipColor = Color3.fromRGB(255, 168, 82),
	lightColor = Color3.fromRGB(255, 158, 72),
	restBrightnessAttribute = "WickLampRestBrightness",
}

return Lantern
