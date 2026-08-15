--!strict
-- THE DESCENT LADDER — a two-person cage on a winch, the shaft it drops into, and the hatch that
-- covers the mouth when it is away. Family-tinted.
-- Place at: ReplicatedStorage/Shared/NewModelsAndObjects/DescentLadder
--
-- WHAT IT REPLACED: a floating cyan Neon disc, a light pillar and a glowing orb, standing free in
-- the Basin's room with no mechanism of any kind. Touching an invisible box around it put you on the
-- next floor instantly. This is the same objective with a machine under it.
--
-- NOT THE LOBBY'S ELEVATOR, AND DELIBERATELY NOT BUILT LIKE IT. The Landing's car is polished
-- company infrastructure: multi-seat, enclosed, on rails, with a headframe and a counterweight. This
-- is what an expedition rigs once it is past all that — two riders, open framing, whatever the cave
-- and the party's own gear provide. The open frame is load-bearing on the whole idea: you have to be
-- able to see real rock going past, or the ride is a fade with extra steps.
--
-- EXACTLY ONE THING HERE EMITS LIGHT: the work lamp on the headframe (`Config/DescentLadder.workLamp`).
-- The cage, the shaft, the collar and the hatch are all dark, so the ride itself is lit by the candle
-- the rider is carrying and by nothing else — which is why the shaft ribs matter so much, since they
-- are the only thing passing that flame to say the cage is moving at all.
--
-- THE LAMP IS VISUAL INFORMATION AND NOT A GAMEPLAY SIGNAL, which is the distinction ART-BIBLE §4
-- actually draws. `server/LightSources` assembles the threat-perception field from server-owned
-- flames, flares, decoys and remains — it never scans the world for `PointLight`s — so a decorative
-- lamp cannot change what any creature sees, what it is drawn to, or how far off a rider can be
-- perceived. It replaces the beacon this fixture retired: the way down still says "here" from across
-- a dark room, it just says it as a lamp somebody hung rather than as a magic blue pillar.
--
-- THE STATIC HALF AND THE MOVING HALF ARE SEPARATE MODELS, for exactly the reason the lobby's
-- headframe is not parented to its car: whatever moves carries every descendant with it, and a
-- headframe that sank with the cage would take the room's ceiling apart on the way down.

local Types = require(script.Parent.Parent.Types)
local LadderConfig = require(script.Parent.Parent.Config.DescentLadder)
-- The ladder's work lamp is the Gas Lantern at three-quarter size, so it is built by the file that
-- owns that silhouette rather than reimplemented here. Safe direction: `Lantern` requires only Types
-- and its own config, so it can never require this back.
local Lantern = require(script.Parent.Lantern)

local DescentLadder = {}

-- THE HOIST STACK ABOVE THE ROOF, named because two things need it: `buildCage` places these parts,
-- and `build` measures the cage's total height from them so the server knows when the cage is clear
-- of the mouth. A literal in one place and a measurement in the other would drift the first time the
-- yoke is restyled.
local YOKE_RISE_RATIO = 0.32
local CHAIN_STUB_OFFSET = 0.45
local CHAIN_STUB_HEIGHT = 0.9
-- The lip round the mouth. `buildCollarAndHatch` stands the hatch leaves on top of it, so this is also
-- the underside of the closed hatch.
local COLLAR_HEIGHT = 0.3

-- The cage's highest point, measured up from its own pivot (the deck's centre).
local function cageTopOffset(): number
	local config = LadderConfig
	return config.deckThickness / 2
		+ config.cageHeight
		+ config.cageWidth * YOKE_RISE_RATIO
		+ CHAIN_STUB_OFFSET
		+ CHAIN_STUB_HEIGHT / 2
end

-- The rock this shaft is cut through, handed in by the builder so the lining matches the family's
-- own wall stone without this file resolving a palette of its own.
export type RockPalette = {
	color: Color3,
	material: Enum.Material,
}

