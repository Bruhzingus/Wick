--!strict
-- CREATURE DRESSING — the geometry a cave family adds to a creature body.
-- Place at: ReplicatedStorage/Creatures/CreatureDressing
--
-- ONE BUILDER, FIVE BODIES, THREE FAMILIES. A body says WHERE it collects things (its anchors); the
-- family says WHAT has taken hold there (Config/CaveFamilies.presentation.creatures, resolved by
-- Logic/CaveFamilyRules.creatureDressing). Neither knows anything about the other, which is why the
-- Moss crawler, the Ice moth and the Ice Warden are all this one file.
--
-- WHAT THIS MAY BUILD, and the list is deliberately short:
--
--   * SHAG — short wet tufts, plus a few strands long enough to hang and sway on the gait. Built as
--     tapered cylinders splayed around the anchor's own normal, so growth follows the limb rather
--     than sticking out of it at a right angle like a pin cushion.
--   * RIME — flattened frost plates crusted onto UPWARD-FACING surfaces only, plus occasional thin
--     spurs. The upward-face rule is what makes it read as frost that settled rather than paint.
--   * NONE — nothing at all. Not a no-op wrapper around an empty loop: the function returns before
--     it allocates anything, so a Stone body is exactly the body it was before this file existed.
--
-- WHAT IT MAY NEVER TOUCH. It only ever ADDS parts; it never moves, resizes, recolours or removes
-- one that was already there. The skeleton, the proportions, the joints, the animation, the
-- silhouette category, the crimson dark-hunter eye slits and the Drawn's wings and warm halo are the
-- same in every family, because those are what a player reads a threat by in the dark. A body passes
-- only the anchors it is willing to have dressed, and never one on the head.
--
-- EVERY PART IS COSMETIC. Nothing here collides, queries, touches, or carries mass — the caller's own
-- presentation pass would strip those anyway, but a dressing part must never be the reason a body
-- starts interacting with the world.

local PartKit = require(script.Parent.PartKit)

local CreatureDressing = {}

-- Where a body is willing to collect growth. `part` is what the feature attaches to, `normal` is the
-- outward direction in that part's LOCAL space, and `scale` lets a body ask for smaller features on
-- its smaller limbs without the family having to know which limb is which.
export type Anchor = {
	part: BasePart,
	normal: Vector3,
	scale: number,
	-- Does this surface FACE UP when the body is standing? Declared by the body rather than inferred
	-- from the normal, because a limb's local axes have been rotated by its own joint chain and the
	-- local +Y of a thigh is not up. Rime only settles on surfaces flagged here; shag ignores it.
	upward: boolean?,
	-- Set on the handful of anchors a body is happy to see something HANG from — shoulders and
	-- forearms, not feet. Becomes a swaying strand under shag and an icicle spur under rime.
	allowStrand: boolean?,
}

export type Dressing = {
	growthStyle: string,
	growthCoverage: number,
	growthSize: number,
	growthPalette: { Color3 },
	growthMaterial: Enum.Material,
	skinMaterial: Enum.Material?,
	headExclusion: boolean,
}

