--!strict

local Harness = require(script.Parent.Harness)
local LampRules = require(script.Parent.Parent.Logic.LampRules)
local LampConfig = require(script.Parent.Parent.Config.LampNetwork)

-- The owned-node set a player reaches by buying the whole trunk. Written out rather than derived so
-- a test that depends on it fails loudly if the trunk is ever renamed.
local TRUNK = { "lamp.pay_table", "lamp.contract_board" }

local function withAll(): { string }
	local owned: { string } = {}
	for _, node in LampConfig.nodes do
		table.insert(owned, node.id)
	end
	return owned
end

local suite: Harness.Suite = {
	name = "LampRules",
	tests = {
		Harness.test("every node id is unique and every prerequisite names a real node", function()
			-- A typo in a `requires` string would otherwise present as a node nobody can ever buy, with
			-- no error anywhere — the failure mode a config-driven track is most exposed to.
			local seen: { [string]: boolean } = {}
			for _, node in LampConfig.nodes do
				Harness.expect(not seen[node.id], "duplicate node id " .. node.id)
				seen[node.id] = true
			end
			for _, node in LampConfig.nodes do
				for _, required in node.requires do
					Harness.expect(seen[required], node.id .. " requires unknown node " .. required)
				end
				for _, candidate in node.requiresAny do
					Harness.expect(seen[candidate], node.id .. " lists unknown any-of node " .. candidate)
				end
				Harness.expect(
					node.requiresAnyCount <= #node.requiresAny,
					node.id .. " needs more any-of nodes than it lists, so it could never be bought"
				)
			end
		end),

		Harness.test("the prerequisite graph is acyclic and every node is reachable from nothing", function()
			-- Two nodes requiring each other would be invisible in review and unbuyable in play. Proven
			-- by repeatedly buying everything currently affordable and asserting the set closes over all
			-- nodes; a cycle leaves its members permanently unreachable and the loop stalls.
			local owned: { string } = {}
			for _ = 1, #LampConfig.nodes do
				for _, node in LampConfig.nodes do
					if
						not LampRules.ownsNode(owned, node.id)
						and LampRules.missingPrerequisite(owned, node.id) == nil
					then
						table.insert(owned, node.id)
					end
				end
			end
			Harness.equal(
				#owned,
				#LampConfig.nodes,
				"some node is unreachable — the graph has a cycle or a dead edge"
			)
		end),

		Harness.test("exactly one node is buyable from an empty profile", function()
			-- A track with two roots has no "first purchase", and the cheapest thing a new player can
			-- afford stops being an obvious next step.
			local roots = 0
			for _, node in LampConfig.nodes do
				if LampRules.missingPrerequisite({}, node.id) == nil then
					roots += 1
				end
			end
			Harness.equal(roots, 1, "the track must have exactly one entry point")
		end),

		Harness.test("costs are whole positive numbers and rise along every edge", function()
			-- Currency is persisted, so a fractional cost is a persisted float waiting to happen. And a
			-- node cheaper than its own prerequisite would let a player see the expensive thing first.
			for _, node in LampConfig.nodes do
				Harness.expect(
					node.cost > 0 and node.cost % 1 == 0,
					node.id .. " must cost a whole positive number of Raw Wax"
				)
				for _, required in node.requires do
					local parent = LampRules.getNode(required)
					Harness.expect(
						parent ~= nil and node.cost > (parent :: LampRules.LampNode).cost,
						node.id .. " must cost more than its prerequisite " .. required
					)
				end
			end
		end),

		Harness.test("every node states what it does at the point of purchase", function()
			-- The prompt clause is not flavour: it is how a name that cannot carry its own meaning still
			-- gets bought on purpose. An empty one is a node nobody can evaluate at the counter.
			for _, node in LampConfig.nodes do
				Harness.expect(#node.displayName > 0, "a node must have a name")
				Harness.expect(#node.promptClause > 0, node.id .. " must state its effect on the prompt")
			end
		end),

		Harness.test("a missing hard prerequisite is named exactly", function()
			-- The refusal a player reads has to point at a specific thing to go and buy.
			Harness.equal(LampRules.missingPrerequisite({}, "lamp.contract_board"), "lamp.pay_table")
			Harness.equal(LampRules.missingPrerequisite({ "lamp.pay_table" }, "lamp.contract_board"), nil)
			Harness.equal(LampRules.missingPrerequisite(TRUNK, "lamp.deep_seam"), "lamp.twin_seam")
		end),

		Harness.test("the any-of gate needs its count, and points at the cheapest way in", function()
			local gate = "lamp.hard_contracts"
			local node = LampRules.getNode(gate)
			Harness.expect(node ~= nil, "the hard-contract gate must exist")
			local required = (node :: LampRules.LampNode).requiresAnyCount
			Harness.expect(required >= 2, "the branch point must need more than one road in")

			-- Zero of the any-of set: refused, and pointed at the cheapest candidate rather than an
			-- arbitrary one, so the advice is the shortest road rather than the first row written.
			local cheapest: string? = nil
			local cheapestCost = math.huge
			for _, candidateId in (node :: LampRules.LampNode).requiresAny do
				local candidate = LampRules.getNode(candidateId)
				if candidate ~= nil and candidate.cost < cheapestCost then
					cheapest, cheapestCost = candidateId, candidate.cost
				end
			end
			Harness.equal(LampRules.missingPrerequisite(TRUNK, gate), cheapest)

			-- One short is still refused; the count is a real threshold, not a suggestion.
			local oneShort = table.clone(TRUNK)
			table.insert(oneShort, (node :: LampRules.LampNode).requiresAny[1])
			Harness.expect(
				LampRules.missingPrerequisite(oneShort, gate) ~= nil,
				"one of the any-of set must not open a gate that asks for two"
			)

			-- Any two of them open it — including the two a seam-branch player and a room-branch player
			-- would each have arrived with.
			local candidates = (node :: LampRules.LampNode).requiresAny
			for first = 1, #candidates do
				for second = first + 1, #candidates do
					local owned = table.clone(TRUNK)
					table.insert(owned, candidates[first])
					table.insert(owned, candidates[second])
					Harness.equal(
						LampRules.missingPrerequisite(owned, gate),
						nil,
						"any two of the branch nodes must open the gate"
					)
				end
			end
		end),

		Harness.test("an unknown node is never accidentally buyable or priced", function()
			Harness.equal(LampRules.getNode("lamp.nope"), nil)
			Harness.equal(LampRules.getNode(""), nil)
			Harness.equal(LampRules.costOf("lamp.nope"), 0, "an unknown node must never produce a charge")
			Harness.equal(LampRules.ownsNode({}, "lamp.nope"), false)
		end),

		Harness.test("every contract costs the player something and pays a whole permille", function()
			-- A contract at or below the neutral rate would be a handicap for free, and a fractional
			-- permille would put a float into a payout that is persisted as an integer.
			local seen: { [string]: boolean } = {}
			for _, contract in LampConfig.contracts.rows do
				Harness.expect(not seen[contract.id], "duplicate contract id " .. contract.id)
				seen[contract.id] = true
				Harness.expect(
					contract.payoutPermille > LampConfig.wager.basePermille,
					contract.id .. " must pay more than the neutral rate or it is a handicap for nothing"
				)
				Harness.expect(contract.payoutPermille % 1 == 0, contract.id .. " must pay a whole permille")
				Harness.expect(#contract.rule > 0, contract.id .. " must state its rule")
				Harness.expect(
					LampRules.getNode(contract.unlockNode) ~= nil,
					contract.id .. " is sold by unknown node " .. contract.unlockNode
				)
			end
		end),

		Harness.test("no contract caps how many units a player may bank", function()
			-- THE RULE, and it is arithmetic rather than taste: a multiplier on quantity cannot pay back
			-- a loss of quantity. A "break only N deposits" row at 1700 permille banks 86 against 517 at
			-- floor 8 and would need 6000 to break even. This test cannot read intent, so it pins the
			-- ceiling that any such row would have to exceed — a row authored above it is a row somebody
			-- has tried to pay for a unit cap, and it fails here rather than in play.
			for _, contract in LampConfig.contracts.rows do
				Harness.expect(
					contract.payoutPermille <= 3000,
					contract.id
						.. " pays past the point any safety/time/capability cost can justify;"
						.. " a rate this high usually means the rule caps units, which can never be paid back"
				)
			end
		end),

		Harness.test("every node names a layer, and only the Pay Table is exempt from a rollback", function()
			-- A node with no layer would fall through `nodeIsLive` and fail closed forever, which reads
			-- in game as a lamp nobody can ever buy for no stated reason.
			local exempt = 0
			for _, node in LampConfig.nodes do
				Harness.expect(typeof(node.layer) == "string" and #node.layer > 0, node.id .. " needs a layer")
				if node.layer == "always" then
					exempt += 1
					Harness.equal(
						node.id,
						"lamp.pay_table",
						node.id .. " claims it can never be rolled back; only a read-only display may"
					)
				end
			end
			Harness.equal(exempt, 1, "exactly one node may be exempt from rollback")
		end),

		Harness.test("a node whose layer is rolled back cannot be sold", function()
			-- THE rule this gate exists for: purchases are final and there is no refund mechanic, so
			-- taking currency for a lamp whose effect is switched off is unrecoverable for the player.
			-- Ownership is never revoked by a rollback — this only stops NEW sales.
			for _, node in LampConfig.nodes do
				Harness.equal(
					LampRules.nodeIsLive(node.id),
					LampRules.layerIsLive(node.layer),
					node.id .. " must be sellable exactly when its layer is live"
				)
			end
			-- Fail closed on nonsense, rather than defaulting to sellable.
			Harness.equal(LampRules.layerIsLive("no-such-layer"), false, "an unknown layer must fail closed")
			Harness.equal(LampRules.nodeIsLive("lamp.nope"), false, "an unknown node is never sellable")
		end),

		Harness.test("a rolled-back contract layer offers nothing to anyone", function()
			-- The rollback flags are real switches, so the suite has to hold in BOTH states rather than
			-- silently encoding whichever one happens to be shipping. When the layer is off, owning every
			-- node in the game must still offer zero rows and pay the neutral rate — an unenforced
			-- contract that still paid would be the pure-power upgrade this whole track forbids.
			if LampRules.contractsEnabled() then
				return
			end
			Harness.equal(#LampRules.availableContracts(withAll(), 4), 0, "a disabled layer must offer nothing")
			Harness.equal(
				LampRules.resolvePermille(LampConfig.contracts.rows[1].id, nil, 12),
				LampConfig.wager.basePermille,
				"a disabled layer must never pay a contract rate"
			)
		end),

		Harness.test("party-only contracts are hidden from solo, and standing rows are not", function()
			if not LampRules.contractsEnabled() then
				return
			end
			local owned = withAll()
			local solo = LampRules.availableContracts(owned, 1)
			for _, contract in solo do
				Harness.equal(contract.minPartySize, 1, contract.id .. " must not be offered to a solo player")
			end
			local pair = LampRules.availableContracts(owned, 2)
			Harness.expect(#pair > #solo, "a party must be offered strictly more than a solo player")
		end),

		Harness.test("a locked board offers nothing, whatever the party size", function()
			-- True in either rollback state: not owning the board is its own reason for an empty list.
			Harness.equal(#LampRules.availableContracts({}, 4), 0)
			Harness.equal(#LampRules.availableContracts({ "lamp.pay_table" }, 4), 0)
			if not LampRules.contractsEnabled() then
				return
			end
			Harness.expect(
				#LampRules.availableContracts(TRUNK, 1) > 0,
				"the trunk must actually open the standing contracts"
			)
		end),

		Harness.test("a wager target must beat the player's own record", function()
			-- This single rule is what stops the wager being free money for naming a depth you were
			-- going to reach anyway, and it makes the bet self-scaling with no further tuning.
			local floor = LampConfig.wager.minimumTarget
			Harness.equal(LampRules.minimumWagerTarget(0), floor, "a new player starts at the configured floor")
			Harness.equal(LampRules.minimumWagerTarget(floor - 2), floor, "the floor still binds below it")
			Harness.equal(LampRules.minimumWagerTarget(floor + 3), floor + 4, "past the floor it is always record + 1")
			-- Hostile records must not lower the bar.
			Harness.equal(LampRules.minimumWagerTarget(-5), floor)
			Harness.equal(LampRules.minimumWagerTarget(0 / 0), floor)
		end),

		Harness.test("wager payouts are whole permille, monotonic, and capped", function()
			local wager = LampConfig.wager
			Harness.equal(LampRules.wagerPermilleFor(wager.minimumTarget), wager.basePermille + wager.permillePerDepth)

			local previous = 0
			for target = wager.minimumTarget, wager.minimumTarget + 30 do
				local permille = LampRules.wagerPermilleFor(target)
				Harness.expect(permille % 1 == 0, "wager permille must be whole at target " .. target)
				Harness.expect(permille >= previous, "a deeper target must never pay less")
				Harness.expect(permille <= wager.maximumPermille, "the cap must bind at target " .. target)
				previous = permille
			end
			Harness.equal(
				LampRules.wagerPermilleFor(10_000),
				wager.maximumPermille,
				"depth is uncapped, so the multiplier must not be"
			)

			-- Anything invalid is worth nothing extra rather than something surprising.
			for _, bad in { wager.minimumTarget - 1, -3, 7.5, 0 / 0, math.huge } do
				Harness.equal(LampRules.wagerPermilleFor(bad), wager.basePermille, "invalid target " .. tostring(bad))
			end
		end),

		Harness.test("a resolved bet never pays below neutral and never stacks two scalars", function()
			local base = LampConfig.wager.basePermille
			local target = LampConfig.wager.minimumTarget + 2

			Harness.equal(LampRules.resolvePermille(nil, nil, 12), base, "no bet pays the neutral rate")
			Harness.equal(LampRules.resolvePermille("contract.nope", nil, 12), base, "an unknown contract pays neutral")

			if LampRules.wagerEnabled() then
				-- A wager pays only if the player actually got there.
				Harness.equal(
					LampRules.resolvePermille(nil, target, target - 1),
					base,
					"a missed wager pays nothing extra"
				)
				Harness.equal(LampRules.resolvePermille(nil, target, target), LampRules.wagerPermilleFor(target))
				Harness.equal(LampRules.resolvePermille(nil, target, target + 5), LampRules.wagerPermilleFor(target))
			end

			if not LampRules.contractsEnabled() then
				return
			end
			local contract = LampConfig.contracts.rows[1]
			Harness.equal(LampRules.resolvePermille(contract.id, nil, 1), contract.payoutPermille)

			-- Both set at once should be unreachable upstream. If stale profile fields ever produce it,
			-- exactly one scalar must apply — never their product.
			Harness.equal(
				LampRules.resolvePermille(contract.id, target, target + 5),
				contract.payoutPermille,
				"a contract and a wager must never compound"
			)
		end),
	},
}

return suite
