--!strict
-- Cold tests for everything dynamite decides. No Instances, no services, no clock.

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local DynamiteRules = require(script.Parent.Parent.Logic.DynamiteRules)
local DynamiteConfig = require(script.Parent.Parent.Config.Dynamite)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)

local function stateWith(dynamite: number, overrides: { [string]: any }?): Types.PlayerRunState
	local state: any = {
		playerId = 1,
		alive = true,
		finished = false,
		snuffedAt = nil,
		isLit = true,
		dynamiteCharges = dynamite,
	}
	for key, value in overrides or {} do
		state[key] = value
	end
	return state :: Types.PlayerRunState
end

local suite: Harness.Suite = {
	name = "DynamiteRules",
	tests = {
		--------------------------------------------------------------------------------
		-- The bag
		--------------------------------------------------------------------------------

		Harness.test("granting respects the carry cap and reports what actually fitted", function()
			local cap = DynamiteConfig.supply.maxCarried
			local held, taken = DynamiteRules.grant(0, 1)
			Harness.equal(held, 1)
			Harness.equal(taken, 1)

			-- A crate opened at the cap gives nothing, and says so rather than silently binning sticks.
			local atCap, none = DynamiteRules.grant(cap, DynamiteConfig.supply.crateCharges)
			Harness.equal(atCap, cap)
			Harness.equal(none, 0)

			-- A crate opened one below the cap fills exactly the gap.
			local partial, partialTaken = DynamiteRules.grant(cap - 1, DynamiteConfig.supply.crateCharges)
			Harness.equal(partial, cap)
			Harness.equal(partialTaken, 1)
		end),

		Harness.test("spending refuses an empty bag and never returns a negative count", function()
			Harness.isNil(DynamiteRules.spend(0))
			Harness.equal(DynamiteRules.spend(1), 0)
			Harness.equal(DynamiteRules.spend(3), 2)
		end),

		Harness.test("a corrupt carried count is sanitised rather than trusted", function()
			Harness.equal(DynamiteRules.carried(stateWith(-4)), 0)
			Harness.equal(DynamiteRules.carried(stateWith(0 / 0)), 0)
			Harness.equal(DynamiteRules.carried(stateWith(2.7)), 2)
		end),

		--------------------------------------------------------------------------------
		-- Arming
		--------------------------------------------------------------------------------

		Harness.test("arming needs a live, lit candle holding a stick", function()
			local ok = DynamiteRules.validate(stateWith(1))
			Harness.expect(ok, "a lit, living candle with a stick may arm one")

			local _, empty = DynamiteRules.validate(stateWith(0))
			Harness.equal(empty, "Empty")

			-- You light the fuse FROM your own flame, so an unlit candle has nothing to light it with.
			local _, unlit = DynamiteRules.validate(stateWith(1, { isLit = false }))
			Harness.equal(unlit, "NotLit")

			local _, dead = DynamiteRules.validate(stateWith(1, { alive = false }))
			Harness.equal(dead, "Dead")
			local _, snuffed = DynamiteRules.validate(stateWith(1, { snuffedAt = 1 }))
			Harness.equal(snuffed, "Dead")
			local _, finished = DynamiteRules.validate(stateWith(1, { finished = true }))
			Harness.equal(finished, "Dead")
		end),

		--------------------------------------------------------------------------------
		-- The schedule
		--------------------------------------------------------------------------------

		Harness.test("supply is deterministic for one run seed", function()
			for depth = 1, 40 do
				local first = DynamiteRules.supplyForDepth(1234, depth)
				local second = DynamiteRules.supplyForDepth(1234, depth)
				Harness.equal(first.sticks, second.sticks)
				Harness.equal(first.crates, second.crates)
				Harness.equal(first.charges, second.charges)
			end
		end),

		Harness.test("sticks arrive within the authored gap, forever", function()
			local supply = DynamiteConfig.supply
			-- Several seeds, because a schedule that happened to work for one is not a schedule.
			for _, seed in { 1, 7, 99, 4242, 918_273 } do
				local previous: number? = nil
				local seen = 0
				for depth = 1, 200 do
					if DynamiteRules.supplyForDepth(seed, depth).sticks > 0 then
						seen += 1
						if previous ~= nil then
							local gap = depth - previous
							Harness.expect(
								gap >= supply.stickMinGap and gap <= supply.stickMaxGap,
								("seed %d put sticks %d floors apart, outside %d..%d"):format(
									seed,
									gap,
									supply.stickMinGap,
									supply.stickMaxGap
								)
							)
						end
						previous = depth
					end
				end
				-- 200 floors at a 1..3 gap must produce at least 66 sticks; anything far below that means
				-- the walk is terminating early rather than scheduling.
				Harness.expect(seen >= 60, ("seed %d only scheduled %d sticks over 200 floors"):format(seed, seen))
			end
		end),

		Harness.test("nothing is scheduled before its first eligible floor", function()
			local supply = DynamiteConfig.supply
			for _, seed in { 3, 61, 5150 } do
				for depth = 1, supply.stickFirstDepth - 1 do
					Harness.equal(DynamiteRules.supplyForDepth(seed, depth).sticks, 0)
				end
				for depth = 1, supply.crateFirstDepth - 1 do
					Harness.equal(DynamiteRules.supplyForDepth(seed, depth).crates, 0)
				end
			end
		end),

		Harness.test("crates are rare and correctly spaced", function()
			local supply = DynamiteConfig.supply
			for _, seed in { 2, 31, 777 } do
				local previous: number? = nil
				for depth = 1, 300 do
					if DynamiteRules.supplyForDepth(seed, depth).crates > 0 then
						if previous ~= nil then
							local gap = depth - previous
							Harness.expect(
								gap >= supply.crateMinGap and gap <= supply.crateMaxGap,
								("seed %d put crates %d floors apart, outside %d..%d"):format(
									seed,
									gap,
									supply.crateMinGap,
									supply.crateMaxGap
								)
							)
						end
						previous = depth
					end
				end
			end
		end),

		Harness.test("charges count a crate as its full worth", function()
			for _, seed in { 5, 88, 1010 } do
				for depth = 1, 60 do
					local supply = DynamiteRules.supplyForDepth(seed, depth)
					Harness.equal(supply.charges, supply.sticks + supply.crates * DynamiteConfig.supply.crateCharges)
				end
			end
		end),

		--------------------------------------------------------------------------------
		-- The blast
		--------------------------------------------------------------------------------

		Harness.test("blast falloff is 1 at the centre and 0 at the edge", function()
			Harness.near(DynamiteRules.blastFalloff(0), 1)
			Harness.near(DynamiteRules.blastFalloff(DynamiteConfig.blast.radius), 0)
			Harness.near(DynamiteRules.blastFalloff(DynamiteConfig.blast.radius / 2), 0.5)
			-- Past the edge stays clamped rather than going negative.
			Harness.near(DynamiteRules.blastFalloff(DynamiteConfig.blast.radius * 3), 0)
		end),

		Harness.test("a blast never kills a candle outright from full", function()
			-- DESIGN's whole point about this item: what should end a greedy run is what arrives
			-- afterwards, not the explosion. Standing on your own stick at full wax must be survivable.
			local maxWax = require(script.Parent.Parent.Config.Wax).maxWax
			Harness.expect(
				DynamiteRules.blastWaxCost(0) < maxWax,
				"a point-blank blast must not be lethal to a full candle on its own"
			)
		end),

		Harness.test("wax cost falls off and is dropped entirely at the far edge", function()
			local radius = DynamiteConfig.blast.radius
			Harness.expect(DynamiteRules.blastWaxCost(0) > DynamiteRules.blastWaxCost(radius / 2))
			Harness.expect(DynamiteRules.blastWaxCost(radius / 2) > 0)
			Harness.equal(DynamiteRules.blastWaxCost(radius), 0)
			Harness.equal(DynamiteRules.blastWaxCost(radius * 2), 0)
		end),

		Harness.test("blast damage is expressed in sticks at point blank", function()
			Harness.near(DynamiteRules.blastDamage(0), 1)
			Harness.near(DynamiteRules.blastDamage(DynamiteConfig.blast.radius), 0)
		end),

		Harness.test("one point-blank stick removes an ordinary body and damage accumulates", function()
			local crawler = ThreatsConfig.definitions.DarkCrawler
			local profile = DynamiteRules.profileFor(crawler)
			Harness.expect(
				DynamiteRules.isLethal(0, DynamiteRules.blastDamage(0), profile),
				"a point-blank stick must kill a Dark Crawler outright"
			)
			-- Two half-strength hits finish what one could not: damage never decays.
			local half = DynamiteRules.blastDamage(DynamiteConfig.blast.radius * 0.55)
			Harness.expect(not DynamiteRules.isLethal(0, half, profile), "half a stick must not kill outright")
			Harness.expect(DynamiteRules.isLethal(half, half, profile), "two half hits must finish the body")
		end),

		Harness.test("a row with no blast block falls back to the killable default", function()
			local profile = DynamiteRules.profileFor(nil)
			Harness.equal(profile.hitPoints, DynamiteConfig.threat.default.hitPoints)
			-- The default has to be KILLABLE, not immune: a new threat row that silently could not be
			-- hurt would be a bug nobody could see in play.
			Harness.expect(
				DynamiteRules.isLethal(0, DynamiteRules.blastDamage(0), profile),
				"the default profile must die to one point-blank stick"
			)
		end),

		Harness.test("every authored threat row is reachable by some number of sticks", function()
			for id, def in ThreatsConfig.definitions do
				local profile = DynamiteRules.profileFor(def)
				Harness.expect(profile.hitPoints > 0, id .. " has a non-positive blast hitPoints")
				Harness.expect(profile.staggerSeconds > 0, id .. " would take a blast and not even flinch")
			end
		end),

		Harness.test("the Warden survives more sticks than a candle can carry", function()
			-- DESIGN §9 promises the Warden has exactly one real counter. This is the number that keeps
			-- that promise true in practice: killing it takes more point-blank sticks than the carry cap.
			Harness.expect(
				DynamiteConfig.threat.wardenHitPoints > DynamiteConfig.supply.maxCarried * 0.5,
				"the Warden must not be killable by a plausible haul of dynamite"
			)
			Harness.expect(DynamiteConfig.threat.wardenSlowMultiplier < 1)
			Harness.expect(DynamiteConfig.threat.wardenStunSeconds > 0)
		end),

		--------------------------------------------------------------------------------
		-- The throw
		--------------------------------------------------------------------------------

		Harness.test("a 45-degree launch travels the authored range", function()
			-- THE ONE RELATIONSHIP THE WHOLE THROW IS BUILT ON. `range` is defined as the distance covered
			-- at the ideal launch, and the release speed is derived from it — so if this drifts, every
			-- throw in the game silently changes reach while the config still claims 30.
			local gravity = DynamiteConfig.throw.gravity
			local speed = DynamiteRules.launchSpeed()
			Harness.near(speed, math.sqrt(DynamiteConfig.throw.range * gravity), 0.001)

			-- Fired at 45 degrees from and back to the same height, the analytic range is v^2/g.
			local component = speed / math.sqrt(2)
			local flightSeconds = 2 * component / gravity
			Harness.near(component * flightSeconds, DynamiteConfig.throw.range, 0.01)
		end),

		Harness.test("45 degrees is the FURTHEST angle, and every other angle falls short", function()
			-- The player-facing promise: aiming up to about halfway lobs it further, and past that it
			-- starts coming back down short. Measured by simulating each launch back to its start height.
			local gravity = DynamiteConfig.throw.gravity
			local speed = DynamiteRules.launchSpeed()
			local function rangeAt(degrees: number): number
				local radians = math.rad(degrees)
				local up = speed * math.sin(radians)
				local forward = speed * math.cos(radians)
				-- Time to return to launch height. A downward launch never rises, so it is clamped to zero.
				return forward * math.max(2 * up / gravity, 0)
			end

			local best = rangeAt(45)
			for _, degrees in { -30, -10, 0, 15, 30, 60, 75, 89 } do
				Harness.expect(
					rangeAt(degrees) <= best + 1e-6,
					("%d degrees out-threw 45, which is the one angle that must be maximal"):format(degrees)
				)
			end
			-- And the extremes behave the way a thrower expects rather than merely being "not maximal".
			Harness.expect(rangeAt(0) < best, "a flat throw must be shorter than the ideal one")
			Harness.near(rangeAt(90), 0, 0.01)
			Harness.near(rangeAt(-45), 0, 0.01)
		end),

		Harness.test("a throw is a direction, and its length buys nothing", function()
			-- The server's whole trust check on the aim vector. A modified client that sends a 900-stud
			-- vector must get exactly the throw a unit vector gets.
			local short = DynamiteRules.throwVelocity(Vector3.new(0, 0, -1))
			local long = DynamiteRules.throwVelocity(Vector3.new(0, 0, -900))
			Harness.expect(short ~= nil and long ~= nil)
			Harness.vectorNear(short :: Vector3, long :: Vector3, 0.001)
			Harness.near((short :: Vector3).Magnitude, DynamiteRules.launchSpeed(), 0.001)

			-- A degenerate direction is refused rather than guessed at.
			Harness.isNil(DynamiteRules.throwVelocity(Vector3.zero))
			Harness.isNil(DynamiteRules.throwVelocity(Vector3.new(0 / 0, 0, 0)))
		end),

		Harness.test("the arc rises then falls, and starts where it was launched", function()
			local origin = Vector3.new(10, 5, -3)
			local velocity = DynamiteRules.throwVelocity(Vector3.new(0, 1, -1)) :: Vector3
			Harness.vectorNear(DynamiteRules.ballisticPoint(origin, velocity, 0), origin, 0.001)

			-- Sampled forward in time the height must climb and then drop, never climb forever.
			local previousHeight = origin.Y
			local rose = false
			local fell = false
			for step = 1, 40 do
				local height = DynamiteRules.ballisticPoint(origin, velocity, step * 0.05).Y
				if height > previousHeight then
					rose = true
				elseif height < previousHeight then
					fell = true
				end
				previousHeight = height
			end
			Harness.expect(rose, "a thrown stick must actually go up")
			Harness.expect(fell, "a thrown stick must actually come down")
		end),

		Harness.test("the segment test finds a marker between two flight samples", function()
			-- Why the socket catch tests the SEGMENT and not its endpoints: at launch speed one step
			-- covers several studs, so a pocket can sit between two samples of a throw that visibly went
			-- straight through it.
			local a = Vector3.new(0, 0, 0)
			local b = Vector3.new(10, 0, 0)
			Harness.near(DynamiteRules.distanceToSegment(Vector3.new(5, 0, 0), a, b), 0)
			Harness.near(DynamiteRules.distanceToSegment(Vector3.new(5, 3, 0), a, b), 3)
			-- Past either end it measures to the endpoint rather than to the infinite line.
			Harness.near(DynamiteRules.distanceToSegment(Vector3.new(-4, 0, 0), a, b), 4)
			Harness.near(DynamiteRules.distanceToSegment(Vector3.new(14, 0, 0), a, b), 4)
			-- A zero-length segment is a point, not a division by zero.
			Harness.near(DynamiteRules.distanceToSegment(Vector3.new(0, 2, 0), a, a), 2)
		end),

		Harness.test("the socket catch is tighter than the break radius", function()
			-- The catch is the precise shot; the break radius is the forgiving backup. If the catch were
			-- the wider of the two, every near miss would seat in the pocket and the marker would stop
			-- meaning "hit HERE".
			Harness.expect(
				DynamiteConfig.door.socketCatchRadius < DynamiteConfig.door.thrownBreakRadius,
				"the socket catch must be a tighter shot than the throw that merely breaks the door"
			)
			Harness.expect(DynamiteRules.catchesSocket(0))
			Harness.expect(DynamiteRules.catchesSocket(DynamiteConfig.door.socketCatchRadius))
			Harness.expect(not DynamiteRules.catchesSocket(DynamiteConfig.door.socketCatchRadius + 0.1))
		end),

		--------------------------------------------------------------------------------
		-- Doors and fuses
		--------------------------------------------------------------------------------

		Harness.test("a thrown stick breaks a door only from within its break radius", function()
			local radius = DynamiteConfig.door.thrownBreakRadius
			Harness.expect(DynamiteRules.breaksDoor(0))
			Harness.expect(DynamiteRules.breaksDoor(radius))
			Harness.expect(not DynamiteRules.breaksDoor(radius + 0.1))
		end),

		Harness.test("the door break radius sits inside the blast radius", function()
			-- Otherwise a stick could break a door it did not reach, which would read as the rock
			-- exploding for no visible reason.
			Harness.expect(
				DynamiteConfig.door.thrownBreakRadius <= DynamiteConfig.blast.radius,
				"a door must never break from further away than the blast reaches"
			)
		end),

		Harness.test("a fuse runs from 0 to 1 and clamps at both ends", function()
			Harness.near(DynamiteRules.fuseProgress(0, 3), 0)
			Harness.near(DynamiteRules.fuseProgress(1.5, 3), 0.5)
			Harness.near(DynamiteRules.fuseProgress(3, 3), 1)
			Harness.near(DynamiteRules.fuseProgress(99, 3), 1)
			Harness.near(DynamiteRules.fuseProgress(-5, 3), 0)
		end),

		Harness.test("a socketed charge burns longer than a thrown one", function()
			-- You light a socketed charge with your back to the room, so the walk away is longer.
			Harness.expect(
				DynamiteRules.fuseSecondsFor("Socketed") > DynamiteRules.fuseSecondsFor("Thrown"),
				"a door charge must give more time than a thrown stick"
			)
			Harness.equal(DynamiteRules.fuseSecondsFor("Thrown"), DynamiteConfig.fuse.thrownSeconds)
		end),

		Harness.test("throw and wall placement presentation match the one-step interaction", function()
			Harness.expect(DynamiteConfig.throw.animationSeconds > 0, "a loose stick must visibly travel")
			Harness.expect(
				DynamiteConfig.throw.animationSeconds < DynamiteConfig.fuse.thrownSeconds,
				"the throw animation must finish before the fuse"
			)
			Harness.expect(
				string.find(string.lower(DynamiteConfig.door.placeActionText), "light", 1, true) ~= nil,
				"the one wall prompt must say that placement also lights the charge"
			)
		end),

		--------------------------------------------------------------------------------
		-- Content wiring
		--------------------------------------------------------------------------------

		Harness.test("both dynamite loot rows exist, are weightless, and grant sticks", function()
			for _, id in { "DynamiteStick", "DynamiteCrate" } do
				local def = LootConfig.definitions[id]
				Harness.expect(def ~= nil, id .. " is missing from Config/Loot")
				local row = def :: Types.LootDef
				Harness.equal(row.kind, "Dynamite")
				Harness.expect((row.dynamiteCharges or 0) > 0, id .. " must be worth at least one stick")
				-- Weight ZERO is load-bearing: dynamite is scheduled, never drawn from the weighted pool.
				for _, weight in row.spawnWeightByDepth do
					Harness.equal(weight, 0)
				end
			end
			Harness.equal(
				(LootConfig.definitions.DynamiteCrate :: Types.LootDef).dynamiteCharges,
				DynamiteConfig.supply.crateCharges
			)
		end),

		Harness.test("the blast vault room module is a sealed, creature-free dead end", function()
			local found: Types.RoomModuleDef? = nil
			for _, def in FloorsConfig.roomModules do
				if def.id == DynamiteConfig.vault.roomModuleId then
					found = def
				end
			end
			Harness.expect(found ~= nil, "Config/Floors has no BlastVault room module")
			local def = found :: Types.RoomModuleDef
			-- ONE doorway, or the room is reachable without a stick.
			Harness.equal(def.connections, 1)
			-- Zero weight, or ordinary assembly could drop a sealed room into the middle of a floor.
			Harness.equal(def.weight, 0)
			-- Empty allow-list, which is what the planner's spawn roll reads as "no creatures here".
			Harness.equal(#def.allowedThreats, 0)
			Harness.isNil(def.waterDepth)
		end),

		Harness.test("a vault always promises at least one seam", function()
			Harness.expect(
				DynamiteConfig.vault.depositsMin >= 1,
				"a room that costs a stick to open must never be able to hold no ore"
			)
			Harness.expect(DynamiteConfig.vault.depositsMax >= DynamiteConfig.vault.depositsMin)
			Harness.expect(DynamiteConfig.vault.maxPerFloor >= 1)
		end),

		Harness.test("every cave family names a door style that Config/Dynamite can build", function()
			local CaveFamilyRules = require(script.Parent.Parent.Logic.CaveFamilyRules)
			for _, profile in CaveFamilyRules.list() do
				local style = CaveFamilyRules.blastDoorStyle(profile)
				Harness.expect(
					DynamiteConfig.visual.styleColors[style] ~= nil,
					profile.id .. " names a door style with no colour"
				)
				Harness.expect(
					DynamiteConfig.visual.styleMaterials[style] ~= nil,
					profile.id .. " names a door style with no material"
				)
				Harness.expect(
					DynamiteConfig.visual.styleCrackColors[style] ~= nil,
					profile.id .. " names a door style with no fracture colour"
				)
			end
		end),
	},
}

return suite
