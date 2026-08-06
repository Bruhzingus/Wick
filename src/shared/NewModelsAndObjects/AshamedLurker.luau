--!strict
-- AshamedLurker — the arch creature's body. Built locally by client/AshamedLurkerController around
-- the server's invisible proxy; it holds no gameplay state and decides nothing. All geometry is
-- derived from the doorway it occupies (width, height, which half is trapped) so one builder covers
-- every arch the planner can pick.
--
-- It is a small, starved humanoid, not a rock pile: ash-grey flesh, exposed rib rods, pale finger
-- bones, and a long jaw. Only the wall socket and the back plates imitate cave stone, which is what
-- lets it disappear against the springer until a flame is close enough to resolve the body.
--
-- The face fissure is non-emissive black negative space. It never glows: the creature is read by
-- silhouette, not by eyes in the dark.
--
-- Poses are non-compounding. Every joint keeps its build-time C0 in PartKit.Joint.base and each
-- frame re-derives the target from that base, so a state that is entered twice looks identical.

local PartKit = require(script.Parent.PartKit)
local Config = require(script.Parent.Parent.Config.AshamedLurker)
local Rules = require(script.Parent.Parent.Logic.AshamedLurkerRules)
local Protocol = require(script.Parent.Parent.AshamedLurkerVisualProtocol)

local AshamedLurker = {}
AshamedLurker.__index = AshamedLurker

export type BuildOptions = {
	doorWidth: number,
	doorHeight: number,
	trapSide: Rules.TrapSide,
	seed: number?,
	-- THE ROCK THIS CREATURE IS PRETENDING TO BE. Its whole premise is that the wall socket and the
	-- back plates disappear into the springer until a flame is close enough to resolve the body in
	-- front of them — so they have to be the rock of the cave it is actually standing in.
	--
	-- These were hardcoded to Stone's slate, with a comment saying they were matched to the wall. They
	-- were: to STONE's wall. In Moss and Ice the plates were visibly grey slate set into green-grey rock
	-- or packed glacier, which handed those two families a free tell the creature was never designed to
	-- give and left the ambush working in exactly one cave of three.
	--
	-- The FLESH is deliberately not here. Skin, bone and the black face fissure are identical in every
	-- family: this is one creature that hides against different walls, not three creatures.
	rockColor: Color3?,
	rockLightColor: Color3?,
	rockMaterial: Enum.Material?,
}

type Rig = {
	hub: PartKit.Joint,
	chest: PartKit.Joint,
	neck: PartKit.Joint,
	head: PartKit.Joint,
	jaw: PartKit.Joint,
	fissure: PartKit.Joint,
	armShoulder: PartKit.Joint,
	armElbow: PartKit.Joint,
	armWrist: PartKit.Joint,
	wallShoulder: PartKit.Joint,
	wallElbow: PartKit.Joint,
	wallWrist: PartKit.Joint,
	fingers: { PartKit.Joint },
}

export type Lurker = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		rig: Rig,
		side: number,
		lungeStuds: number,
		t: number,
		state: string,
		stateAge: number,
		rng: Random,
		fadeParts: { BasePart },
	},
	AshamedLurker
))

local SKIN_MATERIAL = Enum.Material.Slate
local BONE_MATERIAL = Enum.Material.Concrete
local ROCK_MATERIAL = Enum.Material.Slate

-- A bone's frame: centred between two points with its long (cylinder) axis running a -> b. The up
-- hint keeps CFrame.lookAt from degenerating on a vertical limb.
local function boneFrame(a: Vector3, b: Vector3): CFrame
	local delta = b - a
	if delta.Magnitude < 1e-4 then
		return CFrame.new(a)
	end
	local up = if math.abs(delta.Unit.Y) > 0.99 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
	return CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0)
end

local function smoothstep(alpha: number): number
	local clamped = math.clamp(alpha, 0, 1)
	return clamped * clamped * (3 - 2 * clamped)
end

-- Slow gathering followed by a sharp commitment. This is intentionally not the recovery curve:
-- reversing the same easing would make the creature read like a hinged prop.
local function easeInCubic(alpha: number): number
	local clamped = math.clamp(alpha, 0, 1)
	return clamped * clamped * clamped
end

