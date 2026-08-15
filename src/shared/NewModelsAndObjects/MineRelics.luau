--!strict
-- THE OLD WORKINGS — twelve procedural silhouettes of abandoned mining equipment.
-- Place at: ReplicatedStorage/Shared/NewModelsAndObjects/MineRelics
--
-- Built to the same laws CaveKit is built to, for the same reason: a prop that is modelled in a
-- different visual language to the rock around it reads as an imported asset instantly, however
-- good it is on its own. So everything here is flat plates, square stock and simple cylinders —
-- no bevels, no surface noise, no decorative detail competing with the outline (ART-BIBLE §2).
-- Detail is spent on SILHOUETTE and on DAMAGE, never on fidelity.
--
-- EVERY PIECE IS DEGRADED, AND THE DEGRADATION IS STRUCTURAL. Nothing here is a clean object with a
-- rust palette on it. A cart is off its rails and leaning; a ladder is missing rungs and split at
-- the top; a prop frame has one post kicked out and a sagged header; a crate has burst; a rail run
-- buckles and throws a sleeper. That is what sells "this has been here a very long time" — colour
-- alone reads as a new object that someone tinted.
--
-- DAMP RISES FROM THE FLOOR. Anything within a couple of studs of the ground is mixed toward the
-- damp tint (`Config/MineRelics.palette.dampTint`), so a piece is darkest where it has been standing
-- in the wet and lightest where the candle actually catches it. Free, and it does more for the read
-- than any amount of extra geometry.
--
-- COLLISION IS ON MASS, NOT ON DETAIL. Every substantial body — cart, crate, keg, post, ladder,
-- winch — carries an invisible collider, so a player cannot walk through it and threat obstacle
-- casts see it, exactly like a CaveKit boulder. GROUND-FLUSH detail does not: rails, sleepers,
-- ballast, spilled ore and fallen tools sit under ankle height, and a collidable object there is a
-- movement snag rather than an obstacle. That distinction is what lets a relic have real collision
-- without ever interfering with how the cave routes.
--
-- NOTHING SELF-ILLUMINATES. The lantern on the hook post is COLD — dark glass, low reflectance, no
-- Neon and no light source. It is a lamp that went out, which is the only kind of lamp this game
-- has room for.

local CollectionService = game:GetService("CollectionService")

local MineRelicsConfig = require(script.Parent.Parent.Config.MineRelics)
local MineRelicVisualProtocol = require(script.Parent.Parent.MineRelicVisualProtocol)

local MineRelics = {}

-- What has taken hold on this equipment in this cave, resolved by `Logic/CaveFamilyRules` from the
-- family's own surface cover. A family answers "what grows on things down here"; each silhouette
-- answers "and these are the ledges it collects on".
export type Weathering = {
	palette: { Color3 },
	material: Enum.Material,
	shape: "Patch" | "Shard",
	-- Chance any one authored anchor carries growth, already scaled by the family.
	density: number,
	size: number,
}

-- Standalone fallback, replaced per floor by `configure`.
local currentWeathering: Weathering = {
	palette = { Color3.fromRGB(16, 46, 26) },
	material = Enum.Material.Grass,
	shape = "Patch",
	density = 0.28,
	size = 0.8,
}

