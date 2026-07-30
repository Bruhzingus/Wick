--!strict
-- Mining session coordinator.
--
-- This module selects the seam the player is examining, binds cross-platform input, mirrors the
-- server-owned stance, and routes authoritative results to focused presentation modules. It never
-- chooses accuracy, progress, depletion, cargo, or noise: those remain server-owned.
--
-- The only client prediction is the cosmetic down-stroke. A click starts the viewmodel immediately
-- and carries a shared-clock timestamp to the server's tightly bounded rewind path; the server still
-- validates the world and returns the outcome used by every HUD, sound, and debris response.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MiningRules = require(ReplicatedStorage.Shared.Logic.MiningRules)
local MiningVisualProtocol = require(ReplicatedStorage.Shared.MiningVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local MiningHUD = require(script.Parent.MiningHUD)
local MiningViewmodelController = require(script.Parent.MiningViewmodelController)
local MiningWorldPresentation = require(script.Parent.MiningWorldPresentation)
local UITheme = require(script.Parent.UITheme)

local MiningController = {}

local player = Players.LocalPlayer
local palette = UITheme.palette
local qteConfig = Config.Mining.qte

local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local ACTION_NAME = "WickMineStrike"
local EXIT_ACTION_NAME = "WickMineExit"
local EXIT_KEYS: { Enum.KeyCode } = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Space,
}

local started = false
local controlsBound = false
local currentDepth = 0

-- `activeRoot` is an approach/input target only. The server repeats reach, floor, light, burn, and
-- obstruction checks both when the stance opens and whenever it resolves.
local activeRoot: BasePart? = nil
local engagedRoot: BasePart? = nil
local engagedRow: MiningRules.DepositRow? = nil
local sweepStartedAt: number? = nil
local bandCenter = Config.Mining.timing.perfectCenter

-- Presentation-only grade history. It changes a Perfect accent by at most four percent and grants
-- no score or progress.
local perfectStreak = 0
local lastSwingAccuracy: string? = nil
local swingReleasedWax = false
local swingDisplayPhase = 0
local swingSerial = 0

-- Request latches prevent reliable RemoteEvent round trips from becoming duplicate player actions.
-- A second input is swallowed locally while the authority independently validates every request.
local engagePending = false
local engageCancellationPending = false
local strikePending = false
local requestGeneration = 0

-- Only run/floor invalidation advances this generation. A normal `disengaged("Depleted")` follows
-- the private payout response in the same server frame and must not erase its delayed contact beat.
local presentationLifetimeGeneration = 0

local function characterPosition(): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character.PrimaryPart
	return if root ~= nil then root.Position else nil
end

local function canSeeDeposit(model: Model, root: BasePart): boolean
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return false
	end
	local offset = root.Position - camera.CFrame.Position
	local distance = offset.Magnitude
	if distance <= 1e-3 then
		return true
	end
	if camera.CFrame.LookVector:Dot(offset / distance) < Config.Mining.deposit.promptViewDot then
		return false
	end
	if not Config.Mining.deposit.requiresLineOfSight then
		return true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local characters: { Instance } = {}
	for _, candidate in Players:GetPlayers() do
		local character = candidate.Character
		if character ~= nil then
			table.insert(characters, character)
		end
	end
	params.FilterDescendantsInstances = characters
	params.IgnoreWater = false
	local hit = Workspace:Raycast(camera.CFrame.Position, offset, params)
	return hit == nil or hit.Instance:IsDescendantOf(model)
end

