--!strict
-- THE GAS LANTERN — the fixture a run ends at (DESIGN §12), family-tinted.
-- Place at: ReplicatedStorage/Shared/NewModelsAndObjects/Lantern
--
-- WHAT IT REPLACED: `newPart(Vector3.new(2, 3, 2), ...)`. One dark grey box, no glow, no fixture, no
-- presentation at all — the least developed object in the game despite owning its most loaded
-- moment. Everything the Brazier DOES is unchanged: `server/BrazierService` still previews the same
-- arithmetic, commits on the same held prompt and pays through the same transactional boundary.
--
-- THE ENCLOSED GLASS IS THE POINT. Every other flame in this game is carried in the open, in your
-- own hands, shrinking. This one is behind panes on a post and it stays lit after you walk away — it
-- is the only safe flame in the world, and the reward for finishing a floor is being allowed to make
-- one. `Enum.Material.Glass` is already in this game's material language (BrightWax's faceted loot
-- silhouette), so nothing new is being introduced to say it.
--
-- COLD UNTIL LIT, AND BUILT THAT WAY RATHER THAN DRESSED THAT WAY. The flame parts and the light
-- exist from the first frame and are simply off (`setLit`). Creating them at ignition would put an
-- Instance.new on the single most timing-sensitive frame in the game, and a fixture whose geometry
-- changes shape as it catches reads as a swap rather than as an ignition.
--
-- THE FLAME IS NOT CANDLE-ORANGE. See `Config/Lantern`: a pale blue-white core with warm tips, which
-- is what burning gas looks like and is claimed by nothing else in the palette.

local Types = require(script.Parent.Parent.Types)
local LanternConfig = require(script.Parent.Parent.Config.Lantern)

local Lantern = {}