export type BuiltLadder = {
	-- Everything bolted to the room: shaft lining, headframe, collar, hatch leaves.
	model: Model,
	-- The one thing that moves. Its own model so a client can pivot it without dragging the shaft.
	cage: Model,
	cageRestPivot: CFrame,
	cageBottomPivot: CFrame,
	-- How far the cage travels, resolved here so no caller re-derives it from config and drifts.
	rideDistance: number,
	-- The hatch leaves, in their two authored poses. The server writes these; nothing interpolates
	-- them — a shaft cover is thrown, not eased.
	hatchLeaves: { BasePart },
	hatchOpen: { CFrame },
	hatchClosed: { CFrame },
	-- How far the cage has to travel before the mouth may be covered: the distance from the closed
	-- hatch's underside up to the cage's highest point. Resolved here for the same reason
	-- `rideDistance` is — it is a fact about this built geometry, and a server that re-derived it from
	-- config would drift the moment the cage or the collar changed shape.
	hatchClearanceStuds: number,
	gateLeaves: { BasePart },
	gateOpen: { CFrame },
	gateClosed: { CFrame },
	-- What the ProximityPrompt hangs on: the winch lever, at hand height on the cage frame.
	promptAnchor: BasePart,
	-- Where a rider is put when they board, in the same base-position space `CharacterService.teleport`
	-- expects (feet, not centre).
	riderPosition: Vector3,
}

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
	created.CanQuery = false
	created.CanTouch = false
	-- Shadows off on everything below the floor line. The shaft is unlit past the rider's own candle,
	-- so none of these shadows can fall anywhere a player can see, and dozens of thin ribs and rails
	-- forty studs deep are exactly the geometry that shimmers under a shadow map at that distance.
	created.CastShadow = false
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

local function beamBetween(
	parent: Instance,
	name: string,
	from: Vector3,
	to: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material
): BasePart
	local delta = to - from
	local midpoint = (from + to) / 2
	return part(
		parent,
		name,
		Vector3.new(thickness, thickness, delta.Magnitude),
		CFrame.lookAt(midpoint, to),
		color,
		material
	)
end

-- One shared local-space answer for every piece of hoist hardware. +Z is the rear of the cage; +X
-- is the rider's right. Keeping this derived from cage size makes the cable stay on the rear-right
-- edge when the car is resized instead of drifting back through its centre.
local function hoistOffset(): Vector2
	local config = LadderConfig
	return Vector2.new(config.cageWidth / 2 + math.max(config.hoistSideOutset, 0), config.cageDepth / 2)
end