function MineRelics.configure(weathering: Weathering)
	assert(#weathering.palette > 0, "MineRelics weathering requires at least one colour")
	currentWeathering = weathering
end

-- Height over which the damp mix fades out. Deliberately about the height of a standing crate: the
-- gradient has to resolve within one object, not across the room.
local DAMP_HEIGHT = 2.6
-- Part cylinders run along local X. These stand one up and lay one along Z respectively.
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

type PartOptions = {
	shape: Enum.PartType?,
	castShadow: boolean?,
	transparency: number?,
	reflectance: number?,
}

local function palette()
	return MineRelicsConfig.palette
end

-- Mix toward the damp tint by how close to the floor this piece sits. `at` is in model space, whose
-- origin is the piece's own ground contact, so this is one dot product rather than a world query.
local function damp(color: Color3, at: CFrame): Color3
	local p = palette()
	local wetness = math.clamp(1 - at.Position.Y / DAMP_HEIGHT, 0, 1)
	return color:Lerp(p.dampTint, wetness * p.dampBlend)
end

local function part(
	model: Model,
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material,
	opts: PartOptions?
): BasePart
	local o = opts or {}
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.CFrame = at
	created.Shape = o.shape or Enum.PartType.Block
	created.Color = damp(color, at)
	created.Material = material
	created.Transparency = o.transparency or 0
	created.Reflectance = o.reflectance or 0
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	-- Small detail never casts. See CodeBreakdown: the one-shadow-per-client budget is spent on
	-- structural surfaces and collidable mass, and a bolt's shadow is invisible at candle range.
	created.CastShadow = o.castShadow == true
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = model
	return created
end

-- A visible mass: casts, and is what the eye reads the object by.
local function mass(
	model: Model,
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material,
	opts: PartOptions?
): BasePart
	local o: PartOptions = if opts ~= nil then table.clone(opts) else {}
	o.castShadow = true
	return part(model, name, size, at, color, material, o)
end

-- The only collidable thing in a relic, and the only thing an AI obstacle cast can see. Boxes rather
-- than the real geometry, on the same reasoning CaveKit gives for its cylinders: gameplay wants a
-- conservative volume, not a mesh.
local function collider(model: Model, size: Vector3, at: CFrame)
	local created = Instance.new("Part")
	created.Name = "Collider"
	created.Size = size
	created.CFrame = at
	created.Anchored = true
	created.CanCollide = true
	created.CanQuery = true
	created.CanTouch = false
	created.CastShadow = false
	created.Transparency = 1
	created.Parent = model
end

local function pick(list: { Color3 }, rng: Random): Color3
	return list[rng:NextInteger(1, #list)]
end

local function iron(rng: Random): Color3
	return pick(palette().ironColors, rng)
end

local function timber(rng: Random): Color3
	return pick(palette().timberColors, rng)
end

local function spoilColor(rng: Random): Color3
	return pick(palette().spoilColors, rng)
end

-- Small deterministic misalignment. Nothing man-made in this cave is square any more, and a single
-- degree of skew on every plate is what stops a stack of boxes reading as a stack of boxes.
local function skew(rng: Random, degrees: number): CFrame
	local d = math.rad(degrees)
	return CFrame.Angles(rng:NextNumber(-d, d), rng:NextNumber(-d, d), rng:NextNumber(-d, d))
end

-- One patch of whatever this cave grows, on a ledge that would actually collect it. Rolls against
-- the family's density, so a Stone cave gets the occasional dark fleck and a Moss cave furs the
-- upward faces.
local function growth(model: Model, at: CFrame, extent: number, rng: Random)
	local w = currentWeathering
	if w.density <= 0 or rng:NextNumber() >= w.density then
		return
	end
	local size = extent * w.size
	local isShard = w.shape == "Shard"
	local created = if isShard then Instance.new("WedgePart") else Instance.new("Part")
	created.Name = if isShard then "RelicRime" else "RelicGrowth"
	created.Size = if isShard
		then Vector3.new(size, size * 0.7, size * 0.5)
		else Vector3.new(size, 0.09, size * rng:NextNumber(0.6, 1))
	created.CFrame = at * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	created.Color = pick(w.palette, rng)
	created.Material = w.material
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = false
	created.Parent = model
end

-- Loose spill: ore that came out of a cart, spoil out of a barrow, powder out of a keg. Flat chips
-- pressed into the floor, never a heap of boulders — this is what fell, not what fractured.
local function spill(model: Model, at: CFrame, area: number, count: number, rng: Random)
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = math.sqrt(rng:NextNumber()) * area
		local size = rng:NextNumber(0.18, 0.52)
		part(
			model,
			"Spoil",
			Vector3.new(size, size * rng:NextNumber(0.24, 0.4), size * rng:NextNumber(0.7, 1.1)),
			at * CFrame.new(math.cos(angle) * radius, size * 0.1, math.sin(angle) * radius) * skew(rng, 16),
			spoilColor(rng),
			palette().spoilMaterial
		)
	end
end

--------------------------------------------------------------------------------
-- Shared sub-assemblies
--------------------------------------------------------------------------------

-- A spoked-look wheel, without spokes: a rim cylinder and a narrower hub, which at candle range is
-- exactly what a cart wheel reads as and costs two parts instead of ten.
local function wheel(model: Model, at: CFrame, diameter: number, rng: Random)
	local p = palette()
	mass(
		model,
		"Wheel",
		Vector3.new(0.22, diameter, diameter),
		at,
		iron(rng),
		p.ironMaterial,
		{ shape = Enum.PartType.Cylinder }
	)
	part(
		model,
		"Hub",
		Vector3.new(0.3, diameter * 0.42, diameter * 0.42),
		at,
		p.fittingColor,
		p.fittingMaterial,
		{ shape = Enum.PartType.Cylinder }
	)
end

-- Square timber stock with a split, dry end. `at` is the base; the post grows along +Y.
local function post(model: Model, at: CFrame, thickness: number, height: number, rng: Random): CFrame
	local top = at * CFrame.new(0, height, 0)
	mass(
		model,
		"Post",
		Vector3.new(thickness, height, thickness * rng:NextNumber(0.9, 1.05)),
		at * CFrame.new(0, height / 2, 0),
		timber(rng),
		palette().timberMaterial
	)
	part(
		model,
		"SplitEnd",
		Vector3.new(thickness * 0.7, thickness * 0.5, thickness * 0.7),
		top * CFrame.new(0, -thickness * 0.2, 0) * skew(rng, 9),
		palette().timberSplitColor,
		palette().timberMaterial
	)
	return top
end

-- A banded crate. `broken` bursts one face open and darkens the interior, which is the whole
-- difference between "storage" and "abandoned storage".
local function crate(model: Model, at: CFrame, size: number, broken: boolean, rng: Random)
	local p = palette()
	local body = timber(rng)
	mass(model, "CrateBody", Vector3.new(size, size * 0.92, size * 0.86), at, body, p.timberMaterial)

	-- Slats on the two faces that will actually be seen, and corner posts on all four verticals.
	for _, side in { -1, 1 } do
		for slat = 1, 3 do
			local y = (slat - 2) * size * 0.3
			part(
				model,
				"Slat",
				Vector3.new(size * 1.02, size * 0.2, size * 0.06),
				at * CFrame.new(0, y, side * size * 0.45) * skew(rng, 2),
				body:Lerp(p.timberSplitColor, rng:NextNumber(0.1, 0.5)),
				p.timberMaterial
			)
		end
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(
				model,
				"CratePost",
				Vector3.new(size * 0.12, size * 0.94, size * 0.12),
				at * CFrame.new(x * size * 0.46, 0, z * size * 0.42),
				body:Lerp(p.timberSplitColor, 0.25),
				p.timberMaterial
			)
		end
	end
	-- Iron banding, and one band that has sprung off its corner.
	for _, y in { -0.3, 0.3 } do
		part(
			model,
			"CrateBand",
			Vector3.new(size * 1.05, size * 0.1, size * 0.9),
			at * CFrame.new(0, y * size, 0),
			p.fittingColor,
			p.fittingMaterial
		)
	end

	if broken then
		-- A staved-in lid: the top plate driven down and one board levered up out of it.
		part(
			model,
			"BurstLid",
			Vector3.new(size * 0.8, size * 0.1, size * 0.7),
			at * CFrame.new(0, size * 0.34, 0) * CFrame.Angles(math.rad(11), 0, math.rad(-7)),
			p.timberSplitColor,
			p.timberMaterial
		)
		part(
			model,
			"PriedBoard",
			Vector3.new(size * 0.22, size * 0.06, size * 0.8),
			at * CFrame.new(size * 0.22, size * 0.5, 0) * CFrame.Angles(math.rad(38), math.rad(9), 0),
			p.timberSplitColor,
			p.timberMaterial
		)
	end
	growth(model, at * CFrame.new(0, size * 0.47, 0), size * 0.5, rng)
end

-- A hooped barrel from six parts: a bellied body, two end discs and two hoops. Roblox cylinders are
-- smooth, so the belly is what stops it reading as a bin — a keg is widest at its middle.
local function keg(model: Model, at: CFrame, height: number, diameter: number, rng: Random)
	local p = palette()
	local body = timber(rng)
	mass(
		model,
		"KegBody",
		Vector3.new(height * 0.62, diameter, diameter),
		at,
		body,
		p.timberMaterial,
		{ shape = Enum.PartType.Cylinder }
	)
	for _, side in { -1, 1 } do
		mass(
			model,
			"KegEnd",
			Vector3.new(height * 0.2, diameter * 0.84, diameter * 0.84),
			at * CFrame.new(side * height * 0.4, 0, 0),
			body:Lerp(p.timberSplitColor, 0.3),
			p.timberMaterial,
			{ shape = Enum.PartType.Cylinder }
		)
		part(
			model,
			"KegHoop",
			Vector3.new(height * 0.07, diameter * 0.94, diameter * 0.94),
			at * CFrame.new(side * height * 0.24, 0, 0),
			p.fittingColor,
			p.fittingMaterial,
			{ shape = Enum.PartType.Cylinder }
		)
	end
	-- Local +Y is the barrel's side when it is stood on end and its top when it is laid down, which is
	-- the right answer in both cases without the caller having to say which it built.
	growth(model, at * CFrame.new(0, diameter * 0.5, 0), diameter * 0.5, rng)
end

--------------------------------------------------------------------------------
-- The eleven silhouettes
--------------------------------------------------------------------------------

-- 1. THE ORE CART. The hero piece and the one every other relic is scaled against: a splay-sided
-- tub on four wheels, off its track, bedded down on one corner with its load half out of it.
local function buildMinecart(model: Model, rng: Random)
	local p = palette()
	-- Bedded into the floor and leaning. The lean is the entire read: a level cart is a cart that is
	-- still in service.
	local base = CFrame.new(0, 1.34, 0) * CFrame.Angles(math.rad(-4), rng:NextNumber(-0.2, 0.2), math.rad(11))
	local length, width, depth = 4.4, 2.7, 1.7

	-- Chassis: two timber runners the tub is bolted down onto.
	for _, x in { -1, 1 } do
		mass(
			model,
			"Runner",
			Vector3.new(0.3, 0.34, length * 1.04),
			base * CFrame.new(x * width * 0.36, -depth * 0.5, 0),
			timber(rng),
			p.timberMaterial
		)
	end

	-- The tub. Five plates, the four sides splayed outward so the silhouette tapers toward the floor.
	local plate = iron(rng)
	mass(
		model,
		"TubFloor",
		Vector3.new(width * 0.82, 0.22, length * 0.9),
		base * CFrame.new(0, -depth * 0.42, 0),
		plate,
		p.ironMaterial
	)
	for _, x in { -1, 1 } do
		mass(
			model,
			"TubSide",
			Vector3.new(0.2, depth, length * 0.98),
			base * CFrame.new(x * width * 0.46, 0, 0) * CFrame.Angles(0, 0, math.rad(-x * 9)),
			plate,
			p.ironMaterial
		)
	end
	for _, z in { -1, 1 } do
		mass(
			model,
			"TubEnd",
			Vector3.new(width * 0.9, depth, 0.2),
			base * CFrame.new(0, 0, z * length * 0.5) * CFrame.Angles(math.rad(z * 9), 0, 0),
			plate,
			p.ironMaterial
		)
	end
	-- Riveted banding along the rim and the corner posts, which is what makes plate read as plate.
	for _, x in { -1, 1 } do
		part(
			model,
			"RimBand",
			Vector3.new(0.28, 0.24, length * 1.02),
			base * CFrame.new(x * width * 0.5, depth * 0.48, 0),
			p.fittingColor,
			p.fittingMaterial
		)
		for _, z in { -1, 1 } do
			part(
				model,
				"CornerPost",
				Vector3.new(0.22, depth * 1.02, 0.22),
				base * CFrame.new(x * width * 0.46, 0, z * length * 0.47),
				p.fittingColor,
				p.fittingMaterial
			)
		end
	end
	-- One end plate has torn away at the top corner, so the tub's outline is broken.
	part(
		model,
		"TornPlate",
		Vector3.new(width * 0.42, 0.5, 0.18),
		base * CFrame.new(width * 0.2, depth * 0.42, -length * 0.5) * CFrame.Angles(math.rad(-26), 0, math.rad(8)),
		plate,
		p.ironMaterial
	)

	-- Running gear: two axles, three wheels still on, one thrown off and lying flat.
	for _, z in { -1, 1 } do
		part(
			model,
			"Axle",
			Vector3.new(width * 1.08, 0.16, 0.16),
			base * CFrame.new(0, -depth * 0.62, z * length * 0.3),
			p.fittingColor,
			p.fittingMaterial,
			{ shape = Enum.PartType.Cylinder }
		)
	end
	for index, offset in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1) } do
		wheel(
			model,
			base * CFrame.new(offset.X * width * 0.56, -depth * 0.62, offset.Z * length * 0.3),
			0.95 + index * 0.01,
			rng
		)
	end
	wheel(model, CFrame.new(width * 0.95, 0.12, length * 0.34) * UPRIGHT * skew(rng, 7), 0.95, rng)

	-- The load, half in and half out of the open end.
	spill(model, base * CFrame.new(0, -depth * 0.3, 0), width * 0.32, 7, rng)
	spill(model, CFrame.new(0.4, 0, -length * 0.62), 1.9, 11, rng)

	growth(model, base * CFrame.new(-width * 0.5, depth * 0.5, length * 0.2), 0.9, rng)
	growth(model, base * CFrame.new(0, -depth * 0.55, -length * 0.36), 1.1, rng)

	collider(model, Vector3.new(width * 1.1, depth * 1.6, length * 1.06), base * CFrame.new(0, -depth * 0.1, 0))
	return CFrame.new(0, 1.4, 0)
end

-- 2. THE RAIL RUN. A length of track going nowhere, with the sleepers rotted out from under it and
-- one section buckled up off the bed. Flush to the floor by design: this is the piece that says
-- "ore moved along here" without putting anything in the way of moving along here.
local function buildRailRun(model: Model, rng: Random)
	local p = palette()
	local sleepers = 8
	local spacing = 1.3
	local gauge = 1.7
	local runLength = sleepers * spacing

	for index = 1, sleepers do
		local z = (index - (sleepers + 1) / 2) * spacing
		-- Two sleepers have rotted out and lie skewed across the bed instead of under the rail.
		local displaced = index == 3 or index == 7
		local at = if displaced
			then CFrame.new(rng:NextNumber(-0.9, 0.9), 0.1, z) * CFrame.Angles(0, rng:NextNumber(0.8, 2.2), math.rad(6))
			else CFrame.new(0, 0.14, z) * skew(rng, 4)
		part(
			model,
			"Sleeper",
			Vector3.new(gauge * 1.5, 0.26, 0.62),
			at,
			timber(rng),
			p.timberMaterial,
			{ castShadow = not displaced }
		)
		if index % 3 == 0 then
			growth(model, at * CFrame.new(rng:NextNumber(-0.5, 0.5), 0.14, 0), 0.7, rng)
		end
	end

	-- Rails in three sections each, so the far third can kick up and twist out of gauge.
	for _, x in { -1, 1 } do
		local railColor = iron(rng)
		for section = 1, 3 do
			local z = (section - 2) * runLength / 3
			local buckled = section == 3
			local at = if buckled
				then CFrame.new(x * gauge * 0.5 + x * 0.35, 0.55, z) * CFrame.Angles(
					math.rad(-14),
					math.rad(x * 7),
					math.rad(x * 12)
				)
				else CFrame.new(x * gauge * 0.5, 0.31, z) * skew(rng, 1.5)
			mass(model, "Rail", Vector3.new(0.2, 0.24, runLength / 3 * 0.98), at, railColor, p.ironMaterial)
			-- The rail head: a slightly wider flat that catches the flame along its whole length, which
			-- is the only thing that makes a rail read as a rail in near-darkness.
			part(
				model,
				"RailHead",
				Vector3.new(0.3, 0.09, runLength / 3 * 0.98),
				at * CFrame.new(0, 0.16, 0),
				p.fittingColor,
				p.fittingMaterial
			)
		end
	end

	-- Ballast washed in between the sleepers.
	spill(model, CFrame.new(0, 0, -runLength * 0.1), gauge * 1.4, 14, rng)
	-- The one collidable thing here, and it is the one thing that is actually in the air: the buckle.
	collider(model, Vector3.new(gauge * 1.6, 1.1, runLength / 3), CFrame.new(0, 0.6, runLength / 3))
	return CFrame.new(0, 0.6, runLength * 0.2)
end

-- 3. THE BUFFER STOP. Where the track ended, jammed against the rock: a timber baulk braced back
-- into the floor with an iron face somebody's cart hit hard enough to bend.
local function buildBufferStop(model: Model, rng: Random)
	local p = palette()
	local gauge = 1.7

	for _, x in { -1, 1 } do
		local railColor = iron(rng)
		mass(
			model,
			"Rail",
			Vector3.new(0.2, 0.24, 5.6),
			CFrame.new(x * gauge * 0.5, 0.31, -2),
			railColor,
			p.ironMaterial
		)
		part(
			model,
			"RailHead",
			Vector3.new(0.3, 0.09, 5.6),
			CFrame.new(x * gauge * 0.5, 0.47, -2),
			p.fittingColor,
			p.fittingMaterial
		)
	end
	for index = 1, 4 do
		local at = CFrame.new(0, 0.14, -index * 1.3) * skew(rng, 4)
		part(model, "Sleeper", Vector3.new(gauge * 1.5, 0.26, 0.62), at, timber(rng), p.timberMaterial)
	end

	-- The baulk: a heavy squared beam across the track, canted where the ground gave under one end.
	local baulk = CFrame.new(0, 0.95, 0.5) * CFrame.Angles(0, 0, math.rad(-6))
	mass(model, "Baulk", Vector3.new(gauge * 1.9, 1.05, 0.85), baulk, timber(rng), p.timberMaterial)
	mass(
		model,
		"StrikePlate",
		Vector3.new(gauge * 1.5, 0.72, 0.16),
		baulk * CFrame.new(0, 0.05, -0.5) * CFrame.Angles(math.rad(7), 0, 0),
		p.fittingColor,
		p.fittingMaterial
	)
	for _, x in { -1, 1 } do
		-- Braces raking back into the floor, which is what a buffer stop actually is.
		mass(
			model,
			"Brace",
			Vector3.new(0.34, 2.3, 0.34),
			CFrame.new(x * gauge * 0.6, 0.8, -0.45) * CFrame.Angles(math.rad(38), 0, math.rad(-x * 6)),
			timber(rng),
			p.timberMaterial
		)
	end
	-- A rail end kicked up over the baulk by whatever hit it.
	part(
		model,
		"BentRail",
		Vector3.new(0.2, 0.24, 2),
		CFrame.new(gauge * 0.5, 1.15, -0.5) * CFrame.Angles(math.rad(-32), math.rad(11), 0),
		iron(rng),
		p.ironMaterial
	)

	spill(model, CFrame.new(0, 0, -1.2), 2.2, 12, rng)
	growth(model, baulk * CFrame.new(rng:NextNumber(-0.7, 0.7), 0.53, 0), 1.1, rng)
	growth(model, CFrame.new(gauge * 0.7, 0.2, -2.4), 0.9, rng)

	collider(model, Vector3.new(gauge * 2, 2.1, 1.5), CFrame.new(0, 1.05, 0.35))
	return CFrame.new(0, 1.2, 0)
end

-- 4. THE PROP FRAME. Two posts and a header holding up a roof that stopped needing holding up a
-- long time ago. The header has sagged and split and one post has been kicked off its footing —
-- which is why this stands against a wall and never across a route.
local function buildPitProps(model: Model, rng: Random)
	local p = palette()
	local span, height, thickness = 4.4, 6.6, 0.6

	-- Left post: sound, leaning slightly under the load.
	local leftTop = post(model, CFrame.new(-span / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(3)), thickness, height, rng)
	-- Right post: kicked out at the base and short, with its top no longer under anything.
	local rightTop = post(
		model,
		CFrame.new(span / 2 + 0.4, 0, 0.2) * CFrame.Angles(math.rad(4), 0, math.rad(-11)),
		thickness,
		height * 0.82,
		rng
	)

	-- The header, as two halves meeting in a sag. One beam rotated would read as a ramp; two reads as
	-- a beam that has broken over its own middle.
	local headerY = height + thickness * 0.4
	for _, side in { -1, 1 } do
		mass(
			model,
			"Header",
			Vector3.new(span * 0.56, thickness * 0.9, thickness * 1.1),
			CFrame.new(side * span * 0.26, headerY - 0.18, 0) * CFrame.Angles(0, 0, math.rad(side * 4)),
			timber(rng),
			p.timberMaterial
		)
	end
	part(
		model,
		"Splinter",
		Vector3.new(0.7, 0.3, thickness * 0.9),
		CFrame.new(0, headerY - 0.5, 0) * CFrame.Angles(0, math.rad(14), math.rad(-24)),
		p.timberSplitColor,
		p.timberMaterial
	)
	-- One diagonal brace still doing its job, one lying where it fell.
	mass(
		model,
		"Brace",
		Vector3.new(0.38, 2.6, 0.38),
		CFrame.new(-span * 0.34, height * 0.78, 0) * CFrame.Angles(0, 0, math.rad(42)),
		timber(rng),
		p.timberMaterial
	)
	part(
		model,
		"FallenBrace",
		Vector3.new(0.38, 0.38, 3.1),
		-- Out into the room, never toward +Z: that is where the rock is for a wall-anchored piece. The
		-- yaw band keeps a three-stud beam lying broadly ALONG the wall rather than swinging its far
		-- end back into it.
		CFrame.new(0.9, 0.2, -1.2) * CFrame.Angles(math.rad(4), rng:NextNumber(1.25, 1.85), 0),
		timber(rng),
		p.timberMaterial
	)
	-- Footings: flat stones wedged under each post, and the rock that came down when the right one went.
	for _, x in { -span / 2, span / 2 + 0.4 } do
		part(
			model,
			"Footing",
			Vector3.new(thickness * 2, 0.24, thickness * 2),
			CFrame.new(x, 0.12, 0) * skew(rng, 5),
			spoilColor(rng),
			p.spoilMaterial
		)
	end
	-- The rock that came down when the right post went, spilling INTO the room. A scatter centred at
	-- +Z would throw half its chips into the wall the frame is standing against.
	spill(model, CFrame.new(span / 2 + 0.2, 0, -1), 1.9, 10, rng)

	growth(model, leftTop * CFrame.new(0, -1.6, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.9, rng)
	growth(model, rightTop * CFrame.new(0, -0.4, 0), 0.9, rng)
	growth(model, CFrame.new(-span / 2, 0.3, 0.4), 1.2, rng)

	for _, x in { -span / 2, span / 2 + 0.4 } do
		collider(model, Vector3.new(thickness * 1.6, height, thickness * 1.6), CFrame.new(x, height / 2, 0))
	end
	return CFrame.new(0, height * 0.6, 0)
end

-- 5. THE SUPPLY STACK. Crates somebody carried down and never carried back up, one of them burst
-- open and long since emptied.
local function buildSupplyCrates(model: Model, rng: Random)
	local p = palette()

	crate(model, CFrame.new(0, 1.05, 0) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), 2.1, false, rng)
	crate(
		model,
		CFrame.new(rng:NextNumber(-0.25, 0.25), 2.7, rng:NextNumber(-0.2, 0.2))
			* CFrame.Angles(math.rad(-4), rng:NextNumber(-0.6, 0.6), math.rad(6)),
		1.7,
		true,
		rng
	)
	-- A third crate that came off the stack and landed on its side.
	crate(
		model,
		CFrame.new(2.3, 0.75, 0.7) * CFrame.Angles(math.rad(84), rng:NextNumber(-0.4, 0.4), math.rad(5)),
		1.6,
		true,
		rng
	)

	-- A slumped sack: a sphere mesh flattened, because a sack is the one thing here that was never
	-- square and it stops the group reading as three boxes.
	local sack = mass(
		model,
		"Sack",
		Vector3.new(1.3, 0.85, 1.1),
		CFrame.new(-1.7, 0.42, 0.4) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(9)),
		timber(rng):Lerp(p.ropeColor, 0.45),
		p.ropeMaterial
	)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = sack
	part(
		model,
		"SackTie",
		Vector3.new(0.34, 0.34, 0.34),
		CFrame.new(-1.7, 0.85, 0.4) * skew(rng, 20),
		p.ropeColor,
		p.ropeMaterial
	)

	spill(model, CFrame.new(2.6, 0, -0.4), 1.5, 9, rng)
	growth(model, CFrame.new(-0.9, 0.1, -1), 1.1, rng)

	collider(model, Vector3.new(2.4, 3.5, 2.2), CFrame.new(0, 1.75, 0))
	collider(model, Vector3.new(1.9, 1.6, 1.9), CFrame.new(2.3, 0.8, 0.7))
	return CFrame.new(0, 1.9, 0)