local function rangeAlpha(value: number, startAt: number, endAt: number): number
	if endAt <= startAt then
		return if value >= endAt then 1 else 0
	end
	return math.clamp((value - startAt) / (endAt - startAt), 0, 1)
end

local function commitAmount(windupAlpha: number, leadFraction: number): number
	return easeInCubic(rangeAlpha(windupAlpha, leadFraction, 1))
end

local function recoveryAmount(recoveryAlpha: number, recoveryStartFraction: number): number
	return 1 - smoothstep(rangeAlpha(recoveryAlpha, recoveryStartFraction, 1))
end

local function pulse(alpha: number): number
	local clamped = math.clamp(alpha, 0, 1)
	if clamped <= 0 or clamped >= 1 then
		return 0
	end
	return math.sin(clamped * math.pi)
end

function AshamedLurker.build(parent: Instance, options: BuildOptions): Lurker
	local visual = Config.visual
	local placement = Config.placement
	-- Falls back to the config's own colours when a caller has no family in hand, so this body still
	-- builds correctly outside an expedition and in any tool that renders it standalone.
	local rockColor = options.rockColor or visual.rock
	local rockLightColor = options.rockLightColor or visual.rockLight
	local rockMaterial = options.rockMaterial or ROCK_MATERIAL
	local width = options.doorWidth
	local height = options.doorHeight
	local side = Rules.sideSign(options.trapSide)
	local rng = Random.new(options.seed or 1)

	local model = Instance.new("Model")
	model.Name = "AshamedLurkerBody"

	-- Root: the doorway's floor centre. The controller pins it to the server proxy every frame.
	local root = Instance.new("Part")
	root.Name = "LurkerRoot"
	root.Size = Vector3.one * 0.4
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model

	-- Everything below is laid out in root-local space and linked by frames, so the whole body can be
	-- described by the points it passes through rather than by a stack of relative rotations.
	local frames: { [BasePart]: CFrame } = { [root] = CFrame.new() }
	local function link(parentPart: BasePart, child: BasePart, childFrame: CFrame): PartKit.Joint
		local parentFrame = frames[parentPart] or CFrame.new()
		frames[child] = childFrame
		return PartKit.joint(parentPart, child, parentFrame:Inverse() * childFrame)
	end
	local function blob(name: string, size: Vector3, color: Color3, material: Enum.Material?): BasePart
		return PartKit.ellipsoid(
			model,
			{ name = name, size = size, color = color, material = material or SKIN_MATERIAL }
		)
	end
	local function bone(
		name: string,
		a: Vector3,
		b: Vector3,
		diameter: number,
		color: Color3,
		material: Enum.Material?
	): (BasePart, CFrame)
		local part = PartKit.tube(model, name, (b - a).Magnitude, diameter, color, material or SKIN_MATERIAL, false)
		return part, boneFrame(a, b)
	end

	local edgeX = width / 2 - placement.edgeInset
	-- The RESTING arm, which is shorter than what the creature can actually reach when it lunges.
	-- The silhouette is meant to under-sell the danger, not advertise its full range.
	local reach = Rules.restArmReach(width)
	local laneInner = edgeX - reach
	-- The same function the server validates a stare against, evaluated in root-local space: the
	-- head a player sees and the point the server checks can never drift apart.
	local facePosition = Rules.facePosition(CFrame.identity, width, height, options.trapSide)

	-- Wall socket: the only genuinely rock-like mass, welded to the arch rather than the creature, so
	-- the retreat animation leaves the stone behind.
	local socket = blob("WallSocket", Vector3.new(2.3, 3.0, 2.0), rockColor, rockMaterial)
	link(root, socket, CFrame.new(side * (edgeX + 0.55), facePosition.Y + 0.2, 0.5))
	for index = 1, 3 do
		local plate = PartKit.part(model, {
			name = "SocketPlate" .. index,
			size = Vector3.new(0.5, rng:NextNumber(0.9, 1.5), rng:NextNumber(0.8, 1.3)),
			color = if index % 2 == 0 then rockColor else rockLightColor,
			material = rockMaterial,
		})
		link(
			socket,
			plate,
			CFrame.new(side * (edgeX + 0.1), facePosition.Y + rng:NextNumber(-1.1, 1.3), rng:NextNumber(-0.5, 1.2))
				* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.5, 0.5))
		)
	end

	-- Hub: the single joint the lunge and the retreat both drive.
	local hub = PartKit.part(model, {
		name = "Hub",
		size = Vector3.one * 0.3,
		transparency = 1,
		castShadow = false,
	})
	local hubFrame = CFrame.new(side * (edgeX - 0.25), facePosition.Y + 0.15, 0.35)
	local hubJoint = link(root, hub, hubFrame)

	local chestPosition = facePosition + Vector3.new(side * 0.72, -0.62, 0.28)
	local chest = blob("Chest", Vector3.new(1.05, 1.0, 0.78), visual.skinPale)
	local chestJoint = link(hub, chest, CFrame.new(chestPosition) * CFrame.Angles(0, 0, math.rad(-12 * side)))

	local abdomen = blob("Abdomen", Vector3.new(0.66, 0.72, 0.6), visual.skin)
	link(chest, abdomen, CFrame.new(chestPosition + Vector3.new(side * 0.14, -0.82, 0.06)))

	local pelvis = blob("Pelvis", Vector3.new(0.8, 0.6, 0.68), visual.skin)
	local pelvisPosition = chestPosition + Vector3.new(side * 0.24, -1.5, 0.1)
	link(abdomen, pelvis, CFrame.new(pelvisPosition))

	-- Rib rods ride the chest's front (the side the head faces), so they read as ridges under skin.
	for index = 1, 4 do
		local y = 0.3 - (index - 1) * 0.19
		local ribPart, ribFrame = bone(
			"Rib" .. index,
			chestPosition + Vector3.new(-side * 0.3, y, -0.34),
			chestPosition + Vector3.new(-side * 0.3, y - 0.06, 0.34),
			0.07,
			visual.bone,
			BONE_MATERIAL
		)
		link(chest, ribPart, ribFrame)
	end
	local sternumPart, sternumFrame = bone(
		"Sternum",
		chestPosition + Vector3.new(-side * 0.36, 0.38, 0),
		chestPosition + Vector3.new(-side * 0.36, -0.34, 0),
		0.08,
		visual.boneDark,
		BONE_MATERIAL
	)
	link(chest, sternumPart, sternumFrame)

	-- Back plates: stone against the arch, flesh against the doorway. From the far side this is the
	-- silhouette that reads before anything else resolves.
	for index = 1, 3 do
		local plate = PartKit.part(model, {
			name = "BackPlate" .. index,
			size = Vector3.new(0.34, 0.62, 0.5),
			color = if index % 2 == 0 then rockLightColor else rockColor,
			material = rockMaterial,
		})
		link(
			chest,
			plate,
			CFrame.new(chestPosition + Vector3.new(side * 0.46, 0.34 - index * 0.34, 0.06))
				* CFrame.Angles(0, 0, math.rad(side * (18 + index * 9)))
		)
	end

	local neckPosition = chestPosition + Vector3.new(-side * 0.24, 0.62, -0.08)
	local neck = blob("Neck", Vector3.new(0.3, 0.42, 0.3), visual.skin)
	local neckJoint = link(chest, neck, CFrame.new(neckPosition))

	-- The head faces ACROSS the opening (toward the open lane), which is what makes the face legible
	-- from both approaches while a player stands in the safe half.
	local headFrame = CFrame.lookAt(facePosition, facePosition + Vector3.new(-side, -0.18, 0))
	local head = blob("Head", Vector3.new(0.62, 0.72, 1.05), visual.skinPale)
	local headJoint = link(neck, head, headFrame)

	local jaw = blob("Jaw", Vector3.new(0.5, 0.24, 0.86), visual.skin)
	local jawJoint = link(head, jaw, headFrame * CFrame.new(0, -0.3, -0.24))

	local fissure = PartKit.part(model, {
		name = "FaceFissure",
		size = Vector3.new(0.07, 0.56, 0.1),
		color = visual.void,
		material = Enum.Material.SmoothPlastic,
		castShadow = false,
	})
	local fissureJoint = link(head, fissure, headFrame * CFrame.new(0, 0.06, -0.48))

	for _, spurSide in { -1, 1 } do
		local spurPart, spurFrame = bone(
			"Spur" .. (if spurSide < 0 then "L" else "R"),
			facePosition + Vector3.new(side * 0.12, 0.3, spurSide * 0.2),
			facePosition + Vector3.new(side * 0.62, 0.72, spurSide * 0.34),
			0.1,
			visual.boneDark,
			BONE_MATERIAL
		)
		link(head, spurPart, spurFrame)
	end

	-- The trip arm. It hangs from the shoulder diagonally across the trap lane and stops short of the
	-- centre line; Rules.restArmReach already guaranteed it cannot cross into the open lane.
	local shoulderPosition = chestPosition + Vector3.new(-side * 0.5, 0.28, 0.02)
	local handPosition = Vector3.new(side * (laneInner + 0.55), 1.45, 0)
	local elbowPosition = shoulderPosition:Lerp(handPosition, 0.46) + Vector3.new(side * 0.45, 0.35, -0.3)

	local shoulder = blob("ArmShoulder", Vector3.new(0.4, 0.4, 0.4), visual.skinPale)
	local armShoulderJoint = link(chest, shoulder, CFrame.new(shoulderPosition))
	local upperPart, upperFrame = bone("UpperArm", shoulderPosition, elbowPosition, 0.3, visual.skin)
	link(shoulder, upperPart, upperFrame)
	local elbow = blob("ArmElbow", Vector3.new(0.28, 0.28, 0.28), visual.boneDark, BONE_MATERIAL)
	local armElbowJoint = link(upperPart, elbow, CFrame.new(elbowPosition))
	local forearmPart, forearmFrame = bone("Forearm", elbowPosition, handPosition, 0.22, visual.skinPale)
	link(elbow, forearmPart, forearmFrame)
	local hand = blob("Hand", Vector3.new(0.3, 0.2, 0.46), visual.bone, BONE_MATERIAL)
	local armWristJoint = link(forearmPart, hand, CFrame.new(handPosition))

	local fingers: { PartKit.Joint } = {}
	for index = -1, 1 do
		local tip = handPosition + Vector3.new(-side * 0.62, -0.34, index * 0.22)
		local fingerPart, fingerFrame =
			bone("Finger" .. (index + 2), handPosition, tip, 0.08, visual.bone, BONE_MATERIAL)
		table.insert(fingers, link(hand, fingerPart, fingerFrame))
	end

	-- The clinging arm wraps the springer. It keeps the torso pulled against the arch and gives the
	-- shame animation a second hand to cover the face with.
	local wallShoulderPosition = chestPosition + Vector3.new(side * 0.46, 0.26, 0.12)
	local wallElbowPosition = Vector3.new(side * (edgeX - 0.05), facePosition.Y + 0.55, 0.55)
	local wallHandPosition = Vector3.new(side * (edgeX + 0.35), facePosition.Y + 1.4, 0.35)

	local wallShoulder = blob("WallShoulder", Vector3.new(0.36, 0.36, 0.36), visual.skinPale)
	local wallShoulderJoint = link(chest, wallShoulder, CFrame.new(wallShoulderPosition))
	local wallUpperPart, wallUpperFrame =
		bone("WallUpperArm", wallShoulderPosition, wallElbowPosition, 0.26, visual.skin)
	link(wallShoulder, wallUpperPart, wallUpperFrame)
	local wallElbow = blob("WallElbow", Vector3.new(0.24, 0.24, 0.24), visual.boneDark, BONE_MATERIAL)
	local wallElbowJoint = link(wallUpperPart, wallElbow, CFrame.new(wallElbowPosition))
	local wallForearmPart, wallForearmFrame =
		bone("WallForearm", wallElbowPosition, wallHandPosition, 0.2, visual.skinPale)
	link(wallElbow, wallForearmPart, wallForearmFrame)
	local wallHand = blob("WallHand", Vector3.new(0.26, 0.18, 0.4), visual.boneDark, BONE_MATERIAL)
	local wallWristJoint = link(wallForearmPart, wallHand, CFrame.new(wallHandPosition))

	-- Legs are folded, not standing. It hangs off the arch; nothing bears its weight.
	for _, legSide in { -1, 1 } do
		local hip = pelvisPosition + Vector3.new(0, -0.16, legSide * 0.24)
		local knee = hip + Vector3.new(-side * 0.62, -0.6, legSide * 0.24)
		local ankle = knee + Vector3.new(side * 0.3, -0.86, -legSide * 0.06)
		local name = if legSide < 0 then "Left" else "Right"
		local thighPart, thighFrame = bone(name .. "Thigh", hip, knee, 0.26, visual.skin)
		link(pelvis, thighPart, thighFrame)
		local shinPart, shinFrame = bone(name .. "Shin", knee, ankle, 0.18, visual.skinPale)
		link(thighPart, shinPart, shinFrame)
		local foot = blob(name .. "Foot", Vector3.new(0.22, 0.16, 0.44), visual.boneDark, BONE_MATERIAL)
		link(shinPart, foot, CFrame.new(ankle + Vector3.new(-side * 0.1, -0.06, 0)))
	end

	-- Cache the parts that retreat into the socket. No descendant scans or table allocation happen in
	-- RenderStepped, and every local presentation part is massless as well as collision/query/touch
	-- neutral. The socket itself remains visible while the flesh withdraws, then disappears with the
	-- whole client body when the authoritative state becomes Hidden.
	local fadeParts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Massless = true
			local isSocket = descendant == socket or string.sub(descendant.Name, 1, 11) == "SocketPlate"
			if descendant ~= root and descendant ~= hub and not isSocket then
				table.insert(fadeParts, descendant)
			end
		end
	end

	PartKit.finalise(model, root, true)
	model.Parent = parent

	local self = setmetatable({
		model = model,
		root = root,
		rig = {
			hub = hubJoint,
			chest = chestJoint,
			neck = neckJoint,
			head = headJoint,
			jaw = jawJoint,
			fissure = fissureJoint,
			armShoulder = armShoulderJoint,
			armElbow = armElbowJoint,
			armWrist = armWristJoint,
			wallShoulder = wallShoulderJoint,
			wallElbow = wallElbowJoint,
			wallWrist = wallWristJoint,
			fingers = fingers,
		},
		side = side,
		lungeStuds = Rules.visualLungeStuds(width),
		t = 0,
		state = Protocol.states.dormant,
		stateAge = 0,
		rng = rng,
		fadeParts = fadeParts,
	}, AshamedLurker)
	return self
