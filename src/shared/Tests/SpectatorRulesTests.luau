--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config)
local SpectatorRules = require(script.Parent.Parent.Logic.SpectatorRules)

local function sample(ownerId: number, at: number, seq: number, depth: number?): Types.SpectatorSample
	return {
		ownerId = ownerId,
		position = Vector3.new(seq, 0, 0),
		depth = depth or 1,
		at = at,
		seq = seq,
	}
end

local suite: Harness.Suite = {
	name = "SpectatorRules",
	tests = {
		Harness.test("only a terminally dead player is a ghost", function()
			Harness.equal(SpectatorRules.isGhost(false, false), true)
			-- Alive, snuffed or not, is not a ghost: a snuffed candle is still revivable.
			Harness.equal(SpectatorRules.isGhost(true, false), false)
			-- A brazier exit resolves the run alive; those players leave rather than haunt it.
			Harness.equal(SpectatorRules.isGhost(true, true), false)
			Harness.equal(SpectatorRules.isGhost(false, true), false)
		end),

		Harness.test("a snuffed teammate is still followable, a resolved one is not", function()
			Harness.equal(SpectatorRules.canFollow(true, false), true)
			Harness.equal(SpectatorRules.canFollow(true, true), false)
			Harness.equal(SpectatorRules.canFollow(false, false), false)
		end),

		Harness.test("footfalls are recorded by distance travelled, not by time", function()
			Harness.equal(SpectatorRules.shouldSample(nil, Vector3.zero, 4), true)
			Harness.equal(SpectatorRules.shouldSample(Vector3.zero, Vector3.new(3.9, 0, 0), 4), false)
			Harness.equal(SpectatorRules.shouldSample(Vector3.zero, Vector3.new(4, 0, 0), 4), true)
			-- Standing still never produces a second mark.
			Harness.equal(SpectatorRules.shouldSample(Vector3.zero, Vector3.zero, 4), false)
		end),

		Harness.test("pruning drops aged samples and then the oldest over the cap", function()
			local samples = { sample(1, 0, 1), sample(1, 10, 2), sample(1, 20, 3), sample(1, 30, 4) }
			local aged = SpectatorRules.pruneSamples(samples, 35, 20, 100)
			Harness.equal(#aged, 2)
			Harness.equal(aged[1].seq, 3)
			Harness.equal(aged[2].seq, 4)

			local capped = SpectatorRules.pruneSamples(samples, 30, 1000, 2)
			Harness.equal(#capped, 2)
			Harness.equal(capped[1].seq, 3, "the OLDEST are dropped, so the newest two survive")
			Harness.equal(capped[2].seq, 4)

			Harness.equal(#SpectatorRules.pruneSamples(samples, 30, 1000, 0), 0)
		end),

		Harness.test("trail fade runs from full to the configured floor and then to nothing", function()
			Harness.near(SpectatorRules.trailAlpha(0, 40, 0.1), 1)
			Harness.near(SpectatorRules.trailAlpha(20, 40, 0.1), 0.55)
			-- At and past the lifetime the mark is gone entirely; the floor only lifts the live curve.
			Harness.near(SpectatorRules.trailAlpha(40, 40, 0.1), 0)
			Harness.near(SpectatorRules.trailAlpha(400, 40, 0.1), 0)
			Harness.near(SpectatorRules.trailAlpha(1, 0, 0.1), 0)
		end),

		Harness.test("the follow key cycles teammates in id order and then off", function()
			local candidates = { 30, 10, 20 }
			Harness.equal(SpectatorRules.nextFollowTarget(candidates, nil), 10)
			Harness.equal(SpectatorRules.nextFollowTarget(candidates, 10), 20)
			Harness.equal(SpectatorRules.nextFollowTarget(candidates, 20), 30)
			-- Past the last teammate is free roam, not a wrap: leaving the party has to be reachable.
			Harness.isNil(SpectatorRules.nextFollowTarget(candidates, 30))
			-- A target that just died or extracted is no longer in the list; start over.
			Harness.equal(SpectatorRules.nextFollowTarget(candidates, 999), 10)
			Harness.isNil(SpectatorRules.nextFollowTarget({}, nil))
			Harness.isNil(SpectatorRules.nextFollowTarget({}, 10))
		end),

		Harness.test("a ghost is pulled back for a floor change, a lost body, or real distance", function()
			local ghost = Vector3.new(0, 0, 0)
			local target = Vector3.new(10, 0, 0)
			Harness.equal(SpectatorRules.needsReanchor(ghost, 1, target, 1, 90), false)
			-- THE CASE THIS RULE EXISTS FOR: the party descended and the ghost cannot use the hole.
			Harness.equal(SpectatorRules.needsReanchor(ghost, 1, target, 2, 90), true)
			Harness.equal(SpectatorRules.needsReanchor(nil, 1, target, 1, 90), true)
			Harness.equal(SpectatorRules.needsReanchor(ghost, 1, Vector3.new(91, 0, 0), 1, 90), true)
			Harness.equal(SpectatorRules.needsReanchor(ghost, 1, Vector3.new(90, 0, 0), 1, 90), false)
		end),

		Harness.test("the anchor is the target's own feet, lifted and never offset sideways", function()
			local anchored = SpectatorRules.anchorPosition(Vector3.new(4, 2, -6), 0.5)
			Harness.vectorNear(anchored, Vector3.new(4, 2.5, -6))
			Harness.vectorNear(SpectatorRules.anchorPosition(Vector3.new(4, 2, -6), -3), Vector3.new(4, 2, -6))
		end),

		Harness.test("owner colours are stable, in range, and cover the configured palette", function()
			local palette = #Config.Spectator.trail.ownerColors
			Harness.expect(palette > 0, "the trail needs at least one owner colour")
			local first = SpectatorRules.colorIndexFor(12345, palette)
			Harness.equal(SpectatorRules.colorIndexFor(12345, palette), first)
			for _, ownerId in { 1, 2, 3, 4, 99, 1000000, -7 } do
				local index = SpectatorRules.colorIndexFor(ownerId, palette)
				Harness.expect(index >= 1 and index <= palette, "colour index out of palette range")
			end
			Harness.equal(SpectatorRules.colorIndexFor(1, 0), 0)
		end),

		Harness.test("the ghost's light cannot reach as far as an ordinary candle", function()
			-- The design promise "cannot light up much" is a value relationship, not a comment.
			Harness.expect(
				Config.Spectator.light.range < Config.Light.minRange,
				"a ghost must shed less light than the dimmest living candle"
			)
			Harness.expect(Config.Spectator.light.fadeAfterSeconds > 0, "the faint glow must expire")
		end),
	},
}

return suite