end

-- 6. THE POWDER STORE. Two kegs of blasting powder nobody came back for — one still standing with
-- its head staved in, one on its side with a hoop off and its contents long since spilled and set.
local function buildPowderKegs(model: Model, rng: Random)
	local p = palette()

	-- Upright: cylinders run along local X, so the whole keg is turned up onto its end.
	local standing = CFrame.new(0, 1.05, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(4)) * UPRIGHT
	keg(model, standing, 2.05, 1.5, rng)
	-- The head driven in, and one stave levered up out of it.
	part(
		model,
		"StavedHead",
		Vector3.new(0.14, 1.2, 1.2),
		-- Proud of the end plate `keg` already put at 0.82, or it would be buried inside it.
		standing
			* CFrame.new(1, 0, 0)
			* CFrame.Angles(0, math.rad(9), math.rad(6)),
		p.timberSplitColor,
		p.timberMaterial,
		{ shape = Enum.PartType.Cylinder }
	)
	part(
		model,
		"SprungStave",
		Vector3.new(0.18, 0.9, 0.2),
		CFrame.new(0.35, 2.35, 0.2) * CFrame.Angles(math.rad(24), 0, math.rad(31)),
		p.timberSplitColor,
		p.timberMaterial
	)

	-- Fallen: laid along Z, rolled against whatever stopped it.
	local fallen = CFrame.new(2.1, 0.72, -0.6) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0) * ALONG_Z
	keg(model, fallen, 1.9, 1.4, rng)
	part(
		model,
		"LooseHoop",
		Vector3.new(0.12, 1.5, 1.5),
		CFrame.new(3.3, 0.1, 0.5) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(4)) * UPRIGHT,
		p.fittingColor,
		p.fittingMaterial,
		{ shape = Enum.PartType.Cylinder }
	)

	-- Powder that got out and set hard. Darker and flatter than ore spill, so the two read apart.
	for index = 1, 7 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = math.sqrt(rng:NextNumber()) * 1.5
		local size = rng:NextNumber(0.5, 1.1)
		part(
			model,
			"SetPowder",
			Vector3.new(size, 0.1, size * rng:NextNumber(0.7, 1.2)),
			CFrame.new(2.1 + math.cos(angle) * radius, 0.05 + index * 0.001, -0.6 + math.sin(angle) * radius)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			p.dampTint:Lerp(spoilColor(rng), 0.3),
			p.spoilMaterial
		)
	end

	growth(model, CFrame.new(-0.9, 0.1, 0.7), 1, rng)

	collider(model, Vector3.new(1.7, 2.2, 1.7), CFrame.new(0, 1.1, 0))
	collider(model, Vector3.new(1.6, 1.5, 2.1), CFrame.new(2.1, 0.75, -0.6))
	return CFrame.new(0, 1.5, 0)
