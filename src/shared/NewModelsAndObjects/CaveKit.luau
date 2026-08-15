--!strict
-- CaveKit — procedural cave formations, faceted low-poly style.
-- Place at: ReplicatedStorage/CaveKit
--
-- Tuned by the owning game's cave-dressing config: flat facets,
-- few large parts. Rounded organic formations look correct in isolation and
-- wrong next to angular walls — the eye reads the mismatch instantly, so this
-- builds everything from rotated blocks and wedges instead.
--
-- Construction rule: each level is a single block, rotated a random amount in
-- yaw from the one below and overlapping it by ~25%. The rotation is what kills
-- the stacked-blocks read — an unrotated taper is a wedding cake, but yaw-offset
-- levels produce an irregular faceted silhouette that reads as fractured rock.
--
-- Visual and collision stay separate: blocks are CanCollide off, and 2-4
-- invisible cylinders carry the physics. Cheaper and more stable.

local Cave = {}

export type StyleConfig = {
	palette: { Color3 },
	dampTint: Color3,
	materials: { Enum.Material },
	wetMaterial: Enum.Material,
	wetReflectance: number,
	-- HOW THIS FAMILY'S FORMATIONS HAND THE CANDLE BACK. Optional, and nil means "exactly the
	-- behaviour this kit had before finishes existed" — no reflectance, no transparency, and
	-- critically NO EXTRA RANDOM ROLLS, so a family that does not set them builds every formation
	-- from the same random stream it always did. That matters more than it looks: Stone is the
	-- regression baseline, and every later placement on a floor draws from the same Random.
	--
	-- Where they ARE set, they are what makes a formation read as ice rather than as ice-coloured
	-- rock. A matte opaque spire is a rock spire whatever colour it is painted; the same spire with
	-- a highlight sliding down one face as the flame moves is an icicle.
	reflectanceMin: number?,
	reflectanceMax: number?,
	transparencyMin: number?,
	transparencyMax: number?,
}

-- Standalone fallback. WICK configures this once before building a floor.
local currentStyle: StyleConfig = {
	palette = {
		Color3.fromRGB(52, 56, 66),
		Color3.fromRGB(62, 66, 78),
		Color3.fromRGB(45, 49, 59),
		Color3.fromRGB(70, 73, 84),
	},
	-- Bases sit in shadow and stay damp. Mixed toward this near the floor.
	dampTint = Color3.fromRGB(28, 31, 39),
	materials = {
		Enum.Material.Slate,
		Enum.Material.Basalt,
		Enum.Material.Concrete,
		Enum.Material.Rock,
	},
	wetMaterial = Enum.Material.Slate,
	wetReflectance = 0.03,
}