-- THE SHAFT: a lined tube below the mouth. The ribs are the whole point — they are the parallax that
-- makes the ride read as motion instead of as a dark screen with a countdown behind it.
local function buildShaft(model: Model, origin: Vector3, style: Types.FixtureStyle, rock: RockPalette, depth: number)
	local config = LadderConfig
	local innerHalf = config.cageWidth / 2 + config.shaftClearance
	local openingHeight = math.clamp(config.arrival.openingHeight, 0, depth)
	local centreY = origin.Y - depth / 2
	local hoist = hoistOffset()

	-- Four rock faces. Cut rather than built: this is the wall of a hole, so it is the family's own
	-- stone and not the expedition's timber.
	for _, wall in
		{
			{ size = Vector3.new(innerHalf * 2 + 2, depth, 1), offset = Vector3.new(0, 0, innerHalf + 0.5) },
			{ size = Vector3.new(1, depth, innerHalf * 2), offset = Vector3.new(innerHalf + 0.5, 0, 0) },
			{ size = Vector3.new(1, depth, innerHalf * 2), offset = Vector3.new(-innerHalf - 0.5, 0, 0) },
		}
	do
		local face = part(
			model,
			"ShaftFace",
			wall.size,
			CFrame.new(Vector3.new(origin.X, centreY, origin.Z) + wall.offset),
			rock.color,
			rock.material
		)
		face.CanCollide = true
	end
	local frontDepth = depth - openingHeight
	if frontDepth > 0 then
		local face = part(
			model,
			"ShaftFace",
			Vector3.new(innerHalf * 2 + 2, frontDepth, 1),
			CFrame.new(origin.X, origin.Y - frontDepth / 2, origin.Z - innerHalf - 0.5),
			rock.color,
			rock.material
		)
		face.CanCollide = true
	end

	-- GUIDE RAILS, one down each side of the cage's own tube. What turns a hole into a track something
	-- runs in.
	for _, side in { 1, -1 } do
		part(
			model,
			"ShaftGuideRail",
			Vector3.new(0.36, depth, 0.7),
			CFrame.new(origin.X + side * (config.cageWidth / 2 + config.shaftClearance / 2), centreY, origin.Z),
			style.frameColor,
			style.frameMaterial
		)
	end

	-- THE RIB RINGS. A perimeter ring at each interval, never a plate: a solid plate at that spacing
	-- puts the rider's head through a floor every few studs on the way down.
	local ribCount = math.max(1, math.floor(depth / config.shaftRibSpacing))
	local ribThickness = config.shaftRibThickness
	local ribSpan = innerHalf * 2
	for index = 1, ribCount do
		local y = origin.Y - index * config.shaftRibSpacing
		local segments: { { size: Vector3, offset: Vector3, front: boolean? } } = {
			{ size = Vector3.new(ribSpan, ribThickness, ribThickness), offset = Vector3.new(0, 0, innerHalf) },
			{
				size = Vector3.new(ribSpan, ribThickness, ribThickness),
				offset = Vector3.new(0, 0, -innerHalf),
				front = true,
			},
			{
				size = Vector3.new(ribThickness, ribThickness, ribSpan - ribThickness * 2),
				offset = Vector3.new(innerHalf, 0, 0),
			},
			{
				size = Vector3.new(ribThickness, ribThickness, ribSpan - ribThickness * 2),
				offset = Vector3.new(-innerHalf, 0, 0),
			},
		}
		for _, segment in segments do
			-- Match the lower front-wall opening. Comparing from the top would remove the first rib and
			-- leave a bar across the actual doorway at the bottom of the shaft.
			if segment.front == true and y <= origin.Y - depth + openingHeight then
				continue
			end
			part(
				model,
				"ShaftRib",
				segment.size,
				CFrame.new(Vector3.new(origin.X, y, origin.Z) + segment.offset),
				style.deckColor,
				style.deckMaterial
			)
		end
	end

	-- THE CHAIN, running from the upper sheave to the lower landing as one continuous piece.
	part(
		model,
		"ShaftChain",
		Vector3.new(config.chainThickness, depth, config.chainThickness),
		CFrame.new(origin.X + hoist.X, centreY, origin.Z + hoist.Y),
		style.lineColor,
		style.lineMaterial
	)
end

