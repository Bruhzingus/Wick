--!strict
-- THE WORK LAMP — one enclosed glass lamp hanging off the descent headframe, family-tinted.
-- Place at: ReplicatedStorage/Shared/NewModelsAndObjects/Lantern
--
-- WHAT THIS FILE USED TO BE. It built the Gas Lantern a run ended at, the floor-wide network of
-- smaller copies that answered it, and the wall mount all of them shared. Extraction is a Brazier
-- again (`NewModelsAndObjects/Brazier`) and the cave is lit by burnt-out wall candles a player
-- lights by hand (`NewModelsAndObjects/WallLamp`), so all of that has been deleted rather than left
-- in place unused: dead geometry in a file like this is geometry somebody will eventually build.
--
-- WHY THIS ONE SURVIVED. It is not a fixture anybody interacts with and it has no state. Somebody
-- hung a lamp over the winch so they could see to work it, and it has been burning since before the
-- player arrived — which is the one honest use left for a gas lamp in a cave lit by candles.
--
-- IT IS LIT ON ARRIVAL AND NOTHING WAITS ON IT. Lighting a lamp is a moment a player earns at the
-- wall candles; a work lamp that also had to be lit would spend that moment on a machine.
--
-- WHAT ITS LIGHT MAY AND MAY NOT DO. It is a decorative `PointLight`, invisible to
-- `server/LightSources`, so it cannot change what any threat sees, what any threat is drawn to, or
-- how far a player can be perceived from. It is pure visual information: something in the dark that
-- says a machine is over here.

local Types = require(script.Parent.Parent.Types)
local LanternConfig = require(script.Parent.Parent.Config.Lantern)

local Lantern = {}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): BasePart
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.CFrame = at
	created.Color = color
	created.Material = material
	created.Shape = shape or Enum.PartType.Block
	created.Anchored = true
	created.CanCollide = false
	-- Nothing here answers an AI obstacle probe or a tool cast: it is a lamp hanging in the air over
	-- a machine, and it must not be something a player, a threat or a raycast can find.
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = true
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- THE CARRY HOOP, described in three bars: two uprights and a spanner across their tops. A real arc
-- would need a dozen segments to stop reading as a polygon, and at this scale the silhouette a
-- candle actually catches is the gap under the hoop rather than its curvature.
local function buildBail(model: Model, style: Types.FixtureStyle, top: Vector3, width: number)
	local rise = width * 0.62
	for _, side in { 1, -1 } do
		part(
			model,
			"WorkLampBail",
			Vector3.new(0.06, rise, 0.06),
			CFrame.new(top + Vector3.new(side * width / 2, rise / 2, 0)) * CFrame.Angles(0, 0, side * math.rad(-9)),
			style.lineColor,
			style.lineMaterial
		)
	end
	part(
		model,
		"WorkLampBail",
		Vector3.new(width * 0.92, 0.06, 0.06),
		CFrame.new(top + Vector3.new(0, rise, 0)),
		style.lineColor,
		style.lineMaterial
	)
end

-- ONE WORK LAMP, hung by its bail from `hangFrom`.
function Lantern.buildWorkLamp(
	style: Types.FixtureStyle,
	hangFrom: Vector3,
	scale: number,
	range: number,
	brightness: number
): Model
	local config = LanternConfig
	local model = Instance.new("Model")
	model.Name = "WorkLamp"

	local width = config.housingWidth * scale
	local height = config.housingHeight * scale
	local halfW = width / 2
	-- The lamp hangs BELOW its hook by the length of its own bail, so the hook, the loop and the lamp
	-- read as three connected things rather than a box floating under a bracket.
	local bailRise = width * 0.62 * 0.62
	local centre = hangFrom - Vector3.new(0, bailRise + height / 2 + 0.08, 0)

	part(
		model,
		"WorkLampFloor",
		Vector3.new(width, 0.08 * scale, width),
		CFrame.new(centre - Vector3.new(0, height / 2, 0)),
		style.frameColor,
		style.frameMaterial
	)
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) } do
		part(
			model,
			"WorkLampFrame",
			Vector3.new(0.08 * scale, height, 0.08 * scale),
			CFrame.new(centre + Vector3.new(corner.X * halfW, 0, corner.Z * halfW)),
			style.frameColor,
			style.frameMaterial
		)
	end
	local cap = part(
		model,
		"WorkLampCap",
		Vector3.new(width + config.capOverhang * scale * 2, 0.12 * scale, width + config.capOverhang * scale * 2),
		CFrame.new(centre + Vector3.new(0, height / 2 + 0.06, 0)),
		style.frameColor,
		style.frameMaterial
	)
	model.PrimaryPart = cap

	-- Panes, already clear because this one is already burning.
	for _, face in
		{
			{ offset = Vector3.new(0, 0, halfW), size = Vector3.new(width - 0.06, height - 0.14, 0.05) },
			{ offset = Vector3.new(0, 0, -halfW), size = Vector3.new(width - 0.06, height - 0.14, 0.05) },
			{ offset = Vector3.new(halfW, 0, 0), size = Vector3.new(0.05, height - 0.14, width - 0.06) },
			{ offset = Vector3.new(-halfW, 0, 0), size = Vector3.new(0.05, height - 0.14, width - 0.06) },
		}
	do
		local pane = part(
			model,
			"WorkLampGlass",
			face.size,
			CFrame.new(centre + face.offset),
			config.glassColor,
			Enum.Material.Glass
		)
		pane.Transparency = config.glassLitTransparency
		pane.CastShadow = false
	end

	buildBail(model, style, centre + Vector3.new(0, height / 2 + 0.12, 0), width * 0.62)
	-- The hook it hangs from, back up to whatever is carrying it.
	part(
		model,
		"WorkLampHook",
		Vector3.new(0.07, bailRise + 0.1, 0.07),
		CFrame.new(hangFrom - Vector3.new(0, bailRise / 2, 0)),
		style.lineColor,
		style.lineMaterial
	)

	-- The flame, one piece rather than two: at this size a separate tip would be a single pixel doing
	-- nothing but muddying the core's colour.
	local flame = part(
		model,
		"WorkLampFlame",
		Vector3.new(0.2 * scale, config.flameHeight * scale, 0.2 * scale),
		CFrame.new(centre - Vector3.new(0, height * 0.18, 0)),
		config.flameCoreColor:Lerp(config.flameTipColor, 0.45),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	flame.CastShadow = false

	-- The one lamp in the game that is born burning, so it is the one that has to turn its own light
	-- on. Stamped with its resting brightness like every other lamp light, so a stray flare event
	-- could never leave it settled at the wrong output.
	local light = Instance.new("PointLight")
	light.Name = "WorkLampLight"
	light.Color = config.lightColor
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Enabled = true
	light:SetAttribute(config.restBrightnessAttribute, brightness)
	light.Parent = flame

	return model
end

return Lantern
