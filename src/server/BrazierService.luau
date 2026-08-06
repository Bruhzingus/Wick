--!strict
-- The Brazier (DESIGN §12): the only way Raw Wax becomes money. Shows the player the real arithmetic
-- while they stand at it (deliberate design choice), commits on a held prompt, and pays through the
-- transactional Persistence boundary.
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

type Brazier = { position: Vector3, ignited: BasePart? }

local braziers: { [number]: Brazier } = {} -- keyed by depth
local previewShown: { [Types.PlayerId]: boolean } = {}
local previewAccumulator = 0

local function commit(player: Player, depth: number)
	local state = PlayerState.get(player.UserId)
	local brazier = braziers[depth]
	if state == nil or brazier == nil then
		return
	end
	if not state.alive or state.finished or state.snuffedAt ~= nil or not state.isLit then
		return
	end
	if state.depth ~= depth then
		return
	end
	if
		(state.position - brazier.position).Magnitude
		> Config.Brazier.promptRange + Config.Brazier.positionToleranceStuds
	then
		return
	end

	local globalDepth = PlayerState.globalDepth(state)

	-- THE PAYOUT, ATTEMPTED BEFORE ANYTHING ELSE IS COMMITTED. If the profile write fails the player
	-- keeps their cargo and their run: `finished` is not latched, the candle is not drained, and the
	-- brazier stays usable. Draining first and discovering the write failed afterwards would strand a
	-- player at an unusable brazier holding a bag they were never paid for.
	local outcome = ExtractionService.extract(player.UserId, globalDepth)
	if not outcome.ok then
		Remotes.get("RunEvent"):FireClient(player, "message", {
			text = "The brazier could not bank your haul. Your Raw Wax is safe. Try again.",
		})
		return
	end

	state.finished = true
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
		units = outcome.units,
		balance = outcome.balance,
		wax = math.floor(delivered * 1000) / 1000,
	})

	CharacterService.freeze(player.UserId)
	local ignited = brazier.ignited
	if ignited ~= nil then
		ignited.Material = Enum.Material.Neon
		ignited.Color = Color3.fromRGB(255, 170, 60)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 100)
		light.Range = Config.Light.maxRange
		light.Brightness = Config.Light.maxBrightness
		light.Parent = ignited
	end

	Remotes.get("RunEvent"):FireClient(player, "results", {
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
		partyStillInside = ExtractionService.hasUnresolvedPartyMember(player.UserId),
		pendingPartyBonus = ExtractionService.pendingPartyBonus(player.UserId),
	})
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

function BrazierService.registerFloor(depth: number, position: Vector3, parent: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = "BrazierBowl"
	anchor.Size = Vector3.new(2, 1, 2)
	anchor.Color = Color3.fromRGB(50, 40, 35)
	anchor.Material = Enum.Material.SmoothPlastic
	anchor.Anchored = true
	anchor.Position = position
	anchor.Parent = parent

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Light the Brazier"
	prompt.ObjectText = "End your run"
	prompt.HoldDuration = Config.Brazier.commitHoldSeconds
	prompt.MaxActivationDistance = Config.Brazier.promptRange
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player: Player)
		commit(player, depth)
	end)
	prompt.Parent = anchor

	braziers[depth] = { position = position, ignited = anchor }
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
			-- THE ONLY PLACE A PLAYER SEES WHAT THEIR BAG IS WORTH. In the cave they carry a unit
			-- count and nothing more; the exact currency value is revealed here, at the exit, which is
			-- where the decision it informs actually gets made. Computed by the same call the commit
			-- uses, so the number shown and the number paid cannot drift apart.
			local breakdown = ExtractionService.previewValue(playerId)
			previewShown[playerId] = true
			Remotes.get("RunEvent"):FireClient(player, "brazierPreview", {
				units = if breakdown ~= nil then breakdown.units else 0,
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
end

function BrazierService.reset()
	table.clear(braziers) -- anchors die with the floor models
	table.clear(previewShown)
	previewAccumulator = 0
end

return BrazierService