-- THE HEADFRAME: two legs either side of the mouth, an axle across them, and the sheave the chain
-- runs over. Without it the cage is a box that sinks into a trapdoor; with it, it is machinery.
local function buildHeadframe(model: Model, origin: Vector3, style: Types.FixtureStyle)
	local config = LadderConfig
	local innerHalf = config.cageWidth / 2 + config.shaftClearance
	-- Clear of the shaft lining, so the legs stand on real rock rather than over the hole. The lining
	-- reaches `innerHalf + 1`; anything inside that is standing on nothing.
	local legX = innerHalf + 1.6
	local height = config.headframeHeight
	local hoist = hoistOffset()
	local cableX = origin.X + hoist.X
	local cableZ = origin.Z + hoist.Y
	-- THE WHEEL'S RADIUS IS NOT A LOOK, IT IS WHERE THE CHAIN HANGS. The chain drops vertically
	-- down the rear-right edge, so the sheave sits one radius behind that line for the chain to touch
	-- its rim instead of passing through its hub. Move the cable and the wheel follows it.
	local sheaveRadius = 0.9
	local frameZ = cableZ + sheaveRadius
	local axleY = origin.Y + height - 1.4

	for _, side in { 1, -1 } do
		local leg = part(
			model,
			"HeadframeLeg",
			Vector3.new(0.5, height, 0.5),
			CFrame.new(origin.X + side * legX, origin.Y + height / 2, frameZ),
			style.deckColor,
			style.deckMaterial
		)
		leg.CanCollide = true
		leg.CastShadow = true
		-- A raking brace back down to the floor on each side. Two vertical posts read as a doorway; a
		-- braced frame reads as something taking a load.
		part(
			model,
			"HeadframeBrace",
			Vector3.new(0.3, height * 0.7, 0.3),
			CFrame.new(origin.X + side * (legX + 0.9), origin.Y + height * 0.34, frameZ)
				* CFrame.Angles(0, 0, side * math.rad(16)),
			style.deckColor,
			style.deckMaterial
		)
	end

	part(
		model,
		"HeadframeBeam",
		Vector3.new(legX * 2 + 0.5, 0.42, 0.5),
		CFrame.new(origin.X, origin.Y + height - 0.5, frameZ),
		style.deckColor,
		style.deckMaterial
	)

	-- THE WORK LAMP, on a bracket off the beam.
	--
	-- IT HANGS JUST OUTSIDE THE MOUTH, NOT OVER IT, and that is structural rather than compositional:
	-- the column directly above the shaft is the cage's own path, and the cage's yoke and chain stub
	-- reach nearly to the beam when it is parked. A lamp centred over the opening would be inside the
	-- cage. One step outboard puts it over the collar, where it lights the thing a player is walking
	-- toward and stays clear of everything that moves.
	--
	-- Hung on the ROOM side of the frame (`origin.Z`, not `frameZ`) for a related reason: a player
	-- approaches this from the room, and a lamp tucked in behind the sheave would only resolve once
	-- they no longer needed it.
	local lamp = config.workLamp
	if lamp.enabled then
		local lampX = origin.X + innerHalf + 0.3
		part(
			model,
			"WorkLampBracket",
			Vector3.new(0.16, 0.16, math.abs(frameZ - origin.Z) + 0.5),
			CFrame.new(lampX, origin.Y + height - 0.72, (origin.Z + frameZ) / 2),
			style.frameColor,
			style.frameMaterial
		)
		local built = Lantern.buildWorkLamp(
			style,
			Vector3.new(lampX, origin.Y + height - 0.8, origin.Z),
			lamp.scale,
			lamp.lightRange,
			lamp.lightBrightness
		)
		built.Parent = model
	end

	-- A Roblox cylinder runs along its own X, which is already the axis both of these want.
	part(
		model,
		"SheaveAxle",
		Vector3.new(legX * 2, 0.24, 0.24),
		CFrame.new(origin.X, axleY, frameZ),
		style.frameColor,
		style.frameMaterial,
		Enum.PartType.Cylinder
	)
	part(
		model,
		"Sheave",
		Vector3.new(0.24, sheaveRadius * 2, sheaveRadius * 2),
		CFrame.new(cableX, axleY, frameZ),
		style.frameColor,
		style.frameMaterial,
		Enum.PartType.Cylinder
	)

	-- The chain from the sheave down to the parked cage's yoke.
	local chainTop = origin.Y + height - 1.4
	local chainBottom = origin.Y + LadderConfig.cageHeight + 0.6
	if chainBottom < chainTop then
		part(
			model,
			"HoistChain",
			Vector3.new(config.chainThickness, chainTop - chainBottom, config.chainThickness),
			CFrame.new(cableX, (chainTop + chainBottom) / 2, cableZ),
			style.lineColor,
			style.lineMaterial
		)
	end
end