end

local function idleWaves(self: Lurker): (number, number)
	local dormant = Config.motion.dormant
	local breath = math.sin(self.t * dormant.breathRadiansPerSecond)
	local twitch = math.sin(self.t * dormant.twitchPrimaryRadiansPerSecond)
		+ math.sin(self.t * dormant.twitchSecondaryRadiansPerSecond) * dormant.twitchSecondaryWeight
	return breath, twitch
end

local function fingerIdleRadians(self: Lurker, index: number, blend: number): number
	local dormant = Config.motion.dormant
	local wave = math.sin(self.t * dormant.fingerRadiansPerSecond + index * dormant.fingerPhaseStepRadians)
	return math.rad(dormant.fingerCurlDegrees) * wave * blend
end

local function setFade(self: Lurker, alpha: number)
	local clamped = math.clamp(alpha, 0, 1)
	for _, part in self.fadeParts do
		part.LocalTransparencyModifier = clamped
	end
end

local function actionAmount(
	stateAge: number,
	impactSeconds: number,
	recoverySeconds: number,
	leadFraction: number,
	recoveryStartFraction: number
): number
	if stateAge <= impactSeconds then
		local windupAlpha = if impactSeconds <= 0 then 1 else stateAge / impactSeconds
		return commitAmount(windupAlpha, leadFraction)
	end
	local recoveryAlpha = if recoverySeconds <= 0 then 1 else (stateAge - impactSeconds) / recoverySeconds
	return recoveryAmount(recoveryAlpha, recoveryStartFraction)