function Cave.configure(style: StyleConfig)
	assert(#style.palette > 0, "CaveKit style requires at least one color")
	assert(#style.materials > 0, "CaveKit style requires at least one material")
	currentStyle = style
end

export type FormOptions = {
	height: number?,
	radius: number?,
	levels: number?,
	lean: number?,
	taper: number?,
	wet: boolean?,
	seed: number?,
	collide: boolean?,
	twist: number?, -- degrees of yaw between levels; higher is more chaotic
}

local function look(p: BasePart, rng: Random, damp: number, wet: boolean?)
	local st = currentStyle
	p.Color = st.palette[rng:NextInteger(1, #st.palette)]:Lerp(st.dampTint, damp * 0.75)
	if wet and rng:NextNumber() < 0.4 then
		p.Material = st.wetMaterial
		p.Reflectance = st.wetReflectance
	else
		p.Material = st.materials[rng:NextInteger(1, #st.materials)]
	end

	-- The family's optional surface finish, applied per facet. Both blocks are guarded so a style
	-- that sets neither consumes no rolls and is byte-identical to the pre-finish kit — see the
	-- StyleConfig fields for why that guard is load-bearing rather than an optimisation.
	--
	-- Reflectance is applied AFTER the wet branch above deliberately: a wet formation already got a
	-- faint authored sheen, and a family that has opted into a real finish is making a statement
	-- about its whole substance that should win over the shared damp rule.
	local reflectanceMin, reflectanceMax = st.reflectanceMin, st.reflectanceMax
	if reflectanceMin ~= nil and reflectanceMax ~= nil and reflectanceMax > reflectanceMin then
		p.Reflectance = rng:NextNumber(reflectanceMin, reflectanceMax)
	end
	local transparencyMin, transparencyMax = st.transparencyMin, st.transparencyMax
	if transparencyMin ~= nil and transparencyMax ~= nil and transparencyMax > transparencyMin then
		-- Damped toward opaque at the base of a formation, where `damp` is already near 1: a spire
		-- that is as clear at its root as at its tip loses the seated, grown-out-of-the-rock read
		-- that the damp tint above exists to give it.
		p.Transparency = rng:NextNumber(transparencyMin, transparencyMax) * (1 - damp * 0.55)
	end
end

local function shard(
	parent: Instance,
	at: CFrame,
	size: Vector3,
	rng: Random,
	damp: number,
	wet: boolean?,
	wedge: boolean?
): BasePart
	local p = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Name = if wedge then "Facet" else "Block"
	p.Size = size
	p.CFrame = at
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	look(p, rng, damp, wet)
	p.Parent = parent
	return p
end

local function collider(parent: Instance, at: CFrame, height: number, diameter: number)
	local p = Instance.new("Part")
	p.Name = "Collider"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = at * CFrame.Angles(0, 0, math.rad(90))
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = parent
end

-- dir = 1 grows up from a floor, -1 hangs from a ceiling.
local function spire(parent: Instance, base: CFrame, dir: number, o: FormOptions, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = if dir > 0 then "Stalagmite" else "Stalactite"

	local height = o.height or 4
	local radius = o.radius or (height * 0.19)
	local taper = o.taper or (if dir > 0 then 0.8 else 1.3)
	local levels = o.levels or math.clamp(math.round(height * 0.9) + 1, 3, 7)
	local leanTotal = math.rad(o.lean or 7)
	local twist = math.rad(o.twist or 46)
	local collide = if o.collide ~= nil then o.collide else true

	-- Angular skirt: two large flat slabs crossed at the base, rotated off
	-- axis. Gives the flared foot without a curve anywhere.
	for i = 1, 2 do
		local w = radius * (2.6 - i * 0.5)
		local skirt = shard(
			model,
			base * CFrame.new(0, dir * radius * 0.28, 0) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
			Vector3.new(w, radius * 0.62, w * (0.7 + rng:NextNumber() * 0.5)),
			rng,
			1,
			o.wet
		)
		skirt.CastShadow = collide
	end

	local cur = base * CFrame.new(0, dir * radius * 0.34, 0)
	local leanDir = rng:NextNumber() * math.pi * 2
	local yaw = rng:NextNumber() * math.pi
	local levelH = height / levels

	for i = 1, levels do
		local t0 = (i - 1) / levels
		local t1 = i / levels
		local w0 = radius * 2 * (1 - t0) ^ taper
		local w1 = radius * 2 * (1 - t1) ^ taper
		local w = math.max((w0 + w1) * 0.5, radius * 0.12)

		leanDir += (rng:NextNumber() - 0.5) * 1.3
		local per = leanTotal / levels
		cur = cur * CFrame.Angles(math.cos(leanDir) * per, 0, math.sin(leanDir) * per)

		-- Yaw offset per level is the whole trick. Without it this is a cake.
		yaw += twist * (0.55 + rng:NextNumber() * 0.9)

		-- Overlap downward by a quarter of the level so no seam ever opens up.
		local blockH = levelH * 1.28
		local centre = cur
			* CFrame.new(0, dir * blockH * 0.36, 0)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(math.rad((rng:NextNumber() - 0.5) * 9), 0, math.rad((rng:NextNumber() - 0.5) * 9))

		local block = shard(
			model,
			centre,
			Vector3.new(w * (0.82 + rng:NextNumber() * 0.4), blockH, w * (0.82 + rng:NextNumber() * 0.4)),
			rng,
			1 - t0 * 0.85,
			o.wet
		)
		block.CastShadow = collide

		-- Occasional ledge: a wide thin slab jutting from one side. Deposition
		-- is uneven and this is what stops the profile reading as machined.
		if rng:NextNumber() < 0.3 and i < levels then
			local lw = w * (0.6 + rng:NextNumber() * 0.6)
			local ledge = shard(
				model,
				centre
					* CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
					* CFrame.new(w * 0.3, blockH * 0.2, 0)
					* CFrame.Angles(0, 0, math.rad(rng:NextInteger(-22, 22))),
				Vector3.new(lw, blockH * 0.22, lw * 0.8),
				rng,
				1 - t0 * 0.85,
				o.wet
			)
			ledge.CastShadow = collide
		end

		cur = cur * CFrame.new(0, dir * levelH, 0)
	end

	-- Point: two wedges back to back make a ridged, broken-looking tip.
	local tipW = radius * (if dir > 0 then 0.55 else 0.34)
	local tipH = radius * (if dir > 0 then 1.1 else 1.9)
	local tipYaw = rng:NextNumber() * math.pi
	for _, s in { 0, math.pi } do
		local w = shard(
			model,
			cur
				* CFrame.Angles(0, tipYaw + s, 0)
				* CFrame.new(0, dir * tipH * 0.5, tipW * 0.25)
				* CFrame.Angles(if dir > 0 then 0 else math.rad(180), 0, 0),
			Vector3.new(tipW, tipH, tipW * 0.5),
			rng,
			0.15,
			true,
			true
		)
		w.CastShadow = false
	end

	if dir < 0 then
		local a = Instance.new("Attachment")
		a.Name = "DripPoint"
		a.Position = Vector3.new(0, -tipH * 0.5, 0)
		a.Parent = model:FindFirstChildWhichIsA("BasePart")
	end

	if collide then
		local bands = math.clamp(math.round(height / 1.6), 2, 4)
		for i = 1, bands do
			local t = (i - 0.5) / bands
			local h = height / bands
			collider(
				model,
				base * CFrame.new(0, dir * ((i - 1) * h + h / 2), 0),
				h,
				math.max(radius * 2 * (1 - t) ^ taper * 1.25, 0.3)
			)
		end
	end

	model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
	model.Parent = parent
	return model
end

function Cave.stalagmite(parent: Instance, at: CFrame, opts: FormOptions?): Model
	local o = opts or {}
	return spire(parent, at, 1, o, Random.new(o.seed or math.random(1, 1e6)))
end

function Cave.stalactite(parent: Instance, at: CFrame, opts: FormOptions?): Model
	local o = opts or {}
	return spire(parent, at, -1, o, Random.new(o.seed or math.random(1, 1e6)))
end

-- Joined pair. Thick and waisted; slender columns are what read as stacked.
function Cave.column(parent: Instance, floorAt: CFrame, height: number, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "Column"

	local radius = o.radius or math.max(height * 0.14, 0.8)
	local levels = math.clamp(math.round(height * 0.8), 5, 12)
	local twist = math.rad(o.twist or 38)
	local yaw = rng:NextNumber() * math.pi
	local levelH = height / levels
	local cur = floorAt
	local leanDir = rng:NextNumber() * math.pi * 2

	for i = 1, levels do
		local t = (i - 0.5) / levels
		local pinch = 0.62 + 0.38 * math.abs(math.cos(t * math.pi))
		local w = radius * 2 * pinch

		leanDir += (rng:NextNumber() - 0.5) * 1.0
		cur = cur * CFrame.Angles(math.cos(leanDir) * math.rad(3) / levels, 0, math.sin(leanDir) * math.rad(3) / levels)
		yaw += twist * (0.6 + rng:NextNumber() * 0.8)

		local blockH = levelH * 1.26
		local centre = cur * CFrame.new(0, blockH * 0.36, 0) * CFrame.Angles(0, yaw, 0)
		shard(
			model,
			centre,
			Vector3.new(w * (0.86 + rng:NextNumber() * 0.3), blockH, w * (0.86 + rng:NextNumber() * 0.3)),
			rng,
			math.max(0, 1 - t * 2.4),
			o.wet
		)
		cur = cur * CFrame.new(0, levelH, 0)
	end

	for i = 1, 4 do
		local h = height / 4
		local t = (i - 0.5) / 4
		collider(
			model,
			floorAt * CFrame.new(0, (i - 1) * h + h / 2, 0),
			h,
			radius * 2 * (0.62 + 0.38 * math.abs(math.cos(t * math.pi))) * 1.2
		)
	end

	model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
	model.Parent = parent
	return model
end

-- Thin angular spikes from the ceiling. Cheap and they sell a cave roof fast.
function Cave.sodaStraws(parent: Instance, ceilingAt: CFrame, count: number, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "SodaStraws"
	local spread = o.radius or 1.8

	for i = 1, count do
		local a = rng:NextNumber() * math.pi * 2
		local r = math.sqrt(rng:NextNumber()) * spread
		local len = (o.height or 1.6) * (0.35 + rng:NextNumber() ^ 1.7 * 1.5)
		local w = 0.10 + rng:NextNumber() * 0.08
		local at = ceilingAt
			* CFrame.new(math.cos(a) * r, 0, math.sin(a) * r)
			* CFrame.Angles(
				math.rad((rng:NextNumber() - 0.5) * 7),
				rng:NextNumber() * math.pi,
				math.rad((rng:NextNumber() - 0.5) * 7)
			)
		local p = shard(
			model,
			at * CFrame.new(0, -len * 0.5, 0),
			Vector3.new(w, len, w * (0.7 + rng:NextNumber() * 0.6)),
			rng,
			0.2,
			true
		)
		p.CastShadow = false
		if i == 1 then
			model.PrimaryPart = p
		end
	end

	model.Parent = parent
	return model
end

-- A tight cluster of sharp tapered spikes hanging from a ceiling or a doorway
-- arch. This is NOT a small stalactite and it is not a soda straw:
--   * a stalactite (`spire` above) is a wide fractured cone with a flared skirt
--     and ledges jutting off it — deposited rock, blunt and irregular;
--   * a soda straw is a uniform hair-thin rod with no taper at all;
--   * an icicle is neither. It is smooth, strongly tapered along its whole
--     length, and it comes in a ROW of them at obviously different lengths.
-- That row-of-uneven-tapers silhouette is what a player actually reads "ice" off
-- at candle range, which is why it earns its own form rather than a recolour of
-- one of the two above.
--
-- Length distribution is `t^1.9` across the authored range on purpose. A uniform
-- roll produces a cluster of mostly middling spikes, which reads as a comb; the
-- power curve makes most of them short and a couple of them long, which is what
-- real icicle fringes look like and what gives the cluster a silhouette.
--
-- Collision-neutral always. These hang in doorway mouths, and a doorway is the
-- one place in a cave where a stray collider would actually cost somebody a run.
function Cave.icicles(parent: Instance, ceilingAt: CFrame, count: number, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "Icicles"

	local spread = o.radius or 2.4
	local maxLength = o.height or 5
	local rootThickness = o.taper or 0.6
	local levels = math.clamp(o.levels or 3, 1, 5)

	for index = 1, count do
		local bearing = rng:NextNumber() * math.pi * 2
		local distance = math.sqrt(rng:NextNumber()) * spread
		local length = maxLength * (0.24 + rng:NextNumber() ^ 1.9 * 0.76)
		local width = rootThickness * (0.62 + rng:NextNumber() * 0.7)
		-- Hung from the ceiling with a small random tilt, so a fringe never reads
		-- as a set of parallel rails.
		local root = ceilingAt
			* CFrame.new(math.cos(bearing) * distance, 0, math.sin(bearing) * distance)
			* CFrame.Angles(
				math.rad((rng:NextNumber() - 0.5) * 11),
				rng:NextNumber() * math.pi,
				math.rad((rng:NextNumber() - 0.5) * 11)
			)

		local cursor = root
		local levelLength = length / levels
		local yaw = rng:NextNumber() * math.pi
		for level = 1, levels do
			local t = (level - 0.5) / levels
			-- Taper to a seventh of the root, matching the doorway barricade's
			-- fangs so the two read as the same substance.
			local w = width * (1 - 0.86 * t)
			yaw += rng:NextNumber(0.5, 1.4)
			local blockLength = levelLength * 1.3
			local piece = shard(
				model,
				cursor * CFrame.new(0, -blockLength * 0.36, 0) * CFrame.Angles(0, yaw, 0),
				Vector3.new(w, blockLength, w * (0.78 + rng:NextNumber() * 0.34)),
				rng,
				-- Barely damped: an icicle catches the flame along its whole
				-- length, unlike a rock spire whose base sits in shadow.
				0.18,
				o.wet
			)
			piece.CastShadow = false
			if index == 1 and level == 1 then
				model.PrimaryPart = piece
			end
			cursor = cursor * CFrame.new(0, -levelLength, 0)
		end

		-- Two crossed wedges for a needle point rather than a cut-off stub.
		local tipWidth = width * 0.3
		local tipLength = width * 1.7
		local tipYaw = rng:NextNumber() * math.pi
		for _, turn in { 0, math.pi } do
			local tip = shard(
				model,
				cursor
					* CFrame.Angles(0, tipYaw + turn, 0)
					* CFrame.new(0, -tipLength * 0.5, tipWidth * 0.25)
					* CFrame.Angles(math.rad(180), 0, 0),
				Vector3.new(tipWidth, tipLength, tipWidth * 0.55),
				rng,
				0.1,
				true,
				true
			)
			tip.CastShadow = false
		end
	end

	model.Parent = parent
	return model
end

-- Flowstone drapery: a thin sheet of deposited rock hanging down a WALL, in
-- folds, the way water sheeting off a lip leaves it. This is the only form in
-- the kit that is neither floor-standing nor ceiling-hung, and it exists because
-- a cave wall had nothing on it but small chips and flat cover patches — the two
-- smallest scales there are — so the largest surface in a room was also the one
-- carrying the least silhouette.
--
-- THE RIPPLE IS THE WHOLE FORM, not the colour and not the outline. Each fold's
-- segments sit at DIFFERENT DEPTHS off the rock, so a flame moving across the
-- sheet runs a highlight down one ridge while the groove beside it goes black.
-- That is what the eye reads a hanging sheet by (ART-BIBLE §4: a surface is
-- defined by how it hands the candle back). Built flat, the same geometry is a
-- board leaning on a wall, however well it is tinted — which is exactly the
-- failure the frost-as-blue-cardboard note in §4 describes.
--
-- Fold lengths use the `t^1.7` curve `icicles` uses, for the same reason: a
-- uniform roll gives every fold roughly one length and the bottom edge reads as
-- hemmed. The power curve keeps most folds short and lets two run long, which is
-- the scalloped lower edge real flowstone has.
--
-- Collision-neutral always. It hangs off the wall into the room by a stud or
-- two, exactly as the wall chips already do, and a collider there would be an
-- invisible snag on the surface players hug when something is behind them.
function Cave.drapery(parent: Instance, wallAt: CFrame, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "Drapery"

	local halfWidth = o.radius or 3
	local maxLength = o.height or 6
	local rootThickness = o.taper or 0.6
	local segments = math.clamp(o.levels or 3, 2, 5)
	local folds = math.clamp(math.round(halfWidth * 1.5), 3, 7)
	local foldSpacing = halfWidth * 2 / folds
	-- How far the sheet peels off the rock at its deepest. Deliberately small and
	-- tied to the sheet's own thickness: a drapery stands PROUD of a wall, and one
	-- that stands clear of it is a slab propped against it.
	local waveDepth = rootThickness * 2.1

	-- A welded shoulder across the top. Without it every fold starts in mid-air
	-- and the sheet reads as hung on the wall rather than grown out of it.
	local shoulder = shard(
		model,
		wallAt * CFrame.new(0, -rootThickness * 0.6, waveDepth * 0.3),
		Vector3.new(halfWidth * 1.9, rootThickness * 1.6, waveDepth * 0.85),
		rng,
		1,
		o.wet
	)
	shoulder.CastShadow = false
	model.PrimaryPart = shoulder

	for index = 1, folds do
		local lateral = -halfWidth + (index - 0.5) * foldSpacing + rng:NextNumber(-1, 1) * foldSpacing * 0.22
		local length = maxLength * (0.3 + rng:NextNumber() ^ 1.7 * 0.7)
		-- Wider than its slot, so neighbouring folds overlap and no straight black
		-- seam ever opens between two of them.
		local width = foldSpacing * rng:NextNumber(1.05, 1.5)
		local phase = rng:NextNumber(0, math.pi * 2)
		local turns = rng:NextNumber(1.1, 2.2)
		local segmentLength = length / segments
		local cursor = 0

		for segment = 1, segments do
			local t = (segment - 0.5) / segments
			local depth = waveDepth * (0.32 + 0.68 * (math.sin(phase + t * turns * math.pi * 2) * 0.5 + 0.5))
			local blockLength = segmentLength * 1.3
			local piece = shard(
				model,
				wallAt
					* CFrame.new(lateral, -(cursor + blockLength * 0.36), depth)
					* CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), rng:NextNumber(-0.1, 0.1)),
				Vector3.new(width * (1 - 0.2 * t), blockLength, rootThickness * (1 - 0.4 * t)),
				rng,
				-- Darkest where it meets the rock, brightest at the free edge —
				-- the same top-to-tip gradient every spire in this kit uses.
				1 - t * 0.8,
				o.wet
			)
			piece.CastShadow = false
			cursor += segmentLength
		end

		-- A blunt chisel toe, not a needle. One wedge, wide and short: a drapery
		-- ends in a lobe where the sheet ran out, and the two-crossed-wedges point
		-- the spires and icicles use would turn every fold into a spike.
		local toe = shard(
			model,
			wallAt
				* CFrame.new(lateral, -(cursor + rootThickness * 0.55), waveDepth * 0.45)
				* CFrame.Angles(math.rad(180), rng:NextNumber(-0.2, 0.2), 0),
			Vector3.new(width * 0.8, rootThickness * 1.4, rootThickness * 0.7),
			rng,
			0.12,
			o.wet,
			true
		)
		toe.CastShadow = false
	end

	model.Parent = parent
	return model
end

-- Breakdown boulders: angular where they fractured, always partly buried. A
-- rock resting fully on top of the floor reads as a prop.
function Cave.boulder(parent: Instance, at: CFrame, size: number, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "Boulder"

	local sink = size * 0.34
	for i = 1, rng:NextInteger(3, 5) do
		local s = size * (0.55 + rng:NextNumber() * 0.65)
		local p = shard(
			model,
			at
				* CFrame.new(
					(rng:NextNumber() - 0.5) * size * 0.55,
					(rng:NextNumber() - 0.35) * size * 0.28 - sink,
					(rng:NextNumber() - 0.5) * size * 0.55
				)
				* CFrame.Angles(rng:NextNumber() * 1.1, rng:NextNumber() * 6.28, rng:NextNumber() * 1.1),
			Vector3.new(s, s * (0.45 + rng:NextNumber() * 0.5), s * (0.6 + rng:NextNumber() * 0.55)),
			rng,
			0.35,
			o.wet
		)
		if i == 1 then
			model.PrimaryPart = p
		end
	end

	local c = Instance.new("Part")
	c.Name = "Collider"
	c.Shape = Enum.PartType.Ball
	c.Size = Vector3.new(size * 1.45, size * 1.05, size * 1.45)
	c.CFrame = at * CFrame.new(0, -sink * 0.4, 0)
	c.Anchored = true
	c.CanCollide = true
	c.CanQuery = true
	c.CanTouch = false
	c.CastShadow = false
	c.Transparency = 1
	c.Parent = model

	model.Parent = parent
	return model
end

-- A loose chip uses the same broken, faceted language as the resting boulders, but has no
-- collider and stays small enough to read as something that has just shed from a wall.
-- Presentation controllers may pivot this anchored model without ever affecting traversal.
function Cave.looseRock(parent: Instance, at: CFrame, size: number, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "LooseRock"

	for index = 1, rng:NextInteger(3, 4) do
		local width = size * rng:NextNumber(0.58, 0.88)
		local part = shard(
			model,
			at
				* CFrame.new(
					(rng:NextNumber() - 0.5) * size * 0.34,
					(rng:NextNumber() - 0.5) * size * 0.24,
					(rng:NextNumber() - 0.5) * size * 0.34
				)
				* CFrame.Angles(rng:NextNumber() * 1.2, rng:NextNumber() * math.pi * 2, rng:NextNumber() * 1.2),
			Vector3.new(width, width * rng:NextNumber(0.48, 0.72), width * rng:NextNumber(0.58, 0.86)),
			rng,
			0.42,
			o.wet,
			index % 2 == 0
		)
		part.CastShadow = false
		if index == 1 then
			model.PrimaryPart = part
		end
	end

	model.Parent = parent
	return model
end

-- Rubble: small flat chips scattered on the floor. The cheapest thing here and
-- the fastest way to stop a floor plane reading as a plane.
function Cave.rubble(parent: Instance, at: CFrame, area: number, count: number, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "Rubble"
	for i = 1, count do
		local a = rng:NextNumber() * math.pi * 2
		local r = math.sqrt(rng:NextNumber()) * area
		local s = 0.16 + rng:NextNumber() ^ 2 * 0.7
		local p = shard(
			model,
			at
				* CFrame.new(math.cos(a) * r, s * 0.12, math.sin(a) * r)
				* CFrame.Angles(
					math.rad(rng:NextInteger(-16, 16)),
					rng:NextNumber() * 6.28,
					math.rad(rng:NextInteger(-16, 16))
				),
			Vector3.new(s, s * (0.2 + rng:NextNumber() * 0.25), s * (0.6 + rng:NextNumber() * 0.7)),
			rng,
			0.5,
			false
		)
		p.CastShadow = false
		if i == 1 then
			model.PrimaryPart = p
		end
	end
	model.Parent = parent
	return model
end

return Cave