-- THE COLLAR AND THE HATCH. The collar is the raised lip a player steps over to board; the hatch is
-- two leaves that fold flat across the mouth whenever the cage is not parked in it.
--
-- THE HATCH IS NOT DRESSING. An empty shaft in a walkable room is a hole a teammate falls into, and
-- the cage is genuinely away for the length of a ride plus the length of the winch hauling it back.
-- A working shaft would be covered; covering it is also what makes that window safe.
local function buildCollarAndHatch(
	model: Model,
	origin: Vector3,
	style: Types.FixtureStyle
): ({ BasePart }, { CFrame }, { CFrame })
	local config = LadderConfig
	local innerHalf = config.cageWidth / 2 + config.shaftClearance
	local collarHeight = COLLAR_HEIGHT

	-- THE LIP ROUND THE MOUTH, and it is doing more than dressing. It bridges the ring of open shaft
	-- between the parked cage's deck edge and the rock, which would otherwise be a stud-wide slot all
	-- the way round a hole. `slot` is what is deliberately left open: wide enough that the cage never
	-- clips the collar on its way past, far too narrow for anything to fall through.
	local slot = 0.35
	local collarInner = config.cageWidth / 2 + slot
	local collarOuter = innerHalf + 0.8
	local collarWidth = collarOuter - collarInner
	local collarMid = (collarInner + collarOuter) / 2
	for _, side in
		{
			{ size = Vector3.new(collarOuter * 2, collarHeight, collarWidth), offset = Vector3.new(0, 0, collarMid) },
			{ size = Vector3.new(collarOuter * 2, collarHeight, collarWidth), offset = Vector3.new(0, 0, -collarMid) },
			{ size = Vector3.new(collarWidth, collarHeight, collarInner * 2), offset = Vector3.new(collarMid, 0, 0) },
			{ size = Vector3.new(collarWidth, collarHeight, collarInner * 2), offset = Vector3.new(-collarMid, 0, 0) },
		}
	do
		local collar = part(
			model,
			"ShaftCollar",
			side.size,
			CFrame.new(Vector3.new(origin.X, origin.Y + collarHeight / 2, origin.Z) + side.offset),
			style.deckColor,
			style.deckMaterial
		)
		collar.CanCollide = true
		collar.CastShadow = true
	end

	local leaves: { BasePart } = {}
	local open: { CFrame } = {}
	local closed: { CFrame } = {}
	local leafWidth = innerHalf
	-- The leaves lie ON the collar rather than level with it, which is both what a real hatch does and
	-- what keeps two coplanar slabs from z-fighting across the whole mouth.
	local leafY = origin.Y + collarHeight + config.hatchThickness / 2

	-- TWO LEAVES, hinged on opposite edges. One full-width leaf standing on end would put a six-stud
	-- board upright next to the mouth every time somebody rides down; two half-width ones fold back
	-- against the collar and stay out of the silhouette.
	for _, side in { -1, 1 } do
		local hinge = CFrame.new(origin.X + side * innerHalf, leafY, origin.Z)
		local closedPose = hinge * CFrame.new(-side * leafWidth / 2, 0, 0)
		-- Just past vertical, so a leaf leans back onto the collar rather than balancing on its hinge.
		local openPose = hinge * CFrame.Angles(0, 0, side * math.rad(-104)) * CFrame.new(-side * leafWidth / 2, 0, 0)
		local leaf = part(
			model,
			"ShaftHatch",
			Vector3.new(leafWidth, config.hatchThickness, innerHalf * 2),
			openPose,
			style.deckColor,
			style.deckMaterial
		)
		leaf.CanCollide = true
		leaf.CastShadow = true
		table.insert(leaves, leaf)
		table.insert(open, openPose)
		table.insert(closed, closedPose)
	end

	return leaves, open, closed
end