end

-- Dry breathing and a slow, wrong head twitch. Nothing here is a tell: the crossing arm keeps its
-- resting silhouette and every articulated joint is explicitly returned to its base-relative pose.
function AshamedLurker.poseDormant(self: Lurker)
	local dormant = Config.motion.dormant
	local breath, twitch = idleWaves(self)
	local side = self.side

	PartKit.pose(self.rig.hub, CFrame.new(0, breath * dormant.hubBobStuds, 0))
	PartKit.pose(
		self.rig.chest,
		CFrame.new(0, breath * dormant.chestBobStuds, 0)
			* CFrame.Angles(math.rad(dormant.chestPitchDegrees) * breath, 0, 0)
	)
	PartKit.pose(self.rig.neck, CFrame.Angles(math.rad(dormant.neckPitchDegrees) * breath, 0, 0))
	PartKit.pose(
		self.rig.head,
		CFrame.Angles(
			math.rad(dormant.headTwitchPitchDegrees) * twitch,
			math.rad(dormant.headTwitchYawDegrees) * twitch * side,
			0
		)
	)
	PartKit.pose(
		self.rig.jaw,
		CFrame.Angles(math.rad(dormant.jawRestDegrees) + math.rad(dormant.jawBreathDegrees) * breath, 0, 0)
	)
	PartKit.pose(self.rig.fissure, CFrame.identity)
	PartKit.pose(self.rig.armShoulder, CFrame.Angles(0, 0, math.rad(dormant.shoulderBreathDegrees) * breath * side))
	PartKit.pose(self.rig.armElbow, CFrame.identity)
	PartKit.pose(self.rig.armWrist, CFrame.identity)
	PartKit.pose(
		self.rig.wallShoulder,
		CFrame.Angles(0, 0, -math.rad(dormant.wallShoulderBreathDegrees) * breath * side)
	)
	PartKit.pose(self.rig.wallElbow, CFrame.identity)
	PartKit.pose(self.rig.wallWrist, CFrame.identity)
	for index, finger in self.rig.fingers do
		PartKit.pose(finger, CFrame.Angles(fingerIdleRadians(self, index, 1), 0, 0))
	end
