--!strict
-- The Brazier (DESIGN §12): the only way Raw Wax becomes money. Shows the player the real arithmetic
-- while they stand at it (deliberate design choice), commits on a held prompt, and pays through the
-- transactional Persistence boundary.
--
-- THE FIXTURE IS NOW A GAS LANTERN (FLOOR-FIXTURES-OVERHAUL, Config/Lantern) and the service is not.
-- Every number, gate and payout path below is exactly what it was when the object was one grey box:
-- what changed is that there is something to walk up to, that it catches when you commit, and that
-- it stays lit for everybody afterwards. The file keeps its name because the SYSTEM is unchanged —
-- renaming it would have implied a mechanical change that did not happen.
--
-- "GAS, NOT WAX" IS FICTION, NOT A RULE. The lamp is fed by its own supply so it does not draw on the
-- candle in the player's hands — but it never did. The reward has always been a value READ from the
-- Raw Wax that player is carrying, and it still is.
--
-- PHASE 8 REMOVED THE LIVING WAX PAYOUT ENTIRELY. This service used to credit currency for the wax
-- still in your candle at cash-out — `waxDelivered * depth * group * tier` — which made the optimal
-- run "burn as little as possible and never stop to mine". Wax is now purely what keeps you alive,
-- and it is worth nothing at the top of the shaft. What you get paid for is what you dug out of the
-- rock and carried up, priced by the depth it came from (Logic/ExtractionValue).
--
-- WHAT THE CANDLE'S REMAINING WAX DOES NOW: nothing but keep you alive on the way. It is still
-- drained to empty here, and still attributed to "Extraction" in the wax ledger, so the run summary
-- reconciles — but no part of that number reaches a profile.
--
-- THE GROUP MULTIPLIER MOVED TOO. It used to be a proximity bonus counted at this brazier; it is now
-- an "everyone came back" bonus settled by ExtractionService once the last party member is out.
-- Standing next to someone no longer pays — surviving together does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Lantern = require(ReplicatedStorage.Shared.NewModelsAndObjects.Lantern)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local ExtractionService = require(script.Parent.ExtractionService)
local RunSummaryService = require(script.Parent.RunSummaryService)
local ThreatService = require(script.Parent.ThreatService)
local AshamedLurkerService = require(script.Parent.AshamedLurkerService)
local StoneWardenService = require(script.Parent.StoneWardenService)
local Telemetry = require(script.Parent.Telemetry)

local BrazierService = {}

-- ONE FLOOR'S GAS LANTERN (Config/Lantern, FLOOR-FIXTURES-OVERHAUL). `lit` is SHARED and one-way:
-- the first player to commit here catches the lamp for everybody, and it never goes out again.
--
-- WHY SHARED. The reward is already independent per player — each commit reads that player's own
-- cargo, pays their own profile, and can happen minutes apart — so the only question the prop had to
-- answer was whose lantern it is. Making the lit state private would mean two people standing at the
-- same fixture disagreeing about whether it is on fire, which is a worse answer than "somebody
-- started the chain reaction here, and the light is real".
type Brazier = {
	depth: number,
	position: Vector3,
	lantern: Lantern.BuiltLantern?,
	lit: boolean,
	-- The cave-wide wall lamps, ordered outward from this fixture by the builder in the order they
	-- catch (Config/Lantern.network). Shared and one-way exactly as `lit` is.
	networkLamps: { Lantern.BuiltLantern },
	groupPrompt: ProximityPrompt,
	groupReady: { [Types.PlayerId]: boolean },
	groupCommitInProgress: boolean,
	networkSequenceRunning: boolean,
}

local braziers: { [number]: Brazier } = {} -- keyed by depth
local previewShown: { [Types.PlayerId]: boolean } = {}
local previewAccumulator = 0