-- THE CAGE. Deck, four corner posts, two bands, an open roof ring, a yoke, and the winch lever the
-- prompt hangs on. Everything is authored around `restPivot`, whose origin is the deck's own centre,
-- so the whole model can be pivoted down the shaft as one rigid thing.
local function buildCage(
	style: Types.FixtureStyle,
	restPivot: CFrame
): (Model, BasePart, { BasePart }, { CFrame }, { CFrame })
	local config = LadderConfig
	local cage = Instance.new("Model")
	cage.Name = "DescentCage"

	local halfW = config.cageWidth / 2
	local halfD = config.cageDepth / 2
	local deckTop = config.deckThickness / 2
	local hoist = hoistOffset()
	assert(
		hoist.X + config.chainThickness / 2 <= halfW + config.shaftClearance,
		"DescentLadder hoist does not fit between the cage and shaft wall"
	)
	local seatCount = math.max(math.floor(config.riderCapacity), 1)
	for index = 1, seatCount do
		local seatX = if seatCount <= 1 then 0 else ((index - 1) - (seatCount - 1) / 2) * config.riderSpacingStuds * 2
		local headDistance = Vector2.new(hoist.X - seatX, hoist.Y).Magnitude
		assert(
			headDistance >= config.riderHeadClearRadius,
			"DescentLadder hoist overlaps an authored rider's first-person clearance"
		)
	end

	local deck = part(
		cage,
		"CageDeck",
		Vector3.new(config.cageWidth, config.deckThickness, config.cageDepth),
		restPivot,
		style.deckColor,
		style.deckMaterial
	)
	-- THE ONE PIECE WITH COLLISION AND QUERY BOTH ON. It is a floor: the rider stands on it while
	-- parked, and it is what caps the mouth so nobody walks into an occupied shaft.
	deck.CanCollide = true
	deck.CanQuery = true
	deck.CastShadow = true
	cage.PrimaryPart = deck

	-- Deck boards, laid across. Free grain that also gives the eye something to lose against the ribs
	-- on the way down.
	for index = -1, 1 do
		part(
			cage,
			"CageBoard",
			Vector3.new(config.cageWidth * 0.94, 0.08, config.cageDepth * 0.26),
			restPivot * CFrame.new(0, deckTop + 0.04, index * config.cageDepth * 0.3),
			style.frameColor,
			style.frameMaterial
		)
	end

	local corners = {
		Vector3.new(halfW, 0, halfD),
		Vector3.new(halfW, 0, -halfD),
		Vector3.new(-halfW, 0, halfD),
		Vector3.new(-halfW, 0, -halfD),
	}
	for _, corner in corners do
		part(
			cage,
			"CagePost",
			Vector3.new(config.barThickness, config.cageHeight, config.barThickness),
			restPivot * CFrame.new(corner.X, deckTop + config.cageHeight / 2, corner.Z),
			style.frameColor,
			style.frameMaterial
		)
	end

	-- The frame stays visually open, but its three non-door sides and roof are real boundaries while
	-- the cage travels. Riders keep ordinary movement during descent, so thin rails alone cannot be
	-- trusted to contain a candle-sized collider; these invisible planes provide the same closed-car
	-- guarantee as the front gate without blocking the view of the shaft.
	for _, barrier in
		{
			{
				size = Vector3.new(config.cageWidth, config.cageHeight, config.barThickness),
				offset = Vector3.new(0, deckTop + config.cageHeight / 2, halfD),
			},
			{
				size = Vector3.new(config.barThickness, config.cageHeight, config.cageDepth),
				offset = Vector3.new(-halfW, deckTop + config.cageHeight / 2, 0),
			},
			{
				size = Vector3.new(config.barThickness, config.cageHeight, config.cageDepth),
				offset = Vector3.new(halfW, deckTop + config.cageHeight / 2, 0),
			},
			{
				size = Vector3.new(config.cageWidth, config.barThickness, config.cageDepth),
				offset = Vector3.new(0, deckTop + config.cageHeight, 0),
			},
		}
	do
		local wall = part(
			cage,
			"CageContainment",
			barrier.size,
			restPivot * CFrame.new(barrier.offset),
			style.frameColor,
			style.frameMaterial
		)
		wall.CanCollide = true
		wall.Transparency = 1
	end

	-- TWO BANDS AND A ROOF RING, and nothing else. Open framing is what lets the rider see the rock
	-- going past; every additional bar is a fraction of the ride spent looking at the cage instead.
	--
	-- THE FRONT (-Z) FACE IS NOT IN THIS LOOP, and must never be put back into it. -Z is the doorway,
	-- and a band welded across it is a band the gate cannot take with it: the leaves slide clear on
	-- arrival and leave two bars hanging at waist and chest height in the one gap the rider walks out
	-- of. The gate carries the front segment of each band itself, at these exact heights and
	-- thicknesses (see the leaf rails below), so the rings still close all the way round while it is
	-- shut and leave with it when it opens.
	local bandRings = {
		{ y = 0.34, thickness = config.barThickness },
		{ y = 0.72, thickness = config.barThickness * 0.8 },
	}
	for _, spec in bandRings do
		local y = deckTop + config.cageHeight * spec.y
		for _, band in
			{
				{
					size = Vector3.new(config.cageWidth, spec.thickness, spec.thickness),
					offset = Vector3.new(0, 0, halfD),
				},
				{
					size = Vector3.new(spec.thickness, spec.thickness, config.cageDepth),
					offset = Vector3.new(halfW, 0, 0),
				},
				{
					size = Vector3.new(spec.thickness, spec.thickness, config.cageDepth),
					offset = Vector3.new(-halfW, 0, 0),
				},
			}
		do
			part(
				cage,
				"CageBand",
				band.size,
				restPivot * CFrame.new(band.offset.X, y, band.offset.Z),
				style.frameColor,
				style.frameMaterial
			)
		end
	end

	-- THE ROOF RING, AND NOTHING ACROSS IT.
	--
	-- There used to be a fifth beam here spanning the middle at `offset = Vector3.zero`. It was the one
	-- piece of this fixture a rider could not look past: the ride is first person from a flame standing
	-- on the deck's centre line, so a bar over the centre sat directly above the eye for the whole
	-- descent and swept the screen every time the camera lifted. The perimeter beams already close the
	-- frame; the middle of it is the rider's own airspace and stays empty. Do not put a spar, a light,
	-- a hook or a sign back across it.
	local roofY = deckTop + config.cageHeight
	for _, beam in
		{
			{
				size = Vector3.new(config.cageWidth, config.barThickness, config.barThickness),
				offset = Vector3.new(0, 0, halfD),
			},
			{
				size = Vector3.new(config.cageWidth, config.barThickness, config.barThickness),
				offset = Vector3.new(0, 0, -halfD),
			},
			{
				size = Vector3.new(config.barThickness, config.barThickness, config.cageDepth),
				offset = Vector3.new(halfW, 0, 0),
			},
			{
				size = Vector3.new(config.barThickness, config.barThickness, config.cageDepth),
				offset = Vector3.new(-halfW, 0, 0),
			},
		}
	do
		part(
			cage,
			"CageRoofBeam",
			beam.size,
			restPivot * CFrame.new(beam.offset.X, roofY, beam.offset.Z),
			style.frameColor,
			style.frameMaterial
		)
	end

	-- THE YOKE lives entirely on the REAR roof edge. Its two exact corner-to-apex struts and the cable
	-- share the outboard point above, leaving the full rider/head volume open instead of drawing two
	-- diagonal bars and a chain through the first-person view.
	local yokeApex = (restPivot * CFrame.new(hoist.X, roofY + config.cageWidth * YOKE_RISE_RATIO, hoist.Y)).Position
	for _, side in { -1, 1 } do
		local corner = (restPivot * CFrame.new(side * halfW, roofY, halfD)).Position
		beamBetween(cage, "CageYoke", corner, yokeApex, config.barThickness, style.frameColor, style.frameMaterial)
	end
	part(
		cage,
		"CageChainStub",
		Vector3.new(config.chainThickness, CHAIN_STUB_HEIGHT, config.chainThickness),
		restPivot * CFrame.new(hoist.X, roofY + config.cageWidth * YOKE_RISE_RATIO + CHAIN_STUB_OFFSET, hoist.Y),
		style.lineColor,
		style.lineMaterial
	)

	-- THE ONE-WAY GATE, on the cage's front (-Z). Two lattice leaves slide apart for boarding and
	-- arrival, then close before either leg moves. Invisible half-panel colliders make the visual bars
	-- a real boundary without turning the ride into a view-blocking solid wall.
	local gateLeaves: { BasePart } = {}
	local gateOpen: { CFrame } = {}
	local gateClosed: { CFrame } = {}
	local gateHeight = config.cageHeight * 0.78
	local leafWidth = config.cageWidth / 2
	local function addGatePart(
		size: Vector3,
		localClosed: CFrame,
		localOpen: CFrame,
		visible: boolean,
		collidable: boolean
	)
		local leaf = part(cage, "CageGate", size, restPivot * localClosed, style.frameColor, style.frameMaterial)
		leaf.CanCollide = collidable
		leaf.CanQuery = collidable
		leaf.CastShadow = visible
		if not visible then
			leaf.Transparency = 1
		end
		table.insert(gateLeaves, leaf)
		table.insert(gateClosed, localClosed)
		table.insert(gateOpen, localOpen)
	end
	for _, side in { -1, 1 } do
		local closedX = side * leafWidth / 2
		local openShift = side * (leafWidth + 0.45)
		local closedBase = CFrame.new(closedX, deckTop + gateHeight / 2, -halfD)
		local openBase = CFrame.new(closedX + openShift, deckTop + gateHeight / 2, -halfD)
		addGatePart(Vector3.new(leafWidth, gateHeight, config.barThickness * 0.35), closedBase, openBase, false, true)
		for barIndex = -1, 1 do
			local x = closedX + barIndex * leafWidth * 0.32
			local openX = x + openShift
			addGatePart(
				Vector3.new(config.barThickness, gateHeight, config.barThickness),
				CFrame.new(x, deckTop + gateHeight / 2, -halfD),
				CFrame.new(openX, deckTop + gateHeight / 2, -halfD),
				true,
				false
			)
		end
		-- THE LEAF RAILS ARE THE CAGE BANDS' FRONT SEGMENTS. They are authored off `bandRings` rather
		-- than off `gateHeight` so a shut gate meets the side bands at exactly their own height and
		-- thickness and the two rings close, while an open one carries them out of the doorway instead
		-- of stranding them across the exit.
		for _, spec in bandRings do
			local y = deckTop + config.cageHeight * spec.y
			addGatePart(
				Vector3.new(leafWidth, spec.thickness, spec.thickness),
				CFrame.new(closedX, y, -halfD),
				CFrame.new(closedX + openShift, y, -halfD),
				true,
				false
			)
		end
	end

	-- THE LEVER. What the prompt hangs on, at hand height on the frame the rider faces: the
	-- interaction is with a control, not with an abstract volume in the middle of the cage.
	local leverPost = part(
		cage,
		"CageLeverMount",
		Vector3.new(0.3, 0.8, 0.3),
		restPivot * CFrame.new(-halfW, deckTop + config.cageHeight * 0.42, 0),
		style.frameColor,
		style.frameMaterial
	)
	part(
		cage,
		"CageLever",
		Vector3.new(0.16, 0.9, 0.16),
		restPivot
			* CFrame.new(-halfW - 0.24, deckTop + config.cageHeight * 0.42 + 0.5, 0)
			* CFrame.Angles(0, 0, math.rad(22)),
		style.lineColor,
		style.lineMaterial
	)

	return cage, leverPost, gateLeaves, gateOpen, gateClosed
