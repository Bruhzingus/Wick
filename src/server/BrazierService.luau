--!strict
-- The Brazier (DESIGN §12): the only way Raw Wax becomes money. Shows the player the real arithmetic
-- while they stand at it (deliberate design choice), commits on a held prompt, and pays through the
-- transactional Persistence boundary.
--
-- THE FIXTURE IS A BRAZIER (Config/Brazier, NewModelsAndObjects/Brazier) and the service is what it
-- always was. Every number, gate and payout path below is exactly what it was when the object was one
-- grey box: what changed is that there is something to walk up to, that it catches when you commit,
-- and that it stays lit for everybody afterwards.
--
-- WHAT WAS REMOVED FROM THIS FILE, and why it is a deletion rather than a move. For one iteration the
-- fixture here was a Gas Lantern whose ignition also ran a floor-wide lamp cascade and held the
-- player frozen through a five-second camera beat before their results card. That coupling made the
-- object that ENDS ONE PLAYER'S RUN responsible for lighting rooms nobody was standing in, and it was
-- a cutscene that had to be staged, timed and compressed to fit — none of which this service should
-- ever have been holding.
--
-- Lighting the cave is now a player verb with its own fixtures and its own service
-- (`server/WallLampService`), available mid-run and unrelated to cashing out. So the lamp list, the
-- cascade, the free-look window, the camera turn and the enemy sweep are all gone from here, and what
-- is left is the thing this file is for: you hold a prompt at a fire, you get paid, you see your card.
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
local Brazier = require(ReplicatedStorage.Shared.NewModelsAndObjects.Brazier)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local ExtractionService = require(script.Parent.ExtractionService)
local RunSummaryService = require(script.Parent.RunSummaryService)
local Telemetry = require(script.Parent.Telemetry)

local BrazierService = {}

-- ONE FLOOR'S BRAZIER (Config/Brazier). `lit` is SHARED and one-way: the first player to commit here
-- lights the fire for everybody, and it never goes out again.
--
-- WHY SHARED. The reward is already independent per player — each commit reads that player's own
-- cargo, pays their own profile, and can happen minutes apart — so the only question the prop had to
-- answer was whose fire it is. Making the lit state private would mean two people standing at the
-- same bowl disagreeing about whether it is burning, which is a worse answer than "somebody lit this,
-- and the fire is real".
type BrazierFloor = {
	depth: number,
	position: Vector3,
	built: Brazier.BuiltBrazier?,
	lit: boolean,
	groupPrompt: ProximityPrompt,
	groupReady: { [Types.PlayerId]: boolean },
	groupCommitInProgress: boolean,
}

local braziers: { [number]: BrazierFloor } = {} -- keyed by depth
local previewShown: { [Types.PlayerId]: boolean } = {}
local previewAccumulator = 0

