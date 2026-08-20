--!strict
-- THE EIGHT SHRINE CANDLES that ring Unlittius' dais (Config/Unlittius, DESIGN §9b).
-- Place at: ReplicatedStorage/Shared/NewModelsAndObjects/UnlittiusCandle
--
-- THIS IS THE OBJECTIVE, SO IT HAS TO READ AS ONE FROM ACROSS A DARK ROOM. Everything about the shape
-- is in service of that: a waist-high carved plinth so the silhouette breaks the floor line, a fat
-- spent pillar with old wax run down it, and a violet-limned rune band on the plinth that is the only
-- thing on an unlit candle a player can see before their own flame reaches it. Lighting one turns the
-- rune band warm and the pillar amber, so an eight-candle chamber tells you its own score.
--
-- IT IS THE SAME OBJECT LANGUAGE AS THE CAVE'S WALL LAMPS (NewModelsAndObjects/WallLamp) and is built
-- to the same laws (ART-BIBLE §2): flat plates, square stock, simple cylinders, no bevels, no surface
-- noise. Detail is spent on silhouette because at the edge of candle range an outline is all a player
-- gets. What is deliberately NOT shared is the fixture itself — a wall lamp is bolted to rock and
-- these stand free on a shrine floor, and forcing one model to be both would have meant a bracket
-- hanging off nothing.
--
-- COLD UNTIL LIT, AND BUILT THAT WAY RATHER THAN DRESSED THAT WAY. The flame, the light and the warm
-- colours all exist from the first frame and are simply off. Creating them at ignition would put an
-- `Instance.new` on a frame the player is watching, and a fixture whose geometry changes shape as it
-- catches reads as a swap rather than as an ignition — the wall lamp learned this first.
--
-- THE LIGHT HERE IS VISUAL ONLY. What a lit candle is worth to a threat is decided by
-- `server/UnlittiusEncounterService` from `Config/Unlittius` and assembled into the perception field
-- by `server/LightSources`; nothing in the game builds that field by scanning the world for
-- PointLights.

local CollectionService = game:GetService("CollectionService")

local UnlittiusConfig = require(script.Parent.Parent.Config.Unlittius)
local UnlittiusVisualProtocol = require(script.Parent.Parent.UnlittiusVisualProtocol)

local UnlittiusCandle = {}

export type BuiltCandle = {
	model: Model,
	index: number,
	-- The flame's world position: what the prompt hangs off and what the light field is emitted from.
	flamePosition: Vector3,
	-- The invisible part carrying the tag, the attributes and the ProximityPrompt. Deliberately not
	-- the pillar or the flame, both of which change colour and transparency when the candle catches.
	anchor: BasePart,
	plinth: BasePart,
	pillar: BasePart,
	wick: BasePart,
	flameCore: BasePart,
	flameTip: BasePart,
	runeBand: BasePart,
	light: PointLight,
	lit: boolean,
}

