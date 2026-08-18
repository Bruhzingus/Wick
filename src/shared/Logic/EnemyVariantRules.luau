--!strict
-- Pure: which dressing a wick-pack body wears, and what that costs it.
--
-- WHY THIS IS ITS OWN MODULE rather than a branch inside each enemy service. Three services and the
-- boss encounter all have to answer the same two questions — "which variant does this cave produce"
-- and "what does that variant do to this creature's stats" — and a spawner that got either wrong
-- would produce an ice-blue grub in a moss cave, or a body whose health disagreed with the one the
-- pack module scaled internally. One pure function each, so all four callers cannot drift apart and
-- a cold test can pin the mapping without touching an Instance.
--
-- THE PACK ALREADY SCALES ITS OWN HEALTH. `Module.new` reads `EnemyKit.VariantStats` and
-- `EnemyKit.ElderStats` and applies both to `self.health` before it returns. So `healthMultiplier`
-- below exists for the SPAWNER's benefit (budgeting a floor, sizing a brood), never to be applied a
-- second time to a body that has already scaled itself. `speedMultiplier` is the opposite: the pack
-- deliberately leaves movement to the host, so that one MUST be applied by whatever moves the body.

local EnemyVariantRules = {}

export type Variant = "regular" | "moss" | "ice"

-- MIRRORS `EnemyKit.VariantStats` / `EnemyKit.ElderStats`, and is pinned to them by
-- `EnemySpawnRulesTests` rather than required from them.
--
-- Requiring the pack directly was tried and reverted, because it quietly costs more than the
-- duplication does: `EnemyKit` calls `game:GetService` at load, so anything requiring it stops being
-- cold-loadable — and this module lives in `Logic`, where the whole contract is that a rule can be
-- tested without an engine. One `Logic` module reaching into the pack would make every future pure
-- module that reads variants un-testable too, which is a much worse trade than two small tables that
-- a test compares field by field and fails loudly on.
--
-- THE TEST IS THE POINT. Without it this comment would be a promise; with it, a retune of the pack
-- that forgets this file is a red suite rather than a creature whose speed disagrees with its health.
local VARIANT_STATS: { [Variant]: { health: number, speed: number, fireDamage: number } } = {
	regular = { health = 1.0, speed = 1.0, fireDamage = 1.0 },
	moss = { health = 1.35, speed = 0.8, fireDamage = 0.75 },
	ice = { health = 0.7, speed = 1.25, fireDamage = 1.6 },
}

local ELDER_STATS = { health = 2.2, speed = 0.9, scale = 1.18 }

-- THE ONE MAPPING FROM CAVE TO CREATURE. Config/CaveFamilies ids are STONE / MOSS / ICE and the pack
-- speaks regular / moss / ice, which is a clean one-to-one — the only real decision here is that
-- STONE maps to "regular" rather than to a fourth dressing, because the pack has no stone palette and
-- inventing one would mean editing EnemyKit.
--
-- An unknown family resolves to "regular" rather than erroring. A cave family is authored content and
-- a new one should not be able to stop a floor from spawning creatures; the failure mode of the other
-- choice is a dead floor, and the failure mode of this one is an undressed body.
function EnemyVariantRules.variantForFamily(familyId: string?): Variant
	if familyId == "MOSS" then
		return "moss"
	elseif familyId == "ICE" then
		return "ice"
	end
	return "regular"
end

function EnemyVariantRules.healthMultiplier(variant: Variant, elder: boolean): number
	local stats = VARIANT_STATS[variant] or VARIANT_STATS.regular
	return stats.health * (if elder then ELDER_STATS.health else 1)
end

-- FOR A SPEED THE PACK HAS NEVER SEEN, such as `Config.Longarm.fleeSpeed` or
-- `Config.WaxGrub.trailFollowSpeed` — values this game invented, that no pack constructor ever reads.
-- Those need the full variant-and-elder multiplier applied exactly once, which is what this returns.
--
-- IT IS THE WRONG FUNCTION FOR `body.speed`. `WaxGrub.new` / `StoneGnawer.new` / `Longarm.new` each
-- write `self.speed = Config.<x>.speed * stats.speed` at construction — the pack already bakes the
-- VARIANT factor into that field. Multiplying `body.speed` by this function a second time squares the
-- variant term: an ice body (stats.speed 1.25) would end up at 1.5625x instead of 1.25x, and a moss
-- elder would compound two 0.8 factors into 0.64 where only one was ever meant to apply. Use
-- `elderSpeedMultiplier` on `body.speed` instead — see its own comment for the worked example.
function EnemyVariantRules.speedMultiplier(variant: Variant, elder: boolean): number
	local stats = VARIANT_STATS[variant] or VARIANT_STATS.regular
	return stats.speed * (if elder then ELDER_STATS.speed else 1)
end

-- FOR `body.speed`, WHICH THE PACK HAS ALREADY VARIANT-SCALED. Only the elder factor is missing from
-- it — the pack's own health scaling applies both `stats.health` and `ELDER_STATS.health`, but its
-- speed scaling is variant-only (`WaxGrub.Config.speed * stats.speed`, nothing about elders). This is
-- the other half: `body.speed * elderSpeedMultiplier(elder)` gives the correct final speed exactly
-- once, where `body.speed * speedMultiplier(variant, elder)` would apply the variant term twice.
function EnemyVariantRules.elderSpeedMultiplier(elder: boolean): number
	return if elder then ELDER_STATS.speed else 1
end

-- How much bigger an elder's silhouette is. The pack applies this to the parts itself in
-- `EnemyKit.finish`; the spawner needs it to size a collider, a hitbox query or a spawn clearance
-- check against the body that actually got built.
function EnemyVariantRules.scaleMultiplier(elder: boolean): number
	return if elder then ELDER_STATS.scale else 1
end

-- WHETHER A BUILT BODY IS AN ELDER. Read off the model the pack already wrote it to, never predicted.
--
-- There used to be a `rollsElder(seed)` here that reproduced the pack's own 1-in-12 roll from the
-- same seed, so a spawner could know before building. It has been removed rather than tested: it was
-- only correct while `EnemyKit.begin` kept its exact current order of `Random` calls, nothing in the
-- game actually needed the answer early, and a predictor that silently disagrees with the thing it
-- predicts is a bug waiting for someone to add a second `NextNumber` to a constructor. Build the
-- body, then ask it.
function EnemyVariantRules.isElder(model: Model): boolean
	return model:GetAttribute("Elder") == true
end

function EnemyVariantRules.variantStats(variant: Variant)
	return VARIANT_STATS[variant] or VARIANT_STATS.regular
end

function EnemyVariantRules.elderStats()
	return ELDER_STATS
end

return EnemyVariantRules
