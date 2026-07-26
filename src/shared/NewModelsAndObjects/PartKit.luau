--!strict
-- PartKit — primitives, joints, hitboxes and sound rigs for procedural creatures.
-- Place at: ReplicatedStorage/Creatures/PartKit
--
-- Darkness notes:
--   * Chitin is Slate/Pebble, not SmoothPlastic. Both carry normal detail that
--     catches grazing light at the edge of a flame — free surface interest.
--   * Base colours sit just above black so falloff resolves an edge instead of
--     a void. Pure black (0,0,0) renders as nothing and reads as a hole.
--   * Neon ignores lighting entirely. It is the only thing visible in true
--     darkness, so it is the creature's entire long-range silhouette. Use it
--     sparingly and deliberately.

local PartKit = {}

export type PartOptions = {
	name: string?,
	size: Vector3,
	shape: Enum.PartType?,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	castShadow: boolean?,
}

export type Joint = {
	motor: Motor6D,
	base: CFrame,
}

export type Emitter = {
	sound: Sound,
	attachment: Attachment,
}

local DEFAULT_COLOR = Color3.fromRGB(19, 20, 25)

function PartKit.part(parent: Instance, opts: PartOptions): BasePart
	local p = Instance.new("Part")
	p.Name = opts.name or "Segment"
	p.Size = opts.size
	p.Shape = opts.shape or Enum.PartType.Block
	p.Color = opts.color or DEFAULT_COLOR
	p.Material = opts.material or Enum.Material.Slate
	p.Transparency = opts.transparency or 0
	p.Reflectance = opts.reflectance or 0
	p.CastShadow = if opts.castShadow ~= nil then opts.castShadow else true
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- True ellipsoid. A Ball part is ALWAYS a perfect sphere in Roblox: it takes the
-- smallest axis of Size and throws the other two away, so a 0.92 x 0.80 x 0.54
-- "ribcage" renders as a 0.54 marble. Anything egg-shaped — torso, skull, jaw,
-- hand, foot — has to be a Block carrying a Sphere SpecialMesh, which does scale
-- on all three axes.
function PartKit.ellipsoid(parent: Instance, opts: PartOptions): BasePart
	local p = PartKit.part(parent, opts)
	p.Shape = Enum.PartType.Block
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.one
	mesh.Parent = p
	return p
end

-- Self-illuminating accent. Never casts shadow (pointless and costly).
function PartKit.neon(parent: Instance, opts: PartOptions): BasePart
	local p = PartKit.part(parent, opts)
	p.Material = Enum.Material.Neon
	p.CastShadow = false
	return p
end

function PartKit.joint(part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame?): Joint
	local m = Instance.new("Motor6D")
	m.Name = part1.Name .. "Joint"
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1 or CFrame.new()
	m.Parent = part0
	return { motor = m, base = c0 }
end

function PartKit.pose(joint: Joint, rotation: CFrame)
	joint.motor.C0 = joint.base * rotation
end

-- Limb segment pivoting at its near end, extending along -Z.
function PartKit.segment(parent: Instance, name: string, length: number, thickness: number, color: Color3): BasePart
	return PartKit.part(parent, {
		name = name,
		size = Vector3.new(thickness, thickness, length),
		color = color,
	})
end

function PartKit.segmentPivot(length: number): CFrame
	return CFrame.new(0, 0, length / 2)
end

-- Round limb segment. A Cylinder's axis is local X, so the pivot bakes in a 90
-- degree yaw to lay it along the joint's -Z. Pair with a sphere at each joint of
-- the same diameter and a chain of these reads as one smooth capsule limb
-- rather than a stack of boxes.
function PartKit.tube(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	castShadow: boolean?
): BasePart
	return PartKit.part(parent, {
		name = name,
		size = Vector3.new(length, diameter, diameter),
		shape = Enum.PartType.Cylinder,
		color = color,
		material = material,
		castShadow = castShadow,
	})
end

function PartKit.tubePivot(length: number): CFrame
	return CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(0, 0, length / 2)
end

-- Where the NEXT joint in a limb chain goes. tubePivot grabs a tube at its local
-- -X end and runs the body out to +X, so the far tip is at +length/2, and the
-- child joint has to be yawed -90 for its own -Z (the direction a tubePivot child
-- extends in) to continue down the limb. Chaining at -length/2, or yawing +90,
-- folds the next segment back up over its parent — a shin that grows out of the
-- hip rather than the knee.
function PartKit.tubeTip(length: number): CFrame
	return CFrame.new(length / 2, 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
end

-- The only part your game should raycast or region-query against. Everything
-- else has CanQuery off so limb geometry never eats a hit.
function PartKit.hitbox(model: Model, root: BasePart, size: Vector3, offset: CFrame?): BasePart
	local h = Instance.new("Part")
	h.Name = "Hitbox"
	h.Size = size
	h.Transparency = 1
	h.CanCollide = false
	h.CanQuery = true
	h.CanTouch = true
	h.CastShadow = false
	h.Anchored = false
	h.Massless = true
	h.Parent = model

	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = h
	w.C0 = offset or CFrame.new()
	w.Parent = h

	return h
end

-- 3D sound rig. Distances are tuned for a game where you cannot see far:
-- audio has to arrive well before the creature does.
function PartKit.emitter(
	parent: BasePart,
	assetId: string,
	opts: {
		volume: number?,
		minDistance: number?,
		maxDistance: number?,
		looped: boolean?,
		name: string?,
	}?
): Emitter
	local o = opts or {}
	local a = Instance.new("Attachment")
	a.Name = (o.name or "Emitter") .. "Point"
	a.Parent = parent

	local s = Instance.new("Sound")
	s.Name = o.name or "Emitter"
	s.SoundId = assetId
	s.Volume = o.volume or 0.5
	s.Looped = o.looped or false
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = o.minDistance or 8
	s.RollOffMaxDistance = o.maxDistance or 70
	s.Parent = a

	return { sound = s, attachment = a }
end

function PartKit.finalise(model: Model, root: BasePart, anchored: boolean)
	model.PrimaryPart = root
	root.Anchored = anchored
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
		end
	end
end

-- Cheap linear blend for illumination-driven colour shifts.
function PartKit.lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

return PartKit