-- Part cylinders run along local X. Everything below is authored upright.
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local PLINTH_HEIGHT = 2.6
local PLINTH_WIDTH = 2.2
local PILLAR_HEIGHT = 2.0
local PILLAR_RADIUS = 0.62
local DEAD_WAX = Color3.fromRGB(178, 170, 154)
local LIT_WAX = Color3.fromRGB(228, 206, 158)
local DEAD_WICK = Color3.fromRGB(26, 22, 20)
local LIT_WICK = Color3.fromRGB(64, 48, 38)
local STONE = Color3.fromRGB(78, 72, 66)
local STONE_DARK = Color3.fromRGB(52, 48, 44)

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): BasePart
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.CFrame = cframe
	created.Color = color
	created.Material = material
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- Build one candle standing on the floor at `base`, facing the dais at `lookAt`.
function UnlittiusCandle.build(index: number, base: Vector3, lookAt: Vector3, depth: number): BuiltCandle
	local model = Instance.new("Model")
	model.Name = string.format("UnlittiusCandle%02d", index)

	local facing = Vector3.new(lookAt.X - base.X, 0, lookAt.Z - base.Z)
	local frame = if facing.Magnitude > 0.01 then CFrame.lookAt(base, base + facing.Unit) else CFrame.new(base)

	-- THE PLINTH. Two courses of squared stone, the upper one turned a few degrees off the lower so
	-- the object reads as carved and set rather than extruded — the same trick the hood layers use on
	-- the boss himself.
	local plinth = part(
		model,
		"Plinth",
		Vector3.new(PLINTH_WIDTH, PLINTH_HEIGHT * 0.62, PLINTH_WIDTH),
		frame * CFrame.new(0, PLINTH_HEIGHT * 0.31, 0),
		STONE,
		Enum.Material.Slate
	)
	plinth.CanCollide = true
	part(
		model,
		"PlinthCap",
		Vector3.new(PLINTH_WIDTH * 0.86, PLINTH_HEIGHT * 0.38, PLINTH_WIDTH * 0.86),
		frame * CFrame.new(0, PLINTH_HEIGHT * 0.81, 0) * CFrame.Angles(0, math.rad(11), 0),
		STONE_DARK,
		Enum.Material.Slate
	)
	-- A shallow bowl the pillar sits in, so the wax has somewhere to have run to.
	part(
		model,
		"Bowl",
		Vector3.new(PILLAR_RADIUS * 3.4, 0.24, PILLAR_RADIUS * 3.4),
		frame * CFrame.new(0, PLINTH_HEIGHT + 0.08, 0),
		STONE_DARK,
		Enum.Material.Slate
	)

	-- THE RUNE BAND. The only part of a dead candle that emits anything, and the reason all eight are
	-- findable in the dark. It is violet while the candle is cold — his mark on the shrine — and turns
	-- amber the moment it catches, which is the chamber's own scoreboard.
	local runeBand = part(
		model,
		"RuneBand",
		Vector3.new(PLINTH_WIDTH * 0.9, 0.22, PLINTH_WIDTH * 0.9),
		frame * CFrame.new(0, PLINTH_HEIGHT * 0.52, 0),
		UnlittiusConfig.body.runeColor,
		Enum.Material.Neon
	)
	runeBand.Transparency = 0.35

	-- THE PILLAR. Spent, guttered, and visibly older than the party.
	local pillar = part(
		model,
		"Pillar",
		Vector3.new(PILLAR_HEIGHT, PILLAR_RADIUS * 2, PILLAR_RADIUS * 2),
		frame * CFrame.new(0, PLINTH_HEIGHT + 0.2 + PILLAR_HEIGHT * 0.5, 0) * UPRIGHT,
		DEAD_WAX,
		Enum.Material.Sandstone
	)
	pillar.Shape = Enum.PartType.Cylinder
	for drip = 1, 4 do
		local angle = drip / 4 * math.pi * 2 + index * 0.7
		local length = 0.5 + (drip % 3) * 0.28
		part(
			model,
			"WaxDrip",
			Vector3.new(0.18, length, 0.18),
			frame
				* CFrame.new(
					math.cos(angle) * PILLAR_RADIUS * 0.92,
					PLINTH_HEIGHT + 0.2 + PILLAR_HEIGHT - length * 0.5 - 0.2,
					math.sin(angle) * PILLAR_RADIUS * 0.92
				),
			DEAD_WAX,
			Enum.Material.Sandstone
		)
	end

	local wickBase = PLINTH_HEIGHT + 0.2 + PILLAR_HEIGHT
	local wick = part(
		model,
		"Wick",
		Vector3.new(0.1, 0.42, 0.1),
		frame * CFrame.new(0, wickBase + 0.21, 0),
		DEAD_WICK,
		Enum.Material.Slate
	)

	-- The flame: two nested pieces so it has an inner core and a softer tip, exactly as the player's
	-- own candle and the cave's wall lamps are built.
	local flamePosition = (frame * CFrame.new(0, wickBase + 0.6, 0)).Position
	local flameCore = part(
		model,
		"FlameCore",
		Vector3.new(0.34, 0.52, 0.34),
		CFrame.new(flamePosition),
		Color3.fromRGB(255, 214, 150),
		Enum.Material.Neon
	)
	flameCore.Shape = Enum.PartType.Ball
	flameCore.Transparency = 1
	flameCore.CastShadow = false
	local flameTip = part(
		model,
		"FlameTip",
		Vector3.new(0.2, 0.72, 0.2),
		CFrame.new(flamePosition + Vector3.new(0, 0.22, 0)),
		Color3.fromRGB(255, 168, 82),
		Enum.Material.Neon
	)
	flameTip.Shape = Enum.PartType.Ball
	flameTip.Transparency = 1
	flameTip.CastShadow = false

	local light = Instance.new("PointLight")
	light.Name = "CandleLight"
	light.Color = Color3.fromRGB(255, 186, 118)
	light.Range = UnlittiusConfig.encounter.candleLightRange
	light.Brightness = UnlittiusConfig.encounter.candleLightIntensity
	light.Shadows = true
	light.Enabled = false
	light.Parent = flameCore

	-- THE ANCHOR. Invisible, query-able, and the only thing the prompt and the tag ever hang off, so
	-- that turning the pillar amber or the flame on cannot take the interaction with it.
	local anchor = part(
		model,
		"Anchor",
		Vector3.new(PLINTH_WIDTH, PLINTH_HEIGHT + PILLAR_HEIGHT, PLINTH_WIDTH),
		frame * CFrame.new(0, (PLINTH_HEIGHT + PILLAR_HEIGHT) * 0.5, 0),
		STONE,
		Enum.Material.Slate
	)
	anchor.Transparency = 1
	anchor.CanQuery = true
	anchor.CastShadow = false
	anchor:SetAttribute(UnlittiusVisualProtocol.candle.attributes.index, index)
	anchor:SetAttribute(UnlittiusVisualProtocol.candle.attributes.lit, false)
	anchor:SetAttribute(UnlittiusVisualProtocol.candle.attributes.depth, depth)
	CollectionService:AddTag(anchor, UnlittiusVisualProtocol.candle.tag)

	model.PrimaryPart = anchor

	return {
		model = model,
		index = index,
		flamePosition = flamePosition,
		anchor = anchor,
		plinth = plinth,
		pillar = pillar,
		wick = wick,
		flameCore = flameCore,
		flameTip = flameTip,
		runeBand = runeBand,
		light = light,
		lit = false,
	}