end

-- ONE LADDER, built around `origin` — the pad's centre on the room floor. The shaft below it must
-- already have been carved out of the rock by the caller; this file builds the lining, never the
-- hole.
--
-- `rideDistance` comes from the floor geometry owner and spans one complete floor gap. The successor
-- entry room is aligned under this origin, so the lower end is a real landing rather than a hidden
-- transform between unrelated rooms.
function DescentLadder.build(
	style: Types.FixtureStyle,
	rock: RockPalette,
	origin: Vector3,
	rideDistance: number
): BuiltLadder
	local config = LadderConfig
	local model = Instance.new("Model")
	model.Name = "DescentLadder"

	local shaftDepth = math.max(rideDistance, config.cageHeight + 4)
	buildShaft(model, origin, style, rock, shaftDepth)
	buildHeadframe(model, origin, style)
	local hatchLeaves, hatchOpen, hatchClosed = buildCollarAndHatch(model, origin, style)

	-- The deck's top sits a hair proud of the room floor so the boards catch light instead of
	-- z-fighting the terrain they are flush with.
	local deckTopY = origin.Y + 0.04
	local restPivot = CFrame.new(origin.X, deckTopY - config.deckThickness / 2, origin.Z)
	local cage, promptAnchor, gateLeaves, gateOpen, gateClosed = buildCage(style, restPivot)
	local bottomPivot = restPivot * CFrame.new(0, -rideDistance, 0)

	-- THE CAGE PARKS THROUGH THE HATCH'S PLANE, WHICH IS WHY THIS EXISTS. The deck sits level with the
	-- room floor and the closed hatch lies on the collar just above it, so a hatch thrown shut at the
	-- moment of departure closes across a cage that is still standing in the mouth — and the ride then
	-- drags the riders down through that slab. The server holds it open until the cage has fallen this
	-- far, which is the point the mouth is genuinely empty.
	local hatchClearance = math.max((restPivot.Y + cageTopOffset()) - (origin.Y + COLLAR_HEIGHT), 0)

	return {
		model = model,
		cage = cage,
		cageRestPivot = restPivot,
		cageBottomPivot = bottomPivot,
		rideDistance = rideDistance,
		hatchLeaves = hatchLeaves,
		hatchOpen = hatchOpen,
		hatchClosed = hatchClosed,
		hatchClearanceStuds = hatchClearance,
		gateLeaves = gateLeaves,
		gateOpen = gateOpen,
		gateClosed = gateClosed,
		promptAnchor = promptAnchor,
		riderPosition = Vector3.new(origin.X, deckTopY, origin.Z),
	}
end

return DescentLadder