end

-- The lunge is reconstructed from server age. Torso and shoulders gather first, the reaching arm
-- follows, and head/jaw arrive last; every channel is exactly one at the authoritative grab check.
-- A miss follows the same complete motion because the server publishes Triggered before it rechecks
-- the runner. Recovery is staggered rather than reversing the wind-up like a mechanical hinge.
function AshamedLurker.poseTriggered(self: Lurker)
	local trigger = Config.trigger
	local motion = Config.motion.triggered
	local dormant = Config.motion.dormant
	local impactSeconds = math.max(0, trigger.grabCheckDelaySeconds)
	local recoverySeconds = math.max(0, trigger.recoverySeconds)
	local bodyAmount = actionAmount(
		self.stateAge,
		impactSeconds,
		recoverySeconds,
		motion.bodyLeadFraction,
		motion.bodyRecoveryStartFraction
	)
	local armAmount = actionAmount(
		self.stateAge,
		impactSeconds,
		recoverySeconds,
		motion.armLeadFraction,
		motion.armRecoveryStartFraction
	)
	local headAmount = actionAmount(
		self.stateAge,
		impactSeconds,
		recoverySeconds,
		motion.headLeadFraction,
		motion.headRecoveryStartFraction
	)
	local recoveryAlpha = if self.stateAge <= impactSeconds
		then 0
		else if recoverySeconds <= 0 then 1 else (self.stateAge - impactSeconds) / recoverySeconds
	local recoveryDrag = pulse(rangeAlpha(recoveryAlpha, motion.bodyRecoveryStartFraction, 1))
	local breath, twitch = idleWaves(self)
	-- Full idle at both action boundaries prevents a state-change snap; only the committed middle
	-- damps it to the configured residual life.
	local idleBlend = 1 - (1 - motion.idleBlend) * bodyAmount
	local side = self.side

	PartKit.pose(
		self.rig.hub,
		CFrame.new(
			-side * self.lungeStuds * bodyAmount,
			breath * dormant.hubBobStuds * idleBlend
				- motion.hubDropStuds * bodyAmount
				- motion.recoverySagStuds * recoveryDrag,
			0
		) * CFrame.Angles(0, 0, math.rad(motion.hubRollDegrees) * side * bodyAmount)
	)
	PartKit.pose(
		self.rig.chest,
		CFrame.new(0, breath * dormant.chestBobStuds * idleBlend, 0)
			* CFrame.Angles(
				math.rad(dormant.chestPitchDegrees) * breath * idleBlend
					+ math.rad(motion.chestPitchDegrees) * bodyAmount,
				math.rad(motion.chestYawDegrees) * side * bodyAmount
					+ math.rad(motion.recoveryChestTwistDegrees) * side * recoveryDrag,
				0
			)
	)
	PartKit.pose(
		self.rig.neck,
		CFrame.Angles(
			math.rad(dormant.neckPitchDegrees) * breath * idleBlend + math.rad(motion.neckPitchDegrees) * headAmount,
			0,
			0
		)
	)
	PartKit.pose(
		self.rig.head,
		CFrame.Angles(
			math.rad(dormant.headTwitchPitchDegrees) * twitch * idleBlend
				+ math.rad(motion.headPitchDegrees) * headAmount,
			math.rad(dormant.headTwitchYawDegrees) * twitch * side * idleBlend
				+ math.rad(motion.headYawDegrees) * side * headAmount,
			0
		)
	)
	PartKit.pose(
		self.rig.jaw,
		CFrame.Angles(
			math.rad(dormant.jawRestDegrees)
				+ math.rad(dormant.jawBreathDegrees) * breath * idleBlend
				+ math.rad(motion.jawOpenDegrees) * headAmount,
			0,
			0
		)
	)
	PartKit.pose(self.rig.fissure, CFrame.identity)
	PartKit.pose(
		self.rig.armShoulder,
		CFrame.Angles(
			math.rad(motion.armShoulderPitchDegrees) * armAmount,
			math.rad(motion.armShoulderYawDegrees) * side * armAmount,
			math.rad(dormant.shoulderBreathDegrees) * breath * side * idleBlend
				+ math.rad(motion.armShoulderRollDegrees) * side * armAmount
				+ math.rad(motion.recoveryShoulderHangDegrees) * side * recoveryDrag
		)
	)
	PartKit.pose(self.rig.armElbow, CFrame.Angles(math.rad(motion.armElbowPitchDegrees) * armAmount, 0, 0))
	PartKit.pose(self.rig.armWrist, CFrame.Angles(0, math.rad(motion.armWristYawDegrees) * side * armAmount, 0))
	PartKit.pose(
		self.rig.wallShoulder,
		CFrame.Angles(
			math.rad(motion.wallShoulderPitchDegrees) * bodyAmount,
			0,
			-math.rad(dormant.wallShoulderBreathDegrees) * breath * side * idleBlend
				+ math.rad(motion.wallShoulderRollDegrees) * side * bodyAmount
		)
	)
	PartKit.pose(self.rig.wallElbow, CFrame.Angles(math.rad(motion.wallElbowPitchDegrees) * bodyAmount, 0, 0))
	PartKit.pose(self.rig.wallWrist, CFrame.Angles(0, math.rad(motion.wallWristYawDegrees) * side * bodyAmount, 0))
	for index, finger in self.rig.fingers do
		local idleCurl = fingerIdleRadians(self, index, idleBlend)
		PartKit.pose(finger, CFrame.Angles(idleCurl + math.rad(motion.fingerCurlDegrees) * armAmount, 0, 0))
	end
