--!strict
-- Builds and animates detailed threat bodies locally around server-owned invisible proxies.
-- Local bodies never participate in collision, queries, contact, AI, or wax decisions.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)
local AudioCues = require(script.Parent.AudioCues)
local Calver = require(ReplicatedStorage.Shared.NewModelsAndObjects.Calver)
local CaveListener = require(ReplicatedStorage.Shared.NewModelsAndObjects.CaveListener)
local CaveMoth = require(ReplicatedStorage.Shared.NewModelsAndObjects.CaveMoth)
local CeilingFly = require(ReplicatedStorage.Shared.NewModelsAndObjects.CeilingFly)
local DarkCrawler = require(ReplicatedStorage.Shared.NewModelsAndObjects.DarkCrawler)
local Knotwalker = require(ReplicatedStorage.Shared.NewModelsAndObjects.Knotwalker)
local Protocol = require(ReplicatedStorage.Shared.NewModelsAndObjects.ThreatVisualProtocol)

local ThreatVisualController = {}

type Dressing = CaveFamilyRules.CreatureDressing

type Visual = {
	model: Model,
	root: BasePart,
	update: (dt: number, mode: string, illumination: number, moving: boolean, targetPosition: Vector3?) -> (),
	-- Only bodies with an attack animation supply this; the rest ignore the pulse.
	-- `elapsed` is normally nil. Timestamped pre-effect actions use it to reconstruct the server's
	-- current point in the authored motion instead of starting late from frame zero.
	strike: ((elapsed: number?) -> ())?,
	-- AUDIO EVENTS THE ANIMATION ITSELF PRODUCES, each consumed once per call.
	--
	-- `footfall` returns the weight of a foot that has just reached the ground, `impact` whether a
	-- swing has just arrived. Asking the body rather than running a timer here is the whole point: a
	-- creature's stride length, its cadence, and how much of its gait a candle or a mid-swing pause
	-- has taken out of it all live in the animation, so a sound sourced from the animation is in step
	-- with the legs at every speed and can never play while the silhouette is standing still.
	footfall: (() -> number?)?,
	impact: (() -> boolean)?,
	destroy: () -> (),
}

type Entry = {
	proxy: Model,
	kind: string,
	visual: Visual?,
	nextBuzzAt: number,
	nextWingAt: number,
	nextIdleAt: number,
	lastAttackPulse: number,
	lastIntentSequence: number,
	-- Carried from the pulse to the animation's strike frame, so the close-mixed victim sting lands
	-- with the blow rather than with the decision to throw it.
	pendingVictim: number?,
}

local entries: { [Model]: Entry } = {}
local visualsFolder: Folder? = nil
local rng = Random.new()

