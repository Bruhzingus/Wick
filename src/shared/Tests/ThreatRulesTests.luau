--!strict
-- The roster is a shared trio every cave draws plus one signature creature per family, and these are
-- the properties that let it be that without losing what the eight rows before it were carrying: a
-- difficulty ramp that used to live in a spawn table, and a contact effect that used to live in a row
-- of its own.

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local ThreatRules = require(script.Parent.Parent.Logic.ThreatRules)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local MovementConfig = require(script.Parent.Parent.Config.Movement)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)

local DEEPEST_AUTHORED = 10

local function definition(id: string): Types.ThreatDef
	local def = ThreatsConfig.definitions[id]
	assert(def ~= nil, "Config/Threats must define " .. id)
	return def
end

-- Every threat a room may legally spawn has to be a real row, or the planner would weight an id that
-- resolves to nothing and quietly lose a spawn. Cheap to check and the exact mistake a new creature
-- invites, since an allow-list entry and a definition are edited in two different files.
local function allowListedIdsAreReal(): (boolean, string)
	for _, module in FloorsConfig.roomModules do
		for _, threatId in module.allowedThreats do
			if ThreatsConfig.definitions[threatId] == nil then
				return false, module.id .. " allows a threat that does not exist: " .. tostring(threatId)
			end
		end
	end
	return true, ""
end