-- The nearest in-reach deposit the player is actually examining. This is prompt hygiene, not
-- authority; the server performs its own body-space raycast and distance checks.
local function findNearestDeposit(): BasePart?
	local origin = characterPosition()
	if origin == nil then
		return nil
	end
	local attributes = MiningVisualProtocol.attributes
	local range = Config.Mining.deposit.interactionRange
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, tagged in CollectionService:GetTagged(MiningVisualProtocol.depositTag) do
		if not tagged:IsA("Model") then
			continue
		end
		local model = tagged :: Model
		local root = model.PrimaryPart
		if root == nil or root:GetAttribute(attributes.depleted) == true then
			continue
		end
		if root:GetAttribute(attributes.depth) ~= currentDepth then
			continue
		end
		local distance = (root.Position - origin).Magnitude
		if distance <= range and distance < bestDistance and canSeeDeposit(model, root) then
			best = root
			bestDistance = distance
		end
	end
	return best
end

local function endStanceDisplay()
	sweepStartedAt = nil
	engagedRoot = nil
	engagedRow = nil
	perfectStreak = 0
	MiningHUD.hideStance()
	MiningViewmodelController.disengage()
end

local function requestDisengage()
	if sweepStartedAt == nil and not engagePending then
		return
	end
	-- The display yields immediately to the movement request instead of waiting for a round trip.
	requestGeneration += 1
	if engagePending then
		-- Reliable C→S order is engage then disengage. Block a new engage until the matching server
		-- teardown arrives, and suppress the stale engaged presentation it may send first.
		engageCancellationPending = true
		local generation = requestGeneration
		task.delay(qteConfig.requestTimeoutSeconds, function()
			if requestGeneration == generation then
				engageCancellationPending = false
			end
		end)
	end
	engagePending = false
	strikePending = false
	endStanceDisplay()
	Remotes.get("MineStrike"):FireServer("disengage")
end

local function actionLabel(): string
	if sweepStartedAt ~= nil then
		if UserInputService.TouchEnabled then
			return "STOP TO RELEASE"
		elseif UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
			return "[B] RELEASE"
		end
		return "[Q] RELEASE"
	end

	local row = if activeRoot ~= nil
		then MiningRules.rowById(activeRoot:GetAttribute(MiningVisualProtocol.attributes.rowId))
		else nil
	local seamName = string.upper(if row ~= nil then row.displayName else "WAX SEAM")
	if UserInputService.TouchEnabled then
		return "MINE " .. seamName
	elseif UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		return "[RT]  MINE " .. seamName
	end
	return "[LMB]  MINE " .. seamName
end

local function adoptSweep(payload: { [string]: any })
	local startedAt = tonumber(payload.startedAt)
	if startedAt == nil then
		return
	end
	sweepStartedAt = startedAt
	bandCenter = tonumber(payload.bandCenter) or bandCenter
	MiningHUD.setBandCenter(bandCenter)
end

local function currentDepositFromPayload(payload: { [string]: any }): BasePart?
	local deposit = payload.deposit
	if
		typeof(deposit) ~= "Instance"
		or not deposit:IsA("BasePart")
		or deposit.Parent == nil
		or deposit:GetAttribute(MiningVisualProtocol.attributes.depth) ~= currentDepth
	then
		return nil
	end
	return deposit
end