end

-- 7. THE WINDLASS. A hand winch on an A-frame, its rope still paid out to a bucket that is sitting
-- on the floor because there is no longer anything below it to lower into.
local function buildWindlass(model: Model, rng: Random)
	local p = palette()
	local height, spread, drumLength = 3, 1.5, 2.6

	-- Four raking legs, paired into two A-frames.
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			mass(
				model,
				"Leg",
				Vector3.new(0.34, height * 1.06, 0.34),
				CFrame.new(x * drumLength * 0.46, height / 2, z * spread * 0.5)
					* CFrame.Angles(math.rad(-z * 14), 0, math.rad(-x * 5)),
				timber(rng),
				p.timberMaterial
			)
		end
		part(
			model,
			"HeadBlock",
			Vector3.new(0.5, 0.4, spread * 0.9),
			CFrame.new(x * drumLength * 0.46, height, 0),
			timber(rng),
			p.timberMaterial
		)
	end

	-- Drum and its rope coil.
	local drum = CFrame.new(0, height - 0.1, 0)
	mass(
		model,
		"Drum",
		Vector3.new(drumLength, 0.75, 0.75),
		drum,
		timber(rng),
		p.timberMaterial,
		{ shape = Enum.PartType.Cylinder }
	)
	for _, offset in { -0.55, -0.2, 0.2, 0.62 } do
		part(
			model,
			"RopeCoil",
			Vector3.new(0.22, 0.92, 0.92),
			drum * CFrame.new(offset, 0, 0),
			p.ropeColor,
			p.ropeMaterial,
			{ shape = Enum.PartType.Cylinder }
		)
	end
	-- The crank: two bars off one end, which is the detail that names the object.
	part(
		model,
		"CrankArm",
		Vector3.new(0.16, 0.9, 0.16),
		drum * CFrame.new(drumLength * 0.58, 0.35, 0) * CFrame.Angles(math.rad(28), 0, 0),
		p.fittingColor,
		p.fittingMaterial
	)
	part(
		model,
		"CrankHandle",
		Vector3.new(0.7, 0.15, 0.15),
		drum * CFrame.new(drumLength * 0.58 + 0.3, 0.7, 0.15) * CFrame.Angles(0, math.rad(90), 0),
		p.fittingColor,
		p.fittingMaterial
	)

	-- Rope hanging slack in two straight runs, then the bucket it ends in, tipped over.
	part(
		model,
		"Rope",
		Vector3.new(0.13, height * 0.62, 0.13),
		CFrame.new(0.15, height * 0.66, 0.5) * CFrame.Angles(math.rad(-9), 0, math.rad(3)),
		p.ropeColor,
		p.ropeMaterial
	)
	part(
		model,
		"Rope",
		Vector3.new(0.13, 1.5, 0.13),
		CFrame.new(0.3, 0.8, 1.15) * CFrame.Angles(math.rad(-34), 0, math.rad(8)),
		p.ropeColor,
		p.ropeMaterial
	)
	local bucket = CFrame.new(0.55, 0.55, 1.75) * CFrame.Angles(math.rad(72), rng:NextNumber(0, math.pi), 0)
	mass(
		model,
		"Bucket",
		Vector3.new(1.05, 1.15, 1.05),
		bucket,
		iron(rng),
		p.ironMaterial,
		{ shape = Enum.PartType.Cylinder }
	)
	part(
		model,
		"BucketHoop",
		Vector3.new(0.14, 1.2, 1.2),
		bucket * CFrame.new(0.4, 0, 0),
		p.fittingColor,
		p.fittingMaterial,
		{ shape = Enum.PartType.Cylinder }
	)
	spill(model, CFrame.new(0.9, 0, 2.3), 1.2, 7, rng)

	growth(model, CFrame.new(-drumLength * 0.46, 0.4, spread * 0.5) * CFrame.Angles(0, 0, math.rad(90)), 0.9, rng)
	growth(model, drum * CFrame.new(-0.9, 0.4, 0), 0.8, rng)

	for _, x in { -1, 1 } do
		collider(model, Vector3.new(0.9, height, spread * 1.5), CFrame.new(x * drumLength * 0.46, height / 2, 0))
	end
	collider(model, Vector3.new(1.3, 1.2, 1.3), CFrame.new(0.55, 0.55, 1.75))
	return CFrame.new(0, height * 0.8, 0)