local suite: Harness.Suite = {
	name = "ThreatRules",
	tests = {
		Harness.test("every row is a creature a player can tell apart from the one beside it", function()
			-- THE RULE THE CONSOLIDATION ESTABLISHED, restated now that the roster has grown again. It
			-- used to be spelled "exactly three rows", which was only ever a proxy: what actually matters
			-- is that a row exists when a player can MEET it and DISTINGUISH it. Eight rows drawing three
			-- bodies broke that. Six rows drawing six bodies does not.
			--
			-- So the assertion is on bodies, not on a count. Every row must name a visual style no other
			-- row uses, or resolve to a category silhouette that no other row is also resolving to.
			local seenBodies: { [string]: string } = {}
			local ids: { string } = {}
			for id in ThreatsConfig.definitions do
				table.insert(ids, id)
			end
			table.sort(ids)

			for _, id in ids do
				local def = definition(id)
				-- A row with no style of its own falls back to its category's shared silhouette, which is
				-- exactly one body per category and may therefore be claimed by only one row.
				local body = if def.visualStyle ~= nil and def.visualStyle ~= "Default"
					then def.visualStyle
					else "Category:" .. def.category
				local owner = seenBodies[body]
				Harness.expect(
					owner == nil,
					string.format(
						"%s and %s draw the same body (%s) with no label between them",
						id,
						tostring(owner),
						body
					)
				)
				seenBodies[body] = id
			end

			-- And the shared roster every cave draws is still exactly the three it was consolidated to.
			-- Anything beyond that is a family signature creature and belongs to exactly one cave.
			for _, id in { "DarkCrawler", "Moth", "VoidFly" } do
				Harness.expect(ThreatsConfig.definitions[id] ~= nil, "the shared roster lost " .. id)
			end
		end),

		Harness.test("every threat a room may spawn is a real row", function()
			local ok, message = allowListedIdsAreReal()
			Harness.expect(ok, message)
		end),

		Harness.test("the signature creatures keep their categories readable", function()
			-- A player judges a threat by its eyes: crimson angled slits mean dark-hunter, a warm halo
			-- means Drawn. All three signature creatures are hunters, so all three must carry a negative
			-- light response at every depth — `ThreatRules.validate` already rejects a sign that crosses
			-- zero, and this pins the intent rather than the check.
			for _, id in { "Listener", "Knotwalker", "Calver" } do
				local def = definition(id)
				Harness.equal(def.category, "DarkHunter", id .. " must read as a hunter")
				Harness.expect(def.lightResponse < 0, id .. " must be repelled by light like every hunter")
				-- None of them may arrive during the tutorial band: floors 1-3 teach light, and a creature
				-- that ignores light, predicts your route, or drops the ceiling would muddy that lesson
				-- before it has landed.
				for depth = 1, 2 do
					Harness.equal(def.spawnWeightByDepth[depth], 0, id .. " must not appear on floor " .. depth)
				end
			end
		end),

		Harness.test("the ceiling striker never touches anybody", function()
			-- ITS ENTIRE OUTPUT IS AN ENVIRONMENTAL TRIGGER. Zero contact damage, no staged attack, and
			-- crucially it must NOT be a row that snuffs without warning — because that property is what
			-- makes Logic/FloorPlanner refuse to hang formations in a room, and this creature is useless
			-- in a room with nothing overhead.
			local calver = definition("Calver")
			Harness.equal(calver.waxDamagePerSecond, 0, "a striker must not drain on contact")
			Harness.isNil(calver.contactAttack, "a striker has no staged attack")
			Harness.isNil(calver.sustainedContact, "a striker cannot smother anybody")
			Harness.expect(not ThreatRules.canSnuff(calver), "a striker must not be able to snuff a candle itself")
			Harness.expect(
				not ThreatRules.snuffsWithoutWarning(calver),
				"a striker must not protect its own room from the formations it needs"
			)
		end),

		Harness.test("depth may sharpen a signature creature, never remove its counterplay", function()
			-- Each of the three has exactly one thing a player does about it, and each of those lives in
			-- a field the depth curve is not allowed to touch: you outrun and out-quiet the Listener, you
			-- change route on the Knotwalker, and you leave the ground under the Calver.
			local listener = definition("Listener")
			for _, depth in { 1, 5, DEEPEST_AUTHORED, 40 } do
				local resolved = ThreatRules.atDepth(listener, depth)
				Harness.expect(
					resolved.speed < MovementConfig.runSpeed,
					"a Listener must stay outrunnable at depth " .. depth
				)
			end

			-- The commitment window and the wind-up are the two reaction guarantees on the roster, and
			-- neither appears in ThreatDepthScaling's closed field list at all — so they cannot be
			-- scaled even by accident. Asserted as the properties they protect.
			local knotwalker = definition("Knotwalker")
			Harness.expect(
				(knotwalker.intercept :: any).commitmentSeconds > 0,
				"a prediction a player cannot outlast is not counterplay"
			)
			Harness.expect(
				(knotwalker.intercept :: any).roomsAhead <= 1,
				"aiming further than one room reads as cheating"
			)
			local calver = definition("Calver")
			Harness.expect(
				(calver.ceilingStrike :: any).windUpSeconds > 0,
				"a strike with no wind-up is an unreadable hazard"
			)
		end),

		Harness.test("every authored row passes its own validation", function()
			local ok, issues = ThreatRules.validate(ThreatsConfig.definitions)
			local detail = ""
			for _, issue in issues do
				detail ..= "\n" .. issue.threatId .. "." .. issue.field .. ": " .. issue.message
			end
			Harness.expect(ok, "Config/Threats has invalid rows:" .. detail)
		end),

		Harness.test("a crawler gets harder to avoid and harder to shake as it descends", function()
			-- The ramp the old dark-hunter trio produced by composition, now stated on one row: it
			-- senses much further and the same flare buys less retreat.
			local shallow = ThreatRules.atDepth(definition("DarkCrawler"), 1)
			local deep = ThreatRules.atDepth(definition("DarkCrawler"), DEEPEST_AUTHORED)

			Harness.expect(
				deep.detectionRadius > shallow.detectionRadius * 1.4,
				"a deep crawler must sense substantially further than a shallow one"
			)
			Harness.expect(
				math.abs(deep.lightResponse) < math.abs(shallow.lightResponse),
				"a deep crawler must be harder to drive off with light"
			)
			Harness.expect(deep.waxDamagePerSecond > shallow.waxDamagePerSecond, "and cost more to be caught by")

			-- WHAT DEPTH IS NOT ALLOWED TO DO. Outrunning a crawler is the counterplay that has to keep
			-- working at every floor, so the ramp may never turn one into something faster than a
			-- sprinting player. The old trio's speeds were 8/11/5.5 and the composite never left the
			-- low eights; this holds that line.
			Harness.expect(deep.speed < shallow.speed * 1.25, "depth must not turn a crawler into a chase enemy")
		end),

		Harness.test("depth never changes what a body looks like or how far it reaches", function()
			-- A player learns a threat by its silhouette and by the gap it can close. Either of those
			-- drifting with depth would make the creature unlearnable, which is the failure the closed
			-- scaling list exists to prevent.
			for _, id in { "DarkCrawler", "Moth", "VoidFly" } do
				local authored = definition(id)
				for _, depth in { 1, 5, DEEPEST_AUTHORED, 40 } do
					local resolved = ThreatRules.atDepth(authored, depth)
					Harness.equal(resolved.bodySize, authored.bodySize, id .. " changed size at depth " .. depth)
					Harness.equal(resolved.contactRadius, authored.contactRadius, id .. " changed reach")
					Harness.equal(resolved.category, authored.category, id .. " changed category")
					Harness.equal(resolved.contactEffect, authored.contactEffect, id .. " changed contact effect")
					Harness.equal(resolved.perch, authored.perch, id .. " changed its perch profile")
				end
			end
		end),

		Harness.test("floor 1 is exactly what the row was authored as", function()
			-- The flat values ARE the shallow profile. If a curve's first entry ever drifted from the
			-- field beside it, reading the row would stop telling you what floor 1 meets.
			for _, id in { "DarkCrawler", "Moth", "VoidFly" } do
				local authored = definition(id)
				local resolved = ThreatRules.atDepth(authored, 1)
				Harness.near(resolved.speed, authored.speed, 1e-9, id .. " speed drifted at floor 1")
				Harness.near(resolved.detectionRadius, authored.detectionRadius, 1e-9, id .. " sensing drifted")
				Harness.near(resolved.lightResponse, authored.lightResponse, 1e-9, id .. " light response drifted")
				Harness.near(
					resolved.waxDamagePerSecond,
					authored.waxDamagePerSecond,
					1e-9,
					id .. " wax damage drifted"
				)
			end
		end),

		Harness.test("curves clamp at both ends instead of running off", function()
			local def = definition("DarkCrawler")
			local deepest = ThreatRules.atDepth(def, DEEPEST_AUTHORED)
			-- Floors well past the authored table hold the deepest value. A run does not stop at ten.
			for _, depth in { DEEPEST_AUTHORED + 1, 25, 100 } do
				local past = ThreatRules.atDepth(def, depth)
				Harness.equal(past.detectionRadius, deepest.detectionRadius, "sensing must clamp at depth " .. depth)
				Harness.equal(past.lightResponse, deepest.lightResponse, "light response must clamp")
			end
			-- Nonsense depths resolve to floor 1 rather than erroring: a threat still has to be built.
			local floorOne = ThreatRules.atDepth(def, 1)
			for _, depth in { 0, -5, 0 / 0 } do
				local resolved = ThreatRules.atDepth(def, depth)
				Harness.equal(resolved.speed, floorOne.speed, "a depth below 1 must resolve as floor 1")
			end
		end),

		Harness.test("a row with nothing to scale is returned untouched", function()
			local plain: Types.ThreatDef = {
				id = "Plain",
				displayName = "Plain",
				category = "DarkHunter",
				speed = 5,
				detectionRadius = 10,
				lightResponse = -1,
				waxDamagePerSecond = 0.01,
				contactEffect = "Drain",
				contactRadius = 2,
				bodySize = 2,
				spawnWeightByDepth = { 1 },
			}
			Harness.equal(ThreatRules.atDepth(plain, 7), plain, "an unscaled row must not be copied")
		end),

		Harness.test("a moth stops being a wax cost and becomes a way to die", function()
			-- THE MECHANIC THAT USED TO BE A CREATURE. Contact that extinguishes was its own rare row,
			-- drawn with the same body and palette as an ordinary moth, so the only tell was dying to
			-- it. It is now what an ordinary moth does to somebody who cannot get off it.
			local moth = definition("Moth")
			Harness.expect(moth.sustainedContact ~= nil, "the moth must still be able to take a flame")
			Harness.equal(moth.contactEffect, "Drain", "and must still cost wax on ordinary contact")

			-- SILENT THROUGH THE TEACHING FLOORS, which is where the row that owned this mechanic used
			-- to first appear and exactly where the tutorial hints stop (Config/Feel: maxDepth 3).
			-- Nothing puts a player out before the game has finished explaining itself.
			for depth = 1, 3 do
				local resolved = ThreatRules.atDepth(moth, depth)
				local sustained = resolved.sustainedContact :: Types.SustainedContactProfile
				Harness.equal(sustained.secondsToSnuff, 0, "a moth must not snuff on floor " .. depth)
				Harness.equal(ThreatRules.canSnuff(resolved), false, "and must not read as snuff-capable there")
			end

			-- And from floor 4 the window is real and closes with depth.
			local first = ThreatRules.atDepth(moth, 4)
			local deep = ThreatRules.atDepth(moth, DEEPEST_AUTHORED)
			local firstSeconds = (first.sustainedContact :: Types.SustainedContactProfile).secondsToSnuff
			local deepSeconds = (deep.sustainedContact :: Types.SustainedContactProfile).secondsToSnuff
			Harness.expect(firstSeconds > 0, "the mechanic must switch on at floor 4")
			Harness.expect(deepSeconds < firstSeconds, "and must tighten as the cave deepens")
			Harness.expect(ThreatRules.canSnuff(deep), "a deep moth must read as snuff-capable")

			-- YOU CAN ALWAYS LEAVE, but leaving must burn. Running outpaces a moth at every depth, while
			-- the snuff-capable floors keep it above a walk so escape cannot ignore movement wax.
			for depth = 1, DEEPEST_AUTHORED do
				local resolved = ThreatRules.atDepth(moth, depth)
				Harness.expect(
					resolved.speed < MovementConfig.runSpeed,
					"a moth must never outrun a player at depth " .. depth
				)
				local sustained = resolved.sustainedContact :: Types.SustainedContactProfile
				if sustained.secondsToSnuff > 0 then
					Harness.expect(
						resolved.speed > MovementConfig.walkSpeed,
						"escaping a snuff-capable moth must require a wax-costing run at depth " .. depth
					)
				end
			end
		end),

		Harness.test("only unavoidable extinguish protects a room from falling stone", function()
			-- DESIGN §9: a room may not stack an extinguish there is no answer to under a dripstone.
			-- The ceiling ambusher qualifies, because its dive resolves whether or not you saw it.
			Harness.expect(
				ThreatRules.snuffsWithoutWarning(definition("VoidFly")),
				"the VoidFly must still protect the room it holds"
			)
			-- The moth deliberately does not: its snuff takes seconds of unbroken contact a player can
			-- walk out of, and protecting every moth room would clear the hazard off most of a floor.
			Harness.equal(
				ThreatRules.snuffsWithoutWarning(ThreatRules.atDepth(definition("Moth"), DEEPEST_AUTHORED)),
				false,
				"a snuff with a window in it must not protect a room"
			)
			Harness.equal(ThreatRules.snuffsWithoutWarning(definition("DarkCrawler")), false)
		end),

		Harness.test("validation catches the ways a row can lie about itself", function()
			local base: Types.ThreatDef = {
				id = "Broken",
				displayName = "Broken",
				category = "Drawn",
				speed = 5,
				detectionRadius = 10,
				lightResponse = 1,
				waxDamagePerSecond = 0.01,
				contactEffect = "Drain",
				contactRadius = 2,
				bodySize = 2,
				spawnWeightByDepth = { 1 },
			}
			local function issuesFor(mutate: (Types.ThreatDef) -> ()): number
				local def = table.clone(base)
				mutate(def)
				local _, issues = ThreatRules.validate({ Broken = def })
				return #issues
			end

			Harness.equal(issuesFor(function() end), 0, "the baseline row must be valid")
			Harness.expect(issuesFor(function(def)
				def.id = "SomethingElse"
			end) > 0, "a row keyed differently from its own id must fail")
			-- The sign of lightResponse IS the category. A curve crossing zero would mean a creature
			-- that flees light in the shallows and chases it deeper down.
			Harness.expect(issuesFor(function(def)
				def.depthScaling = { lightResponse = { 1, 0.5, -0.5 } }
			end) > 0, "a light response that changes sign with depth must fail")
			Harness.expect(issuesFor(function(def)
				def.contactEffect = "Snuff"
				def.sustainedContact = { secondsToSnuff = 5, graceSeconds = 0.5 }
			end) > 0, "a row that already snuffs cannot also escalate into one")
			Harness.expect(issuesFor(function(def)
				def.depthScaling = { sustainedContactSecondsToSnuff = { 5 } }
			end) > 0, "scaling a clock the row does not have must fail")
		end),
	},
}

return suite