-- THE IGNITION.
--
-- FIRED ON EVERY COMMIT, LIT ONLY ONCE. The fire catches for the whole floor the first time anybody
-- uses it; the flare and the answering echoes play again for each player who commits, because that
-- beat belongs to the decision rather than to the object. A second player ending their run at an
-- already-burning brazier still gets their own moment.
--
-- IT REACHES NOTHING OUTSIDE THIS ROOM. It used to clear every enemy the floor owned, which was a
-- consequence of the fixture also being the thing that lit the cave; a floor is now made safer by
-- players lighting it (`server/WallLampService`), and cashing out neither helps nor harms whoever is
-- still down there.
local function igniteBrazier(floor: BrazierFloor, litFrom: Vector3)
	local built = floor.built
	if built == nil then
		return
	end
	if not floor.lit then
		floor.lit = true
		Brazier.setLit(built, true)
	end

	-- Echo anchors spread back toward the approach instead of all stacking at the fixture.
	local away = Vector3.new(litFrom.X - built.rimPosition.X, 0, litFrom.Z - built.rimPosition.Z)
	local direction = if away.Magnitude > 0.5 then away.Unit else Vector3.new(0, 0, -1)
	Remotes.get("RunEvent"):FireAllClients("brazierLit", {
		position = built.rimPosition,
		direction = direction,
		model = built.model,
	})
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
			text = "The brazier would not catch. Your Raw Wax is safe. Try again.",
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

	-- The candle stops being an actor and stays as scenery. It is no longer turned to face anything:
	-- there is no staged shot to point it at, and the fire it just lit is the thing it was already
	-- standing in front of.
	CharacterService.freeze(player.UserId)
	local partyStillInside = if groupScene == true
		then false
		else ExtractionService.hasUnresolvedPartyMember(player.UserId)
	igniteBrazier(brazier, state.position)

	-- THE CARD IS BUILT AND SHOWN NOW. Every number on it is read at the instant the player committed:
	-- the card is a report of the decision that was just made, and the payout, the bonus and the
	-- party's state were all settled above.
	--
	-- THERE IS NO LONGER A YIELD BETWEEN THE TWO. This used to hold the player frozen for a five-second
	-- lamp cascade before revealing the card, which is why the block below re-checked whether the run
	-- still existed on the far side of the wait. Nothing waits any more, so nothing can change
	-- underneath it, and a teammate's unrelated extraction can no longer land inside this player's own
	-- moment.
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

	-- A GROUP COMMIT STILL RE-READS THE SHARED NUMBERS. Every member's payout runs as its own task on
	-- the same tick, so a member early in the loop computed their card before the members after them
	-- had been paid — and the balance and the party bonus are cross-member figures. This is a read of
	-- values another task in this same batch may have moved, not a guard against a yield.
	if groupScene == true then
		if player.Parent ~= Players or PlayerState.get(player.UserId) ~= state or not state.finished then
			return false
		end
		results.balance = Interfaces.Persistence.get(player.UserId).currency
		results.rawWax = ExtractionService.resultsPayload(player.UserId)
		results.partyStillInside = ExtractionService.hasUnresolvedPartyMember(player.UserId)
		results.pendingPartyBonus = ExtractionService.pendingPartyBonus(player.UserId)
	end
	Remotes.get("RunEvent"):FireClient(player, "results", results)
	return true
end

local function validGroupMember(player: Player, brazier: BrazierFloor): boolean
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

local function groupReadyStatus(brazier: BrazierFloor): (number, { Types.PlayerId })
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

local function updateGroupPrompt(brazier: BrazierFloor)
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

local function commitGroup(brazier: BrazierFloor, required: { Types.PlayerId })
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
	-- Each task owns one transactional profile write, but all begin on this server tick and reveal
	-- together. A failed write safely leaves only that player's cargo and run unresolved;
	-- cross-profile currency writes cannot be atomic.
	for _, playerId in required do
		local member = Players:GetPlayerByUserId(playerId)
		if member ~= nil then
			task.spawn(function()
				commit(member, brazier.depth, true)
			end)
		end
	end
	-- Long enough for every member's own payout task above to have finished. It used to be the length
	-- of the lamp cascade plus a second; there is no cascade here any more, so it is a plain latch
	-- release and nothing is waiting on a camera.
	task.delay(math.max(Config.Brazier.groupPromptResetSeconds, 0), function()
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
			text = "You are the last runner. Light the brazier normally.",
		})
		return
	end

	-- A split party cannot leave readiness behind on another floor's brazier.
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

-- The fixture is built by `FloorBuilder` (NewModelsAndObjects/Brazier) and handed over already cold.
-- This service adds the prompt and owns everything that happens after it is held.
function BrazierService.registerFloor(
	depth: number,
	runtime: {
		position: Vector3,
		built: Brazier.BuiltBrazier,
	}
)
	local built = runtime.built

	-- An invisible anchor above the rim rather than the prompt hung on a coal or a flame: the coals
	-- change colour and material and the flames are revealed at ignition, and a prompt parented to
	-- either would inherit those changes.
	local anchor = Instance.new("Part")
	anchor.Name = "BrazierPrompt"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Position = built.rimPosition + Vector3.new(0, Config.Brazier.fixture.promptHeight, 0)
	anchor.Parent = built.model

	local prompt = Instance.new("ProximityPrompt")
	-- The wording is the whole decision, so it says what it does rather than what it is: this is the
	-- moment DESIGN §12 calls "the run ends on a decision you made".
	prompt.ActionText = "Light the brazier"
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
		built = built,
		lit = false,
		groupPrompt = groupPrompt,
		groupReady = {},
		groupCommitInProgress = false,
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