-- Deterministic per body. A dressed creature has to look the same to every client that builds it and
-- the same after it is culled and rebuilt, so the caller passes a seed rather than this file reaching
-- for a shared RNG.
local function paletteColor(palette: { Color3 }, rng: Random): Color3
	if #palette == 0 then
		return Color3.fromRGB(20, 20, 20)
	end
	return palette[rng:NextInteger(1, #palette)]
end

-- Dressing parts go BESIDE their anchor in the model, never inside it. A BasePart parented to another
-- BasePart renders fine, but it puts geometry somewhere every `GetDescendants` sweep in the codebase
-- has to walk into to find — and the presentation and finalise passes both do exactly that.
local function hostFor(anchor: BasePart): Instance
	return anchor.Parent or anchor
end

-- A frame on the anchor's surface, facing out along its normal. Used by both styles so a tuft and a
-- frost plate sit on a limb the same way.
local function surfaceFrame(anchor: Anchor, spread: number, rng: Random): CFrame
	local normal = if anchor.normal.Magnitude > 1e-4 then anchor.normal.Unit else Vector3.yAxis
	local reference = if math.abs(normal.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
	local tangent = normal:Cross(reference).Unit
	local bitangent = normal:Cross(tangent).Unit
	local size = anchor.part.Size
	-- Scatter across the face rather than stacking on its centre. Kept inside the part's own extent so
	-- a feature never floats off the end of a limb.
	local offset = tangent * (rng:NextNumber(-0.5, 0.5) * size.X * 0.6)
		+ bitangent * (rng:NextNumber(-0.5, 0.5) * size.Z * 0.6)
	local jitter = tangent * rng:NextNumber(-spread, spread) + bitangent * rng:NextNumber(-spread, spread)
	local direction = (normal + jitter).Unit
	local origin = offset + normal * (math.min(size.X, size.Y, size.Z) * 0.42)
	return CFrame.lookAt(origin, origin + direction, reference)
end

-- Jointed with a Motor6D exactly like every other part of these bodies, rather than welded in world
-- space. A dressing part is built before the model has been positioned or parented, so its anchor's
-- world CFrame is not meaningful yet — an offset in the anchor's OWN space is the only thing that is.
local function attach(anchor: BasePart, piece: BasePart, frame: CFrame)
	PartKit.joint(anchor, piece, frame)
end

local function cosmetic(piece: BasePart)
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.CastShadow = false
end

-- SHAG. Short tufts, and on the anchors that allow it, the occasional long strand. The strand is the
-- one piece of this whose job is motion rather than texture: it hangs past the limb it grows on, so a
-- Moss body's movement is legible slightly before its outline is.
local function buildShag(anchor: Anchor, dressing: Dressing, rng: Random)
	local tufts = rng:NextInteger(2, 4)
	for _ = 1, tufts do
		local length = rng:NextNumber(0.16, 0.34) * dressing.growthSize * anchor.scale
		local thickness = rng:NextNumber(0.045, 0.085) * dressing.growthSize * anchor.scale
		local piece = PartKit.tube(
			hostFor(anchor.part),
			"Growth",
			length,
			thickness,
			paletteColor(dressing.growthPalette, rng),
			dressing.growthMaterial,
			false
		)
		cosmetic(piece)
		attach(anchor.part, piece, surfaceFrame(anchor, 0.5, rng) * PartKit.tubePivot(length))
	end

	if anchor.allowStrand == true and rng:NextNumber() < 0.45 then
		local length = rng:NextNumber(0.55, 0.95) * dressing.growthSize * anchor.scale
		local strand = PartKit.tube(
			hostFor(anchor.part),
			"GrowthStrand",
			length,
			0.05 * dressing.growthSize * anchor.scale,
			paletteColor(dressing.growthPalette, rng),
			dressing.growthMaterial,
			false
		)
		cosmetic(strand)
		-- Hung DOWNWARD from the anchor rather than out along its normal: a strand that stuck straight
		-- out of a shoulder reads as a spike, and the whole point of this piece is that it dangles.
		local origin = anchor.normal.Unit * (anchor.part.Size.Y * 0.3)
		attach(
			anchor.part,
			strand,
			CFrame.lookAt(origin, origin - Vector3.yAxis, Vector3.zAxis) * PartKit.tubePivot(length)
		)
	end
end

-- RIME. Flattened plates, and only where frost could actually have settled. An anchor whose normal
-- points down or sideways is skipped outright rather than dressed more thinly — that refusal is what
-- sells it as weather instead of decoration.
local function buildRime(anchor: Anchor, dressing: Dressing, rng: Random)
	if anchor.upward ~= true then
		return
	end
	local normal = if anchor.normal.Magnitude > 1e-4 then anchor.normal.Unit else Vector3.yAxis

	local plates = rng:NextInteger(1, 3)
	for _ = 1, plates do
		local width = rng:NextNumber(0.18, 0.36) * dressing.growthSize * anchor.scale
		local piece = PartKit.ellipsoid(hostFor(anchor.part), {
			name = "Rime",
			size = Vector3.new(width, width * rng:NextNumber(0.22, 0.4), width * rng:NextNumber(0.7, 1.1)),
			color = paletteColor(dressing.growthPalette, rng),
			material = dressing.growthMaterial,
			castShadow = false,
		})
		cosmetic(piece)
		attach(anchor.part, piece, surfaceFrame(anchor, 0.22, rng))
	end

	-- A thin spur, on the anchors a body flagged for hanging growth. In Ice these are what catch the
	-- flame as a limb swings — the same anchors, the same timing, an entirely different read.
	if anchor.allowStrand == true and rng:NextNumber() < 0.5 then
		local length = rng:NextNumber(0.3, 0.6) * dressing.growthSize * anchor.scale
		local spur = PartKit.tube(
			hostFor(anchor.part),
			"RimeSpur",
			length,
			0.06 * dressing.growthSize * anchor.scale,
			paletteColor(dressing.growthPalette, rng),
			dressing.growthMaterial,
			false
		)
		cosmetic(spur)
		local origin = normal * (anchor.part.Size.Y * 0.28)
		attach(
			anchor.part,
			spur,
			CFrame.lookAt(origin, origin - Vector3.yAxis, Vector3.zAxis) * PartKit.tubePivot(length)
		)
	end
end

-- Dress a body. Returns immediately for a family that grows nothing, so Stone pays nothing at all —
-- not a loop that builds zero parts, but no allocation and no RNG draw.
function CreatureDressing.apply(dressing: Dressing, anchors: { Anchor }, seed: number)
	if dressing.growthStyle == "None" or dressing.growthCoverage <= 0 or #dressing.growthPalette == 0 then
		return
	end
	local rng = Random.new(seed)
	for _, anchor in anchors do
		if rng:NextNumber() > dressing.growthCoverage then
			continue
		end
		if dressing.growthStyle == "Shag" then
			buildShag(anchor, dressing, rng)
		elseif dressing.growthStyle == "Rime" then
			buildRime(anchor, dressing, rng)
		end
	end
end

-- The family's skin material, where it has an opinion. Applied only to parts a body nominates, never
-- swept across the whole model: eyes, wings and any other readable feature carry their own material
-- for a reason and must not be caught by a family-wide pass.
function CreatureDressing.applySkinMaterial(dressing: Dressing, parts: { BasePart })
	local material = dressing.skinMaterial
	if material == nil then
		return
	end
	for _, part in parts do
		part.Material = material
	end
end

return CreatureDressing