end

-- Caught. The fissure flinches first, then both articulated arms cover the face while the skull
-- turns away and the body withdraws into (not through) its still-visible socket. It is never stunned,
-- killed, or knocked down: it simply cannot bear being clearly seen.
function AshamedLurker.poseAshamed(self: Lurker)
	local duration = Config.ashamedSeconds
	local normalized = if duration <= 0 then 1 else math.clamp(self.stateAge / duration, 0, 1)
	local motion = Config.motion.ashamed
	local dormant = Config.motion.dormant
	local dartFinished = smoothstep(rangeAlpha(normalized, 0, motion.fissureDartEndFraction))
	local cover = smoothstep(rangeAlpha(normalized, motion.coverStartFraction, motion.coverEndFraction))
	local flee = smoothstep(rangeAlpha(normalized, motion.retreatStartFraction, motion.retreatEndFraction))
	local fade = smoothstep(rangeAlpha(normalized, motion.fadeStartFraction, motion.fadeEndFraction))
	local breath, twitch = idleWaves(self)
	local idleBlend = 1 - (1 - motion.idleBlend) * cover
	local side = self.side

	PartKit.pose(
		self.rig.hub,
		CFrame.new(
			side * motion.retreatSideStuds * flee,
			breath * dormant.hubBobStuds * idleBlend + motion.retreatUpStuds * flee,
			motion.retreatThroughStuds * flee
		) * CFrame.Angles(math.rad(motion.retreatPitchDegrees) * flee, 0, 0)
	)
	PartKit.pose(
		self.rig.chest,
		CFrame.new(0, breath * dormant.chestBobStuds * idleBlend, 0)
			* CFrame.Angles(
				math.rad(dormant.chestPitchDegrees) * breath * idleBlend + math.rad(motion.chestPitchDegrees) * cover,
				math.rad(motion.chestYawDegrees) * side * cover,
				0
			)
	)
	PartKit.pose(self.rig.neck, CFrame.Angles(math.rad(dormant.neckPitchDegrees) * breath * idleBlend, 0, 0))
	PartKit.pose(
		self.rig.head,
		CFrame.Angles(
			math.rad(dormant.headTwitchPitchDegrees) * twitch * idleBlend + math.rad(motion.headPitchDegrees) * cover,
			math.rad(dormant.headTwitchYawDegrees) * twitch * side * idleBlend
				+ math.rad(motion.headYawDegrees) * side * cover,
			0
		)
	)
	PartKit.pose(
		self.rig.jaw,
		CFrame.Angles(
			math.rad(dormant.jawRestDegrees)
				+ math.rad(dormant.jawBreathDegrees) * breath * idleBlend
				+ math.rad(motion.jawCloseDegrees) * cover,
			0,
			0
		)
	)
	PartKit.pose(
		self.rig.fissure,
		CFrame.new(
			0,
			0,
			math.sin(self.stateAge * motion.fissureDartRadiansPerSecond) * motion.fissureDartStuds * (1 - dartFinished)
		)
	)
	PartKit.pose(
		self.rig.armShoulder,
		CFrame.Angles(
			math.rad(motion.armShoulderPitchDegrees) * cover,
			math.rad(motion.armShoulderYawDegrees) * side * cover,
			math.rad(dormant.shoulderBreathDegrees) * breath * side * idleBlend
				+ math.rad(motion.armShoulderRollDegrees) * side * cover
		)
	)
	PartKit.pose(self.rig.armElbow, CFrame.Angles(math.rad(motion.armElbowPitchDegrees) * cover, 0, 0))
	PartKit.pose(self.rig.armWrist, CFrame.Angles(0, math.rad(motion.armWristYawDegrees) * side * cover, 0))
	PartKit.pose(
		self.rig.wallShoulder,
		CFrame.Angles(
			math.rad(motion.wallShoulderPitchDegrees) * cover,
			math.rad(motion.wallShoulderYawDegrees) * side * cover,
			-math.rad(dormant.wallShoulderBreathDegrees) * breath * side * idleBlend
				+ math.rad(motion.wallShoulderRollDegrees) * side * cover
		)
	)
	PartKit.pose(self.rig.wallElbow, CFrame.Angles(math.rad(motion.wallElbowPitchDegrees) * cover, 0, 0))
	PartKit.pose(self.rig.wallWrist, CFrame.Angles(0, math.rad(motion.wallWristYawDegrees) * side * cover, 0))
	for index, finger in self.rig.fingers do
		local idleCurl = fingerIdleRadians(self, index, idleBlend)
		PartKit.pose(finger, CFrame.Angles(idleCurl + math.rad(motion.fingerCurlDegrees) * cover, 0, 0))
	end
	setFade(self, fade)
end

function AshamedLurker.setState(self: Lurker, state: string, age: number)
	if self.state ~= state then
		self.state = state
		if state ~= Protocol.states.ashamed then
			setFade(self, 0)
		end
	end
	self.stateAge = math.max(0, age)
end

-- `stateAge` is server-owned and refreshed by setState every frame; only the free-running clock the
-- idle animation uses advances here.
function AshamedLurker.step(self: Lurker, dt: number)
	self.t += dt
	if self.state == Protocol.states.triggered then
		AshamedLurker.poseTriggered(self)
	elseif self.state == Protocol.states.ashamed then
		AshamedLurker.poseAshamed(self)
	else
		AshamedLurker.poseDormant(self)
	end
end

function AshamedLurker.destroy(self: Lurker)
	self.model:Destroy()
end

return AshamedLurker