-- THE IGNITION, and the one-shot chain reaction that answers it.
--
-- FIRED ON EVERY COMMIT, LIT ONLY ONCE. The physical lamp catches for the whole floor the first time
-- anybody uses it; the flare and answering echoes play again for each player who commits, because
-- that beat belongs to the decision rather than to the object. A second player
-- ending their run at an already-lit lantern still gets their own moment.
local function igniteLantern(brazier: Brazier, litFrom: Vector3)
	local lantern = brazier.lantern
	if lantern == nil then
		return
	end
	local firstIgnition = not brazier.lit
	if firstIgnition then
		brazier.lit = true
		Lantern.setLit(lantern, true)
	end

	-- Echo anchors spread back toward the approach instead of all stacking at the fixture.
	local away = Vector3.new(litFrom.X - lantern.headPosition.X, 0, litFrom.Z - lantern.headPosition.Z)
	local direction = if away.Magnitude > 0.5 then away.Unit else Vector3.new(0, 0, -1)
	Remotes.get("RunEvent"):FireAllClients("lanternLit", {
		position = lantern.headPosition,
		direction = direction,
		model = lantern.model,
	})

	-- LIGHT ENDS THE DANGER ON THIS FLOOR. Deeper floors keep their own populations for teammates
	-- who continue; only the cave that visibly changed is made safe. All three enemy ownership paths
	-- are cleared server-side so no invisible AI, delayed grab, or Warden contact survives the visual.
	if firstIgnition then
		local threats = ThreatService.clearDepth(brazier.depth)
		local lurkers = AshamedLurkerService.despawnDepth(brazier.depth)
		local wardens = StoneWardenService.clearDepth(brazier.depth)
		Telemetry.event("lantern_enemies_cleared", nil, {
			depth = brazier.depth,
			threats = threats,
			lurkers = lurkers,
			wardens = wardens,
		})
	end
end

