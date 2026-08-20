--!strict
-- Thin adapter around ThreatBrain: spawns silhouettes from the floor plan, feeds the brain its
-- snapshots, moves parts to the positions the brain returns, and applies contact effects.
-- Zero per-threat-ID logic lives here — additional threats are Config/Threats rows that reuse
-- generic behavior profiles.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local ThreatBrain = require(ReplicatedStorage.Shared.Logic.ThreatBrain)
local ThreatRules = require(ReplicatedStorage.Shared.Logic.ThreatRules)
local DynamiteRules = require(ReplicatedStorage.Shared.Logic.DynamiteRules)
local LightField = require(ReplicatedStorage.Shared.Logic.LightField)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local RoofGeometry = require(ReplicatedStorage.Shared.Logic.RoofGeometry)
local RoomNavigation = require(ReplicatedStorage.Shared.Logic.RoomNavigation)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local LightSources = require(script.Parent.LightSources)
local DripTrailService = require(script.Parent.DripTrailService)
-- One-directional: DripstoneService knows about players, wardens and wax, and never about threats, so
-- a ceiling striker can set a formation off without the hazard layer learning what a threat is.
local DripstoneService = require(script.Parent.DripstoneService)
local NoiseService = require(script.Parent.NoiseService)
-- One-directional, exactly like DripstoneService above: TripwireService knows about doorways, players
-- and wax, and nothing about threats. A row carrying `trapline` asks it to string a wire and asks it
-- who has just gone down; the wire keeps working whether or not anything is still alive to own it.
local TripwireService = require(script.Parent.TripwireService)
local WaxService = require(script.Parent.WaxService)
local DeathService = require(script.Parent.DeathService)
local ThreatVisualProxy = require(script.Parent.ThreatVisualProxy)
local SurfaceProbe = require(script.Parent.SurfaceProbe)
local ThreatVisualProtocol = require(ReplicatedStorage.Shared.NewModelsAndObjects.ThreatVisualProtocol)

local ThreatService = {}

export type RoomSurface = {
	center: Vector3,
	ceilingHeight: number,
	groundField: GroundGeometry.Field,
	roofField: RoofGeometry.Field,
	-- Explicitly limited to the part-floored developer laboratory. Generated caves require a measured
	-- Terrain floor and refuse/hold on a miss instead of reviving the analytic burial fallback.
	allowAnalyticGroundFallback: boolean?,
}

-- Developer test chambers reuse the same authoritative spawn path as generated floors. The caller
-- supplies an already-authored navigation/surface context and names the players that body may
-- perceive; the scope id is server-local and is used only for precise teardown.
export type TestSpawnContext = {
	scopeId: string,
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: RoomSurface },
	roomIndex: number,
	offset: Vector3,
	targetPlayerIds: { [Types.PlayerId]: boolean },
	parent: Instance?,
	geometryRoot: Instance?,
}

type Perch = {
	cframe: CFrame, -- resting frame against the wall face
	height: number, -- world Y of the resting point, so releasing can ease back down
	endsAt: number,
}

-- What a `trapline` row is in the middle of. Everything here is a clock or a place; the RULES are all
-- in the profile on its row (Types/Threat.TraplineProfile) and in Config/Tripwire.
type TraplineWork = {
	-- The opening it has picked and is walking to, if any. Cleared when the wire is tied, and also
	-- whenever a player gets close enough to watch it being tied.
	opening: RoomNavigation.DoorwayOpening?,
	-- Non-nil while it is standing in that opening with its hands in the rock. It does not move, and
	-- it does not react to anything for the duration — which is what makes catching it at work worth
	-- something to the player who does.
	layingUntil: number?,
	nextLayAt: number,
	-- WHOEVER IT IS STANDING OVER. Adopted from TripwireService when one of its wires fires, and held
	-- until `guardUntil` — which is extended while the victim is still down and then runs out.
	guardPlayerId: Types.PlayerId?,
	guardUntil: number,
	nextGuardHitAt: number,
}