end

-- EVERYTHING THAT IS TRUE OF A LIT CANDLE BECOMES TRUE HERE AND NOWHERE ELSE. The server calls this;
-- the change replicates; a player who arrives later sees the same eight-candle score as everyone who
-- was here for it.
function UnlittiusCandle.setLit(built: BuiltCandle, lit: boolean, litAt: number?)
	built.lit = lit
	built.flameCore.Transparency = if lit then 0 else 1
	built.flameTip.Transparency = if lit then 0.12 else 1
	built.wick.Color = if lit then LIT_WICK else DEAD_WICK
	built.pillar.Color = if lit then LIT_WAX else DEAD_WAX
	built.light.Enabled = lit
	-- HIS MARK TURNS INTO THEIRS. The band is violet while he holds the shrine and warm once the
	-- candle is burning, which makes the progress readable from anywhere in the chamber without a
	-- single pixel of UI.
	built.runeBand.Color = if lit then Color3.fromRGB(255, 178, 96) else UnlittiusConfig.body.runeColor
	built.runeBand.Transparency = if lit then 0.18 else 0.35
	for _, descendant in built.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "WaxDrip" then
			descendant.Color = if lit then LIT_WAX else DEAD_WAX
		end
	end
	built.anchor:SetAttribute(UnlittiusVisualProtocol.candle.attributes.lit, lit)
	if lit and litAt ~= nil then
		built.anchor:SetAttribute(UnlittiusVisualProtocol.candle.attributes.litAt, litAt)
	end
end

-- How tall the fixture stands, so a caller can seat it and reserve room for it without measuring the
-- model it has not built yet.
function UnlittiusCandle.height(): number
	return PLINTH_HEIGHT + PILLAR_HEIGHT + 0.6
end

return UnlittiusCandle