end

-- 8. THE HOOK POST. An iron stake driven into the rock with a lamp still hanging off it. The lamp is
-- DEAD — dark glass, no emitter, no Neon — and that is the whole point of the piece: it is the last
-- place somebody had light, and it is not giving you any.
local function buildLanternPost(model: Model, rng: Random)
	local p = palette()
	local height = 3.4
	-- Driven in leaning slightly OUT of the wall it was driven into. The yaw is a small wobble rather
	-- than a free spin: this is a wall piece, so the hook has to end up over the room and not inside
	-- the rock behind it.
	local stake = CFrame.Angles(math.rad(-5), rng:NextNumber(-0.18, 0.18), math.rad(-7))

	mass(
		model,
		"Stake",
		Vector3.new(0.26, height, 0.26),
		stake * CFrame.new(0, height / 2, 0),
		iron(rng),
		p.ironMaterial
	)
	-- Rock wedged round the foot to hold it, and the hook bent over at the top.
	for index = 1, 3 do
		part(
			model,
			"Wedge",
			Vector3.new(0.55, 0.3, 0.45),
			stake * CFrame.new(0, 0.14, 0) * CFrame.Angles(0, index * 2.1, 0) * CFrame.new(0.4, 0, 0) * skew(rng, 12),
			spoilColor(rng),
			p.spoilMaterial
		)
	end
	local head = stake * CFrame.new(0, height, 0)
	part(
		model,
		"Hook",
		Vector3.new(0.18, 0.18, 0.8),
		head * CFrame.new(0, -0.1, -0.35),
		p.fittingColor,
		p.fittingMaterial
	)
	part(
		model,
		"HookTip",
		Vector3.new(0.18, 0.42, 0.18),
		head * CFrame.new(0, -0.3, -0.68) * CFrame.Angles(math.rad(22), 0, 0),
		p.fittingColor,
		p.fittingMaterial
	)

	-- The lamp, hanging still at a frozen swing. A cap, a dish, three bars and the glass between them.
	local lamp = head
		* CFrame.new(0, -1.35, -0.66)
		* CFrame.Angles(math.rad(6), rng:NextNumber(0, math.pi), math.rad(-9))
	part(
		model,
		"Bail",
		Vector3.new(0.09, 0.55, 0.09),
		lamp * CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.rad(4)),
		p.fittingColor,
		p.fittingMaterial
	)
	mass(model, "LampCap", Vector3.new(0.62, 0.16, 0.62), lamp * CFrame.new(0, 0.36, 0), iron(rng), p.ironMaterial)
	mass(model, "LampDish", Vector3.new(0.6, 0.2, 0.6), lamp * CFrame.new(0, -0.36, 0), iron(rng), p.ironMaterial)
	part(
		model,
		"LampGlass",
		Vector3.new(0.42, 0.6, 0.42),
		lamp,
		p.glassColor,
		Enum.Material.Glass,
		{ transparency = p.glassTransparency, reflectance = p.glassReflectance }
	)
	-- Three of the four guards remain; the gap is where the pane went.
	for index = 1, 3 do
		local angle = index * math.pi / 2
		part(
			model,
			"LampGuard",
			Vector3.new(0.07, 0.72, 0.07),
			lamp * CFrame.Angles(0, angle, 0) * CFrame.new(0.24, 0, 0.24),
			p.fittingColor,
			p.fittingMaterial
		)
	end
	-- The broken pane, on the floor under it.
	part(
		model,
		"BrokenPane",
		Vector3.new(0.36, 0.05, 0.3),
		CFrame.new(0.5, 0.04, -0.9) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		p.glassColor,
		Enum.Material.Glass,
		{ transparency = p.glassTransparency + 0.2, reflectance = p.glassReflectance }
	)

	growth(model, stake * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.7, rng)

	collider(model, Vector3.new(0.7, height, 0.7), CFrame.new(0, height / 2, 0))
	return CFrame.new(0, height * 0.7, 0)
