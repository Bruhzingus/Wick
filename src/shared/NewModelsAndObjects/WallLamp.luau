--!strict
-- THE WALL LAMPS — a burnt-out candle in an iron bracket, bolted to cave rock. One per room, plus
-- one crowned lamp in the room the floor ends in.
-- Place at: ReplicatedStorage/Shared/NewModelsAndObjects/WallLamp
--
-- Built to the same laws the Cauldron, CaveKit and MineRelics are built to: flat plates, square stock
-- and simple cylinders, no bevels and no surface noise (ART-BIBLE §2). Detail is spent on SILHOUETTE
-- — the pan, the drips down the side, the crown — because at the edge of candle range an outline is
-- all a player gets.
--
-- WHAT IT REPLACED: an enclosed glass gas lantern that only ever lit itself during a results screen.
-- The object is now a candle for two reasons. Every other flame in this world is a candle, so a
-- second kind of fire with its own colour and its own fuel fiction made the fixture a player is
-- supposed to walk toward look imported. And a candle can be BURNT OUT, which a gas lamp cannot: a
-- dead wick and a pillar that has clearly burned before is the whole story of the cave you are in,
-- told by an object with no dialogue.
--
-- COLD UNTIL LIT, AND BUILT THAT WAY RATHER THAN DRESSED THAT WAY. The flame parts, the lights and
-- the aura all exist from the first frame and are simply off (`setLit`). Creating them at ignition
-- would put an Instance.new on a frame a player is watching, and a fixture whose geometry changes
-- shape as it catches reads as a swap rather than as an ignition.
--
-- THE LIGHTS IN THIS FILE ARE VISUAL ONLY. What a lit lamp is worth to a threat is decided by
-- `server/WallLampService` from `Config/WallLamp`'s perception numbers and assembled into the field
-- by `server/LightSources` — the perception field is never built by scanning the world for lights.
-- Turning a PointLight on here changes what a player can see and nothing else.

local CollectionService = game:GetService("CollectionService")

local Types = require(script.Parent.Parent.Types)
local WallLampConfig = require(script.Parent.Parent.Config.WallLamp)

local WallLamp = {}

export type BuiltWallLamp = {
	model: Model,
	variant: WallLampConfig.WallLampVariant,
	-- The flame's world position: what the prompt hangs off, what the client leans the candle toward,
	-- and what the light field is emitted from.
	flamePosition: Vector3,
	-- The invisible part that carries the tag, the attributes and the prompt. Deliberately not the
	-- flame or the pillar: both change transparency and colour when the lamp catches, and anything
	-- parented to them would inherit that.
	anchor: BasePart,
	pillar: BasePart,
	rim: BasePart,
	wick: BasePart,
	flameCore: BasePart,
	flameTip: BasePart,
	light: PointLight,
	roomLight: SpotLight?,
	aura: { BasePart },
	lit: boolean,
}

