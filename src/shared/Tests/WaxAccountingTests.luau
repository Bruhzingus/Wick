--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local WaxConfig = require(script.Parent.Parent.Config.Wax)
local WaxAccounting = require(script.Parent.Parent.Logic.WaxAccounting)

local function freshWax(): Types.WaxState
	return { current = WaxConfig.startingWax, max = WaxConfig.maxWax }
end

local function newLedger(): Types.WaxLedger
	return WaxAccounting.newLedger(WaxConfig.startingWax, 1, 0)
end

local suite: Harness.Suite = {
	name = "WaxAccounting",
	tests = {
		Harness.test("a spend can never create wax, whatever it is handed", function()
			local nan = 0 / 0
			for _, amount in { -1, -WaxConfig.maxWax, nan, -math.huge } do
				local wax = freshWax()
				local ledger = newLedger()
				local after = WaxAccounting.spend(wax, ledger, amount, "ToolFlare")
				Harness.expect(after.current <= wax.current, "spend of " .. tostring(amount) .. " added wax")
				Harness.equal(ledger.totalGained, 0, "a spend recorded a gain")
			end
			-- A non-finite amount is treated as a no-op, not as "drain everything": a broken caller
			-- must not be able to kill a candle.
			local broken = freshWax()
			local brokenLedger = newLedger()
			local afterBroken, brokenEmptied = WaxAccounting.spend(broken, brokenLedger, math.huge, "DamageThreat")
			Harness.equal(afterBroken.current, broken.current)
			Harness.expect(not brokenEmptied, "a non-finite spend must not report burnout")
			Harness.equal(brokenLedger.totalLost, 0)

			-- An oversized but finite spend stops at the floor rather than going negative.
			local wax = freshWax()
			local ledger = newLedger()
			local after, emptied = WaxAccounting.spend(wax, ledger, WaxConfig.maxWax * 100, "DamageThreat")
			Harness.equal(after.current, 0)
			Harness.expect(emptied, "emptying the candle must report burnout")
			Harness.near(ledger.lostBySource.DamageThreat :: number, WaxConfig.startingWax)
		end),

		Harness.test("a grant can never drain wax and never exceeds capacity", function()
			local nan = 0 / 0
			for _, amount in { -5, nan, -math.huge } do
				local wax = freshWax()
				local ledger = newLedger()
				local after = WaxAccounting.grant(wax, ledger, amount, "BasinGain")
				Harness.equal(after.current, wax.current, "grant of " .. tostring(amount) .. " removed wax")
				Harness.equal(ledger.totalLost, 0, "a grant recorded a loss")
			end
			-- Start below capacity (a fresh candle may already be full) so there is room to fill.
			local ledger = newLedger()
			local wax = WaxAccounting.spend(freshWax(), ledger, WaxConfig.maxWax * 0.5, "PassiveBurn")
			Harness.expect(wax.current < wax.max, "the candle should have room after spending half its capacity")
			local after, applied = WaxAccounting.grant(wax, ledger, WaxConfig.maxWax * 100, "FoundWaxGain")
			Harness.equal(after.current, wax.max, "ordinary gains must stop at capacity")
			Harness.near(applied, wax.max - wax.current)
			Harness.near(ledger.gainedBySource.FoundWaxGain :: number, applied)
		end),

		Harness.test("wax never falls below zero across a long mixed sequence", function()
			local wax = freshWax()
			local ledger = newLedger()
			for index = 1, 200 do
				wax = WaxAccounting.spend(wax, ledger, 0.02, if index % 2 == 0 then "PassiveBurn" else "MovementRun")
				wax = WaxAccounting.grant(wax, ledger, 0.005, "FoundWaxGain")
				Harness.expect(wax.current >= 0 and wax.current <= wax.max, "wax escaped its bounds at step " .. index)
			end
		end),

		Harness.test("every mutation is attributed to the reason it was given", function()
			local wax = freshWax()
			local ledger = newLedger()
			wax = WaxAccounting.spend(wax, ledger, 0.1, "ToolDecoy")
			wax = WaxAccounting.spend(wax, ledger, 0.2, "DamageDripstone")
			wax = WaxAccounting.spend(wax, ledger, 0.05, "ReviveCost")
			wax = WaxAccounting.grant(wax, ledger, 0.15, "BasinGain")
			Harness.near(ledger.lostBySource.ToolDecoy :: number, 0.1)
			Harness.near(ledger.lostBySource.DamageDripstone :: number, 0.2)
			Harness.near(ledger.lostBySource.ReviveCost :: number, 0.05)
			Harness.near(ledger.gainedBySource.BasinGain :: number, 0.15)
			Harness.isNil(ledger.lostBySource.BasinGain, "a gain leaked into the loss column")
		end),

		Harness.test("an unrecognized or client-shaped reason cannot invent a category", function()
			local wax = freshWax()
			local ledger = newLedger()
			-- Anything not in the closed vocabulary — including a string a client might try to smuggle
			-- in — lands in Other, where the summary makes it visible.
			wax = WaxAccounting.spend(wax, ledger, 0.1, "FreeWaxPlease")
			wax = WaxAccounting.spend(wax, ledger, 0.1, nil)
			Harness.near(ledger.lostBySource.Other :: number, 0.2)
			Harness.equal(WaxAccounting.normalizeSource("FreeWaxPlease"), "Other")
			Harness.expect(not WaxAccounting.isSource("FreeWaxPlease"), "unknown reasons are not sources")
			Harness.expect(WaxAccounting.isSource("PassiveBurn"), "known reasons are sources")
		end),

		Harness.test("the summary reconciles starting wax, gains, losses, and ending wax", function()
			local wax = freshWax()
			local ledger = newLedger()
			wax = WaxAccounting.spend(wax, ledger, 0.13, "PassiveBurn")
			wax = WaxAccounting.grant(wax, ledger, 0.04, "FoundWaxGain")
			wax = WaxAccounting.spend(wax, ledger, 0.27, "DamageWater")
			WaxAccounting.noteDepth(ledger, 7)
			WaxAccounting.noteDepth(ledger, 3) -- never walks backwards
			local finalWax, delivered = WaxAccounting.drainToEmpty(wax, ledger, "Extraction")

			local summary = WaxAccounting.summarize(ledger, finalWax.current, 12, "Extraction")
			Harness.near(summary.reconciliationError, 0, 1e-9, "the ledger does not reconcile")
			Harness.equal(summary.endingWax, 0)
			Harness.near(summary.lostBySource.Extraction :: number, delivered)
			Harness.equal(summary.deepestGlobalDepth, 7)
			Harness.equal(summary.outcome, "Extraction")
			Harness.near(summary.durationSeconds, 12)
			Harness.near(summary.totalGained, 0.04)
			Harness.near(summary.totalLost, summary.startingWax + summary.totalGained)
		end),

		Harness.test("a ledger-less mutation still clamps correctly", function()
			-- Not every call site has a ledger (tests, tools, future systems); safety must not depend
			-- on accounting being present.
			local wax = freshWax()
			local after = WaxAccounting.spend(wax, nil, WaxConfig.maxWax * 100, "PassiveBurn")
			Harness.equal(after.current, 0)
			local granted = WaxAccounting.grant(after, nil, WaxConfig.maxWax * 100, "BasinGain")
			Harness.equal(granted.current, granted.max)
		end),
	},
}

return suite