end

-- 9. THE BARROW. Tipped onto its side where somebody let go of it, its load still lying in the arc
-- it fell in.
local function buildWheelbarrow(model: Model, rng: Random)
	local p = palette()
	-- The whole barrow is rolled onto its left side; every piece below is built in that frame.
	local base = CFrame.new(0, 0.75, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(74))
	local tray = iron(rng)

	mass(model, "TrayFloor", Vector3.new(1.5, 0.16, 2.1), base, tray, p.ironMaterial)
	for _, x in { -1, 1 } do
		mass(
			model,
			"TraySide",
			Vector3.new(0.14, 0.85, 2.1),
			base * CFrame.new(x * 0.78, 0.4, 0) * CFrame.Angles(0, 0, math.rad(-x * 13)),
			tray,
			p.ironMaterial
		)
	end
	mass(
		model,
		"TrayBack",
		Vector3.new(1.5, 0.9, 0.14),
		base * CFrame.new(0, 0.42, 1.03) * CFrame.Angles(math.rad(12), 0, 0),
		tray,
		p.ironMaterial
	)
	part(
		model,
		"TrayLip",
		Vector3.new(1.72, 0.12, 0.12),
		base * CFrame.new(0, 0.82, -0.1),
		p.fittingColor,
		p.fittingMaterial
	)

	-- Handles running back past the tray, and the two legs it used to rest on.
	for _, x in { -1, 1 } do
		mass(
			model,
			"Handle",
			Vector3.new(0.2, 0.2, 3.4),
			base * CFrame.new(x * 0.62, -0.14, 0.75) * CFrame.Angles(math.rad(5), 0, 0),
			timber(rng),
			p.timberMaterial
		)
		part(
			model,
			"Leg",
			Vector3.new(0.18, 0.7, 0.18),
			base * CFrame.new(x * 0.62, -0.5, 0.85),
			p.fittingColor,
			p.fittingMaterial
		)
	end
	-- The fork and the wheel at the front.
	for _, x in { -1, 1 } do
		part(
			model,
			"Fork",
			Vector3.new(0.15, 0.15, 1),
			base * CFrame.new(x * 0.32, -0.28, -1.3),
			p.fittingColor,
			p.fittingMaterial
		)
	end
	-- The axle runs across the barrow, which is the frame's own X, so no extra turn: `ALONG_Z` here
	-- would stand the wheel across the direction of travel.
	wheel(model, base * CFrame.new(0, -0.3, -1.75), 1.1, rng)

	spill(model, CFrame.new(-0.2, 0, -0.4) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), 2.1, 13, rng)
	growth(model, base * CFrame.new(0, 0.14, 0.6), 0.9, rng)

	collider(model, Vector3.new(2, 1.5, 3.2), CFrame.new(0, 0.75, 0.2))
	return CFrame.new(0, 1, 0)
end