local function onStrikeInput(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if not controlsBound or inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if engagePending or engageCancellationPending or strikePending then
		return Enum.ContextActionResult.Sink
	end

	local currentSweep = sweepStartedAt
	if currentSweep ~= nil then
		local now = Workspace:GetServerTimeNow()
		-- The server stamp includes recovery. Inputs before it are swallowed rather than sent into the
		-- remote limiter, so mashing cannot consume a later legitimate strike.
		if now < currentSweep then
			return Enum.ContextActionResult.Sink
		end

		strikePending = true
		requestGeneration += 1
		local generation = requestGeneration
		swingDisplayPhase = MiningHUD.displayPhase(MiningRules.sweepPhase(now - currentSweep) or 0)
		lastSwingAccuracy = nil
		swingReleasedWax = false
		swingSerial += 1
		MiningViewmodelController.beginStrike(now, engagedRoot)
		AudioCues.play("MineSwing", 0.94 + math.random() * 0.1)
		Remotes.get("MineStrike"):FireServer("strike", now)
		task.delay(qteConfig.requestTimeoutSeconds, function()
			if requestGeneration == generation and strikePending then
				-- Never authorize a second locally predicted swing without a correlated reply for
				-- this one. A timeout closes the stance; the reliable disengage follows the strike
				-- on the same remote, so any delayed resolution is ordered before teardown.
				requestDisengage()
			end
		end)
		return Enum.ContextActionResult.Sink
	end

	local root = activeRoot
	if root == nil then
		return Enum.ContextActionResult.Pass
	end
	engagePending = true
	requestGeneration += 1
	local generation = requestGeneration
	Remotes.get("MineStrike"):FireServer("engage", root)
	task.delay(qteConfig.requestTimeoutSeconds, function()
		if requestGeneration == generation and engagePending then
			-- Fail closed just like a stalled strike. Sending engage -> disengage on the reliable
			-- remote prevents a second click at another seam from being replayed as the first stance.
			requestDisengage()
		end
	end)
	return Enum.ContextActionResult.Sink
end

local function onExitInput(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or (sweepStartedAt == nil and not engagePending) then
		return Enum.ContextActionResult.Pass
	end
	requestDisengage()
	return Enum.ContextActionResult.Sink
end

local function bindControls()
	if controlsBound then
		return
	end
	controlsBound = true
	ContextActionService:BindAction(
		ACTION_NAME,
		onStrikeInput,
		true,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:BindAction(
		EXIT_ACTION_NAME,
		onExitInput,
		true,
		Enum.KeyCode.Q,
		Enum.UserInputType.MouseButton2,
		Enum.KeyCode.ButtonB
	)
	if UserInputService.TouchEnabled then
		ContextActionService:SetTitle(ACTION_NAME, "MINE")
		ContextActionService:SetPosition(ACTION_NAME, UDim2.new(1, -150, 1, -230))
		ContextActionService:SetTitle(EXIT_ACTION_NAME, "STOP")
		ContextActionService:SetPosition(EXIT_ACTION_NAME, UDim2.new(1, -150, 1, -150))
		task.defer(function()
			MiningHUD.styleTouchButton(ACTION_NAME)
			MiningHUD.styleTouchButton(EXIT_ACTION_NAME)
		end)
		task.delay(0.15, function()
			MiningHUD.styleTouchButton(ACTION_NAME)
			MiningHUD.styleTouchButton(EXIT_ACTION_NAME)
		end)
	end
end

local function unbindControls()
	if not controlsBound then
		return
	end
	controlsBound = false
	ContextActionService:UnbindAction(ACTION_NAME)
	ContextActionService:UnbindAction(EXIT_ACTION_NAME)
	requestGeneration += 1
	presentationLifetimeGeneration += 1
	engagePending = false
	engageCancellationPending = false
	strikePending = false
	activeRoot = nil
	endStanceDisplay()
	MiningHUD.updatePrompt(1, false, "")
	MiningViewmodelController.destroy()
	MiningWorldPresentation.destroy()
end

-- Movement input releases a planted stance on the same frame. It is polled so mining never sinks a
-- key belonging to MovementController.
local function wantsToLeave(): boolean
	for _, key in EXIT_KEYS do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		for _, input in UserInputService:GetGamepadState(gamepad) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.25 then
				return true
			end
		end
	end
	return false
end

local function refreshControls()
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		bindControls()
	else
		unbindControls()
	end
end

local function update(dt: number)
	if not controlsBound then
		MiningHUD.updatePrompt(1, false, "")
		return
	end

	local origin = characterPosition()
	MiningWorldPresentation.updateGlow(origin, currentDepth, dt)

	if (sweepStartedAt ~= nil or engagePending) and wantsToLeave() then
		requestDisengage()
	end

	local engaged = sweepStartedAt ~= nil
	activeRoot = findNearestDeposit()
	local inReach = activeRoot ~= nil
	local showPrompt = inReach and not engaged and not engagePending and not engageCancellationPending
	MiningHUD.updatePrompt(dt, showPrompt, actionLabel())

	local now = Workspace:GetServerTimeNow()
	MiningViewmodelController.update(dt, now, inReach or engaged or engagePending, activeRoot)

	local currentSweep = sweepStartedAt
	if currentSweep ~= nil then
		local holdThroughContact = now < MiningViewmodelController.impactTime() + Config.Mining.pickaxe.impactSeconds
		MiningHUD.updateRail(now, os.clock(), currentSweep, swingDisplayPhase, holdThroughContact, actionLabel())
	end
end

local function handleEngaged(payload: { [string]: any })
	local payloadDeposit = currentDepositFromPayload(payload)
	if payloadDeposit == nil then
		return
	end
	requestGeneration += 1
	engagePending = false
	strikePending = false
	if engageCancellationPending then
		-- The player released a still-pending engage. The server's reliable `disengaged` response is
		-- next; never flash a stance or instruction for an interaction already cancelled locally.
		local generation = requestGeneration
		task.delay(qteConfig.requestTimeoutSeconds, function()
			if requestGeneration == generation then
				engageCancellationPending = false
			end
		end)
		return
	end
	perfectStreak = 0
	lastSwingAccuracy = nil
	swingReleasedWax = false
	swingSerial += 1

	engagedRoot = payloadDeposit
	engagedRow = if engagedRoot ~= nil
		then MiningRules.rowById(engagedRoot:GetAttribute(MiningVisualProtocol.attributes.rowId))
		else nil

	MiningViewmodelController.engage(Workspace:GetServerTimeNow(), engagedRoot)
	adoptSweep(payload)
	MiningHUD.showStance()
	AudioCues.play("MineEngage")
	local seamName = if engagedRow ~= nil then string.upper(engagedRow.displayName) else "WAX SEAM"
	MiningHUD.setHint(seamName .. "  ·  STRIKE THE BRIGHT CORE", palette.textMuted)
	MiningHUD.clearHintAfter(2.2)
end

local function handleStrikeResolved(payload: { [string]: any })
	local payloadDeposit = currentDepositFromPayload(payload)
	if payloadDeposit == nil then
		return
	end
	-- A release or timeout may close the local stance while an already accepted strike is in flight.
	-- Preserve that physical contact, but never let its NEXT-sweep fields reopen a closed or different
	-- stance.
	local stanceOwnsReply = sweepStartedAt ~= nil and engagedRoot == payloadDeposit
	requestGeneration += 1
	local presentationGeneration = requestGeneration
	local expectedLifetime = presentationLifetimeGeneration
	local resolvedSwingSerial = swingSerial
	strikePending = false

	local accuracy = tostring(payload.accuracy or "Miss")
	local depleted = payload.depleted == true
	local releasedWax = (tonumber(payload.shardWax) or 0) > 0
	lastSwingAccuracy = accuracy
	swingReleasedWax = releasedWax
	-- Q/W closes the stance but deliberately lets the already predicted pick finish. Reliable
	-- MineState ordering prevents a newer stance response from preceding this result, so the
	-- outcome-specific contact path can still resolve while next-sweep/HUD state stays suppressed.
	MiningViewmodelController.resolveStrike(accuracy, depleted)

	local contactDisplayPhase = swingDisplayPhase
	local target = payloadDeposit
	local progress = tonumber(payload.progress) or 0
	local feedback = Config.Mining.feedback
	if accuracy == "Perfect" then
		perfectStreak += 1
	else
		perfectStreak = 0
	end
	local streakAtImpact = perfectStreak
	local rowAtResolution = engagedRow

	if stanceOwnsReply then
		adoptSweep(payload)
	end
	-- The following private depletion response owns final contact + break as one hierarchy.
	if depleted then
		return
	end
	local delaySeconds = math.max(0, MiningViewmodelController.impactTime() - Workspace:GetServerTimeNow())
	task.delay(delaySeconds, function()
		-- An accepted contact remains true even if Q/W closes the stance before its local pick reaches
		-- the rock. Only a floor/run transition may erase confirmed physical presentation.
		if presentationLifetimeGeneration ~= expectedLifetime then
			return
		end

		local accentPitch: number? = nil
		if accuracy == "Perfect" then
			accentPitch = math.min(1 + (streakAtImpact - 1) * feedback.comboPitchStep, feedback.comboPitchMax)
		end
		MiningWorldPresentation.presentStrike(target, accuracy, releasedWax, {
			impact = 0.93 + math.random() * 0.14,
			accent = accentPitch,
		})

		-- HUD copy belongs only to the still-current stance; do not paint a closed or newer rail with
		-- an older strike, even though its world contact remains audible and visible.
		if stanceOwnsReply and requestGeneration == presentationGeneration and sweepStartedAt ~= nil then
			perfectStreak = streakAtImpact
			MiningHUD.playHit(accuracy, contactDisplayPhase)
			if accuracy == "Perfect" then
				MiningHUD.setHint(
					string.format(
						"PERFECT BITE  ·  %d CLEAN STRIKES REMAIN",
						MiningRules.cleanStrikesRemaining(progress, rowAtResolution)
					),
					palette.gold
				)
			elseif accuracy == "Miss" then
				MiningHUD.setHint("GLANCE  ·  LOUDER, LESS PROGRESS", palette.danger)
			else
				MiningHUD.setHint(
					string.format(
						"SOLID BITE  ·  %d CLEAN STRIKES REMAIN",
						MiningRules.cleanStrikesRemaining(progress, rowAtResolution)
					),
					palette.ember
				)
			end
			MiningHUD.clearHintAfter(feedback.hintSeconds)
		end

		task.delay(Config.Mining.pickaxe.impactSeconds + Config.Mining.pickaxe.reboundSeconds * 0.35, function()
			if
				presentationLifetimeGeneration == expectedLifetime
				and swingSerial == resolvedSwingSerial
				and Workspace:GetServerTimeNow() <= MiningViewmodelController.swingEndsAt() + 0.1
			then
				AudioCues.play("MineRecover", 0.96 + math.random() * 0.08)
			end
		end)
	end)
end

local function handleDisengaged(payload: { [string]: any })
	requestGeneration += 1
	engagePending = false
	engageCancellationPending = false
	strikePending = false
	endStanceDisplay()

	local reason = tostring(payload.reason or "")
	if reason == "Cancelled" then
		MiningHUD.setHint(nil)
	elseif reason == "NotLit" then
		MiningHUD.setHint("You cannot work a seam in the dark.", palette.danger)
		MiningHUD.clearHintAfter(2.2)
	elseif reason == "Covered" then
		MiningHUD.setHint("Uncover the flame to mine.", palette.danger)
		MiningHUD.clearHintAfter(2.2)
	elseif reason == "TooDim" then
		MiningHUD.setHint("This seam needs maximum flame or a FLARE.", palette.danger)
		MiningHUD.clearHintAfter(2.4)
	elseif reason == "Obstructed" then
		MiningHUD.setHint("Get a clear face on the seam.", palette.danger)
		MiningHUD.clearHintAfter(2.2)
	end
end

local function handleDepleted(payload: { [string]: any })
	local payloadDeposit = currentDepositFromPayload(payload)
	if payloadDeposit == nil then
		return
	end
	requestGeneration += 1
	local expectedLifetime = presentationLifetimeGeneration
	engagePending = false
	engageCancellationPending = false
	strikePending = false
	MiningViewmodelController.markDepleted()

	local target = payloadDeposit
	-- A paid helper can receive private depletion before the public mineImpact echo because they are
	-- separate remotes. Prefer the final breaker result carried here so both routes claim the same
	-- debris and material presentation.
	local accuracy = if type(payload.accuracy) == "string" then payload.accuracy else lastSwingAccuracy or "Good"
	local releasedWax = if type(payload.shardWax) == "boolean" then payload.shardWax else swingReleasedWax
	local delaySeconds = math.max(0, MiningViewmodelController.impactTime() - Workspace:GetServerTimeNow())
	endStanceDisplay()

	local granted = tonumber(payload.rawWaxGranted) or 0
	local carried = tonumber(payload.rawWaxCarried) or MiningHUD.getCargo()
	local minedThisRun = tonumber(payload.minedThisRun) or 0
	task.delay(delaySeconds, function()
		if presentationLifetimeGeneration ~= expectedLifetime then
			return
		end
		MiningWorldPresentation.presentBreak(target, accuracy, releasedWax)
		MiningHUD.playBreak()
		if granted > 0 then
			local previous = MiningHUD.getCargo()
			MiningHUD.setCargo(carried, carried ~= previous)
			MiningHUD.setHint(string.format("+%d RAW WAX  ·  %d CARRIED", granted, carried), palette.gold)
		else
			MiningHUD.setHint(string.format("SEAM OPEN  ·  %d THIS RUN", minedThisRun), palette.gold)
		end
		MiningHUD.clearHintAfter(2.6)
	end)
end

local function resetForWorldTransition(depth: number, clearCargo: boolean)
	currentDepth = depth
	MiningWorldPresentation.clearBreakClaims()
	requestGeneration += 1
	presentationLifetimeGeneration += 1
	engagePending = false
	engageCancellationPending = false
	strikePending = false
	activeRoot = nil
	lastSwingAccuracy = nil
	swingReleasedWax = false
	swingSerial += 1
	endStanceDisplay()
	MiningHUD.setHint(nil)
	if clearCargo then
		MiningHUD.setCargo(0, false)
	end
end

function MiningController.start()
	if started then
		return
	end
	started = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "WickMining"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	MiningHUD.start(gui)
	gui.Parent = player:WaitForChild("PlayerGui")

	Remotes.get("MineState").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if kind == "engaged" then
			handleEngaged(payload)
		elseif kind == "strikeResolved" then
			handleStrikeResolved(payload)
		elseif kind == "disengaged" then
			handleDisengaged(payload)
		elseif kind == "depleted" then
			handleDepleted(payload)
		end
	end)

	-- StateSync is the reconciliation truth, including extraction/death returning cargo to zero.
	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId == player.UserId then
				local total = tonumber(entry.rawWax) or 0
				local previous = MiningHUD.getCargo()
				if total ~= previous then
					MiningHUD.setCargo(total, total > previous)
				end
				break
			end
		end
	end)

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if kind == "mineImpact" then
			if tonumber(payload.strikerId) == player.UserId then
				return
			end
			-- Public impact traffic can outlive a floor teardown. Apply the same live/current-depth
			-- gate as private mining state before reading position or presenting an old cave event.
			local target = currentDepositFromPayload(payload)
			local origin = characterPosition()
			if
				target == nil
				or origin == nil
				or (target.Position - origin).Magnitude > Config.Mining.feedback.impactPresentationRange
			then
				return
			end

			local accuracy = tostring(payload.accuracy or "Miss")
			if payload.depleted == true then
				MiningWorldPresentation.presentBreak(target, accuracy, payload.shardWax == true)
			else
				MiningWorldPresentation.presentStrike(target, accuracy, payload.shardWax == true)
			end
		elseif kind == "floor" then
			resetForWorldTransition(tonumber(payload.depth) or 0, false)
		elseif kind == "countdown" then
			resetForWorldTransition(0, true)
		end
	end)

	refreshControls()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(refreshControls)
	RunService.RenderStepped:Connect(update)
end

return MiningController