local function presentationOnly(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

local function activityForMode(mode: string): number
	local activity = Config.Threats.visuals.procedural.activity
	if mode == "Seek" then
		return activity.seek
	elseif mode == "Stalk" then
		return activity.stalk
	elseif mode == "Flee" then
		return activity.flee
	elseif mode == "Investigate" then
		-- Roused but not hunting. Reads between a drift and a stalk, so a player who hears something
		-- coming can tell from its body that it is looking for a sound rather than for them.
		return activity.investigate
	end
	return activity.wander
end

-- CAVE-FAMILY DRESSING, client side. The server publishes which family a body is standing in and how
-- strongly to tint it (ThreatVisualProtocol.familyVariant / familyTint); this applies it and nothing
-- else. The same AI, collision, speed, damage, perception and states run behind every variant, and
-- the silhouette is identical — a Moss crawler is a DarkCrawler with damp growth on it.
--
-- THREE THINGS ARE NEVER TINTED, and they are the three a player reads a threat by in the dark: the
-- crimson dark-hunter eyes, the yellow Drawn eyes, and the moth wings. Eyes are excluded
-- structurally (a crawler's eyes are not in its skin list at all) and by name for the bodies that
-- colour their parts directly; wings are excluded by name so a moth stays legible as a moth. The
-- config tint strength is capped low for the same reason: a threat may be dressed for its cave and
-- may never be camouflaged against it.
local UNTINTABLE = { "Eye", "Wing", "Halo", "Glow" }

-- A stable seed per body, derived from the server-owned proxy's own name. Every client dresses a
-- given creature identically, and a body rebuilt after being culled comes back wearing exactly what
-- it was wearing — a creature whose growth rearranged itself each time you walked away would be a
-- tell that the body is being rebuilt, which is the one thing this whole layer must never be.
local function dressingSeed(proxy: Model): number
	local total = 0
	for index = 1, #proxy.Name do
		total = (total * 31 + string.byte(proxy.Name, index)) % 2147483647
	end
	return total
end

local function isUntintable(name: string): boolean
	for _, fragment in UNTINTABLE do
		if string.find(name, fragment, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function tintBodyParts(model: Model, color: Color3, strength: number)
	local blend = math.clamp(strength, 0, 1)
	if blend <= 0 then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not isUntintable(descendant.Name) then
			descendant.Color = descendant.Color:Lerp(color, blend)
		end
	end
end

local function crawlerVisual(parent: Instance, dressing: Dressing, seed: number): Visual
	local crawler = DarkCrawler.build(parent)
	-- The crawler re-derives every skin colour from its tracked base/lit pair on each illumination
	-- update, so its tint has to go through the model rather than the parts.
	crawler:applyFamilyTint(dressing.tint, dressing.tintStrength)
	crawler:applyFamilyDressing(dressing, seed)
	presentationOnly(crawler.model)
	return {
		model = crawler.model,
		root = crawler.root,
		update = function(dt, mode, illumination, moving, targetPosition)
			crawler:setIllumination(illumination)
			crawler:setAware(activityForMode(mode))
			crawler:setMoving(moving)
			crawler:lookAt(targetPosition)
			crawler:step(dt)
		end,
		-- Kind is left nil so the body alternates swipe and lunge itself; repeat hits on the same
		-- player never replay one looped pose.
		strike = function(_elapsed)
			crawler:strike()
		end,
		footfall = function()
			return crawler:consumeFootfall()
		end,
		impact = function()
			return crawler:consumeImpact()
		end,
		destroy = function()
			crawler:destroy()
		end,
	}
end

local function mothVisual(parent: Instance, dressing: Dressing, seed: number): Visual
	local moth = CaveMoth.build(parent)
	moth:setTarget(nil)
	tintBodyParts(moth.model, dressing.tint, dressing.tintStrength)
	moth:applyFamilyDressing(dressing, seed)
	presentationOnly(moth.model)
	return {
		model = moth.model,
		root = moth.root,
		update = function(dt, mode, illumination, _moving, targetPosition)
			moth:setPressure(activityForMode(mode))
			moth:setIllumination(illumination)
			moth:lookAt(targetPosition)
			moth:step(dt)
		end,
		strike = function(_elapsed)
			moth:strike()
		end,
		impact = function()
			return moth:consumeImpact()
		end,
		destroy = function()
			moth:destroy()
		end,
	}
end

local function ceilingFlyVisual(parent: Instance, dressing: Dressing, seed: number): Visual
	local fly = CeilingFly.build(parent)
	fly:setFlying(false)
	tintBodyParts(fly.model, dressing.tint, dressing.tintStrength)
	fly:applyFamilyDressing(dressing, seed)
	presentationOnly(fly.model)
	return {
		model = fly.model,
		root = fly.root,
		update = function(dt, mode, illumination, moving, _targetPosition)
			fly:setAlert(activityForMode(mode))
			fly:setIllumination(illumination)
			-- `moving` is horizontal proxy motion, so a vertical dive can report false. Any active
			-- mode is airborne; only a stationary Wander returns to the authored roof-cling pose.
			fly:setFlying(mode ~= "Wander" or moving)
			fly:step(dt)
		end,
		strike = function(_elapsed)
			fly:strike()
		end,
		impact = function()
			return fly:consumeImpact()
		end,
		destroy = function()
			fly:destroy()
		end,
	}
end

-- THE THREE SIGNATURE BODIES. Each satisfies the same interface as the shared roster, so nothing
-- below this point knows there is anything unusual about them — a family-exclusive creature is a body
-- and a config row, not a code path.
local function listenerVisual(parent: Instance, dressing: Dressing, seed: number): Visual
	local listener = CaveListener.build(parent)
	listener:applyFamilyTint(dressing.tint, dressing.tintStrength)
	listener:applyFamilyDressing(dressing, seed)
	presentationOnly(listener.model)
	return {
		model = listener.model,
		root = listener.root,
		update = function(dt, mode, illumination, moving, targetPosition)
			listener:setIllumination(illumination)
			listener:setAware(activityForMode(mode))
			listener:setMoving(moving)
			listener:lookAt(targetPosition)
			listener:step(dt)
		end,
		strike = function(_elapsed)
			listener:strike()
		end,
		footfall = function()
			return listener:consumeFootfall()
		end,
		impact = function()
			return listener:consumeImpact()
		end,
		destroy = function()
			listener:destroy()
		end,
	}
end

local function knotwalkerVisual(parent: Instance, dressing: Dressing, seed: number): Visual
	local walker = Knotwalker.build(parent)
	walker:applyFamilyTint(dressing.tint, dressing.tintStrength)
	walker:applyFamilyDressing(dressing, seed)
	presentationOnly(walker.model)
	return {
		model = walker.model,
		root = walker.root,
		update = function(dt, mode, illumination, moving, targetPosition)
			walker:setIllumination(illumination)
			walker:setAware(activityForMode(mode))
			walker:setMoving(moving)
			walker:lookAt(targetPosition)
			walker:step(dt)
		end,
		strike = function(_elapsed)
			walker:strike()
		end,
		footfall = function()
			return walker:consumeFootfall()
		end,
		impact = function()
			return walker:consumeImpact()
		end,
		destroy = function()
			walker:destroy()
		end,
	}
end

-- The Calver reports no footfall: it never leaves the ceiling, so it has no gait to source one from.
-- Its whole audio presence is the roof-strike, which arrives through `impact` like every other blow.
local function calverVisual(parent: Instance, dressing: Dressing, seed: number): Visual
	local calver = Calver.build(parent)
	calver:applyFamilyTint(dressing.tint, dressing.tintStrength)
	calver:applyFamilyDressing(dressing, seed)
	presentationOnly(calver.model)
	return {
		model = calver.model,
		root = calver.root,
		update = function(dt, mode, illumination, moving, targetPosition)
			calver:setIllumination(illumination)
			calver:setAware(activityForMode(mode))
			calver:setMoving(moving)
			calver:lookAt(targetPosition)
			calver:step(dt)
		end,
		strike = function(elapsed)
			calver:strike(elapsed)
		end,
		impact = function()
			return calver:consumeImpact()
		end,
		destroy = function()
			calver:destroy()
		end,
	}
end

-- THE FAMILY DRESSING IS RESOLVED ONCE, HERE, and handed to whichever body is being built. It used
-- to be a single Color3 dug straight out of `presentation.coverPalette[1]` by this function, which is
-- why "cave family variant" meant one colour lerp for as long as it did; now the family answers with
-- a whole dressing (tint, growth style, coverage, palette, materials) and the body decides where any
-- of it lands.
--
-- The SEED is the proxy's own name, so a body is dressed identically on every client and comes back
-- wearing the same thing after it is culled and rebuilt.
local function buildVisual(kind: string, parent: Instance, dressing: Dressing, seed: number): Visual?
	if kind == Protocol.kinds.crawler then
		return crawlerVisual(parent, dressing, seed)
	elseif kind == Protocol.kinds.moth then
		return mothVisual(parent, dressing, seed)
	elseif kind == Protocol.kinds.ceilingFly then
		return ceilingFlyVisual(parent, dressing, seed)
	elseif kind == Protocol.kinds.listener then
		return listenerVisual(parent, dressing, seed)
	elseif kind == Protocol.kinds.knotwalker then
		return knotwalkerVisual(parent, dressing, seed)
	elseif kind == Protocol.kinds.calver then
		return calverVisual(parent, dressing, seed)
	end
	return nil
end

local function removeProxy(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local entry = entries[instance]
	if entry == nil then
		return
	end
	entries[instance] = nil
	if entry.visual ~= nil then
		entry.visual.destroy()
	end
end

local function addProxy(instance: Instance)
	if not instance:IsA("Model") or entries[instance] ~= nil then
		return
	end
	local kind = instance:GetAttribute(Protocol.attributes.kind)
	local parent = visualsFolder
	if type(kind) ~= "string" or parent == nil then
		return
	end
	local pulse = instance:GetAttribute(Protocol.attributes.attack)
	local intentSequence = instance:GetAttribute(Protocol.attributes.intentSequence)
	local locomotion = Config.Threats.visuals.procedural.locomotionAudio
	entries[instance] = {
		proxy = instance,
		kind = kind,
		visual = nil,
		-- Seeded from the live value: a threat already mid-fight when this client streams it in
		-- must not open with a swing at a player it has not reached yet.
		lastAttackPulse = if type(pulse) == "number" then pulse else 0,
		lastIntentSequence = if type(intentSequence) == "number" then intentSequence else 0,
		pendingVictim = nil,
		nextBuzzAt = os.clock() + rng:NextNumber(
			Config.Threats.visuals.procedural.ceilingFlyBuzz.minIntervalSeconds,
			Config.Threats.visuals.procedural.ceilingFlyBuzz.maxIntervalSeconds
		),
		-- Staggered from the moment this body appeared rather than from a shared clock, so two moths
		-- in one room never beat their wings in unison.
		nextWingAt = os.clock()
			+ rng:NextNumber(locomotion.mothWingMinIntervalSeconds, locomotion.mothWingMaxIntervalSeconds),
		-- Same reasoning, and it matters more here: idle voices are the one creature layer that plays
		-- while nothing is happening, so two of a kind holding one room must never fall into unison.
		nextIdleAt = os.clock() + rng:NextNumber(
			Config.Threats.visuals.procedural.idleAudio.alertIntervalSeconds,
			Config.Threats.visuals.procedural.idleAudio.calmIntervalSeconds
		),
	}
end

local function flyBuzzIsAudible(cameraPosition: Vector3, proxyRoot: BasePart, parent: Folder): boolean
	local buzz = Config.Threats.visuals.procedural.ceilingFlyBuzz
	local offset = proxyRoot.Position - cameraPosition
	local distance = offset.Magnitude
	if distance > buzz.audibleDistance then
		return false
	end
	if distance <= buzz.occlusionEndpointInset then
		return true
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { parent }
	-- This check models cave-wall occlusion, not bodies. Exclude every replicated character so a
	-- teammate crossing the line cannot make the same authoritative fly go silent for one client.
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(exclude, character)
		end
	end
	raycastParams.FilterDescendantsInstances = exclude
	-- Stop just before the roof-mounted root. Terrain immediately behind/around the fly is not an
	-- occluder; walls and cave bends along the rest of the path still correctly muffle its buzz.
	local occlusionRay = offset.Unit * (distance - buzz.occlusionEndpointInset)
	return Workspace:Raycast(cameraPosition, occlusionRay, raycastParams) == nil
end

local function updateFlyBuzz(entry: Entry, proxyRoot: BasePart, cameraPosition: Vector3, parent: Folder, now: number)
	if entry.kind ~= Protocol.kinds.ceilingFly or now < entry.nextBuzzAt then
		return
	end
	local buzz = Config.Threats.visuals.procedural.ceilingFlyBuzz
	if flyBuzzIsAudible(cameraPosition, proxyRoot, parent) then
		AudioCues.playAt(buzz.cueName, proxyRoot)
		entry.nextBuzzAt = now + rng:NextNumber(buzz.minIntervalSeconds, buzz.maxIntervalSeconds)
	else
		entry.nextBuzzAt = now + buzz.outOfRangeRetrySeconds
	end
end

-- THE COMMIT CUE. Ordinary bodies play it on the confirmed-contact beat that starts their cosmetic
-- swing. Calver plays it on fresh timestamped intent before its separate ceiling effect. A contact
-- victim is latched here rather than read at impact because the server may already have moved on by
-- the time the arm arrives; pre-effect intent explicitly clears that latch.
local function playLungeAudio(entry: Entry, proxyRoot: BasePart, latchVictim: boolean?)
	local attackAudio = Config.Threats.visuals.procedural.attackAudio
	if latchVictim == false then
		-- A Calver's pre-effect hammer has no contact victim. In particular, it must not inherit the
		-- player id from some older confirmed-contact pulse if this entry was rebuilt or reused.
		entry.pendingVictim = nil
	end
	-- Voice routing is explicit per rendered kind, so adding a silhouette without authoring both
	-- attack beats fails the config test instead of quietly borrowing another creature's sound.
	local cueName = attackAudio.lungeCueNames[entry.kind]
	if cueName == nil then
		return
	end
	AudioCues.playAt(
		cueName,
		proxyRoot,
		rng:NextNumber(attackAudio.minimumPitchMultiplier, attackAudio.maximumPitchMultiplier)
	)

	if latchVictim ~= false then
		local victim = entry.proxy:GetAttribute(Protocol.attributes.attackVictim)
		entry.pendingVictim = if type(victim) == "number" then victim else nil
	end
end

-- THE BLOW ARRIVING. Fired from the animation's own strike frame, so the hit is heard when the arm
-- gets there instead of while it is still cocked.
local function playImpactAudio(entry: Entry, proxyRoot: BasePart)
	local attackAudio = Config.Threats.visuals.procedural.attackAudio
	local cueName = attackAudio.impactCueNames[entry.kind]
	if cueName == nil then
		return
	end
	local pitchMultiplier = rng:NextNumber(attackAudio.minimumPitchMultiplier, attackAudio.maximumPitchMultiplier)
	AudioCues.playAt(cueName, proxyRoot, pitchMultiplier)

	local victim = entry.pendingVictim
	entry.pendingVictim = nil
	if victim == Players.LocalPlayer.UserId then
		AudioCues.play(attackAudio.victimCueName, pitchMultiplier)
	end
end

-- One foot reaching the ground. `weight` is the gait's own activity at that instant, so a creature
-- creeping through a dark room barely registers and one closing at speed is unmistakable. Below the
-- floor weight nothing plays at all: the crawler's gait keeps ticking over at a shuffle while it
-- stands still, and a stationary body must not sound like an approaching one.
local function playFootstep(entry: Entry, proxyRoot: BasePart, weight: number, cameraPosition: Vector3)
	local locomotion = Config.Threats.visuals.procedural.locomotionAudio
	if weight < locomotion.minimumStepWeight then
		return
	end
	-- Voice routing is explicit per rendered kind, exactly as it is for the attack layers: a body
	-- whose gait is not answered for here stays silent rather than quietly borrowing the weight and
	-- material of a differently sized creature's foot.
	local cueName = locomotion.stepCueNames[entry.kind]
	if cueName == nil then
		return
	end
	if (proxyRoot.Position - cameraPosition).Magnitude > locomotion.audibleDistance then
		return
	end
	local span = math.max(1 - locomotion.minimumStepWeight, 1e-3)
	local hardness = math.clamp((weight - locomotion.minimumStepWeight) / span, 0, 1)
	AudioCues.playAt(
		cueName,
		proxyRoot,
		nil,
		locomotion.quietStepVolume + (locomotion.loudStepVolume - locomotion.quietStepVolume) * hardness
	)
end

-- THE SOUND OF THE ROOM NOT BEING EMPTY. Interval-driven rather than animation-driven, because this
-- layer exists precisely for the body that is doing nothing: a crawler holding a dark corner has no
-- foot plants and no swings to source anything from, and before this it was completely silent.
--
-- Rescheduled whether or not it actually plays, so a body out of range or without an authored voice
-- is not retried every frame. Both the interval and the level track the body's own activity, so a
-- creature that has noticed a player is heard more often and slightly louder — the same read the
-- moth's flutter already gave, extended to the rest of the roster.
local function updateIdleVoice(
	entry: Entry,
	proxyRoot: BasePart,
	cameraPosition: Vector3,
	now: number,
	activity: number
)
	if now < entry.nextIdleAt then
		return
	end
	local idle = Config.Threats.visuals.procedural.idleAudio
	local interval = idle.calmIntervalSeconds - (idle.calmIntervalSeconds - idle.alertIntervalSeconds) * activity
	entry.nextIdleAt = now + interval * rng:NextNumber(0.75, 1.25)

	local cueName = idle.cueNames[entry.kind]
	if cueName == nil then
		return
	end
	if (proxyRoot.Position - cameraPosition).Magnitude > idle.audibleDistance then
		return
	end
	AudioCues.playAt(cueName, proxyRoot, nil, idle.quietVolume + (idle.loudVolume - idle.quietVolume) * activity)
end

-- A moth does not walk, so its flutter is its footstep: an interval cue rather than a per-beat one,
-- because real wingbeats are far too fast to sound as individual events. Louder and faster the more
-- the body is being pulled toward a flame, which makes an approaching moth audible before the wings
-- are visible.
local function updateMothWing(entry: Entry, proxyRoot: BasePart, cameraPosition: Vector3, now: number, activity: number)
	if entry.kind ~= Protocol.kinds.moth or now < entry.nextWingAt then
		return
	end
	local locomotion = Config.Threats.visuals.procedural.locomotionAudio
	-- Rescheduled whether or not it plays, so an out-of-range moth is not retried every frame.
	local interval = locomotion.mothWingMaxIntervalSeconds
		- (locomotion.mothWingMaxIntervalSeconds - locomotion.mothWingMinIntervalSeconds) * activity
	entry.nextWingAt = now + interval * rng:NextNumber(0.8, 1.2)
	if (proxyRoot.Position - cameraPosition).Magnitude > locomotion.audibleDistance then
		return
	end
	AudioCues.playAt(locomotion.mothWingCueName, proxyRoot, 0.92 + activity * 0.22, 0.5 + activity * 0.5)
end

local function render(dt: number)
	local camera = Workspace.CurrentCamera
	local parent = visualsFolder
	if camera == nil or parent == nil then
		return
	end

	local renderConfig = Config.Threats.visuals.procedural
	local boundedDt = math.min(dt, renderConfig.maxAnimationDeltaSeconds)
	local now = os.clock()
	for proxy, entry in entries do
		local proxyRoot = proxy.PrimaryPart
		if proxyRoot == nil or not proxy:IsDescendantOf(Workspace) then
			continue
		end

		local cullLimit = renderConfig.cullDistance + if entry.visual ~= nil then renderConfig.cullHysteresis else 0
		local withinRange = (camera.CFrame.Position - proxyRoot.Position).Magnitude <= cullLimit
		updateFlyBuzz(entry, proxyRoot, camera.CFrame.Position, parent, now)
		if not withinRange then
			if entry.visual ~= nil then
				entry.visual.destroy()
				entry.visual = nil
			end
			-- A swing whose strike frame will now never arrive must not leave its victim sting armed
			-- for whatever this body does next.
			entry.pendingVictim = nil
			continue
		end

		local visual = entry.visual
		local justBuilt = false
		if visual == nil then
			-- Read at build time rather than cached at spawn: a body is rebuilt whenever it re-enters
			-- cull range, so reading the live attributes keeps its dressing correct even if it streamed
			-- in before the server had finished writing them.
			local familyVariant = proxy:GetAttribute(Protocol.attributes.familyVariant)
			local familyTint = proxy:GetAttribute(Protocol.attributes.familyTint)
			local dressing =
				CaveFamilyRules.creatureDressing(if type(familyVariant) == "string" then familyVariant else nil)
			-- The server publishes the tint strength alongside the variant, and it wins over the
			-- profile's own: it is the value that was true when this body was seated.
			if type(familyTint) == "number" then
				dressing.tintStrength = math.clamp(familyTint, 0, 1)
			end
			visual = buildVisual(entry.kind, parent, dressing, dressingSeed(proxy))
			if visual == nil then
				continue
			end
			visual.model.Name = "Visual_" .. proxy.Name
			CollectionService:AddTag(visual.model, Config.Diagnostics.enemyVisualTag)
			entry.visual = visual
			justBuilt = true
		end

		visual.root.CFrame = proxyRoot.CFrame
		local mode = proxy:GetAttribute(Protocol.attributes.mode)
		local illumination = proxy:GetAttribute(Protocol.attributes.illumination)
		local moving = proxy:GetAttribute(Protocol.attributes.moving)
		local targetPosition = proxy:GetAttribute(Protocol.attributes.targetPosition)
		local resolvedMode = if type(mode) == "string" then mode else "Wander"
		visual.update(
			boundedDt,
			resolvedMode,
			if type(illumination) == "number" then illumination else 0,
			if type(moving) == "boolean" then moving else false,
			if typeof(targetPosition) == "Vector3" then targetPosition else nil
		)

		-- Calver begins its visible hammer before the separate authoritative ceiling effect. Rebuild
		-- the phase from the shared server clock, while ordinary contact bodies continue to animate
		-- only after the server confirms a hit below. A culled/rebuilt body absorbs the sequence.
		local intentValue = proxy:GetAttribute(Protocol.attributes.intentSequence)
		local intentSequence = if type(intentValue) == "number" then intentValue else 0
		if intentSequence ~= entry.lastIntentSequence then
			local action = proxy:GetAttribute(Protocol.attributes.intentAction)
			local startedAt = proxy:GetAttribute(Protocol.attributes.intentStartedAt)
			-- The server writes sequence last. If replication ever exposes it first, retain the old
			-- sequence and retry next frame rather than losing the matching timestamped action.
			if type(action) == "string" and type(startedAt) == "number" then
				entry.lastIntentSequence = intentSequence
				if
					not justBuilt
					and entry.kind == Protocol.kinds.calver
					and action == Protocol.actions.ceilingStrike
				then
					local motion = renderConfig.attackMotion.Calver
					local elapsed = math.max(0, Workspace:GetServerTimeNow() - startedAt)
					local total = motion.anticipationSeconds + motion.strikeSeconds + motion.recoverySeconds
					if elapsed < total then
						local strike = visual.strike
						if strike ~= nil then
							strike(elapsed)
						end
						local impactAt = motion.anticipationSeconds + motion.strikeSeconds * motion.impactFraction
						-- A packet arriving after the hammers landed should reconstruct recovery without
						-- playing a chronologically late commit cue over the impact.
						if elapsed < impactAt then
							playLungeAudio(entry, proxyRoot, false)
						end
					end
				end
			end
		end

		-- Pulses that arrived while this body was culled are absorbed rather than replayed: a
		-- rebuilt body catches up to the counter without swinging at contact it never showed.
		local pulse = proxy:GetAttribute(Protocol.attributes.attack)
		local attackPulse = if type(pulse) == "number" then pulse else 0
		if attackPulse ~= entry.lastAttackPulse then
			entry.lastAttackPulse = attackPulse
			if not justBuilt then
				local strike = visual.strike
				if strike ~= nil then
					strike(nil)
				end
				playLungeAudio(entry, proxyRoot)
				-- A body with no attack animation has no strike frame to wait for, so its blow lands
				-- with its wind-up rather than never.
				if visual.impact == nil then
					playImpactAudio(entry, proxyRoot)
				end
			end
		end

		-- Everything below is sourced from the animation rather than from the network, so it stays in
		-- step with the body at whatever speed the body is actually moving.
		local impact = visual.impact
		if impact ~= nil and impact() then
			playImpactAudio(entry, proxyRoot)
		end
		local footfall = visual.footfall
		if footfall ~= nil then
			local weight = footfall()
			if weight ~= nil then
				playFootstep(entry, proxyRoot, weight, camera.CFrame.Position)
			end
		end
		local activity = activityForMode(resolvedMode)
		updateMothWing(entry, proxyRoot, camera.CFrame.Position, now, activity)
		updateIdleVoice(entry, proxyRoot, camera.CFrame.Position, now, activity)
	end
end

function ThreatVisualController.start()
	local folder = Instance.new("Folder")
	folder.Name = "WickThreatVisuals"
	folder.Parent = Workspace
	visualsFolder = folder

	local tag = Config.Feel.threatWarning.collectionTag
	for _, instance in CollectionService:GetTagged(tag) do
		addProxy(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(addProxy)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeProxy)
	RunService.RenderStepped:Connect(render)
end

return ThreatVisualController