type Instance_ = {
	-- The row RESOLVED FOR THIS FLOOR (Logic/ThreatRules.atDepth), not the authored Config table. A
	-- threat's stats are settled once, when it is built, and are an ordinary ThreatDef from here on:
	-- nothing below this line knows the floor's depth or that any scaling happened.
	def: Types.ThreatDef,
	state: Types.ThreatState,
	model: Model,
	visualProxy: ThreatVisualProxy.Proxy?,
	upOffset: number, -- pivot height above the floor plane
	-- Every room on this threat's floor. A threat walks between rooms and each room carves its own
	-- ground and roof, so the fields it stands on have to be looked up from where it IS (see
	-- `surfaceAt`) rather than frozen at spawn.
	--
	-- THE SPAWN ROOM'S OWN FIELDS ARE DELIBERATELY NOT KEPT ALONGSIDE THIS. They were, as the fallback
	-- for a position no cell claimed, and holding them made that wrong answer look reasonable —
	-- birthplace geometry is not "roughly right" for a body that has since walked away from it.
	roomSurfaces: { [number]: RoomSurface },
	visualY: number, -- smoothed world-space root height, separate from ground-plane AI state
	perch: Perch?, -- set only while resting on a wall in Wander mode
	navigation: RoomNavigation.Navigation,
	-- Roaming. `roamAt` is when this threat has drifted around its current room long enough to move
	-- on; `roamFromRoom` is the room it left, so the next roll prefers any doorway but that one.
	roamAt: number,
	roamFromRoom: number?,
	contactHits: { [Types.PlayerId]: number },
	nextContactAt: { [Types.PlayerId]: number },
	-- WHILE THIS IS IN THE FUTURE THE BODY DOES NOT TRAVEL. Set when a contact actually resolves into
	-- an effect, for exactly as long as that creature`s authored attack motion runs. See `holdForAttack`.
	attackHoldUntil: number,
	-- Sustained contact, per player: how long they have been held without a real break, and when
	-- contact was last seen so a lapse can be told from an escape (ThreatBrain.advanceContactSeconds).
	contactSeconds: { [Types.PlayerId]: number },
	lastContactAt: { [Types.PlayerId]: number },
	-- TRAPLINE WORK, or nil for every row without the profile (which is every row but one). What this
	-- creature is in the middle of: the opening it is walking to, whether it is currently tying a wire
	-- there, and whoever it is standing over.
	trapline: TraplineWork?,
	-- Nil for every generated-floor threat. Developer bodies carry an explicit scope and target
	-- allowlist so a chamber in the Landing cannot select or touch unrelated lobby/run players.
	testScopeId: string?,
	testTargetPlayerIds: { [Types.PlayerId]: boolean }?,
}

local instances: { Instance_ } = {}
local rng = Random.new()
local wallFilter: RaycastParams? = nil
local floorsGeometryRoot: Instance? = nil
local testGeometryRoots: { [string]: Instance } = {}
-- Terrain and nothing else. The roof probe is correcting ONE specific disagreement — the analytic
-- roof field against the voxels actually written from it — so it must not be able to mistake a
-- boulder, a wall or a rock column for a ceiling and drag a ceiling ambusher down onto it. Hanging
-- clear of dressing is a different job, already done by `ambush.roofDecorationClearance` when the
-- builder reserves the territory.
local terrainFilter: RaycastParams? = nil
local nextHintAt: { [Types.PlayerId]: number } = {}

local LABEL_COLORS: { [Types.ThreatCategory]: Color3 } = {
	DarkHunter = Color3.fromRGB(150, 165, 200),
	Drawn = Color3.fromRGB(230, 195, 130),
}

local function threatPart(
	model: Model,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	transparency: number?
): BasePart
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function weldTo(root: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = root
end

local function addHunterEyes(root: BasePart, model: Model, scale: number, centerY: number, forward: number)
	local visual = Config.Threats.visuals.darkHunter
	local eyeSize = math.clamp(scale * visual.eyeSizeScale, visual.eyeMinSize, visual.eyeMaxSize)
	for _, side in { -1, 1 } do
		local eye = threatPart(
			model,
			Vector3.new(eyeSize * visual.eyeWidthScale, eyeSize * visual.eyeHeightScale, eyeSize * visual.eyeDepthScale),
			visual.eyeColor,
			Enum.Material.Neon
		)
		eye.Name = "Eye"
		weldTo(
			root,
			eye,
			CFrame.new(side * eyeSize * 1.15, centerY, -forward)
				* CFrame.Angles(0, 0, side * math.rad(visual.eyeAngleDegrees))
		)

		local glow = Instance.new("PointLight")
		glow.Color = visual.eyeColor
		glow.Brightness = visual.eyeGlowBrightness
		glow.Range = visual.eyeGlowRange
		glow.Shadows = false
		glow.Parent = eye
	end
end

-- Category-shaped silhouettes, scaled by the row's bodySize. Shapes at the edge of light,
-- never rendered detail (DESIGN §16). New threats reuse their category's shape automatically.
local function buildThreatModel(def: Types.ThreatDef): (Model, number)
	local s = def.bodySize
	local model = Instance.new("Model")
	model.Name = "Threat_" .. def.id

	local root: BasePart
	local upOffset: number
	if def.visualStyle == "Bug" then
		-- Compact black ceiling bug with grey translucent wings and two visible red pinpricks.
		local hunter = Config.Threats.visuals.darkHunter
		local bug = Config.Threats.visuals.bug
		root = threatPart(model, Vector3.new(s * 0.48, s * 0.34, s), hunter.bodyColor)
		root.Shape = Enum.PartType.Ball
		root.Anchored = true
		for _, side in { -1, 1 } do
			local wing =
				threatPart(model, Vector3.new(s * 0.78, s * 0.06, s * 0.38), bug.wingColor, nil, bug.wingTransparency)
			wing.Shape = Enum.PartType.Ball
			weldTo(
				root,
				wing,
				CFrame.new(side * s * 0.46, s * 0.05, s * 0.08) * CFrame.Angles(0, 0, side * math.rad(14))
			)
		end
		addHunterEyes(root, model, s, 0, s * 0.47)
		upOffset = s * 0.3
	elseif def.category == "DarkHunter" then
		-- A connected, gaunt humanoid silhouette. Every limb overlaps the torso or pelvis so the
		-- figure still reads as a body when only fragments cross the candle's edge light.
		local visual = Config.Threats.visuals.darkHunter
		local torsoHeight = s * 0.92
		local legLength = s * 0.8
		local pelvisHeight = s * 0.3
		local legCenterY = -torsoHeight / 2 - pelvisHeight / 2 - legLength / 2 + s * 0.12
		root = threatPart(model, Vector3.new(s * 0.62, torsoHeight, s * 0.38), visual.bodyColor)
		root.Anchored = true

		local chest = threatPart(model, Vector3.new(s * 0.86, s * 0.3, s * 0.44), visual.bodyColor)
		weldTo(root, chest, CFrame.new(0, torsoHeight * 0.3, -s * 0.04))

		local pelvis = threatPart(model, Vector3.new(s * 0.58, pelvisHeight, s * 0.4), visual.bodyColor)
		weldTo(root, pelvis, CFrame.new(0, -torsoHeight / 2 - pelvisHeight / 2 + s * 0.08, 0))

		local neck = threatPart(model, Vector3.new(s * 0.22, s * 0.28, s * 0.22), visual.bodyColor)
		weldTo(root, neck, CFrame.new(0, torsoHeight / 2 + s * 0.09, -s * 0.06))

		local headCenter = torsoHeight / 2 + s * 0.38
		local head = threatPart(model, Vector3.new(s * 0.52, s * 0.52, s * 0.44), visual.bodyColor)
		weldTo(root, head, CFrame.new(0, headCenter, -s * 0.12) * CFrame.Angles(math.rad(-10), 0, 0))

		for _, side in { -1, 1 } do
			local upperArm = threatPart(model, Vector3.new(s * 0.22, s * 0.68, s * 0.24), visual.bodyColor)
			weldTo(
				root,
				upperArm,
				CFrame.new(side * s * 0.49, torsoHeight * 0.08, -s * 0.09)
					* CFrame.Angles(math.rad(-12), 0, side * math.rad(-8))
			)

			local forearm = threatPart(model, Vector3.new(s * 0.19, s * 0.72, s * 0.21), visual.bodyColor)
			weldTo(
				root,
				forearm,
				CFrame.new(side * s * 0.55, -s * 0.55, -s * 0.24) * CFrame.Angles(math.rad(-18), 0, side * math.rad(5))
			)

			local hand = threatPart(model, Vector3.new(s * 0.23, s * 0.28, s * 0.2), visual.bodyColor)
			weldTo(root, hand, CFrame.new(side * s * 0.57, -s * 0.91, -s * 0.34))

			local leg = threatPart(model, Vector3.new(s * 0.25, legLength, s * 0.29), visual.bodyColor)
			weldTo(root, leg, CFrame.new(side * s * 0.18, legCenterY, 0) * CFrame.Angles(0, 0, side * math.rad(4)))

			local foot = threatPart(model, Vector3.new(s * 0.28, s * 0.2, s * 0.48), visual.bodyColor)
			weldTo(root, foot, CFrame.new(side * s * 0.2, legCenterY - legLength / 2 + s * 0.03, -s * 0.14))
		end

		addHunterEyes(root, model, s, headCenter, s * 0.36)
		upOffset = -legCenterY + legLength / 2 - s * 0.03
	else
		-- Neutral ash moth viewed upright. Wings occupy the X/Y plane so they remain broad and
		-- unmistakable when the moth faces a player; the old horizontal wings vanished edge-on.
		local visual = Config.Threats.visuals.drawn
		root = threatPart(model, Vector3.new(s * 0.27, s * 0.68, s * 0.3), visual.bodyColor)
		root.Shape = Enum.PartType.Ball
		root.Anchored = true

		local thorax = threatPart(model, Vector3.new(s * 0.36, s * 0.4, s * 0.34), visual.thoraxColor)
		thorax.Shape = Enum.PartType.Ball
		weldTo(root, thorax, CFrame.new(0, s * 0.13, -s * 0.08))

		local head = threatPart(model, Vector3.one * (s * 0.27), visual.thoraxColor)
		head.Shape = Enum.PartType.Ball
		weldTo(root, head, CFrame.new(0, s * 0.4, -s * 0.1))

		for _, side in { -1, 1 } do
			local foreWing = threatPart(
				model,
				Vector3.new(s * 0.82, s * 0.94, s * 0.08),
				visual.wingColor,
				nil,
				visual.wingTransparency
			)
			foreWing.Shape = Enum.PartType.Ball
			weldTo(
				root,
				foreWing,
				CFrame.new(side * s * 0.48, s * 0.16, s * 0.09)
					* CFrame.Angles(0, side * math.rad(5), side * math.rad(-17))
			)

			local hindWing = threatPart(
				model,
				Vector3.new(s * 0.62, s * 0.62, s * 0.07),
				visual.wingColor,
				nil,
				visual.wingTransparency + 0.06
			)
			hindWing.Shape = Enum.PartType.Ball
			weldTo(
				root,
				hindWing,
				CFrame.new(side * s * 0.4, -s * 0.28, s * 0.12)
					* CFrame.Angles(0, side * math.rad(-7), side * math.rad(22))
			)

			local antenna = threatPart(model, Vector3.new(s * 0.035, s * 0.42, s * 0.035), visual.bodyColor)
			weldTo(
				root,
				antenna,
				CFrame.new(side * s * 0.13, s * 0.61, -s * 0.11) * CFrame.Angles(0, 0, side * math.rad(-18))
			)
		end
		upOffset = s * 0.58
	end

	-- Grey-box tuning aid, disabled for horror/readability playtests by default.
	if Config.Feel.debug.showThreatLabels then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(140, 26)
		billboard.StudsOffset = Vector3.new(0, upOffset + 1.2, 0)
		billboard.MaxDistance = 90
		billboard.LightInfluence = 0
		billboard.AlwaysOnTop = false
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.TextTransparency = 0.25
		text.TextColor3 = LABEL_COLORS[def.category]
		text.Text = def.displayName
		text.Parent = billboard
		billboard.Parent = root
	end

	model.PrimaryPart = root
	CollectionService:AddTag(model, Config.Feel.threatWarning.collectionTag)
	return model, upOffset
end

local function rebuildGeometryFilters()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	-- Terrain is the cave floor now, so the ground probe and obstacle ray must see it alongside the
	-- part geometry (walls, boulders, columns) that still lives in the floor model. Developer chamber
	-- roots join this same allowlist without replacing the expedition root.
	local roots: { Instance } = { workspace.Terrain }
	local floorsRoot = floorsGeometryRoot
	if floorsRoot ~= nil and floorsRoot.Parent ~= nil then
		table.insert(roots, floorsRoot)
	end
	local expiredScopes: { string } = {}
	for scopeId, root in testGeometryRoots do
		if root.Parent == nil then
			table.insert(expiredScopes, scopeId)
		else
			table.insert(roots, root)
		end
	end
	for _, scopeId in expiredScopes do
		testGeometryRoots[scopeId] = nil
	end
	params.FilterDescendantsInstances = roots
	params.RespectCanCollide = true
	wallFilter = params

	local roofOnly = RaycastParams.new()
	roofOnly.FilterType = Enum.RaycastFilterType.Include
	roofOnly.FilterDescendantsInstances = { workspace.Terrain }
	roofOnly.RespectCanCollide = true
	terrainFilter = roofOnly
end

function ThreatService.setFloorsFolder(folder: Instance)
	floorsGeometryRoot = folder
	rebuildGeometryFilters()
end

local function projectToGround(position: Vector3): Vector3
	if wallFilter == nil then
		return position
	end
	local terrain = Config.Floors.terrain
	local origin = position + Vector3.new(0, terrain.aiGroundProbeHeight, 0)
	local direction = Vector3.new(0, -(terrain.aiGroundProbeHeight + terrain.aiGroundProbeDepth), 0)
	local result = workspace:Raycast(origin, direction, wallFilter)
	if result == nil then
		return position
	end
	return Vector3.new(position.X, result.Position.Y, position.Z)
end

-- THE FIELDS UNDER THE THREAT RIGHT NOW, not the ones it was born on. Each room carves its own
-- ground and roof from its own seeded field, and `GroundGeometry.offset` happily extrapolates a
-- neighbouring room's undulation and wall berm out past the cell it was authored for — which is how
-- a crawler that walked one doorway east ended up standing on air at its old room's berm height, and
-- a ceiling ambusher ended up hunting a roof that does not exist above it.
local function surfaceAt(instance: Instance_, position: Vector3): RoomSurface?
	-- Mid-doorway, or briefly outside every cell, resolves to the NEAREST room on this floor — which
	-- for a body in a doorway is one of the two cells it is standing between.
	--
	-- IT USED TO RESOLVE TO THE SPAWN ROOM, and that is what hung voidflies above the ceiling. The
	-- spawn room is bounded and deterministic but it is not NEAR: a fly that has roamed three rooms
	-- away and clips a doorway gets its birthplace's roof field, evaluated tens of studs outside the
	-- cell it was authored for. The comment here used to claim "the terrain probe below corrects
	-- whatever it gets wrong", and for the floor that is broadly true — `resolveGroundY` casts down
	-- and finds real Terrain either way. For the ROOF it is false in the one direction that matters:
	-- `surfaceRoofY` casts UP from the floor and returns the plan unchanged when it hits nothing, and
	-- it gives up before casting at all when the borrowed plan is already below the body. So a low
	-- crevice's doorway onto a tall cavern handed the fly the cavern's 40-stud roof, it hung there,
	-- and the correction that was supposed to save it could only ever agree.
	local roomIndex = RoomNavigation.roomAt(instance.navigation, position)
		or RoomNavigation.nearestRoom(instance.navigation, position)
	if roomIndex ~= nil then
		local surface = instance.roomSurfaces[roomIndex]
		if surface ~= nil then
			return surface
		end
	end
	-- No room on this floor claims the point at all — `nearestRoom` rejects a Y a floor gap away, so
	-- this is a body that is not on its own floor any more. The spawn room's fields would be a
	-- confident wrong answer for a place they never described; nil is the true one, and every caller
	-- already has a field-free branch (a ground raycast, a hover height) for exactly this.
	return nil
end

local function surfaceGroundPosition(surface: RoomSurface, position: Vector3): Vector3
	local localX = position.X - surface.center.X
	local localZ = position.Z - surface.center.Z
	local groundY = surface.center.Y + GroundGeometry.offset(surface.groundField, localX, localZ)
	return Vector3.new(position.X, groundY, position.Z)
end

-- Reconcile the analytic field with the Terrain that actually got written, the same way every object
-- that stands on the floor already does (see server/SurfaceProbe). The two disagree by up to a voxel,
-- which is the difference between a threat standing on the ground and a threat sunk to its eyes in
-- it. The probe is deliberately a narrow window around the planned height: a long ray finds shelves,
-- overhangs and roofs, and none of those is this spot's floor.
local function resolveGroundY(plannedY: number, x: number, z: number): number?
	-- Ground is Terrain, never the upward-facing top of a boulder, fixture, or another model. Reuse the
	-- same safe open-band origin as static placement; a developer chamber with part geometry simply
	-- may opt into its authored analytic Y because it deliberately has a Part floor instead.
	return SurfaceProbe.tryGroundY(plannedY, x, z, 0)
end

local function surfaceRoofY(instance: Instance_, position: Vector3): number
	local surface = surfaceAt(instance, position)
	if surface == nil then
		return position.Y + Config.Floors.roof.minimumClearance
	end
	local localX = position.X - surface.center.X
	local localZ = position.Z - surface.center.Z
	local groundHeight = GroundGeometry.offset(surface.groundField, localX, localZ)
	local plannedY = surface.center.Y
		+ RoofGeometry.undersideHeight(surface.ceilingHeight, surface.roofField, groundHeight, localX, localZ)

	-- And then the same reconciliation the floor gets. A ceiling ambusher hangs a couple of studs under
	-- the roof, which is well inside the error between the analytic underside and the voxelized one, so
	-- trusting the field alone parks its whole body inside the rock.
	--
	-- The probe casts up FROM THE FLOOR, because the one place this ray must never begin is inside
	-- stone. Anchored a fixed window below the analytic underside it did exactly that wherever the
	-- built ceiling hangs lower than the field predicted: an upward ray starting in solid Terrain
	-- reports no hit, the planned height is returned unchanged, and the fly is hung from a ceiling
	-- that is already above it — spawned inside the rock with its legs poking through, and clamped
	-- back up there every tick after. From open air the first thing the ray can reach IS the underside
	-- being looked for, and finding nothing now means the real roof is at or above the plan, where
	-- hanging from the plan was safe to begin with. A column or overhang closer than the roof reads as
	-- a lower ceiling, which errs into the room rather than into the rock.
	local filter = terrainFilter
	if filter == nil then
		return plannedY
	end
	local originY = position.Y + Config.Floors.terrain.aiRoofProbeFloorInset
	if originY >= plannedY then
		return plannedY
	end
	local hit =
		workspace:Raycast(Vector3.new(position.X, originY, position.Z), Vector3.new(0, plannedY - originY, 0), filter)
	if hit == nil then
		return plannedY
	end
	return math.max(hit.Position.Y, originY)
end

local function groundPositionFor(instance: Instance_, position: Vector3): Vector3
	local surface = surfaceAt(instance, position)
	if surface == nil then
		return projectToGround(position)
	end
	local planned = surfaceGroundPosition(surface, position)
	local measuredY = resolveGroundY(planned.Y, position.X, position.Z)
	if measuredY ~= nil then
		return Vector3.new(position.X, measuredY, position.Z)
	end
	if surface.allowAnalyticGroundFallback then
		return planned
	end
	-- Missing Terrain means the proposed X/Z is not safe ground. Keep the last measured position and
	-- force a rethink instead of walking on an analytic height through structural rock.
	instance.state.targetPosition = instance.state.position
	instance.state.nextThinkAt = 0
	return instance.state.position
end

-- ROWS THAT OWN A PATCH RATHER THAN WALKING THE FLOOR. Both roof-bound profiles qualify: they hold a
-- fixed territory, they route straight to their own target rather than through the room graph, and
-- they fly above the floor obstacles a wall probe exists to catch. Asked as one question in all four
-- places that care, so a third roof-bound row would not mean finding them again.
local function isTerritorial(def: Types.ThreatDef): boolean
	return ThreatRules.roofProfile(def) ~= nil
end

local function targetVisualY(instance: Instance_, groundPosition: Vector3): number
	-- A CEILING STRIKER HANGS, ALWAYS. It has no dive and no attack height: every branch a ceiling
	-- ambusher uses to come down at somebody is simply absent here, which is the whole creature.
	local roof = ThreatRules.roofProfile(instance.def)
	if roof ~= nil and instance.def.ambush == nil then
		if surfaceAt(instance, groundPosition) ~= nil then
			return surfaceRoofY(instance, groundPosition) - roof.ceilingClearance
		end
		return groundPosition.Y + instance.upOffset + roof.hoverHeight
	end

	local ambush = instance.def.ambush
	if ambush == nil then
		return groundPosition.Y + instance.upOffset
	end
	if instance.state.mode == "Seek" then
		return groundPosition.Y + instance.upOffset + ambush.attackHeight
	end
	if surfaceAt(instance, groundPosition) ~= nil then
		-- Never below the height it dives to: a roof probe that came back low must not park the
		-- ambusher under its own attack line.
		local hang = surfaceRoofY(instance, groundPosition) - ambush.ceilingClearance
		return math.max(hang, groundPosition.Y + instance.upOffset + ambush.attackHeight)
	end
	return groundPosition.Y + instance.upOffset + ambush.hoverHeight
end

-- Look outward from a wander point for a cave wall to rest on. Returns nil when the point sits in
-- open floor, which simply leaves the threat drifting the way it always has.
local function findPerch(instance: Instance_, now: number): Perch?
	local profile = instance.def.perch
	local filter = wallFilter
	if profile == nil or filter == nil then
		return nil
	end
	local height = rng:NextNumber(profile.minimumHeight, profile.maximumHeight)
	local origin = groundPositionFor(instance, instance.state.position) + Vector3.new(0, height, 0)
	local directions = math.max(math.floor(profile.searchDirections), 1)
	local firstAngle = rng:NextNumber() * 2 * math.pi
	-- A wall's normal is near-horizontal, so its face slope is acos(|normal.Y|). Requiring that to
	-- exceed the configured minimum rejects floors and roof undersides without a second probe.
	local maximumNormalY = math.cos(math.rad(math.clamp(profile.minimumWallSlopeDegrees, 0, 90)))
	for step = 0, directions - 1 do
		local angle = firstAngle + step * (2 * math.pi / directions)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)) * profile.searchRadius
		local hit = workspace:Raycast(origin, direction, filter)
		if hit ~= nil and math.abs(hit.Normal.Y) <= maximumNormalY then
			local point = hit.Position + hit.Normal * profile.surfaceOffset
			-- Any wall on this floor is a legal perch, the Basin's and a vault's included: a moth
			-- resting on the safe room's wall is exactly the kind of thing that should now be possible.
			return {
				-- Head UP the wall with the belly turned to the stone. Aiming the look vector into the
				-- rock instead (as this did) points the head at the wall, and a moth is ~4.4 studs long
				-- nose to abdomen — so most of the body ended up inside the stone it was supposed to be
				-- resting on. `perch.surfaceOffset` carries the rest: the wings beat toward the face in
				-- this pose, and nothing about the body collides, so the gap is the only thing that
				-- keeps them out of it.
				cframe = CFrame.lookAt(point, point + Vector3.yAxis, hit.Normal),
				height = point.Y,
				endsAt = now + rng:NextNumber(profile.minimumDwellSeconds, profile.maximumDwellSeconds),
			}
		end
	end
	return nil
end

local function approach(current: number, target: number, maximumDelta: number): number
	if current < target then
		return math.min(current + maximumDelta, target)
	end
	return math.max(current - maximumDelta, target)
end

local function rollRoamDwell(now: number): number
	local roam = Config.Threats.behavior.roam
	return now + rng:NextNumber(roam.minimumDwellSeconds, roam.maximumDwellSeconds)
end

-- Move a threat's wander anchor into a neighbouring room once its dwell is up, so a floor's threats
-- redistribute themselves over a run rather than each patrolling the tile it spawned on. The brain
-- stays room-blind: this only re-homes it, and its ordinary Wander roll plus RoomNavigation do the
-- rest of the walk, through the doorways, at wander speed.
local function advanceRoam(instance: Instance_, now: number)
	-- A territorial row owns a fixed patch by design, and a moth resting on a wall is ambience: it
	-- roams when it lets go, not while it is clinging.
	if isTerritorial(instance.def) or instance.perch ~= nil then
		return
	end
	-- Anything that has sensed something is already going somewhere it chose. Hunting, retreating and
	-- investigating all push the dwell out, so roaming can never cut short a threat that is engaged.
	if instance.state.mode ~= "Wander" then
		instance.roamAt = rollRoamDwell(now)
		return
	end
	if now < instance.roamAt then
		return
	end

	local leavingRoom = RoomNavigation.roomAt(instance.navigation, instance.state.position)
	local destinationRoom, destination =
		RoomNavigation.roamDestination(instance.navigation, instance.state.position, instance.roamFromRoom, rng)
	instance.roamAt = rollRoamDwell(now)
	if destinationRoom == nil or destination == nil then
		return
	end
	instance.roamFromRoom = leavingRoom
	instance.state.homePosition = destination
	-- Re-anchoring is only half of it: drop the current drift target and decide again on this tick so
	-- the replacement is rolled around the room it is moving to rather than the one it is leaving.
	instance.state.targetPosition = nil
	instance.state.nextThinkAt = now
end

function ThreatService.spawnFloor(
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: RoomSurface }
): number
	local navigation = RoomNavigation.build(plan, roomCenters)
	local now = os.clock()
	local builtCount = 0
	for _, spawn in plan.threatSpawns do
		local authored = Config.Threats.definitions[spawn.threatId]
		if authored == nil then
			continue
		end
		-- Resolve the row against this floor ONCE, here. A creature that is harder deeper down is
		-- harder from the moment it is built, and every read after this — brain, contact, visuals — is
		-- an ordinary def lookup with no depth argument threaded through it.
		local def = ThreatRules.atDepth(authored, plan.globalDepth)
		local center = roomCenters[spawn.roomIndex]
		local roomSurface = roomSurfaces[spawn.roomIndex]
		if center == nil or roomSurface == nil then
			continue
		end
		local position = center + spawn.offset
		-- Seated on the Terrain that was actually written, not on the field it was planned from, so a
		-- threat never starts its life sunk into the floor it is standing on.
		local plannedY = surfaceGroundPosition(roomSurface, position).Y
		local measuredY = resolveGroundY(plannedY, position.X, position.Z)
		if measuredY == nil and not roomSurface.allowAnalyticGroundFallback then
			warn(
				string.format(
					"[WICK] refused threat %q on floor %d room %d: planned point has no measured Terrain floor",
					def.id,
					plan.depth,
					spawn.roomIndex
				)
			)
			continue
		end
		position = Vector3.new(position.X, measuredY or plannedY, position.Z)

		local visualProxy: ThreatVisualProxy.Proxy? = nil
		local model: Model
		local upOffset: number
		if Config.Threats.visuals.procedural.enabled then
			-- The family comes from the plan, so a threat is dressed for the cave it stands in without
			-- ThreatService itself knowing anything about cave families.
			visualProxy = ThreatVisualProxy.build(def, plan.familyId)
			model = visualProxy.model
			upOffset = visualProxy.upOffset
		else
			-- Emergency grey-box fallback for isolating a client-visual regression in Studio.
			model, upOffset = buildThreatModel(def)
		end

		local instance: Instance_ = {
			def = def,
			state = {
				id = def.id,
				category = def.category,
				position = position,
				homePosition = position,
				mode = "Wander" :: Types.ThreatMode,
				targetPosition = nil,
				targetPlayerId = nil,
				nextThinkAt = 0,
				retreatUntil = 0,
				investigateUntil = 0,
				investigateLoudness = 0,
				alarmUntil = 0,
				alarmPosition = nil,
				interceptUntil = 0,
				interceptPosition = nil,
				strikeReadyAt = 0,
				pursuitUntil = 0,
				blastDamage = 0,
			},
			model = model,
			visualProxy = visualProxy,
			upOffset = upOffset,
			roomSurfaces = roomSurfaces,
			visualY = position.Y + upOffset,
			perch = nil,
			navigation = navigation,
			-- Rolled per threat, so a floor's population does not migrate in one synchronised wave.
			roamAt = rollRoamDwell(now),
			roamFromRoom = nil,
			contactHits = {},
			nextContactAt = {},
			attackHoldUntil = 0,
			contactSeconds = {},
			lastContactAt = {},
			-- Rolled per body like `roamAt` above, so two Knotwalkers on one floor do not string their
			-- first wires in the same beat.
			trapline = if def.trapline ~= nil
				then {
					opening = nil,
					layingUntil = nil,
					nextLayAt = now + rng:NextNumber(0, def.trapline.layingCooldownSeconds),
					guardPlayerId = nil,
					guardUntil = 0,
					nextGuardHitAt = 0,
				}
				else nil,
			testScopeId = nil,
			testTargetPlayerIds = nil,
		}
		instance.visualY = targetVisualY(instance, position)
		if visualProxy ~= nil then
			visualProxy.lastSurfaceY = position.Y
			model:SetAttribute(ThreatVisualProtocol.attributes.surfaceY, position.Y)
		end
		model:PivotTo(CFrame.new(position.X, instance.visualY, position.Z))
		model.Parent = workspace
		table.insert(instances, instance)
		builtCount += 1
	end
	return builtCount
end

-- Reuse the production floor-spawn path with exactly one planned row. The shallow plan clone keeps
-- the caller's navigation/surface contract intact while preventing a developer action from
-- mutating the shared plan retained by already-running threat navigation.
local function spawnSingle(threatId: Types.ThreatId, context: TestSpawnContext): Instance_?
	local singlePlan = table.clone(context.plan)
	singlePlan.threatSpawns = {
		{
			threatId = threatId,
			roomIndex = context.roomIndex,
			offset = context.offset,
		},
	}
	local before = #instances
	local built = ThreatService.spawnFloor(singlePlan, context.roomCenters, context.roomSurfaces)
	if built ~= 1 or #instances ~= before + 1 then
		return nil
	end
	return instances[#instances]
end

function ThreatService.spawnTest(threatId: Types.ThreatId, context: TestSpawnContext): Model?
	if context.scopeId == "" then
		return nil
	end
	local geometryRoot = context.geometryRoot
	if geometryRoot ~= nil then
		testGeometryRoots[context.scopeId] = geometryRoot
		rebuildGeometryFilters()
	end

	local instance = spawnSingle(threatId, context)
	if instance == nil then
		return nil
	end
	instance.testScopeId = context.scopeId
	instance.testTargetPlayerIds = table.clone(context.targetPlayerIds)
	local parent = context.parent
	if parent ~= nil then
		instance.model.Parent = parent
	end
	return instance.model
end

-- THREE PERCEPTION FILTERS USED TO LIVE HERE — `sourcesOutsideProtectedRoom`,
-- `trailOutsideProtectedRoom` and `noisesOutsideProtectedRoom` — and all three are gone.
--
-- They were the Basin's sensory half: a flame burning in the safe room, the drips it left on the way
-- in, and any noise made inside it were all erased from every threat's inputs, so nothing outside
-- could even be curious about it. With no protected room left (owner decision, DESIGN §10) the whole
-- light and sound field is visible from everywhere, which is what it always claimed to be.
--
-- The remaining filters are still real and are NOT this: `state.depth == navigation.plan.depth` keeps
-- a floor's creatures from perceiving the floor below, and a deaf row is handed an empty noise list
-- because it has no ears. Those are physics; this was a sanctuary.

local function playerSnapshots(
	navigation: RoomNavigation.Navigation,
	sources: { Types.LightSource },
	now: number,
	targetPlayerIds: { [Types.PlayerId]: boolean }?
): { ThreatBrain.PlayerSnapshot }
	local snapshots: { ThreatBrain.PlayerSnapshot } = {}
	for playerId, state in PlayerState.all() do
		local robloxPlayer = Players:GetPlayerByUserId(playerId)
		local character = if robloxPlayer ~= nil then robloxPlayer.Character else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		local lookDirection: Vector3? = nil
		if root ~= nil and root:IsA("BasePart") then
			local look = root.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 0 then
				lookDirection = flatLook.Unit
			end
		end
		local flamePosition = Vector3.new(
			state.position.X,
			CandleGeometry.flameCenterY(state.position.Y, state.currentHeight),
			state.position.Z
		)
		table.insert(snapshots, {
			playerId = playerId,
			position = state.position,
			lookDirection = lookDirection,
			lightLevel = LightField.intensityAt(flamePosition, sources),
			-- No ROOM makes a player untargetable (DESIGN §10). The only spatial-looking exception is
			-- actually a short state window owned by the elevator while its machinery controls the body.
			-- Otherwise a candle must be alive, still running, still lit, and on THIS floor.
			targetable = (targetPlayerIds == nil or targetPlayerIds[playerId] == true)
				and state.alive
				and not state.finished
				and state.snuffedAt == nil
				and not PlayerState.isThreatProtected(playerId, now)
				and state.depth == navigation.plan.depth,
			-- FLARE is the solo panic counter. The normal dial still changes visibility and light
			-- reads, but reaching its ceiling never hard-counters a ceiling ambusher.
			repelsAmbusher = state.isLit and state.flareEndsAt > now,
		})
	end
	return snapshots
end

local function ambushNeedsImmediateReaction(instance: Instance_, players: { ThreatBrain.PlayerSnapshot }): boolean
	local profile = instance.def.ambush
	if profile == nil then
		return false
	end
	-- The same reach the brain is currently using. A fly mid-harassment is chasing somebody OUTSIDE its
	-- patch, and a flare lit out there has to interrupt the dive on this tick rather than at the next
	-- ordinary repath — burning one is the panic answer, and a panic answer that waits is not one.
	local reach = if instance.state.pursuitUntil > os.clock() then profile.pursuitRadius else profile.territoryRadius
	for _, player in players do
		if player.targetable and player.repelsAmbusher then
			local delta = player.position - instance.state.homePosition
			if Vector3.new(delta.X, 0, delta.Z).Magnitude <= reach then
				return true
			end
		end
	end
	return false
end

local function hunterNeedsImmediatePanicReaction(
	instance: Instance_,
	players: { ThreatBrain.PlayerSnapshot },
	sources: { Types.LightSource }
): boolean
	if instance.def.ambush ~= nil then
		return ambushNeedsImmediateReaction(instance, players)
	end
	if instance.def.category ~= "DarkHunter" then
		return false
	end
	local source = LightField.strongestRetreatSourceAt(instance.state.position, sources)
	return source ~= nil
		and LightField.contributionOf(source, instance.state.position) * math.abs(instance.def.lightResponse)
			> Config.Threats.behavior.repelLightThreshold
end

-- A ROW THAT HEARS PLAYERS MOVE, given the noise it would make.
--
-- Returns `noises` unchanged for every row that has not opted in — which is every row but the Cave
-- Listener — so the shared sound field and every other creature's contract are untouched. Rows that
-- HAVE opted in get a private, synthetic event per moving player appended to their own copy.
--
-- WHY SYNTHESISE RATHER THAN EMIT. A real `NoiseService` emit would be heard by everything on the
-- floor, and Config/Sound is explicit that a global footstep emitter is the one thing that would turn
-- every eared row into an unavoidable one. This is the same field, one listener at a time.
--
-- THE EVENT IS BUILT AT THE PLAYER'S FEET AND DECAYS INSTANTLY (`decaySeconds` of one tick), because
-- it describes a player who is moving RIGHT NOW. A lingering footstep would accumulate into a
-- permanent lure at wherever somebody last ran, which is precisely the failure a real emitter has.
local function withMovementNoise(instance: Instance_, noises: { Types.NoiseEvent }, now: number): { Types.NoiseEvent }
	local hearing = instance.def.hearing
	if hearing == nil then
		return noises
	end
	local loudness = hearing.movementLoudness
	local radius = hearing.movementRadius
	if loudness == nil or radius == nil or loudness <= 0 or radius <= 0 then
		return noises
	end

	local reference = math.max(Config.Movement.runSpeed, 0.001)
	local combined: { Types.NoiseEvent }? = nil
	for playerId, state in PlayerState.all() do
		if state.depth ~= instance.navigation.plan.depth or not state.alive or state.finished then
			continue
		end
		if state.snuffedAt ~= nil or PlayerState.isThreatProtected(playerId, now) then
			continue
		end
		local robloxPlayer = Players:GetPlayerByUserId(playerId)
		local character = if robloxPlayer ~= nil then robloxPlayer.Character else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or not root:IsA("BasePart") then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		-- Scaled by how fast they are ACTUALLY going, so standing still is silent, being slowed is
		-- quieter, and a full sprint is the authored figure. Players in this game run by default
		-- (server/MovementService), so in practice this is a two-state read — but anything that slows a
		-- player genuinely buys them quiet, which is a lever worth having.
		local scaled = loudness * math.clamp(speed / reference, 0, 1)
		if scaled <= 0.01 then
			continue
		end
		if combined == nil then
			combined = table.clone(noises)
		end
		table.insert(combined :: { Types.NoiseEvent }, {
			kind = "Sprint" :: Types.NoiseKind,
			position = root.Position,
			loudness = scaled,
			radius = radius,
			decaySeconds = Config.Threats.behavior.repathIntervalSeconds,
			createdAt = now,
			ownerId = playerId,
		})
	end
	return combined or noises
end

local function movementState(state: Types.ThreatState, targetPosition: Vector3?): Types.ThreatState
	local horizontalTarget = if targetPosition == nil
		then nil
		else Vector3.new(targetPosition.X, state.position.Y, targetPosition.Z)
	return {
		id = state.id,
		category = state.category,
		position = state.position,
		homePosition = state.homePosition,
		mode = state.mode,
		targetPosition = horizontalTarget,
		targetPlayerId = state.targetPlayerId,
		nextThinkAt = state.nextThinkAt,
		retreatUntil = state.retreatUntil,
		investigateUntil = state.investigateUntil,
		investigateLoudness = state.investigateLoudness,
		interceptUntil = state.interceptUntil,
		interceptPosition = state.interceptPosition,
		strikeReadyAt = state.strikeReadyAt,
		pursuitUntil = state.pursuitUntil,
		-- Carried through even though `ThreatBrain.step` is pure movement and never reads it. This is a
		-- throwaway projection that is never assigned back to the live state, so nothing would be lost
		-- either way — but a copy that quietly drops an injury is the kind of thing that becomes a bug
		-- the first time somebody makes this function's result authoritative.
		blastDamage = state.blastDamage,
	}
end

local function sendTutorialHint(instance: Instance_, player: ThreatBrain.PlayerSnapshot, now: number)
	local hints = Config.Feel.tutorialHints
	if not hints.enabled then
		return
	end
	local state = PlayerState.get(player.playerId)
	if state == nil or state.depth > hints.maxDepth or now < (nextHintAt[player.playerId] or 0) then
		return
	end
	nextHintAt[player.playerId] = now + hints.serverCooldownSeconds
	local robloxPlayer = Players:GetPlayerByUserId(player.playerId)
	if robloxPlayer ~= nil then
		Remotes.get("TutorialHint"):FireClient(robloxPlayer, instance.def.id)
	end
end

-- HOW LONG A BODY STANDS STILL TO SWING, taken from the same authored motion the client is about to
-- play (Config/Threats.visuals.procedural.attackMotion) so the plant and the animation are the same
-- length by construction rather than by two numbers agreeing.
--
-- THIS IS THE FIX FOR "IT JUST WALKS INTO YOU". The swing animation was always there and always
-- fired; what was missing is that nothing ever stopped the body. A creature that keeps closing at
-- full speed while its arms are mid-swing reads as a silhouette sliding into the camera with some
-- limb noise attached — the anticipation lands while it is still travelling, the strike lands while
-- it is still travelling, and the player never sees an attack because an attack is a thing that
-- happens INSTEAD of walking.
--
-- ONLY WHILE HUNTING. A body driven off by a flare must be able to leave mid-swing; freezing it for
-- most of a second while it flees would turn its own retreat into another chance to hit it.
local ATTACK_MOTION_KEYS: { [string]: string } = {
	Crawler = "Crawler",
	Moth = "Moth",
	CeilingFly = "CeilingFly",
	Listener = "Listener",
	Knotwalker = "Knotwalker",
	Calver = "Calver",
}

local function holdForAttack(instance: Instance_, now: number)
	local proxy = instance.visualProxy
	if proxy == nil then
		return
	end
	if instance.state.mode == "Flee" then
		return
	end
	local kind = proxy.model:GetAttribute(ThreatVisualProtocol.attributes.kind)
	local key = if type(kind) == "string" then ATTACK_MOTION_KEYS[kind] else nil
	if key == nil then
		return
	end
	local motion = (Config.Threats.visuals.procedural.attackMotion :: { [string]: any })[key]
	if motion == nil then
		return
	end
	local total = motion.anticipationSeconds + motion.strikeSeconds + motion.recoverySeconds
	-- Never shorten a hold that is already running: two contacts inside one swing are one swing.
	instance.attackHoldUntil = math.max(instance.attackHoldUntil, now + total)
end

-- Cosmetic swing, raised only where contact has actually resolved into an effect, so a staged row
-- sitting on its cooldown does not mime a hit it never landed. The proxy paces the beats.
local function signalAttackVisual(instance: Instance_, victimPlayerId: Types.PlayerId, now: number)
	local visualProxy = instance.visualProxy
	if visualProxy ~= nil then
		-- A staged contact row owns a real per-hit cadence. Using the slower generic drain pulse here
		-- suppressed half of VoidFly's four uninterrupted visual bites even though all four server hits
		-- still resolved. This override changes presentation pacing only.
		local staged = instance.def.contactAttack
		ThreatVisualProxy.signalAttack(
			visualProxy,
			victimPlayerId,
			now,
			if staged ~= nil then staged.cooldownSeconds else nil
		)
	end
	-- AND THE BODY PLANTS WHILE IT SWINGS. See `holdForAttack` — without this the animation plays on a
	-- silhouette that is still walking into the player, which is the whole difference between a
	-- creature attacking you and a creature arriving at you.
	holdForAttack(instance, now)
end

-- THE CEILING STRIKE. The Calver's entire output, and the only thing on this service that damages a
-- player without ever touching one.
--
-- THE ORDER MATTERS AND IS THE WHOLE FAIRNESS ARGUMENT. The animation's wind-up fires FIRST (a slow,
-- obvious cocking of both forelimbs, the longest attack envelope in the game), and only after
-- `windUpSeconds` does the formation begin ITS own warning — the same dust, tremor and wobble a player
-- would get from stepping under it themselves. The two windows add rather than replace, so a player
-- who looks up when the creature moves has strictly more time than one who walked into the disc.
--
-- STRIKING BARE ROCK IS A REAL OUTCOME. With nothing in reach it still swings, which is a loud,
-- locatable noise and nothing else. That is deliberate: a creature that only ever animated when it
-- had something to drop would be telling the player the ceiling was loaded before it fell.
local function updateCeilingStrike(instance: Instance_, now: number)
	local profile = instance.def.ceilingStrike
	if profile == nil or instance.state.mode ~= "Seek" or now < instance.state.strikeReadyAt then
		return
	end
	local victimId = instance.state.targetPlayerId
	if victimId == nil then
		return
	end
	instance.state.strikeReadyAt = now + profile.cooldownSeconds

	local visualProxy = instance.visualProxy
	if visualProxy ~= nil then
		ThreatVisualProxy.signalIntent(
			visualProxy,
			Workspace:GetServerTimeNow(),
			ThreatVisualProtocol.actions.ceilingStrike
		)
	end

	local origin = instance.model.PrimaryPart ~= nil and (instance.model.PrimaryPart :: BasePart).Position
		or instance.state.position
	local depth = instance.navigation.plan.depth
	local radius = profile.strikeRadius
	task.delay(profile.windUpSeconds, function()
		-- Re-checked after the wind-up rather than captured before it: a creature driven off by a
		-- flare mid-swing must not still bring the roof down on its way out.
		if instance.model.Parent == nil or now < instance.state.retreatUntil then
			return
		end
		DripstoneService.triggerNearest(depth, origin, radius)
	end)
end

local function applyContact(instance: Instance_, player: ThreatBrain.PlayerSnapshot, now: number, dt: number)
	local attack = instance.def.contactAttack
	if attack ~= nil then
		if instance.state.mode ~= "Seek" or instance.state.targetPlayerId ~= player.playerId then
			return
		end
		if now < (instance.nextContactAt[player.playerId] or 0) then
			return
		end
		instance.nextContactAt[player.playerId] = now + attack.cooldownSeconds
		signalAttackVisual(instance, player.playerId, now)
		sendTutorialHint(instance, player, now)
		if attack.waxDamagePerHit > 0 then
			WaxService.drainExternal(
				player.playerId,
				attack.waxDamagePerHit,
				"DamageThreat",
				instance.def.displayName .. " struck your flame.",
				-- This row's OWN swing cadence, so a Candle Sleeve charges a fast attacker a fraction of
				-- a hit rather than a whole one (Logic/CandleModifiers.chargeCostFor).
				{ kind = "Hit", seconds = attack.cooldownSeconds },
				instance.def.id
			)
		end
		local hits, shouldSnuff =
			ThreatBrain.advanceContactHits(instance.contactHits[player.playerId] or 0, attack.hitsToSnuff)
		instance.contactHits[player.playerId] = hits
		if shouldSnuff then
			instance.contactHits[player.playerId] = nil
			instance.nextContactAt[player.playerId] = nil
			DeathService.snuff(
				player.playerId,
				instance.def.displayName .. " battered your flame out.",
				instance.def.id
			)
		end
		return
	end

	signalAttackVisual(instance, player.playerId, now)
	sendTutorialHint(instance, player, now)
	if instance.def.contactEffect == "Snuff" then
		DeathService.snuff(player.playerId, instance.def.displayName .. " snuffed your flame.", instance.def.id)
		return
	end

	WaxService.drainExternal(
		player.playerId,
		instance.def.waxDamagePerSecond * dt,
		"DamageThreat",
		instance.def.displayName .. " drained your remaining wax.",
		-- A sustained drain, not a swing: the sleeve is spent by the SECOND spent in contact.
		{ kind = "Continuous", seconds = dt },
		instance.def.id
	)

	-- A drain row that escalates. The wax cost above is what contact always does; this is what it
	-- does to somebody who cannot get off it. Both run — the clock is not a replacement for the
	-- drain, it is what happens if the drain is never interrupted.
	local sustained = instance.def.sustainedContact
	if sustained == nil then
		return
	end
	local elapsed, shouldSnuff = ThreatBrain.advanceContactSeconds(
		instance.contactSeconds[player.playerId] or 0,
		instance.lastContactAt[player.playerId] or -math.huge,
		now,
		dt,
		sustained
	)
	instance.contactSeconds[player.playerId] = elapsed
	instance.lastContactAt[player.playerId] = now
	if shouldSnuff then
		instance.contactSeconds[player.playerId] = nil
		instance.lastContactAt[player.playerId] = nil
		DeathService.snuff(player.playerId, instance.def.displayName .. " smothered your flame.", instance.def.id)
	end
end

--------------------------------------------------------------------------------
-- Trapline (Types/Threat.TraplineProfile)
--------------------------------------------------------------------------------

-- The nearest doorway on this creature's own floor that has no wire across it and nobody standing
-- near enough to watch one being tied. Nil when every opening is spoken for, which is a normal answer
-- on a small floor and simply means it waits.
local function chooseOpening(
	instance: Instance_,
	players: { ThreatBrain.PlayerSnapshot },
	profile: Types.TraplineProfile
): RoomNavigation.DoorwayOpening?
	local navigation = instance.navigation
	local position = instance.state.position
	local roomIndex = RoomNavigation.roomAt(navigation, position) or RoomNavigation.nearestRoom(navigation, position)
	if roomIndex == nil then
		return nil
	end
	local depth = navigation.plan.depth
	-- THE LABORATORY WATCHES ON PURPOSE, so it gets its own clearance. `playerClearanceStuds` is 34 in
	-- a real cave and exists so a wire is never strung in front of somebody walking up to the opening;
	-- in the developer room the tester is ALWAYS walking up to the opening, because watching the wire
	-- go up is the entire reason they pressed the button. At 34 the creature simply never laid one
	-- there and the whole trapline behaviour was untestable.
	--
	-- Same class of concession as the flat-floor fallback that room already registers, and it is scoped
	-- the same way: production floors never carry a `testScopeId`, so they keep the full clearance.
	local clearance = if instance.testScopeId ~= nil
		then Config.DevTestRoom.session.traplineClearanceStuds
		else profile.playerClearanceStuds
	local best: RoomNavigation.DoorwayOpening? = nil
	local bestDistance = math.huge
	for _, opening in RoomNavigation.doorwayOpenings(navigation, roomIndex) do
		-- Half the opening's own width: one wire per doorway, and a doorway is the unit.
		if TripwireService.hasWireNear(depth, opening.center, opening.width * 0.5 + 1) then
			continue
		end
		local watched = false
		for _, player in players do
			if not player.targetable then
				continue
			end
			local delta = player.position - opening.center
			if Vector3.new(delta.X, 0, delta.Z).Magnitude <= clearance then
				watched = true
				break
			end
		end
		if watched then
			continue
		end
		local distance = (opening.center - position).Magnitude
		if distance < bestDistance then
			best = opening
			bestDistance = distance
		end
	end
	return best
end

-- Whoever this creature is standing over, or nil. Adopts a fresh catch from TripwireService when it
-- has none and the fall happened within reach of it.
local function updateGuardTarget(instance: Instance_, work: TraplineWork, profile: Types.TraplineProfile, now: number)
	if work.guardPlayerId == nil then
		local catch = TripwireService.takeCatch(instance.navigation.plan.depth)
		if catch == nil then
			return
		end
		if (catch.position - instance.state.position).Magnitude > profile.responseRadiusStuds then
			return
		end
		work.guardPlayerId = catch.playerId
		-- Held until the victim is up, and then a little longer. Extended below for as long as they
		-- stay down, so a three-second stun is three seconds of being stood over rather than a fixed
		-- window that can expire underneath a player who is still on the floor.
		work.guardUntil = now + profile.pursuitSeconds
		work.nextGuardHitAt = now + profile.attackIntervalSeconds
		-- A wire that fired is worth abandoning a half-tied one for. The opening stays untrapped and
		-- will simply be chosen again later.
		work.opening = nil
		work.layingUntil = nil
		return
	end
	if TripwireService.isProne(work.guardPlayerId) then
		work.guardUntil = now + profile.pursuitSeconds
	end
end

-- ONE TRAPLINE CREATURE, ONE TICK. Runs after the brain has decided, and overrides its target: a body
-- that is tying a wire or standing over a victim is not doing what an ordinary dark-hunter would.
-- Everything it writes is an ordinary field the movement, visual and contact code below already read,
-- so nothing downstream needs to know this profile exists.
local function updateTrapline(instance: Instance_, players: { ThreatBrain.PlayerSnapshot }, now: number)
	local profile = instance.def.trapline
	local work = instance.trapline
	if profile == nil or work == nil then
		return
	end

	updateGuardTarget(instance, work, profile, now)

	local guardId = work.guardPlayerId
	if guardId ~= nil then
		if now >= work.guardUntil then
			work.guardPlayerId = nil
			work.nextGuardHitAt = 0
			return
		end
		local victim = PlayerState.get(guardId)
		if victim == nil or not victim.alive or victim.finished or victim.depth ~= instance.navigation.plan.depth then
			work.guardPlayerId = nil
			return
		end
		-- It goes to them and it hits them. This is a Seek with a named target, so the body's own
		-- pursuit animation and the client's attack cue are the ones a player already knows.
		instance.state.mode = "Seek"
		instance.state.targetPlayerId = guardId
		instance.state.targetPosition = victim.position
		local distance = (victim.position - instance.state.position).Magnitude
		if distance <= profile.reachStuds and now >= work.nextGuardHitAt then
			work.nextGuardHitAt = now + profile.attackIntervalSeconds
			signalAttackVisual(instance, guardId, now)
			WaxService.drainExternal(
				guardId,
				profile.waxDamagePerHit,
				"DamageThreat" :: Types.WaxSource,
				instance.def.displayName .. " was on you before you could get up.",
				-- This row's own cadence, so a Candle Sleeve is charged a fraction of a hit per blow
				-- rather than a whole one — the same accounting `applyContact` uses for staged rows.
				{ kind = "Hit", seconds = profile.attackIntervalSeconds },
				instance.def.id
			)
		end
		return
	end

	-- TYING ONE. It stands still for the whole of `layingSeconds`, which is the only free information
	-- the player gets about where a wire is.
	local layingUntil = work.layingUntil
	local opening = work.opening
	if layingUntil ~= nil and opening ~= nil then
		instance.state.mode = "Wander"
		instance.state.targetPlayerId = nil
		instance.state.targetPosition = instance.state.position
		if now < layingUntil then
			return
		end
		work.layingUntil = nil
		work.opening = nil
		work.nextLayAt = now + profile.layingCooldownSeconds
		if TripwireService.lay(instance.navigation.plan.depth, opening, rng:NextInteger(1, 2 ^ 30)) then
			-- Audible, because a doorway that has been worked should be findable by a player who was
			-- listening even if they never saw the body standing in it.
			NoiseService.emit("VineBurn", opening.center, nil)
		end
		return
	end

	-- Nothing to do but hunt normally: it is over its wire budget, or its cooldown is still running.
	if now < work.nextLayAt then
		return
	end
	if TripwireService.armedCount(instance.navigation.plan.depth) >= profile.maximumArmed then
		return
	end

	if opening == nil then
		opening = chooseOpening(instance, players, profile)
		if opening == nil then
			-- Every doorway is either strung or watched. Try again shortly rather than every tick — a
			-- full doorway sweep per body per frame is not worth paying for on a floor with nothing to do.
			work.nextLayAt = now + 3
			return
		end
		work.opening = opening
	end

	-- ABANDONED THE MOMENT SOMEBODY COULD SEE IT. Re-checked on approach rather than only when the
	-- opening was chosen, because the walk takes seconds and a player can arrive during it.
	for _, player in players do
		if not player.targetable then
			continue
		end
		local delta = player.position - opening.center
		if Vector3.new(delta.X, 0, delta.Z).Magnitude <= profile.playerClearanceStuds then
			work.opening = nil
			work.nextLayAt = now + 3
			return
		end
	end

	instance.state.mode = "Wander"
	instance.state.targetPlayerId = nil
	instance.state.targetPosition = opening.center
	local flat =
		Vector3.new(opening.center.X - instance.state.position.X, 0, opening.center.Z - instance.state.position.Z)
	if flat.Magnitude <= Config.Threats.behavior.wanderArrivalToleranceStuds then
		work.layingUntil = now + profile.layingSeconds
	end
end

function ThreatService.tick(dt: number)
	if #instances == 0 then
		return
	end
	local now = os.clock()
	local sources = LightSources.collect(now)
	local trail = DripTrailService.getTrail()
	local noises = NoiseService.events()

	for _, instance in instances do
		-- The WHOLE field, from anywhere on this floor. The only remaining narrowing is the category
		-- read a dark-hunter applies to light, which is perception rather than sanctuary.
		local perceivedSources = if instance.def.category == "DarkHunter"
			then LightField.sourcesForDarkHunters(sources)
			else sources
		local exposedTrail = trail
		-- Deaf rows are handed an empty list: every Drawn threat pays nothing for a perception field it
		-- does not have.
		local audibleNoises: { Types.NoiseEvent } = if instance.def.hearing ~= nil then noises else {}
		audibleNoises = withMovementNoise(instance, audibleNoises, now)
		local players = playerSnapshots(instance.navigation, perceivedSources, now, instance.testTargetPlayerIds)
		-- Before the decision, not after: a threat whose dwell just lapsed re-homes and then thinks on
		-- this same tick, so it never spends one repath interval drifting toward the room it is leaving.
		advanceRoam(instance, now)
		-- Panic light interrupts a live dive on the next server tick instead of waiting for the
		-- ordinary repath cadence. Entering Flee clears staged hits below: the fly is "burned off,"
		-- never damaged.
		if
			now >= instance.state.nextThinkAt
			or hunterNeedsImmediatePanicReaction(instance, players, perceivedSources)
		then
			instance.state = ThreatBrain.think({
				def = instance.def,
				state = instance.state,
				players = players,
				sources = perceivedSources,
				trail = exposedTrail,
				noises = audibleNoises,
				now = now,
				rng = rng,
			})
			if instance.state.mode == "Flee" and instance.def.contactAttack ~= nil then
				table.clear(instance.contactHits)
				table.clear(instance.nextContactAt)
			end
		end

		-- AFTER THE BRAIN, EVERY TICK, NOT ONLY ON A THINK. A trapline row overrides where it is going
		-- (Types/Threat.TraplineProfile), and it has to do that on the same tick the brain re-decides or
		-- the creature would spend every repath interval walking back toward whatever it was chasing.
		-- Running it every tick rather than on the think cadence is also what makes a wire firing
		-- reach its owner immediately instead of up to a repath later.
		updateTrapline(instance, players, now)

		if instance.def.perch ~= nil then
			local perch = instance.perch
			-- Any light the row can sense has already pulled it out of Wander, so a player bright
			-- enough to be noticed walking underneath takes the moth off the wall on that same think.
			if perch ~= nil and (instance.state.mode ~= "Wander" or now >= perch.endsAt) then
				-- Release from the resting height so the drop back to the floor is eased, not snapped.
				instance.visualY = perch.height
				instance.perch = nil
				perch = nil
				if instance.state.mode == "Wander" then
					-- Rethink before the block below runs again, so it roams to a new wander target
					-- instead of immediately re-clinging to the wall it just left.
					instance.state.nextThinkAt = now
				end
			elseif perch == nil and instance.state.mode == "Wander" then
				local target = instance.state.targetPosition
				local arrived = target == nil
					or (target - instance.state.position).Magnitude
						< Config.Threats.behavior.wanderArrivalToleranceStuds
				if arrived then
					perch = findPerch(instance, now)
					if perch ~= nil then
						-- Anchor the ground-plane AI beneath the wall so releasing stays horizontally
						-- continuous and the next roam starts from where the moth actually rested.
						-- The probe needs a Y near the real floor, so it starts from the resting point.
						instance.state.position = groundPositionFor(instance, perch.cframe.Position)
						instance.perch = perch
					end
				end
			end
			if perch ~= nil then
				instance.model:PivotTo(perch.cframe)
				local visualProxy = instance.visualProxy
				if visualProxy ~= nil then
					ThreatVisualProxy.sync(
						visualProxy,
						instance.state.mode,
						nil,
						LightField.intensityAt(perch.cframe.Position, perceivedSources),
						false,
						instance.state.position.Y
					)
				end
				-- A resting moth is ambience: it neither moves nor drains until a light wakes it.
				continue
			end
		end

		local clearance = instance.def.bodySize / 2 + Config.Floors.geometry.wallThickness
		local targetPosition = instance.state.targetPosition
		local waypoint = if targetPosition == nil
			then nil
			elseif isTerritorial(instance.def) then targetPosition
			else RoomNavigation.nextWaypoint(
				instance.navigation,
				instance.state.position,
				targetPosition,
				clearance
			)
		local routedState = movementState(instance.state, waypoint)
		-- PLANTED MID-SWING. `holdForAttack` sets this when a contact actually resolves, for the length of
		-- the attack animation the client is playing; the body keeps its target and its facing and simply
		-- does not travel, so the swing happens instead of the approach rather than during it.
		local nextPosition = if now < instance.attackHoldUntil
			then instance.state.position
			else ThreatBrain.step(routedState, instance.def, dt)
		-- `RoomNavigation.constrainStep` was applied here and has been removed with the protected room
		-- it existed to defend. Nothing replaces it: the obstacle raycast below is what physically stops
		-- a body, and it always was for every wall that is not the Basin's.
		nextPosition = groundPositionFor(instance, nextPosition)
		-- Silhouettes don't ghost through walls: a blocked move stops and forces a rethink. Grounded
		-- bodies keep the broad geometry ray below. Roof-bound bodies sweep their whole gameplay radius
		-- through Terrain at the visible root height: their territory is structurally open, while a live
		-- pursuit may travel beyond it and must stop at the real shaped-room wall instead of entering it.
		local delta = nextPosition - instance.state.position
		local horizontalDelta = Vector3.new(delta.X, 0, delta.Z)
		local territorial = isTerritorial(instance.def)
		if horizontalDelta.Magnitude > 0.01 and territorial and terrainFilter ~= nil then
			local rootPosition = Vector3.new(instance.state.position.X, instance.visualY, instance.state.position.Z)
			local bodyRadius = math.max(instance.def.bodySize / 2, 0.05)
			if workspace:Spherecast(rootPosition, bodyRadius, horizontalDelta, terrainFilter) ~= nil then
				instance.state.targetPosition = instance.state.position
				instance.state.nextThinkAt = now
				continue
			end
		elseif horizontalDelta.Magnitude > 0.01 and wallFilter ~= nil then
			local origin = instance.state.position + Vector3.new(0, instance.upOffset, 0)
			local ray = horizontalDelta + horizontalDelta.Unit * instance.def.bodySize / 2
			if workspace:Raycast(origin, ray, wallFilter) ~= nil then
				-- Temporarily sidestep a boulder/column instead of repeatedly selecting the same
				-- blocked line. The room graph remains authoritative for the next full rethink.
				if horizontalDelta.Magnitude > 0 then
					local side = Vector3.new(-horizontalDelta.Z, 0, horizontalDelta.X).Unit
					if rng:NextInteger(0, 1) == 0 then
						side = -side
					end
					instance.state.targetPosition =
						projectToGround(instance.state.position + side * Config.Floors.terrain.aiObstacleSidestep)
					instance.state.nextThinkAt = now + Config.Threats.behavior.repathIntervalSeconds
				else
					instance.state.nextThinkAt = now
				end
				continue
			end
		end
		instance.state.position = nextPosition
		local ambush = instance.def.ambush
		local wantedVisualY = targetVisualY(instance, nextPosition)
		local roofProfile = ThreatRules.roofProfile(instance.def)
		if roofProfile ~= nil and ambush == nil then
			-- A striker only ever eases back UP to its roof — it has no dive, so one speed covers every
			-- mode it can be in. Clamped under the sampled ceiling for the same reason the ambusher is:
			-- a roof that descends over it must never leave the body embedded in rock.
			instance.visualY = approach(instance.visualY, wantedVisualY, roofProfile.returnSpeed * dt)
			if surfaceAt(instance, nextPosition) ~= nil then
				instance.visualY =
					math.min(instance.visualY, surfaceRoofY(instance, nextPosition) - roofProfile.ceilingClearance)
			end
		elseif ambush ~= nil then
			local verticalSpeed = if instance.state.mode == "Seek" then ambush.diveSpeed else ambush.returnSpeed
			instance.visualY = approach(instance.visualY, wantedVisualY, verticalSpeed * dt)
			if surfaceAt(instance, nextPosition) ~= nil then
				-- A descending roof is a hard upper bound in every mode. Even during a diagonal
				-- dive, horizontal movement may reach lower relief faster than the vertical tween.
				local roofSafeY = surfaceRoofY(instance, nextPosition) - ambush.ceilingClearance
				instance.visualY = math.min(instance.visualY, roofSafeY)
			end
		elseif instance.def.perch ~= nil then
			-- Only ever off-target just after leaving a wall; this flies the moth back down.
			instance.visualY = approach(instance.visualY, wantedVisualY, instance.def.speed * dt)
		else
			instance.visualY = wantedVisualY
		end
		local visualPosition = Vector3.new(nextPosition.X, instance.visualY, nextPosition.Z)
		local target = routedState.targetPosition
		local targetDelta = if target == nil
			then Vector3.zero
			else Vector3.new(target.X - nextPosition.X, 0, target.Z - nextPosition.Z)
		if target ~= nil and targetDelta.Magnitude > 0.5 then
			instance.model:PivotTo(CFrame.lookAt(visualPosition, visualPosition + targetDelta))
		else
			instance.model:PivotTo(CFrame.new(visualPosition))
		end
		local visualProxy = instance.visualProxy
		if visualProxy ~= nil then
			ThreatVisualProxy.sync(
				visualProxy,
				instance.state.mode,
				instance.state.targetPosition,
				LightField.intensityAt(visualPosition, perceivedSources),
				horizontalDelta.Magnitude > 0.01,
				nextPosition.Y
			)
		end

		-- A ceiling striker resolves here instead of through contact: it has a target, a cooldown and a
		-- roof, and it never touches anybody. Its wax cost, when there is one, comes from the formation
		-- it brought down and is applied by DripstoneService like any other impact.
		updateCeilingStrike(instance, now)

		-- Contact: continuous rows use their declared effect; staged rows count discrete attacks.
		local contactAttack = instance.def.contactAttack
		local uninterrupted: { [Types.PlayerId]: boolean } = {}
		local heightReady = if ambush == nil
			then true
			else math.abs(instance.visualY - wantedVisualY) <= ambush.contactHeightTolerance
		for _, player in players do
			if not player.targetable then
				continue
			end
			local playerDelta = player.position - instance.state.position
			local contactDistance = if ambush == nil
				then playerDelta.Magnitude
				else Vector3.new(playerDelta.X, 0, playerDelta.Z).Magnitude
			local isActiveAttack = contactAttack == nil
				or (
					instance.state.mode == "Seek"
					and instance.state.targetPlayerId == player.playerId
					and heightReady
					and not player.repelsAmbusher
				)
			if contactDistance <= instance.def.contactRadius and isActiveAttack then
				if contactAttack ~= nil then
					uninterrupted[player.playerId] = true
				end
				applyContact(instance, player, now, dt)
			end
		end
		if contactAttack ~= nil then
			-- The configured hit count means uninterrupted attacks. Breaking contact, escaping the
			-- territory, being snuffed, or driving the fly away starts the sequence over.
			for playerId in instance.contactHits do
				if not uninterrupted[playerId] then
					instance.contactHits[playerId] = nil
				end
			end
			for playerId in instance.nextContactAt do
				if not uninterrupted[playerId] then
					instance.nextContactAt[playerId] = nil
				end
			end
		end
	end
end

function ThreatService.clearTest(scopeId: string, threatId: Types.ThreatId?): number
	if scopeId == "" then
		return 0
	end
	local removed = 0
	local affectedPlayers: { [Types.PlayerId]: boolean } = {}
	for index = #instances, 1, -1 do
		local instance = instances[index]
		if instance.testScopeId == scopeId and (threatId == nil or instance.def.id == threatId) then
			for playerId in instance.testTargetPlayerIds or {} do
				affectedPlayers[playerId] = true
			end
			instance.model:Destroy()
			table.remove(instances, index)
			removed += 1
		end
	end
	for playerId in affectedPlayers do
		nextHintAt[playerId] = nil
	end

	local scopeStillUsed = false
	for _, instance in instances do
		if instance.testScopeId == scopeId then
			scopeStillUsed = true
			break
		end
	end
	if not scopeStillUsed then
		testGeometryRoots[scopeId] = nil
		rebuildGeometryFilters()
	end
	return removed
end

-- Keep an already-spawned shared lab population aligned with the current occupants. Production
-- instances never carry a scope id and therefore cannot be selected by this route.
function ThreatService.updateTestTargets(scopeId: string, targetPlayerIds: { [Types.PlayerId]: boolean })
	if scopeId == "" then
		return
	end
	for _, instance in instances do
		if instance.testScopeId == scopeId then
			instance.testTargetPlayerIds = table.clone(targetPlayerIds)
		end
	end
end

-- THE SUMMONS. Call every body on one floor to one place for `seconds`, whatever it happens to be
-- doing and whatever it can or cannot perceive. Returns how many were actually roused, so the caller
-- can report the size of what it just started.
--
-- ONE CALLER, ON PURPOSE: an explosive seam detonating (MiningService). This is deliberately not a
-- general-purpose "aggro" verb, and it must not become one — the entire reason the cave reads the way
-- it does is that light and sound are the only two things that move it, and every extra route to a
-- threat's attention is a route the player cannot see coming. If a second caller ever appears, the
-- question to answer first is why that event is not a noise.
--
-- FLOOR-SCOPED AND RADIUS-SCOPED, both. Depth alone would rouse a body at the far end of a floor the
-- blast could not plausibly have reached; radius alone would rouse bodies on a floor below through
-- solid rock. Test bodies are exempt for the same reason they are exempt from `clearDepth`: a lab
-- chamber belongs to its session, not to an expedition.
function ThreatService.alertAll(depth: number, position: Vector3, radius: number, seconds: number): number
	if seconds <= 0 or radius <= 0 then
		return 0
	end
	local until_ = os.clock() + seconds
	local roused = 0
	for _, instance in instances do
		if instance.testScopeId ~= nil or instance.navigation.plan.depth ~= depth then
			continue
		end
		if (instance.state.position - position).Magnitude > radius then
			continue
		end
		-- Written straight onto the live state rather than queued: the brain reads it on its next think
		-- and re-establishes it from there (ThreatBrain.thinkAlarm), so there is no window in which a
		-- body has been summoned but has not been told.
		instance.state.alarmUntil = until_
		instance.state.alarmPosition = position
		-- Think NOW rather than at the end of the current repath interval. Without this a summoned body
		-- can keep walking away from the blast for up to a full interval, which reads as the alarm having
		-- simply not worked.
		instance.state.nextThinkAt = 0
		roused += 1
	end
	return roused
end

export type BlastResult = {
	killed: number,
	staggered: number,
}

-- A STICK OF DYNAMITE GOING OFF (Config/Dynamite, server/DynamiteService).
--
-- THIS IS THE ONE PLACE IN THE GAME A THREAT CAN DIE, and it is a deliberate, narrow exception to
-- DESIGN pillar 2 rather than a drift into combat (owner decision — DESIGN §6a). Everything that
-- makes it narrow lives outside this function: dynamite is found, not bought; roughly one stick every
-- two floors; and detonating one calls the whole floor to the crater. What this function does is only
-- resolve who was close enough.
--
-- THE THREE RULES IT OBEYS:
--
--   1. DISTANCE IS EVERYTHING. Damage is 1.0 at the centre falling linearly to nothing at the edge
--      (`DynamiteRules.blastDamage`), and each row's `blast.hitPoints` is written in those units, so
--      "one stick kills a crawler" and "three could not kill a Warden" are the same sentence.
--   2. DAMAGE ACCUMULATES AND NEVER HEALS. A body that survived is permanently easier to finish.
--   3. A SURVIVOR IS DRIVEN OFF, exactly as a Flare drives one off — same field, same retreat. A
--      blast that failed to kill is still a defensive result, which is what stops a near miss from
--      feeling like a wasted stick.
--
-- Floor-scoped AND radius-scoped for the same reason `alertAll` is, and test bodies are exempt for the
-- same reason: a lab chamber belongs to its session, not to an expedition.
function ThreatService.applyBlast(depth: number, position: Vector3, radius: number): BlastResult
	local result: BlastResult = { killed = 0, staggered = 0 }
	if radius <= 0 then
		return result
	end
	local now = os.clock()
	for index = #instances, 1, -1 do
		local instance = instances[index]
		if instance.testScopeId ~= nil or instance.navigation.plan.depth ~= depth then
			continue
		end
		local distance = (instance.state.position - position).Magnitude
		if distance > radius then
			continue
		end
		local damage = DynamiteRules.blastDamage(distance)
		if damage <= 0 then
			continue
		end
		local profile = DynamiteRules.profileFor(instance.def)
		if DynamiteRules.isLethal(instance.state.blastDamage, damage, profile) then
			-- The body is gone. Destroying the model takes its visual proxy with it (the proxy is
			-- parented to it), so no client is left animating a creature that is no longer there.
			instance.model:Destroy()
			table.remove(instances, index)
			result.killed += 1
			continue
		end
		instance.state.blastDamage += damage
		-- Driven off through the ordinary retreat clock rather than a bespoke "stunned" state, so a
		-- survivor behaves like a flared creature — something every player has already learned to read.
		instance.state.retreatUntil = math.max(instance.state.retreatUntil, now + profile.staggerSeconds)
		instance.state.pursuitUntil = 0
		instance.state.nextThinkAt = 0
		result.staggered += 1
	end
	return result
end

-- Despawn every generated body that belongs to one floor being retired.
-- Test bodies are deliberately exempt: they are owned by the lab session (`clearTest`) rather than
-- by an expedition floor, and their virtual depth is an ordinary number an uncapped run can
-- eventually reach.
function ThreatService.clearDepth(depth: number): number
	local removed = 0
	for index = #instances, 1, -1 do
		local instance = instances[index]
		if instance.testScopeId == nil and instance.navigation.plan.depth == depth then
			instance.model:Destroy()
			table.remove(instances, index)
			removed += 1
		end
	end
	return removed
end

function ThreatService.reset()
	for _, instance in instances do
		instance.model:Destroy()
	end
	table.clear(instances)
	table.clear(nextHintAt)
	table.clear(testGeometryRoots)
	rebuildGeometryFilters()
end

return ThreatService