-- THE CAVE NETWORK CATCHING, one lamp at a time (Config/Lantern.network).
--
-- WHAT THIS IS FOR. Committing used to go straight from the held prompt to the results card with
-- nothing in between: the lamp caught and the UI was already over it. This is the room answering
-- first. The world sequence is shared; only a last/group extraction delays its card to watch it.
--
-- IT IS NOT A JOURNEY. DESIGN §404 and GAME-BRIEF §736 both retired the return-to-surface sequence and
-- said not to revisit it. The player does not move a stud: they keep normal first-person look while
-- the lamps catch through the rooms of the cave.
--
-- REUSES THE GAS LANTERN'S OWN IGNITION EVENT rather than inventing a second VFX path. Each lamp gets
-- the same flare and ignite cue the fixture gets; only the distant echoes are suppressed, since
-- those are the cave answering the ONE lamp that ended a run and one set per room would be noise.
--
-- REPLAYS FOR EVERY COMMIT, LIT ONLY ONCE, for the same reason the fixture's own flare does: `setLit`
-- is idempotent and the beat belongs to the decision rather than to the object. A second player ending
-- their run on an already-lit floor can still see the ordered flare replay.
local function lightNetwork(brazier: Brazier)
	local network = Config.Lantern.network
	if #brazier.networkLamps == 0 then
		return
	end
	-- A held breath after the fixture catches, so the first network lamp reads as an answer to it rather
	-- than as part of the same flash.
	local lead = math.max(network.leadSeconds, 0)
	local settle = math.max(network.settleSeconds, 0)
	local available = math.max(network.freeLookSeconds - lead - settle, 0)
	local stepSeconds = math.min(math.max(network.stepSeconds, 0), available / #brazier.networkLamps)
	task.wait(lead)
	for _, lamp in brazier.networkLamps do
		if lamp.model.Parent == nil then
			-- The floor retired underneath the beat (a restart, a teardown). There is nothing left to
			-- light and the caller's own guards will decide whether a card still belongs on screen.
			return
		end
		Lantern.setLit(lamp, true)
		-- The event contract still carries a direction, but sequence lamps suppress distant echoes and
		-- no longer create travelling particles, so this value has no visible use for them.
		Remotes.get("RunEvent"):FireAllClients("lanternLit", {
			position = lamp.headPosition,
			direction = Vector3.new(0, 0, -1),
			model = lamp.model,
			echoes = false,
		})
		task.wait(stepSeconds)
	end
	-- Let the illuminated cave breathe before the results card covers it.
	task.wait(settle)
end

local function beginNetworkSequence(brazier: Brazier)
	if brazier.networkSequenceRunning then
		return
	end
	brazier.networkSequenceRunning = true
	task.spawn(function()
		lightNetwork(brazier)
		brazier.networkSequenceRunning = false
	end)
end

local function lanternSceneFocus(brazier: Brazier): Vector3
	local lantern = brazier.lantern
	-- The Gas Lantern is the completion room's ONLY lamp. Every network lamp is in another room, so
	-- averaging one into this target would deliberately turn the player toward solid rock.
	return if lantern ~= nil then lantern.headPosition else brazier.position
end

local function commit(player: Player, depth: number, groupScene: boolean?): boolean
	local state = PlayerState.get(player.UserId)
	local brazier = braziers[depth]
	if state == nil or brazier == nil then
		return false
	end
	if brazier.groupCommitInProgress and groupScene ~= true then
		return false
	end
	if not state.alive or state.finished or state.snuffedAt ~= nil or not state.isLit then
		return false
	end
	if state.depth ~= depth then
		return false
	end
	if
		(state.position - brazier.position).Magnitude
		> Config.Brazier.promptRange + Config.Brazier.positionToleranceStuds
	then
		return false
	end

	local globalDepth = PlayerState.globalDepth(state)

	-- THE PAYOUT, ATTEMPTED BEFORE ANYTHING ELSE IS COMMITTED. If the profile write fails the player
	-- keeps their cargo and their run: `finished` is not latched, the candle is not drained, and the
	-- brazier stays usable. Draining first and discovering the write failed afterwards would strand a
	-- player at an unusable brazier holding a bag they were never paid for.
	local outcome = ExtractionService.extract(player.UserId, globalDepth)
	if not outcome.ok then
		Remotes.get("RunEvent"):FireClient(player, "message", {
			text = "The lantern would not catch. Your Raw Wax is safe. Try again.",
		})
		return false
	end

	state.finished = true
	brazier.groupReady[player.UserId] = nil
	-- The candle is emptied and attributed so the wax ledger still reconciles to zero. Nothing about
	-- this number reaches a profile any more: leftover wax is worth exactly nothing at the surface.
	local newWax, delivered = WaxAccounting.drainToEmpty(state.wax, state.waxLedger, "Extraction")
	state.wax = newWax

	local profile = Interfaces.Persistence.get(player.UserId)
	profile.runsCompleted += 1
	profile.deepestFloor = math.max(profile.deepestFloor, globalDepth)
	profile.totalWaxDelivered += delivered
	Interfaces.Persistence.save(player.UserId, profile)
	-- Mirrors the per-profile record into the cross-server standings the hub's board reads.
	Interfaces.Leaderboard.submit(player.UserId, profile.deepestFloor)
	LeaderboardService.requestRefresh()
	RunSummaryService.emit(player.UserId, "Extraction")
	ExtractionService.emitRunSummary(player.UserId, "Extraction", delivered)
	-- This player is out. If they were the last of the party still down there, the "everyone came
	-- back" bonus settles now, retroactively, for every member who extracted alive.
	local bonuses = ExtractionService.settlePartyBonus()
	BrazierService.announceBonuses(bonuses)
	Telemetry.event("brazier_commit", player.UserId, {
		depth = depth,
		globalDepth = globalDepth,
		reward = outcome.payout,
		grams = outcome.grams,
		balance = outcome.balance,
		wax = math.floor(delivered * 1000) / 1000,
	})

	CharacterService.freeze(player.UserId)
	local partyStillInside = if groupScene == true
		then false
		else ExtractionService.hasUnresolvedPartyMember(player.UserId)
	local getsFreeLook = groupScene == true or not partyStillInside
	if getsFreeLook then
		CharacterService.face(player.UserId, lanternSceneFocus(brazier))
		Remotes.get("RunEvent"):FireClient(player, "message", {
			text = "The cave is safe. Look around.",
		})
	end
	if groupScene ~= true or not brazier.networkSequenceRunning then
		igniteLantern(brazier, state.position)
		beginNetworkSequence(brazier)
	end

	-- THE CARD IS BUILT NOW AND SHOWN AFTER THE LIGHTING SHOT. Every number on it is read here, at the
	-- instant the player committed, rather than after the beat: the card is a report of the decision that was
	-- just made, and the payout, the bonus and the party's state were all settled above. Reading them
	-- again on the far side of a yield would let a teammate's unrelated extraction land inside this
	-- player's own moment and change what their card says about it.
	local results = {
		survived = true,
		depthReached = depth,
		-- Reported so the run still reads honestly, and labelled on the card as what it now is: fuel
		-- you had left over, not money you earned.
		waxDelivered = delivered,
		reward = outcome.payout,
		balance = outcome.balance,
		cavePayoutPermille = outcome.cavePayoutPermille,
		depositsMined = state.depositsMinedThisRun,
		depositsMinedAtDepths = state.depositsMinedAtDepths,
		rawWax = ExtractionService.resultsPayload(player.UserId),
		-- The result card's lobby button becomes an explicit early-extraction choice while somebody
		-- else is unresolved. Leaving now keeps the payout above and forfeits only this pending boost.
		partyStillInside = partyStillInside,
		pendingPartyBonus = ExtractionService.pendingPartyBonus(player.UserId),
	}

	-- THE BEAT (Config/Lantern.network). Yields while the room lamps catch and the finished cave holds,
	-- with the player still frozen from the call above. Nothing can go wrong in that window that this has to
	-- handle: `state.finished` was latched before it, and every system that could hurt a runner —
	-- wax drain, hazards, threat targeting — already refuses a finished player.
	if getsFreeLook then
		task.wait(math.max(Config.Lantern.network.freeLookSeconds, 0))
	end

	-- WHO IS STILL OWED THIS CARD. The shot is long enough to leave, and long enough for a restart
	-- to have reset the run out from under this commit. Re-fetching the state and requiring it to be
	-- the same finished table catches both: a reset either clears the entry or clears the flag, and
	-- either way this player's run is no longer the one that was paid.
	if player.Parent ~= Players or PlayerState.get(player.UserId) ~= state or not state.finished then
		return false
	end
	if groupScene == true then
		results.balance = Interfaces.Persistence.get(player.UserId).currency
		results.rawWax = ExtractionService.resultsPayload(player.UserId)
		results.partyStillInside = ExtractionService.hasUnresolvedPartyMember(player.UserId)
		results.pendingPartyBonus = ExtractionService.pendingPartyBonus(player.UserId)
	end
	Remotes.get("RunEvent"):FireClient(player, "results", results)
	return true
end

local function validGroupMember(player: Player, brazier: Brazier): boolean
	local state = PlayerState.get(player.UserId)
	return state ~= nil
		and state.alive
		and not state.finished
		and state.snuffedAt == nil
		and state.isLit
		and state.depth == brazier.depth
		and (state.position - brazier.position).Magnitude
			<= Config.Brazier.promptRange + Config.Brazier.positionToleranceStuds
end

local function groupReadyStatus(brazier: Brazier): (number, { Types.PlayerId })
	for playerId in brazier.groupReady do
		local player = Players:GetPlayerByUserId(playerId)
		if player == nil or not validGroupMember(player, brazier) then
			brazier.groupReady[playerId] = nil
		end
	end
	local required = ExtractionService.unresolvedPartyMembers()
	local ready = 0
	for _, playerId in required do
		if brazier.groupReady[playerId] then
			ready += 1
		end
	end
	return ready, required
end

local function updateGroupPrompt(brazier: Brazier)
	local ready, required = groupReadyStatus(brazier)
	brazier.groupPrompt.Enabled = #required >= 2 and not brazier.groupCommitInProgress
	brazier.groupPrompt.ObjectText = string.format("Group extract · %d/%d ready", ready, #required)
end

local function announceGroupReady(player: Player, isReady: boolean, ready: number, required: number)
	local text = string.format(
		"%s %s group extraction. (%d/%d)",
		player.Name,
		if isReady then "is ready for" else "cancelled",
		ready,
		required
	)
	for _, playerId in ExtractionService.unresolvedPartyMembers() do
		local member = Players:GetPlayerByUserId(playerId)
		if member ~= nil then
			Remotes.get("RunEvent"):FireClient(member, "message", { text = text })
		end
	end
end

local function commitGroup(brazier: Brazier, required: { Types.PlayerId })
	brazier.groupCommitInProgress = true
	brazier.groupPrompt.Enabled = false

	-- Readiness is permission, not authority. Revalidate every member at the commitment edge so a
	-- player who walked away, changed floor, was snuffed, or disconnected cannot be pulled out.
	for _, playerId in required do
		local member = Players:GetPlayerByUserId(playerId)
		if member == nil or not brazier.groupReady[playerId] or not validGroupMember(member, brazier) then
			brazier.groupCommitInProgress = false
			updateGroupPrompt(brazier)
			return
		end
	end

	table.clear(brazier.groupReady)
	Telemetry.event("group_extraction_started", nil, {
		depth = brazier.depth,
		members = #required,
	})
	-- Each task owns one transactional profile write, but all begin on this server tick, share the
	-- same lamp sequence, wait the same five seconds, and reveal together. A failed write safely leaves
	-- only that player's cargo and run unresolved; cross-profile currency writes cannot be atomic.
	for _, playerId in required do
		local member = Players:GetPlayerByUserId(playerId)
		if member ~= nil then
			task.spawn(function()
				commit(member, brazier.depth, true)
			end)
		end
	end
	task.delay(math.max(Config.Lantern.network.freeLookSeconds, 0) + 1, function()
		if braziers[brazier.depth] ~= brazier then
			return
		end
		brazier.groupCommitInProgress = false
		updateGroupPrompt(brazier)
	end)
end

local function toggleGroupReady(player: Player, depth: number)
	local brazier = braziers[depth]
	if brazier == nil or brazier.groupCommitInProgress or not validGroupMember(player, brazier) then
		return
	end
	local _, required = groupReadyStatus(brazier)
	if #required < 2 then
		Remotes.get("RunEvent"):FireClient(player, "message", {
			text = "You are the last runner. Light the lantern normally.",
		})
		return
	end

	-- A split party cannot leave readiness behind on another floor's lantern.
	for _, other in braziers do
		if other ~= brazier then
			other.groupReady[player.UserId] = nil
			updateGroupPrompt(other)
		end
	end
	local isReady = not brazier.groupReady[player.UserId]
	brazier.groupReady[player.UserId] = if isReady then true else nil
	local ready, currentRequired = groupReadyStatus(brazier)
	updateGroupPrompt(brazier)
	announceGroupReady(player, isReady, ready, #currentRequired)

	if ready == #currentRequired and #currentRequired >= 2 then
		commitGroup(brazier, currentRequired)
	end
end

-- Tell everyone who earned it that the party bonus landed. Called after any resolution that could
-- have been the last one, so the message arrives the moment the run is genuinely over rather than
-- being predicted earlier by whoever happened to leave first.
function BrazierService.announceBonuses(bonuses: { [Types.PlayerId]: number })
	for playerId, amount in bonuses do
		local member = Players:GetPlayerByUserId(playerId)
		if member ~= nil and amount > 0 then
			Remotes.get("RunEvent"):FireClient(member, "partyBonus", {
				amount = amount,
				balance = Interfaces.Persistence.get(playerId).currency,
			})
		end
	end
end

function BrazierService.setCaveTier(_tierId: number)
	-- The cave's payout scaling is read by ExtractionService from the tier row directly. Kept as a
	-- no-op entry point so RunOrchestrator's setup sequence does not have to special-case this
	-- service, and so a future brazier that DOES vary by cave has an obvious place to hook in.
end

-- The fixture is built by `FloorBuilder` (NewModelsAndObjects/Lantern) and handed over already cold.
-- This service adds the prompt and owns everything that happens after it is held.
function BrazierService.registerFloor(
	depth: number,
	runtime: {
		position: Vector3,
		built: Lantern.BuiltLantern,
		networkLamps: { Lantern.BuiltLantern },
	}
)
	local lantern = runtime.built

	-- An invisible anchor at the lamp head rather than the prompt hung on a pane or the flame: the
	-- glass is cleared and the flame is revealed at ignition, and a prompt parented to either would
	-- inherit their transparency changes.
	local anchor = Instance.new("Part")
	anchor.Name = "LanternPrompt"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Position = lantern.headPosition
	anchor.Parent = lantern.model

	local prompt = Instance.new("ProximityPrompt")
	-- The wording is the whole decision, so it says what it does rather than what it is: this is the
	-- moment DESIGN §12 calls "the run ends on a decision you made".
	prompt.ActionText = "Light the lantern"
	prompt.ObjectText = "End your run"
	prompt.HoldDuration = Config.Brazier.commitHoldSeconds
	prompt.MaxActivationDistance = Config.Brazier.promptRange
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.UIOffset = Vector2.new(0, -34)
	prompt.Triggered:Connect(function(player: Player)
		commit(player, depth)
	end)
	prompt.Parent = anchor

	-- A separate unanimous path. Every unresolved runner presses this button for themselves; the last
	-- confirmation starts all payouts on the same server tick. G/Y keeps the ordinary E/X individual
	-- exit intact, and Roblox renders both prompts as touch buttons automatically.
	local groupPrompt = Instance.new("ProximityPrompt")
	groupPrompt.Name = "GroupExtractPrompt"
	groupPrompt.ActionText = "Ready together"
	groupPrompt.ObjectText = "Group extract · 0/0 ready"
	groupPrompt.KeyboardKeyCode = Enum.KeyCode.G
	groupPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	groupPrompt.HoldDuration = Config.Brazier.commitHoldSeconds
	groupPrompt.MaxActivationDistance = Config.Brazier.promptRange
	groupPrompt.RequiresLineOfSight = false
	groupPrompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	groupPrompt.UIOffset = Vector2.new(0, 34)
	groupPrompt.Enabled = false
	groupPrompt.Triggered:Connect(function(player: Player)
		toggleGroupReady(player, depth)
	end)
	groupPrompt.Parent = anchor

	braziers[depth] = {
		depth = depth,
		position = runtime.position,
		lantern = lantern,
		lit = false,
		networkLamps = runtime.networkLamps,
		groupPrompt = groupPrompt,
		groupReady = {},
		groupCommitInProgress = false,
		networkSequenceRunning = false,
	}
	updateGroupPrompt(braziers[depth])
end

-- Live arithmetic for anyone standing at their floor's brazier (and a clear when they leave).
function BrazierService.tick(dt: number)
	previewAccumulator += dt
	if previewAccumulator < Config.Brazier.previewUpdateSeconds then
		return
	end
	previewAccumulator = 0

	for playerId, state in PlayerState.all() do
		local player = Players:GetPlayerByUserId(playerId)
		if player == nil then
			continue
		end
		local brazier = braziers[state.depth]
		local near = brazier ~= nil
			and state.alive
			and not state.finished
			and (state.position - brazier.position).Magnitude <= Config.Brazier.promptRange
		if near and brazier ~= nil then
			-- THE ONLY PLACE A PLAYER SEES WHAT THEIR BAG IS WORTH. In the cave they carry a mass in
			-- grams and nothing more; the exact currency value is revealed here, at the exit, which is
			-- where the decision it informs actually gets made. Computed by the same call the commit
			-- uses, so the number shown and the number paid cannot drift apart.
			local breakdown = ExtractionService.previewValue(playerId)
			previewShown[playerId] = true
			Remotes.get("RunEvent"):FireClient(player, "brazierPreview", {
				grams = if breakdown ~= nil then breakdown.grams else 0,
				baseValue = if breakdown ~= nil then breakdown.baseValue else 0,
				cavePayoutPermille = if breakdown ~= nil then breakdown.cavePayoutPermille else 1000,
				total = if breakdown ~= nil then breakdown.total else 0,
				-- What the "everyone came back" bonus would add on top, if the party all make it out.
				-- Shown as a possibility, never as a promise: it is not paid until the last one is up.
				potentialPartyBonus = ExtractionService.potentialPartyBonus(playerId),
			})
		elseif previewShown[playerId] then
			previewShown[playerId] = nil
			Remotes.get("RunEvent"):FireClient(player, "brazierPreviewClear", {})
		end
	end
	for _, brazier in braziers do
		updateGroupPrompt(brazier)
	end
end

function BrazierService.clearDepth(depth: number)
	braziers[depth] = nil
end

function BrazierService.reset()
	table.clear(braziers) -- anchors die with the floor models
	table.clear(previewShown)
	previewAccumulator = 0
end

return BrazierService