-- 10. THE TOOL RACK. A board on the wall with what was left on it: a pick with a broken haft and a
-- shovel worn down to nothing, plus whatever got dropped at the foot of it.
local function buildToolRack(model: Model, rng: Random)
	local p = palette()
	local height = 3.2
	-- Leaning back against the rock, because a board that is fixed flat to a cave wall reads as a
	-- texture rather than an object. Positive pitch tips the top toward +Z, which is where the rock
	-- is for every wall-anchored piece.
	local board = CFrame.new(0, height / 2, 0) * CFrame.Angles(math.rad(8), rng:NextNumber(-0.1, 0.1), 0)

	for _, x in { -0.55, 0.55 } do
		mass(model, "Board", Vector3.new(0.9, height, 0.16), board * CFrame.new(x, 0, 0), timber(rng), p.timberMaterial)
	end
	mass(
		model,
		"CrossBar",
		Vector3.new(2.3, 0.24, 0.2),
		board * CFrame.new(0, height * 0.28, -0.16),
		timber(rng),
		p.timberMaterial
	)
	for _, x in { -0.62, 0.02, 0.66 } do
		part(
			model,
			"Peg",
			Vector3.new(0.11, 0.11, 0.42),
			board * CFrame.new(x, height * 0.28, -0.36),
			p.fittingColor,
			p.fittingMaterial
		)
	end

	-- A pick hung by its head, its haft snapped off short.
	local pickHead = board * CFrame.new(-0.62, height * 0.2, -0.42) * CFrame.Angles(0, math.rad(8), math.rad(-6))
	for _, side in { -1, 1 } do
		mass(
			model,
			"PickBlade",
			Vector3.new(0.14, 0.16, 1.15),
			pickHead * CFrame.new(0, 0, side * 0.55) * CFrame.Angles(math.rad(side * 9), 0, 0),
			iron(rng),
			p.ironMaterial
		)
	end
	part(
		model,
		"PickHaft",
		Vector3.new(0.16, 0.95, 0.16),
		pickHead * CFrame.new(0, -0.5, 0),
		timber(rng),
		p.timberMaterial
	)
	part(
		model,
		"SnappedHaft",
		Vector3.new(0.16, 0.5, 0.16),
		CFrame.new(-1.1, 0.1, -1.1) * CFrame.Angles(math.rad(88), rng:NextNumber(0, math.pi), 0),
		p.timberSplitColor,
		p.timberMaterial
	)

	-- A shovel, worn to a stub, still on its peg.
	local shovel = board * CFrame.new(0.66, height * 0.05, -0.44) * CFrame.Angles(0, 0, math.rad(7))
	part(
		model,
		"ShovelHaft",
		Vector3.new(0.14, 1.9, 0.14),
		shovel * CFrame.new(0, 0.6, 0),
		timber(rng),
		p.timberMaterial
	)
	mass(
		model,
		"ShovelBlade",
		Vector3.new(0.62, 0.7, 0.1),
		shovel * CFrame.new(0, -0.5, 0) * CFrame.Angles(math.rad(8), 0, 0),
		iron(rng),
		p.ironMaterial
	)

	-- What got dropped and never picked up. Out on the floor in FRONT of the rack — a tool lying at
	-- +Z would be lying inside the rock the rack is leaning on.
	for index = 1, 3 do
		part(
			model,
			"HandTool",
			Vector3.new(0.13, 0.13, rng:NextNumber(0.6, 1.1)),
			CFrame.new(rng:NextNumber(-1, 1.4), 0.09, -rng:NextNumber(0.6, 1.6))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(index * 2)),
			iron(rng),
			p.ironMaterial
		)
	end

	growth(model, board * CFrame.new(0, -height * 0.4, -0.1), 0.9, rng)
	growth(model, CFrame.new(0.9, 0.08, -0.9), 1, rng)

	collider(model, Vector3.new(2.6, height, 0.9), CFrame.new(0, height / 2, 0))
	return CFrame.new(0, height * 0.6, 0)
end