-- Part cylinders run along local X. Everything below is authored upright.
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
	-- NOTHING A PLAYER CAN WALK INTO OR SHOOT. These hang at head height in every room on every
	-- floor; giving them collision would put a hard object in the dark at exactly the height a player
	-- runs at, and giving them query would make every tool cast and AI obstacle probe on the floor
	-- pay for them.
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = true
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- Stamped with the brightness it is supposed to settle back to, because `client/LampPresentation`
-- spikes these on ignition and decays them home. Without the attribute it would have to assume one
-- fixture's output, and the crowned lamp burns at several times a room candle's — a room lamp flared
-- against the wrong number would be left permanently too bright.
local function newLampLight(parent: BasePart, name: string, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Name = name
	light.Color = WallLampConfig.lightColor
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Enabled = false
	light:SetAttribute(WallLampConfig.restBrightnessAttribute, brightness)
	light.Parent = parent
	return light
end

-- WAX THAT RAN AND SET. Deterministic from the mount position rather than random, so the same lamp
-- in the same room on a rebuilt floor is the same object — a fixture that reshuffles its own drips
-- when a floor is regenerated would make every screenshot comparison useless.
local function buildDrips(
	model: Model,
	config: WallLampConfig.WallLampGeometry,
	scale: number,
	pillarTop: Vector3,
	color: Color3,
	seed: number
)
	local count = math.max(0, math.floor(config.dripCount))
	local radius = config.pillarRadius * scale
	for index = 1, count do
		-- Spread around the pillar but never evenly: a symmetric ring reads as machined.
		local angle = (index / count) * math.pi * 2 + (seed % 17) * 0.11 + index * 0.37
		local length = config.dripMaxLength * scale * (0.45 + ((seed + index * 53) % 11) / 20)
		local thickness = config.dripThickness * scale
		local at = pillarTop
			+ Vector3.new(
				math.cos(angle) * (radius - thickness * 0.3),
				-length / 2,
				math.sin(angle) * (radius - thickness * 0.3)
			)
		part(
			model,
			"WallLampDrip",
			Vector3.new(thickness, length, thickness),
			CFrame.new(at),
			color,
			Enum.Material.SmoothPlastic
		)
	end
end

-- The crown: short iron uprights fanned around the pan. The one piece of pure ornament in the
-- fixture set, and it exists for a functional reason — this lamp has to be findable across a dark
-- room, and a silhouette does that where a brighter light would only wash out the rock.
local function buildCrown(
	model: Model,
	style: Types.FixtureStyle,
	main: WallLampConfig.MainLampGeometry,
	panTop: Vector3,
	radius: number
)
	local count = math.max(0, math.floor(main.crownPoints))
	if count == 0 then
		return
	end
	for index = 1, count do
		-- A half-turn fan facing the room, not a full ring: the back of the fixture is against rock and
		-- nobody will ever see points built there.
		local t = if count == 1 then 0.5 else (index - 1) / (count - 1)
		local angle = -math.pi / 2 + t * math.pi
		local lean = math.rad(main.crownSpread) * (t * 2 - 1)
		local at = panTop + Vector3.new(math.sin(angle) * radius, main.crownHeight / 2, math.cos(angle) * radius)
		part(
			model,
			"WallLampCrown",
			Vector3.new(main.crownThickness, main.crownHeight, main.crownThickness),
			CFrame.new(at) * CFrame.Angles(0, angle, lean),
			style.frameColor,
			style.frameMaterial
		)
	end
end

-- HOW MUCH ROCK ONE LAMP NEEDS, measured from its mount point.
--
-- `server/FloorBuilder` has to answer three questions before it can install a fixture — how high to
-- probe Terrain, how low, and how much wall to keep clear of random relief — and all three are the
-- same geometry the builder below lays out. Deriving them there would be the same arithmetic written
-- twice in two files that are edited for different reasons, and the copy would rot the first time a
-- pan got wider.
--
-- The aura counts toward width. It lights nothing, but a moss patch growing through the halo of the
-- one fixture a player is meant to find across a dark room is not a thing to leave to luck.
function WallLamp.extent(variant: WallLampConfig.WallLampVariant): { width: number, below: number, above: number }
	local config = WallLampConfig
	local g = config.geometry
	local main = config.main
	local isMain = variant == "Main"
	local scale = if isMain then main.scale else 1

	local width = math.max(g.plateWidth, g.panRadius * 2) * scale
	if isMain then
		width = math.max(width, main.reflectorWidth, main.auraRadius * main.auraOuterMultiplier * 2)
	end

	-- Down to the bottom of the diagonal stay, which is the lowest iron on the fixture.
	local below = g.plateHeight * scale * 0.42 + g.armThickness * scale
	-- Up past the plate, the pan, the whole candle and the flame above it.
	local above = math.max(
		g.plateHeight * scale / 2,
		if isMain then main.reflectorHeight / 2 else 0,
		-g.plateHeight * scale * 0.18
			+ (g.panHeight + g.panLipHeight + g.pillarHeight + g.wickHeight + g.flameHeight * 1.6) * scale
	)
	return { width = width, below = below, above = above }
end

-- ONE LAMP, mounted flat against the rock at `wallSurface` with `inward` pointing into the room.
--
-- The whole fixture is authored in world space around the mount rather than built at the origin and
-- moved, because the bracket has to reach from a plate ON the rock to a candle standing off it: the
-- two ends are in different places by definition and a single pivot cannot describe that.
function WallLamp.build(
	style: Types.FixtureStyle,
	wallSurface: Vector3,
	inward: Vector3,
	variant: WallLampConfig.WallLampVariant
): BuiltWallLamp
	local config = WallLampConfig
	local g = config.geometry
	local main = config.main
	local isMain = variant == "Main"
	local scale = if isMain then main.scale else 1
	local output = if isMain then config.mainOutput else config.roomOutput

	local normal = if inward.Magnitude > 0 then inward.Unit else Vector3.new(0, 0, -1)
	local model = Instance.new("Model")
	model.Name = if isMain then "CrownedWallLamp" else "WallLamp"

	local plateWidth = g.plateWidth * scale
	local plateHeight = g.plateHeight * scale
	local armLength = g.armLength * scale
	local panRadius = g.panRadius * scale
	local pillarHeight = g.pillarHeight * scale
	local pillarRadius = g.pillarRadius * scale

	-- THE BACK PLATE, flat against the rock. This is the piece that says "installed": a candle
	-- floating off a cave wall is a prop, a candle on a plate somebody bolted there is a place.
	local plateCenter = wallSurface + normal * (g.plateThickness * scale / 2)
	local plate = part(
		model,
		"WallLampPlate",
		Vector3.new(plateWidth, plateHeight, g.plateThickness * scale),
		CFrame.lookAt(plateCenter, plateCenter + normal),
		style.frameColor,
		style.frameMaterial
	)
	model.PrimaryPart = plate

	if isMain then
		-- The reflector: a beaten sheet behind the flame that throws light forward instead of into the
		-- rock. It is also, not coincidentally, what makes this lamp read as the important one.
		local reflectorCenter = wallSurface + normal * (main.reflectorThickness / 2 + g.plateThickness * scale)
		part(
			model,
			"WallLampReflector",
			Vector3.new(main.reflectorWidth, main.reflectorHeight, main.reflectorThickness),
			CFrame.lookAt(reflectorCenter, reflectorCenter + normal),
			style.vesselColor,
			style.vesselMaterial
		)
	end

	-- The bracket arm out to the pan, and a diagonal stay under it. Two pieces, because an arm
	-- carrying a candle at the end of a lever with nothing bracing it looks like it is about to fall.
	local armBase = wallSurface + Vector3.new(0, -plateHeight * 0.18, 0)
	local armCenter = armBase + normal * (armLength / 2)
	part(
		model,
		"WallLampArm",
		Vector3.new(g.armThickness * scale, g.armThickness * scale, armLength),
		CFrame.lookAt(armCenter, armCenter + normal),
		style.lineColor,
		style.lineMaterial
	)
	local stayDrop = plateHeight * 0.42
	local stayBase = wallSurface - Vector3.new(0, stayDrop, 0)
	local stayTip = armBase + normal * armLength
	local stayCenter = (stayBase + stayTip) / 2
	part(
		model,
		"WallLampStay",
		Vector3.new(g.armThickness * scale * 0.7, g.armThickness * scale * 0.7, (stayTip - stayBase).Magnitude),
		CFrame.lookAt(stayCenter, stayCenter + (stayTip - stayBase).Unit),
		style.lineColor,
		style.lineMaterial
	)

	-- THE DRIP PAN. A real one exists because wax runs, and this one has been catching it for years.
	local panCenter = armBase + normal * armLength + Vector3.new(0, g.panHeight * scale / 2, 0)
	part(
		model,
		"WallLampPan",
		Vector3.new(g.panHeight * scale, panRadius * 2, panRadius * 2),
		CFrame.new(panCenter) * UPRIGHT,
		style.frameColor,
		style.frameMaterial,
		Enum.PartType.Cylinder
	)
	local lipCenter = panCenter + Vector3.new(0, g.panLipHeight * scale / 2, 0)
	part(
		model,
		"WallLampPanLip",
		Vector3.new(g.panLipHeight * scale, panRadius * 2.04, panRadius * 2.04),
		CFrame.new(lipCenter) * UPRIGHT,
		style.frameColor,
		style.frameMaterial,
		Enum.PartType.Cylinder
	)
	-- Old wax pooled and set in the pan. The fixture's age, stated in one part.
	part(
		model,
		"WallLampPanWax",
		Vector3.new(g.panLipHeight * scale * 0.7, panRadius * 1.82, panRadius * 1.82),
		CFrame.new(panCenter + Vector3.new(0, g.panHeight * scale * 0.4, 0)) * UPRIGHT,
		config.waxColor,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)

	local panTop = panCenter + Vector3.new(0, g.panHeight * scale / 2, 0)
	if isMain then
		buildCrown(model, style, main, panTop, panRadius * 0.94)
	end

	-- THE CANDLE. Fat, short, and obviously used: a pillar somebody expected to burn for a week.
	local pillarCenter = panTop + Vector3.new(0, pillarHeight / 2, 0)
	local pillar = part(
		model,
		"WallLampPillar",
		Vector3.new(pillarHeight, pillarRadius * 2, pillarRadius * 2),
		CFrame.new(pillarCenter) * UPRIGHT,
		config.waxColor,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)

	local pillarTop = panTop + Vector3.new(0, pillarHeight, 0)
	local rimRadius = pillarRadius * g.rimRadiusMultiplier
	-- The melted lip at the top, the same silhouette cue the player's own candle carries. It is how
	-- you know at a glance that this object and the thing in your hands are the same kind of thing.
	local rim = part(
		model,
		"WallLampRim",
		Vector3.new(g.rimHeight * scale, rimRadius * 2, rimRadius * 2),
		CFrame.new(pillarTop - Vector3.new(0, g.rimHeight * scale / 2, 0)) * UPRIGHT,
		config.waxColor,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)

	local seed = math.floor(math.abs(wallSurface.X) * 7 + math.abs(wallSurface.Z) * 13 + math.abs(wallSurface.Y) * 3)
	buildDrips(model, g, scale, pillarTop, config.waxColor, seed)

	-- THE BURNT WICK. The single most important part in this file: it is the difference between a
	-- decoration and an invitation. A wick that has never been lit is a candle nobody has used; a
	-- charred one is a candle somebody used, in this cave, before you got here.
	local wick = part(
		model,
		"WallLampWick",
		Vector3.new(g.wickThickness * scale, g.wickHeight * scale, g.wickThickness * scale),
		CFrame.new(pillarTop + Vector3.new(0, g.wickHeight * scale / 2, 0)),
		config.deadWickColor,
		Enum.Material.SmoothPlastic
	)

	local flameHeight = g.flameHeight * scale
	local flameCenter = pillarTop + Vector3.new(0, g.wickHeight * scale + flameHeight * 0.35, 0)

	-- THE AURA, on the crowned lamp only. Two flat Neon discs behind the flame, dead until it catches.
	-- Neon in this engine is self-illuminating pixels and NOT illumination, so these light nothing:
	-- what the room gets is still only the two real lights below.
	local aura: { BasePart } = {}
	if isMain then
		local auraCenter = flameCenter - normal * (main.auraRadius * 0.22)
		for index, spec in
			{
				{ radius = main.auraRadius, transparency = main.auraTransparency, name = "WallLampAura" },
				{
					radius = main.auraRadius * main.auraOuterMultiplier,
					transparency = main.auraOuterTransparency,
					name = "WallLampAuraOuter",
				},
			}
		do
			local disc = part(
				model,
				spec.name,
				Vector3.new(0.05, spec.radius * 2, spec.radius * 2),
				CFrame.lookAt(auraCenter - normal * (index * 0.03), auraCenter - normal * (index * 0.03) + normal)
					* CFrame.Angles(0, math.pi / 2, 0)
					* UPRIGHT,
				config.auraColor,
				Enum.Material.Neon,
				Enum.PartType.Cylinder
			)
			disc.Transparency = 1
			disc.CastShadow = false
			-- The resting transparency the client breathes around. Stamped rather than assumed for the
			-- same reason the lights are: two discs at two different rests, one animator.
			disc:SetAttribute(config.auraRestAttribute, spec.transparency)
			CollectionService:AddTag(disc, config.auraTag)
			table.insert(aura, disc)
		end
	end

	-- THE FLAME, built cold. Two hard pieces — bright core, warm tip — exactly as the player's own
	-- candle is drawn, because it is the same fire.
	local flameCore = part(
		model,
		"WallLampFlameCore",
		Vector3.new(flameHeight * 0.46, flameHeight, flameHeight * 0.46),
		CFrame.new(flameCenter),
		config.flameCoreColor,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	flameCore.CastShadow = false
	flameCore.Transparency = 1

	local flameTip = part(
		model,
		"WallLampFlameTip",
		Vector3.new(flameHeight * 0.3, flameHeight * 0.62, flameHeight * 0.3),
		CFrame.new(flameCenter + Vector3.new(0, flameHeight * 0.42, 0)),
		config.flameTipColor,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	flameTip.CastShadow = false
	flameTip.Transparency = 1

	local light = newLampLight(flameCore, "WallLampLight", output.pointRange, output.pointBrightness)

	-- ROOM COVERAGE IS DIRECTIONAL. The PointLight above only makes the fixture itself read; this wide,
	-- low-intensity beam spends its energy into the room instead of inside the rock behind it.
	-- Orienting the spherical flame core changes no visible silhouette but gives Front a stable
	-- wall-relative direction.
	flameCore.CFrame = CFrame.lookAt(flameCore.Position, flameCore.Position + normal, Vector3.yAxis)
	local roomLight = Instance.new("SpotLight")
	roomLight.Name = "WallLampRoomLight"
	roomLight.Color = config.lightColor
	roomLight.Face = Enum.NormalId.Front
	roomLight.Range = math.max(output.spotRange, 0)
	roomLight.Brightness = math.max(output.spotBrightness, 0)
	roomLight.Angle = math.clamp(output.spotAngle, 0, 180)
	roomLight.Shadows = false
	roomLight.Enabled = false
	roomLight:SetAttribute(config.restBrightnessAttribute, roomLight.Brightness)
	roomLight.Parent = flameCore

	-- THE ANCHOR: what the tag, the attributes and the prompt live on. An invisible part rather than
	-- the flame or the pillar, because both of those change transparency and colour as the lamp
	-- catches and a prompt parented to either would inherit it.
	local anchor = Instance.new("Part")
	anchor.Name = "WallLampAnchor"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Position = flameCenter
	anchor.Parent = model

	local built: BuiltWallLamp = {
		model = model,
		variant = variant,
		flamePosition = flameCenter,
		anchor = anchor,
		pillar = pillar,
		rim = rim,
		wick = wick,
		flameCore = flameCore,
		flameTip = flameTip,
		light = light,
		roomLight = roomLight,
		aura = aura,
		lit = false,
	}

	anchor:SetAttribute(config.variantAttribute, variant)
	anchor:SetAttribute(config.litAttribute, false)
	CollectionService:AddTag(anchor, config.tag)

	return built
end

-- CAUGHT, OR NOT. `server/WallLampService` is the only caller, and it never calls back to false: a
-- lamp a player lit stays lit for the life of the floor. The signature still takes the boolean so
-- the cold state has exactly one implementation rather than a second "unlight" written later by
-- somebody who could not find this one.
function WallLamp.setLit(built: BuiltWallLamp, lit: boolean)
	local config = WallLampConfig
	built.lit = lit
	built.flameCore.Transparency = if lit then 0 else 1
	built.flameTip.Transparency = if lit then 0.12 else 1
	built.wick.Color = if lit then config.litWickColor else config.deadWickColor
	-- The wax warms where the flame has softened it. A colour shift and nothing more — the pillar is
	-- never a light source, and making it Neon would put a second glowing object in every room.
	built.pillar.Color = if lit then config.waxLitColor else config.waxColor
	built.rim.Color = if lit then config.waxLitColor else config.waxColor
	built.light.Enabled = lit
	if built.roomLight ~= nil then
		built.roomLight.Enabled = lit
	end
	for _, disc in built.aura do
		local rest = disc:GetAttribute(config.auraRestAttribute)
		disc.Transparency = if lit and typeof(rest) == "number" then rest else 1
	end
	built.anchor:SetAttribute(config.litAttribute, lit)
end

return WallLamp
