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

-- Drapery: a folded curtain hanging from a ceiling. Flat slabs at alternating
-- angles, which is exactly how a low-poly curtain should be built.
function Cave.drapery(parent: Instance, ceilingAt: CFrame, length: number, drop: number, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "Drapery"

	local folds = math.max(4, math.round(length * 1.6))
	local phase = rng:NextNumber() * 6.28
	for i = 0, folds do
		local t = i / folds
		local x = (t - 0.5) * length
		local z = math.sin(t * 5.5 + phase) * (0.3 + rng:NextNumber() * 0.45)
		local hang = drop * (0.4 + 0.6 * math.abs(math.sin(t * 3.1 + phase))) * (0.85 + rng:NextNumber() * 0.3)
		local p = shard(
			model,
			ceilingAt
				* CFrame.new(x, -hang * 0.5, z)
				* CFrame.Angles(0, math.rad((rng:NextNumber() - 0.5) * 26), math.rad((rng:NextNumber() - 0.5) * 10)),
			Vector3.new(length / folds * 1.5, hang, 0.16 + rng:NextNumber() * 0.14),
			rng,
			0.4,
			true
		)
		if i == 0 then
			model.PrimaryPart = p
		end
	end

	model.Parent = parent
	return model
end

-- Flowstone: a poured sheet down a wall, built from overlapping angled slabs.
-- Pass a CFrame on the wall with -Z pointing into the room.
function Cave.flowstone(parent: Instance, wallAt: CFrame, width: number, height: number, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "Flowstone"

	local rows = math.max(4, math.round(height * 0.9))
	for i = 0, rows do
		local t = i / rows
		for _ = 1, rng:NextInteger(1, 3) do
			local w = width * (0.3 + rng:NextNumber() * 0.55) * (1 - t * 0.28)
			local h = (height / rows) * (1.5 + rng:NextNumber() * 0.8)
			local depth = (0.3 + rng:NextNumber() * 0.55) * (1 - t * 0.35)
			local p = shard(
				model,
				wallAt
					* CFrame.new((rng:NextNumber() - 0.5) * width * 0.75, -t * height, -depth * 0.45)
					* CFrame.Angles(
						math.rad((rng:NextNumber() - 0.5) * 12),
						math.rad((rng:NextNumber() - 0.5) * 30),
						math.rad((rng:NextNumber() - 0.5) * 16)
					),
				Vector3.new(w, h, depth),
				rng,
				0.55 - t * 0.4,
				true
			)
			if i == 0 then
				model.PrimaryPart = p
			end
		end
	end

	local c = Instance.new("Part")
	c.Name = "Collider"
	c.Size = Vector3.new(width, height, 0.6)
	c.CFrame = wallAt * CFrame.new(0, -height / 2, -0.3)
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

-- Rimstone: terraced dams around a shallow pool. Faceted arcs, not rings.
function Cave.rimstonePool(parent: Instance, at: CFrame, radius: number, opts: FormOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "RimstonePool"

	for ring = 1, 3 do
		local r = radius * (0.45 + 0.55 * ring / 3)
		local segs = math.max(7, math.round(r * 3.2))
		for i = 1, segs do
			local a = (i / segs) * math.pi * 2
			local h = 0.16 + rng:NextNumber() * 0.22 + ring * 0.07
			local wob = r * (0.94 + rng:NextNumber() * 0.12)
			local p = shard(
				model,
				at
					* CFrame.new(math.cos(a) * wob, h * 0.4, math.sin(a) * wob)
					* CFrame.Angles(
						0,
						-a + math.rad((rng:NextNumber() - 0.5) * 16),
						math.rad((rng:NextNumber() - 0.5) * 10)
					),
				Vector3.new((r * 6.6) / segs, h, 0.3 + rng:NextNumber() * 0.2),
				rng,
				0.8,
				true
			)
			if ring == 1 and i == 1 then
				model.PrimaryPart = p
			end
		end
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

export type ScatterOptions = {
	seed: number?,
	count: number?,
	clusters: number?,
	minHeight: number?,
	maxHeight: number?,
	ceilingY: number?,
	pairChance: number?,
	boulderChance: number?,
	columnChance: number?,
	rubbleChance: number?,
	raycastParams: RaycastParams?,
	wet: boolean?,
}

function Cave.scatter(parent: Instance, centre: Vector3, extent: Vector2, opts: ScatterOptions?): Model
	local o = opts or {}
	local rng = Random.new(o.seed or math.random(1, 1e6))
	local model = Instance.new("Model")
	model.Name = "CaveScatter"

	local count = o.count or 40
	local clusters = o.clusters or math.max(3, math.round(count / 7))
	local minH = o.minHeight or 0.5
	local maxH = o.maxHeight or 4.5
	local pairChance = o.pairChance or 0.32
	local boulderChance = o.boulderChance or 0.16
	local columnChance = o.columnChance or 0.04
	local rubbleChance = o.rubbleChance or 0.2

	local centres = {}
	for _ = 1, clusters do
		table.insert(centres, Vector2.new((rng:NextNumber() - 0.5) * extent.X, (rng:NextNumber() - 0.5) * extent.Y))
	end

	for _ = 1, count do
		local c = centres[rng:NextInteger(1, #centres)]
		local a = rng:NextNumber() * math.pi * 2
		local r = math.sqrt(rng:NextNumber()) * (extent.X * 0.12)
		local x = centre.X + c.X + math.cos(a) * r
		local z = centre.Z + c.Y + math.sin(a) * r

		local floorY = centre.Y
		local up = Vector3.yAxis
		if o.raycastParams then
			local hit = workspace:Raycast(Vector3.new(x, centre.Y + 40, z), Vector3.new(0, -120, 0), o.raycastParams)
			if not hit then
				continue
			end
			floorY = hit.Position.Y
			up = hit.Normal
		end

		local base = CFrame.lookAlong(Vector3.new(x, floorY, z), Vector3.new(0, 0, 1), up)

		if rng:NextNumber() < rubbleChance then
			Cave.rubble(
				model,
				base,
				1.2 + rng:NextNumber() * 2.4,
				rng:NextInteger(4, 11),
				{ seed = rng:NextInteger(1, 1e6) }
			)
			continue
		end

		if rng:NextNumber() < boulderChance then
			Cave.boulder(
				model,
				base * CFrame.new(0, 0.4, 0),
				0.5 + rng:NextNumber() ^ 2 * 2.2,
				{ seed = rng:NextInteger(1, 1e6) }
			)
			continue
		end

		local h = minH + (maxH - minH) * rng:NextNumber() ^ 3
		local rad = h * (0.17 + rng:NextNumber() * 0.09)

		if o.ceilingY and rng:NextNumber() < columnChance then
			Cave.column(model, base, o.ceilingY - floorY, { seed = rng:NextInteger(1, 1e6), wet = o.wet })
			continue
		end

		Cave.stalagmite(model, base, {
			height = h,
			radius = rad,
			lean = 5 + rng:NextNumber() * 9,
			seed = rng:NextInteger(1, 1e6),
			wet = o.wet,
		})

		if o.ceilingY and rng:NextNumber() < pairChance then
			local gap = o.ceilingY - (floorY + h)
			if gap > 0.6 then
				Cave.stalactite(model, CFrame.new(x, o.ceilingY, z), {
					height = math.min(h * (0.5 + rng:NextNumber() * 0.9), gap * 0.85),
					radius = rad * 0.6,
					lean = 2 + rng:NextNumber() * 5,
					seed = rng:NextInteger(1, 1e6),
					wet = true,
				})
			end
		end
	end

	model.Parent = parent
	return model
end

return Cave