export type BuiltLantern = {
	model: Model,
	-- The lamp head's world position: what the ignition VFX is thrown from and where the prompt hangs.
	headPosition: Vector3,
	flameCore: BasePart,
	flameTip: BasePart,
	glass: { BasePart },
	light: PointLight,
	roomLight: SpotLight?,
	wick: BasePart,
}

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

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
	-- Same reasoning as the Cauldron's: the post carries collision so the fixture is solid, and
	-- nothing here answers an AI obstacle probe or a tool cast.
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = true
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- EVERY LAMP LIGHT IN THIS FILE, built the same way and stamped with what it is supposed to settle
-- back to. `client/LanternPresentation` spikes these on ignition and decays them home; without the
-- attribute it would have to assume the Gas Lantern's own brightness, and a network lamp flared that
-- way would be left permanently burning at four times its authored output.
--
-- Created disabled by default: an unlit lamp must be as dark as the rock it stands on, or a room
-- gives away its own ending before anybody has earned it.
local function newLampLight(parent: BasePart, name: string, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Name = name
	light.Color = LanternConfig.lightColor
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Enabled = false
	light:SetAttribute(LanternConfig.restBrightnessAttribute, brightness)
	light.Parent = parent
	return light
end

-- THE CARRY HOOP, described in three bars: two uprights and a spanner across their tops. A real arc
-- would need a dozen segments to stop reading as a polygon, and at this scale the silhouette a candle
-- actually catches is the gap under the hoop rather than its curvature. Shared by both lamps so the
-- big one and the little one are visibly the same manufacturer.
local function buildBail(model: Model, style: Types.FixtureStyle, top: Vector3, width: number)
	local rise = width * 0.62
	for _, side in { 1, -1 } do
		part(
			model,
			"LanternBail",
			Vector3.new(0.06, rise, 0.06),
			CFrame.new(top + Vector3.new(side * width / 2, rise / 2, 0)) * CFrame.Angles(0, 0, side * math.rad(-9)),
			style.lineColor,
			style.lineMaterial
		)
	end
	part(
		model,
		"LanternBail",
		Vector3.new(width * 0.92, 0.06, 0.06),
		CFrame.new(top + Vector3.new(0, rise, 0)),
		style.lineColor,
		style.lineMaterial
	)
end

-- HOW DEEP THIS RUN HAS ALREADY REACHED, hung off the post as real links.
--
-- Computed from the floor's own global depth at BUILD time, which is the whole reason it is safe:
-- floors are destroyed two deep behind the party (`Config/Run.floorRetentionBehind`), so anything
-- accumulated from geometry the player actually walked would be counting objects that no longer
-- exist. A number the server already tracks cannot rot.
local function buildDepthChain(model: Model, style: Types.FixtureStyle, origin: Vector3, globalDepth: number)
	local chain = LanternConfig.depthChain
	if not chain.enabled then
		return
	end
	local links = math.clamp(math.floor(globalDepth / math.max(chain.floorsPerLink, 1)), 1, math.floor(chain.maxLinks))
	local bracketY = LanternConfig.postHeight * 0.66
	local bracketX = LanternConfig.postThickness / 2 + 0.28

	part(
		model,
		"LanternChainBracket",
		Vector3.new(bracketX * 2, 0.12, 0.12),
		CFrame.new(origin + Vector3.new(bracketX / 2, bracketY, 0)),
		style.frameColor,
		style.frameMaterial
	)

	-- Links alternate their axis, which is what makes a stack of small boxes read as chain rather
	-- than as a dotted line.
	for index = 1, links do
		local y = bracketY - index * chain.linkHeight * 0.82
		if y <= 0.2 then
			break
		end
		local flat = index % 2 == 0
		part(
			model,
			"LanternDepthLink",
			if flat
				then Vector3.new(chain.linkThickness, chain.linkHeight, chain.linkThickness * 1.9)
				else Vector3.new(chain.linkThickness * 1.9, chain.linkHeight, chain.linkThickness),
			CFrame.new(origin + Vector3.new(bracketX, y, 0)),
			style.lineColor,
			style.lineMaterial
		)
	end
end

-- ONE LANTERN, standing on `origin` (the floor point the Brazier is registered at).
function Lantern.build(style: Types.FixtureStyle, origin: Vector3, globalDepth: number): BuiltLantern
	local config = LanternConfig
	local model = Instance.new("Model")
	model.Name = "GasLantern"

	-- THE STAND. A flat iron pad and a post: this was bolted down by somebody, which is the difference
	-- between a fixture and a rock that happens to glow.
	part(
		model,
		"LanternBase",
		Vector3.new(config.baseHeight, config.baseRadius * 2, config.baseRadius * 2),
		CFrame.new(origin + Vector3.new(0, config.baseHeight / 2, 0)) * UPRIGHT,
		style.frameColor,
		style.frameMaterial,
		Enum.PartType.Cylinder
	)

	local post = part(
		model,
		"LanternPost",
		Vector3.new(config.postThickness, config.postHeight, config.postThickness),
		CFrame.new(origin + Vector3.new(0, config.postHeight / 2, 0)),
		style.deckColor,
		style.deckMaterial
	)
	post.CanCollide = true
	model.PrimaryPart = post

	local headY = config.postHeight + config.housingHeight / 2
	local headCentre = origin + Vector3.new(0, headY, 0)
	local halfW = config.housingWidth / 2

	-- The floor of the lamp, where the burner sits.
	part(
		model,
		"LanternFloor",
		Vector3.new(config.housingWidth, 0.12, config.housingWidth),
		CFrame.new(headCentre - Vector3.new(0, config.housingHeight / 2, 0)),
		style.frameColor,
		style.frameMaterial
	)

	-- FOUR CORNER POSTS AND A CAP. The frame is what makes this a lantern and not a lit cube: the
	-- panes between the uprights are the read, and they only exist because something is holding them.
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) } do
		part(
			model,
			"LanternFrame",
			Vector3.new(0.11, config.housingHeight, 0.11),
			CFrame.new(headCentre + Vector3.new(corner.X * halfW, 0, corner.Z * halfW)),
			style.frameColor,
			style.frameMaterial
		)
	end

	part(
		model,
		"LanternCap",
		Vector3.new(config.housingWidth + config.capOverhang * 2, 0.16, config.housingWidth + config.capOverhang * 2),
		CFrame.new(headCentre + Vector3.new(0, config.housingHeight / 2 + 0.08, 0)),
		style.frameColor,
		style.frameMaterial
	)
	-- A short vent stack on the cap: hot gas has to go somewhere, and the shape says so.
	part(
		model,
		"LanternVent",
		Vector3.new(0.34, 0.26, 0.34),
		CFrame.new(headCentre + Vector3.new(0, config.housingHeight / 2 + 0.29, 0)),
		style.frameColor,
		style.frameMaterial
	)
	-- THE BAIL. The single most recognisable thing about a lantern is the loop you carry it by, and
	-- this one is the only lamp in the game nobody has to — it is bolted to a post. Building it anyway
	-- is what makes the object read as "a lantern that was set down here for good" rather than as a
	-- box with panes; three bars are enough to describe the hoop at this scale.
	buildBail(model, style, headCentre + Vector3.new(0, config.housingHeight / 2 + 0.16, 0), config.housingWidth * 0.62)

	-- THE PANES. Dark and translucent while cold; `setLit` clears them rather than brightening them,
	-- so what a player sees through the glass is the flame behind it and never the glass itself.
	local glass: { BasePart } = {}
	for _, face in
		{
			{
				offset = Vector3.new(0, 0, halfW),
				size = Vector3.new(config.housingWidth - config.glassInset, config.housingHeight - 0.18, 0.06),
			},
			{
				offset = Vector3.new(0, 0, -halfW),
				size = Vector3.new(config.housingWidth - config.glassInset, config.housingHeight - 0.18, 0.06),
			},
			{
				offset = Vector3.new(halfW, 0, 0),
				size = Vector3.new(0.06, config.housingHeight - 0.18, config.housingWidth - config.glassInset),
			},
			{
				offset = Vector3.new(-halfW, 0, 0),
				size = Vector3.new(0.06, config.housingHeight - 0.18, config.housingWidth - config.glassInset),
			},
		}
	do
		local pane = part(
			model,
			"LanternGlass",
			face.size,
			CFrame.new(headCentre + face.offset),
			config.glassColor,
			Enum.Material.Glass
		)
		pane.Transparency = config.glassTransparency
		pane.CastShadow = false
		table.insert(glass, pane)
	end

	-- The gas fittings: a valve wheel on the outside of the frame and the burner it feeds. Small, and
	-- the only thing on the object that explains why this flame does not need wax.
	part(
		model,
		"LanternValve",
		Vector3.new(0.12, 0.12, config.valveLength),
		CFrame.new(headCentre + Vector3.new(halfW + 0.06, -config.housingHeight * 0.3, config.valveLength / 2)),
		style.frameColor,
		style.frameMaterial
	)
	part(
		model,
		"LanternValveWheel",
		Vector3.new(0.08, 0.3, 0.3),
		CFrame.new(headCentre + Vector3.new(halfW + 0.06, -config.housingHeight * 0.3, config.valveLength))
			* CFrame.Angles(0, math.pi / 2, 0)
			* UPRIGHT,
		style.lineColor,
		style.lineMaterial,
		Enum.PartType.Cylinder
	)

	local wick = part(
		model,
		"LanternBurner",
		Vector3.new(0.16, 0.22, 0.16),
		CFrame.new(headCentre - Vector3.new(0, config.housingHeight / 2 - 0.15, 0)),
		config.deadWickColor,
		Enum.Material.Metal
	)

	-- THE FLAME, built cold. Two hard pieces — pale core, warm tip — because that is how every other
	-- flame in this game is drawn, and a soft gradient here would be the one that was not.
	local flameCore = part(
		model,
		"LanternFlameCore",
		Vector3.new(0.26, config.flameHeight, 0.26),
		CFrame.new(headCentre - Vector3.new(0, config.housingHeight / 2 - 0.26 - config.flameHeight / 2, 0)),
		config.flameCoreColor,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	flameCore.CastShadow = false
	flameCore.Transparency = 1

	local flameTip = part(
		model,
		"LanternFlameTip",
		Vector3.new(0.19, config.flameHeight * 0.62, 0.19),
		CFrame.new(headCentre - Vector3.new(0, config.housingHeight / 2 - 0.26 - config.flameHeight, 0)),
		config.flameTipColor,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	flameTip.CastShadow = false
	flameTip.Transparency = 1

	-- The one light this fixture is allowed. Created disabled: an unlit lantern must be as dark as the
	-- rock it stands on, or the room gives away its own ending.
	local light = newLampLight(flameCore, "LanternLight", config.lightRange, config.lightBrightness)

	buildDepthChain(model, style, origin, globalDepth)

	return {
		model = model,
		headPosition = headCentre,
		flameCore = flameCore,
		flameTip = flameTip,
		glass = glass,
		light = light,
		roomLight = nil,
		wick = wick,
	}
end

-- CAUGHT, OR NOT. Called once by `server/BrazierService` the first time any player commits at this
-- fixture, and never called back to false: a lantern that went out again would undo the one promise
-- the object makes.
--
-- The lit prop is SHARED — every player on the floor sees the same lit lamp — while each player's own
-- reward, results card and extraction remain entirely independent, exactly as they already were.
function Lantern.setLit(built: BuiltLantern, lit: boolean)
	local config = LanternConfig
	built.flameCore.Transparency = if lit then 0 else 1
	built.flameTip.Transparency = if lit then 0.12 else 1
	built.wick.Color = if lit then config.flameTipColor else config.deadWickColor
	built.wick.Material = if lit then Enum.Material.Neon else Enum.Material.Metal
	for _, pane in built.glass do
		pane.Transparency = if lit then config.glassLitTransparency else config.glassTransparency
	end
	built.light.Enabled = lit
	if built.roomLight ~= nil then
		built.roomLight.Enabled = lit
	end
end

-- BOLT AN EXISTING LANTERN TO CAVE ROCK. The Gas Lantern and its smaller answering lamps still use
-- the same glass/frame/flame construction; only their support changes. Keeping the mount separate
-- means `setLit` and the client-side ignition flare remain one path for every lamp in the sequence.
--
-- `wallSurface` lies on the inside face of the selected clear wall and `inward` points into the room.
-- The base is intentionally a little way out from that face, joined by a plate and a short iron arm:
-- a wall-mounted fixture reads as installed equipment, not as a floor post that happened to be moved
-- upward into the air.
function Lantern.mountToWall(
	built: BuiltLantern,
	style: Types.FixtureStyle,
	wallSurface: Vector3,
	origin: Vector3,
	inward: Vector3,
	width: number,
	roomLightRange: number,
	roomLightBrightness: number,
	roomLightAngle: number
)
	if inward.Magnitude <= 0 then
		return
	end
	local config = LanternConfig
	local normal = inward.Unit
	local horizontalOffset = Vector3.new(origin.X - wallSurface.X, 0, origin.Z - wallSurface.Z):Dot(normal)
	local armLength = math.max(horizontalOffset, config.baseHeight)
	local plateHeight = math.max(built.headPosition.Y - origin.Y + width / 2, config.baseHeight)
	local plateCenter = Vector3.new(wallSurface.X, origin.Y + plateHeight / 2, wallSurface.Z)
		+ normal * (config.baseHeight / 2)
	part(
		built.model,
		"LanternWallPlate",
		Vector3.new(width, plateHeight, config.baseHeight),
		CFrame.lookAt(plateCenter, plateCenter + normal),
		style.frameColor,
		style.frameMaterial
	)

	local armCenter = Vector3.new(wallSurface.X, origin.Y + config.baseHeight / 2, wallSurface.Z)
		+ normal * (armLength / 2)
	part(
		built.model,
		"LanternWallArm",
		Vector3.new(config.postThickness, config.postThickness, armLength),
		CFrame.lookAt(armCenter, armCenter + normal),
		style.lineColor,
		style.lineMaterial
	)

	-- ROOM COVERAGE IS DIRECTIONAL. The small PointLight inside the glass only makes the fixture read;
	-- this wide, low-intensity beam spends its energy into the room instead of inside the rock behind
	-- it. Orienting the spherical flame core changes no visible silhouette but gives Front a stable
	-- wall-relative direction for the SpotLight.
	built.flameCore.CFrame = CFrame.lookAt(built.flameCore.Position, built.flameCore.Position + normal, Vector3.yAxis)
	local roomLight = Instance.new("SpotLight")
	roomLight.Name = "LanternRoomLight"
	roomLight.Color = config.lightColor
	roomLight.Face = Enum.NormalId.Front
	roomLight.Range = math.max(roomLightRange, 0)
	roomLight.Brightness = math.max(roomLightBrightness, 0)
	roomLight.Angle = math.clamp(roomLightAngle, 0, 180)
	roomLight.Shadows = false
	roomLight.Enabled = false
	roomLight.Parent = built.flameCore
	built.roomLight = roomLight
end

-- A SEQUENCE LAMP: the same lantern again, smaller still, built cold and then mounted to cave rock
-- by `mountToWall`.
--
-- WHY IT IS A `BuiltLantern` AND NOT A NEW TYPE. It is lit by `Lantern.setLit`, flared by
-- `client/LanternPresentation` and named part-for-part like the fixture it answers to, so making it a
-- second shape with its own switch would be two implementations of one idea that could then drift.
-- Everything the commit sequence does to these lamps is something the Gas Lantern already did.
--
-- NO DEPTH CHAIN, NO VALVE, NO PROMPT ANCHOR. Those belong to the object a run ENDS at. These are the
-- room around it: a post, a head, a flame and a light, and nothing a player can interact with.
--
-- AND NOTHING A PLAYER CAN WALK INTO. The Gas Lantern's post is the one part in this file that turns
-- collision on, because that fixture is a thing you stand at. These stay uncollidable exactly as
-- `part` builds them, even once their mounting plates are attached to the wall.
function Lantern.buildNetworkLamp(style: Types.FixtureStyle, origin: Vector3): BuiltLantern
	local config = LanternConfig
	local network = config.network
	local model = Instance.new("Model")
	model.Name = "CaveWallLamp"

	local width = config.housingWidth * network.scale
	local height = config.housingHeight * network.scale
	local halfW = width / 2
	local postThickness = config.postThickness * network.scale

	part(
		model,
		"LanternBase",
		Vector3.new(
			config.baseHeight * network.scale,
			config.baseRadius * network.scale * 2,
			config.baseRadius * network.scale * 2
		),
		CFrame.new(origin + Vector3.new(0, config.baseHeight * network.scale / 2, 0)) * UPRIGHT,
		style.frameColor,
		style.frameMaterial,
		Enum.PartType.Cylinder
	)

	local post = part(
		model,
		"LanternPost",
		Vector3.new(postThickness, network.postHeight, postThickness),
		CFrame.new(origin + Vector3.new(0, network.postHeight / 2, 0)),
		style.deckColor,
		style.deckMaterial
	)
	model.PrimaryPart = post

	local headCentre = origin + Vector3.new(0, network.postHeight + height / 2, 0)

	part(
		model,
		"LanternFloor",
		Vector3.new(width, 0.09, width),
		CFrame.new(headCentre - Vector3.new(0, height / 2, 0)),
		style.frameColor,
		style.frameMaterial
	)
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) } do
		part(
			model,
			"LanternFrame",
			Vector3.new(0.08, height, 0.08),
			CFrame.new(headCentre + Vector3.new(corner.X * halfW, 0, corner.Z * halfW)),
			style.frameColor,
			style.frameMaterial
		)
	end
	part(
		model,
		"LanternCap",
		Vector3.new(
			width + config.capOverhang * network.scale * 2,
			0.13,
			width + config.capOverhang * network.scale * 2
		),
		CFrame.new(headCentre + Vector3.new(0, height / 2 + 0.07, 0)),
		style.frameColor,
		style.frameMaterial
	)
	buildBail(model, style, headCentre + Vector3.new(0, height / 2 + 0.13, 0), width * 0.62)

	-- Dark panes while cold, exactly as the big fixture's are: `setLit` clears them rather than
	-- brightening them, so what a player sees through the glass is the flame and never the glass.
	local glass: { BasePart } = {}
	for _, face in
		{
			{ offset = Vector3.new(0, 0, halfW), size = Vector3.new(width - 0.05, height - 0.12, 0.05) },
			{ offset = Vector3.new(0, 0, -halfW), size = Vector3.new(width - 0.05, height - 0.12, 0.05) },
			{ offset = Vector3.new(halfW, 0, 0), size = Vector3.new(0.05, height - 0.12, width - 0.05) },
			{ offset = Vector3.new(-halfW, 0, 0), size = Vector3.new(0.05, height - 0.12, width - 0.05) },
		}
	do
		local pane = part(
			model,
			"LanternGlass",
			face.size,
			CFrame.new(headCentre + face.offset),
			config.glassColor,
			Enum.Material.Glass
		)
		pane.Transparency = config.glassTransparency
		pane.CastShadow = false
		table.insert(glass, pane)
	end

	local wick = part(
		model,
		"LanternBurner",
		Vector3.new(0.12, 0.16, 0.12),
		CFrame.new(headCentre - Vector3.new(0, height / 2 - 0.11, 0)),
		config.deadWickColor,
		Enum.Material.Metal
	)

	local flameHeight = config.flameHeight * network.scale
	local flameCore = part(
		model,
		"LanternFlameCore",
		Vector3.new(0.2, flameHeight, 0.2),
		CFrame.new(headCentre - Vector3.new(0, height / 2 - 0.19 - flameHeight / 2, 0)),
		config.flameCoreColor,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	flameCore.CastShadow = false
	flameCore.Transparency = 1

	local flameTip = part(
		model,
		"LanternFlameTip",
		Vector3.new(0.14, flameHeight * 0.62, 0.14),
		CFrame.new(headCentre - Vector3.new(0, height / 2 - 0.19 - flameHeight, 0)),
		config.flameTipColor,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	flameTip.CastShadow = false
	flameTip.Transparency = 1

	local light = newLampLight(flameCore, "LanternLight", network.lightRange, network.lightBrightness)

	return {
		model = model,
		headPosition = headCentre,
		flameCore = flameCore,
		flameTip = flameTip,
		glass = glass,
		light = light,
		roomLight = nil,
		wick = wick,
	}
end

-- A WORK LAMP: the same lantern, smaller, already burning, hung off a hook by its bail.
--
-- WHY IT LIVES IN THIS FILE. It is not a different object — it is the expedition's own lamp at
-- three-quarter size, and two lamps in one room built in two different visual languages would read as
-- two different games. Sharing the file means the panes, the frame, the cap and the bail can only
-- ever change together.
--
-- IT IS LIT ON ARRIVAL AND HAS NO STATE. Nothing turns it off, nothing waits for it, and no rule
-- reads it: the Gas Lantern's ignition is a moment a player earns, and a work lamp that also had to
-- be lit would spend that moment twice.
--
-- WHAT ITS LIGHT MAY AND MAY NOT DO. It is a decorative `PointLight`, so it is invisible to
-- `server/LightSources` — the perception field is assembled from server-owned flames, flares, decoys
-- and remains, never by scanning the world for lights — which means this cannot change what any
-- threat sees, what any threat is drawn to, or how far a player can be perceived from. It is pure
-- visual information: something in the dark that says a machine is over here.
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

	-- The flame, one piece rather than the big lamp's two: at this size the tip would be a single
	-- pixel doing nothing but muddying the core's colour.
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

	-- The one lamp in this file that is born burning, so it is the one that has to turn its own light
	-- on: nothing else in the game ever will.
	newLampLight(flame, "WorkLampLight", range, brightness).Enabled = true

	return model
end

return Lantern