-- 11. THE LADDER. Left leaning where it was last climbed, half its rungs gone and the head of it
-- snapped off, so it no longer reaches whatever it was reaching.
local function buildLadder(model: Model, rng: Random)
	local p = palette()
	local length, gap = 8.4, 1.35
	-- Leaning back onto the rock at +Z. The lean is what makes it a ladder rather than two posts, and
	-- its sign is what decides whether the head rests on the wall or hangs out over the room.
	local lean = CFrame.Angles(math.rad(19), rng:NextNumber(-0.14, 0.14), 0)

	-- One stile runs full length; the other is snapped short, which breaks the parallel silhouette.
	local stileLengths = { length, length * 0.78 }
	for index, x in { -gap / 2, gap / 2 } do
		local stileLength = stileLengths[index]
		mass(
			model,
			"Stile",
			Vector3.new(0.24, stileLength, 0.34),
			lean * CFrame.new(x, stileLength / 2, 0),
			timber(rng),
			p.timberMaterial
		)
		part(
			model,
			"StileEnd",
			Vector3.new(0.24, 0.5, 0.34),
			lean * CFrame.new(x, stileLength - 0.2, 0) * CFrame.Angles(math.rad(index * 9), 0, math.rad(index * 12)),
			p.timberSplitColor,
			p.timberMaterial
		)
	end

	local rungs = 9
	for index = 1, rungs do
		local y = index * (length / (rungs + 1))
		-- Two rungs are gone and one hangs by a single end. A ladder with every rung intact is a
		-- ladder somebody would still use.
		if index == 3 or index == 6 then
			continue
		end
		if index == 8 then
			part(
				model,
				"HangingRung",
				Vector3.new(gap, 0.17, 0.17),
				lean * CFrame.new(-0.15, y - 0.35, 0.05) * CFrame.Angles(0, math.rad(12), math.rad(-38)),
				timber(rng),
				p.timberMaterial,
				{ shape = Enum.PartType.Cylinder }
			)
			continue
		end
		part(
			model,
			"Rung",
			Vector3.new(gap * 1.02, 0.18, 0.18),
			lean * CFrame.new(0, y, 0) * skew(rng, 2),
			timber(rng),
			p.timberMaterial,
			{ shape = Enum.PartType.Cylinder }
		)
	end

	-- Rubble banked against the foot, so it reads as standing there rather than propped there today.
	spill(model, CFrame.new(0, 0, 0.3), 1.4, 9, rng)
	growth(model, lean * CFrame.new(-gap / 2, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.8, rng)
	growth(model, lean * CFrame.new(gap / 2, length * 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.7, rng)

	collider(model, Vector3.new(gap * 1.4, length * 0.95, 1), lean * CFrame.new(0, length * 0.47, 0))
	return CFrame.new(0, length * 0.4, 0)
end

-- 12. THE NOTICE. Two stakes driven at the rock with a warped board across them, hazard chevrons
-- flaked off it, and a rope run sagging between the stakes to close whatever this was closing.
--
-- IT CARRIES NO TEXT, AND THAT IS THE DESIGN RATHER THAN A SHORTCUT. A player meets this at candle
-- range in a cave with no ambient light, usually side-on and usually moving; a line of lettering is
-- unreadable in every one of those conditions and would be an instruction rather than an object.
-- Diagonal bars are the one warning mark that survives being three-quarters in shadow, and they say
-- the only thing this needs to say. It also means the piece never has to be translated, and never has
-- to decide what the mining company was called.
--
-- WHAT IT IS ACTUALLY FOR: every other relic describes the room it stands in. This one describes the
-- people who left it — somebody stopped, cut two stakes, and painted a board, and then the thing they
-- were warning about happened anyway. The rope is the half that sells it: a barrier nobody took down.
local function buildDangerSign(model: Model, rng: Random)
	local p = palette()
	local boardWidth, boardHeight = 3.1, 1.5
	local stakeGap, stakeHeight = 2.3, 3.1

	-- Leaning back onto the rock at +Z, the same convention every wall-anchored piece here uses: a
	-- board fixed flat to a cave wall reads as a texture instead of an object.
	local lean = CFrame.Angles(math.rad(11), rng:NextNumber(-0.13, 0.13), 0)

	-- One stake stands, the other is driven shorter and kicked out of plumb. Two matching stakes read
	-- as a fence somebody maintains.
	local stakeHeights = { stakeHeight, stakeHeight * 0.82 }
	for index, x in { -stakeGap / 2, stakeGap / 2 } do
		local thisHeight = stakeHeights[index]
		mass(
			model,
			"Stake",
			Vector3.new(0.3, thisHeight, 0.3 * rng:NextNumber(0.9, 1.1)),
			lean * CFrame.new(x, thisHeight / 2, 0) * CFrame.Angles(0, 0, math.rad(index * 4 - 6)),
			timber(rng),
			p.timberMaterial
		)
		part(
			model,
			"StakeHead",
			Vector3.new(0.24, 0.34, 0.24),
			lean * CFrame.new(x, thisHeight - 0.1, 0) * skew(rng, 11),
			p.timberSplitColor,
			p.timberMaterial
		)
	end

	-- THE BOARD, hung off the taller stake and dropped at the short end, so it sits visibly askew.
	-- Level, it reads as signage; tilted, it reads as signage nobody has straightened in a long time.
	local boardTilt = math.rad(rng:NextNumber(5, 9))
	local board = lean * CFrame.new(0, stakeHeight * 0.62, -0.22) * CFrame.Angles(0, 0, -boardTilt)
	mass(model, "SignBoard", Vector3.new(boardWidth, boardHeight, 0.15), board, timber(rng), p.timberMaterial)
	-- A second plank below the first, split off at one end and still on its nail. The gap between the
	-- two is what stops the sign reading as a single solid rectangle at distance.
	mass(
		model,
		"SignBoardLower",
		Vector3.new(boardWidth * 0.74, boardHeight * 0.42, 0.14),
		board * CFrame.new(-boardWidth * 0.08, -boardHeight * 0.78, 0.01) * CFrame.Angles(0, 0, math.rad(-13)),
		timber(rng),
		p.timberMaterial
	)

	-- THE CHEVRONS. Four diagonal bars laid proud of the board face at -Z (the room side), one of them
	-- missing and one cut short: paint on old timber flakes in patches, and an unbroken set of four
	-- would be the one clean, machined thing in this entire catalog.
	--
	-- CUT TO FIT THE BOARD IN BOTH AXES, which is not the same as cutting them to the board's height.
	-- A box rotated off vertical reaches `length/2*cos(lean) + width/2*sin(lean)` vertically and
	-- `length/2*sin(lean) + width/2*cos(lean)` sideways; sizing a bar at the board's own height ignores
	-- the bar's width and leaves paint hanging off the top and bottom edges with nothing behind it.
	-- Solving the first equation for length is the fix, and the second then sets how far apart the
	-- slots can be. `hazardPlate` in server/LobbyRoomBuilder does the identical sum for the hub's
	-- enamel plates.
	local bars, barLean = 4, math.rad(38)
	local barWidth = 0.34
	local barLength = (boardHeight - barWidth * math.sin(barLean)) / math.cos(barLean) * 0.98
	for index = 1, bars do
		if index == 3 then
			continue
		end
		local slot = (index - (bars + 1) / 2) * (boardWidth / (bars + 1.2))
		local shortened = if index == bars then rng:NextNumber(0.45, 0.62) else rng:NextNumber(0.88, 1)
		part(
			model,
			"HazardBar",
			Vector3.new(barWidth, barLength * shortened, 0.06),
			board * CFrame.new(slot, 0, -0.11) * CFrame.Angles(0, 0, barLean),
			p.paintColor,
			p.paintMaterial
		)
	end

	-- Two nail heads, because the board has to be attached to something the eye can find.
	for _, x in { -stakeGap / 2, stakeGap / 2 } do
		part(
			model,
			"Nail",
			Vector3.new(0.1, 0.1, 0.12),
			board * CFrame.new(x, boardHeight * 0.28, -0.1),
			p.fittingColor,
			p.fittingMaterial
		)
	end

	-- THE ROPE RUN, strung between the stakes below the board and sagging in the middle. Built as three
	-- straight segments walked down and back up rather than a curve, exactly the way the dynamite fuse
	-- is built: at candle range three angled segments read as a hanging line, and nothing here has the
	-- budget for a real catenary.
	local ropeSpan = stakeGap * 1.04
	local ropeY = stakeHeight * 0.3
	local sag = 0.34
	local ropePoints = {
		Vector3.new(-ropeSpan / 2, ropeY, 0),
		Vector3.new(-ropeSpan / 6, ropeY - sag, 0),
		Vector3.new(ropeSpan / 6, ropeY - sag * 0.92, 0),
		Vector3.new(ropeSpan / 2, ropeY + 0.05, 0),
	}
	for index = 1, #ropePoints - 1 do
		local from, to = ropePoints[index], ropePoints[index + 1]
		local delta = to - from
		part(
			model,
			"RopeRun",
			Vector3.new(0.11, 0.11, delta.Magnitude),
			lean * CFrame.lookAt((from + to) / 2, to),
			p.ropeColor,
			p.ropeMaterial,
			{ shape = Enum.PartType.Cylinder }
		)
	end

	-- A cairn of loose rock heaped round the feet of the stakes: this was driven into a cave floor,
	-- not planted in soil, and the heap is how anybody actually makes a stake stand in rock.
	for index = 1, 5 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local size = rng:NextNumber(0.34, 0.62)
		part(
			model,
			"CairnRock",
			Vector3.new(size, size * rng:NextNumber(0.5, 0.8), size * rng:NextNumber(0.7, 1.1)),
			CFrame.new(
				math.cos(angle) * rng:NextNumber(0.5, 1.3),
				size * 0.3,
				math.sin(angle) * rng:NextNumber(0.3, 0.8) - 0.1
			)
				* skew(rng, 22)
				* CFrame.Angles(0, index * 0.9, 0),
			spoilColor(rng),
			p.spoilMaterial
		)
	end
	spill(model, CFrame.new(0, 0, -0.5), 1.5, 7, rng)

	growth(model, board * CFrame.new(boardWidth * 0.3, -boardHeight * 0.45, -0.09), 0.8, rng)
	growth(
		model,
		lean * CFrame.new(-stakeGap / 2, stakeHeight * 0.5, -0.15) * CFrame.Angles(0, 0, math.rad(90)),
		0.7,
		rng
	)
	growth(model, CFrame.new(1, 0.08, -0.9), 0.9, rng)

	collider(model, Vector3.new(stakeGap + 0.6, stakeHeight, 0.9), CFrame.new(0, stakeHeight / 2, 0))
	return CFrame.new(0, stakeHeight * 0.62, 0)
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

-- Each builder returns its own acoustic centre in model space, because "where the mass of this
-- thing is" is a property of the silhouette and nowhere else knows it.
type Builder = (Model, Random) -> CFrame

local BUILDERS: { [string]: Builder } = {
	Minecart = buildMinecart,
	RailRun = buildRailRun,
	BufferStop = buildBufferStop,
	PitProps = buildPitProps,
	SupplyCrates = buildSupplyCrates,
	PowderKegs = buildPowderKegs,
	Windlass = buildWindlass,
	LanternPost = buildLanternPost,
	Wheelbarrow = buildWheelbarrow,
	ToolRack = buildToolRack,
	Ladder = buildLadder,
	DangerSign = buildDangerSign,
}

function MineRelics.hasBuilder(relicId: string): boolean
	return BUILDERS[relicId] ~= nil
end

-- Every id the module can actually build. `Tests/MineRelicRulesTests` compares this against the
-- catalog, so a config row with no silhouette behind it fails a test rather than silently placing
-- an empty model in somebody's cave.
function MineRelics.builtIds(): { string }
	local ids: { string } = {}
	for id in BUILDERS do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- `at` is the piece's ground contact, already seated and oriented by the caller: +Y is up out of the
-- floor and the LookVector is the direction the piece faces (for a wall piece, back into the room).
function MineRelics.build(parent: Instance, relicId: string, at: CFrame, seed: number): Model?
	local builder = BUILDERS[relicId]
	if builder == nil then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "MineRelic_" .. relicId

	local rng = Random.new(seed)
	local acousticCentre = builder(model, rng)

	-- An invisible anchor at the contact point. Doubles as PrimaryPart, so a caller pivots the model
	-- by its ground contact rather than by a bounding box that leans.
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new()
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = model
	model.PrimaryPart = anchor

	local emitter = Instance.new("Attachment")
	emitter.Name = MineRelicVisualProtocol.emitterName
	emitter.CFrame = acousticCentre
	emitter.Parent = anchor

	model.Parent = parent
	model:PivotTo(at)
	CollectionService:AddTag(model, MineRelicVisualProtocol.tag)
	return model
end

return MineRelics
