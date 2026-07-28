--!strict
-- Cave tiers. These rows are the complete tuning surface for where an expedition starts, its
-- difficulty/payout scaling and what it costs to get in; Interfaces/CaveTiers owns only evaluation.
-- Difficulty comes from the global depth these rows produce (Logic/DepthRules), never from the tier
-- id itself.
--
-- PHASE 8 REPLACED THRESHOLD UNLOCKS WITH ADMISSION. A tier used to open forever the moment your
-- lifetime currency crossed a number, which meant the deep caves became free exactly when you stopped
-- needing them to be. Now every descent into a paid cave costs each member a fee up front, and that
-- fee is gone whether you walk out rich or burn out on floor two. Buying permanent access is a
-- separate, deliberately expensive purchase — roughly fifteen descents' worth — so it reads as a
-- long-term goal rather than the obvious thing to do with your first windfall.

export type CaveTier = {
	id: number,
	displayName: string,
	-- Currency taken from EVERY party member at the moment of descent. Zero means the cave is free
	-- and always will be. Non-refundable once the run starts: this is the risk.
	entryFee: number,
	-- One-off price for never paying this cave's fee again. Zero means there is nothing to buy —
	-- either because the cave is already free, or because it is deliberately never ownable.
	permanentUnlockPrice: number,
	-- Absolute global depth this tier's expedition BEGINS at (Logic/DepthRules). Every tier starts at
	-- 1 today, preserving current player-facing behaviour; turning tiers into deeper starting points
	-- is a later task, and this field is where that change lands.
	startDepth: number,
	threatBudgetMultiplier: number,
	-- Scales every Raw Wax payout from this cave, as a PERMILLE integer (1000 = unchanged). Integer
	-- because it multiplies currency, and currency never touches floating point (Config/Extraction).
	payoutPermille: number,
	dripstoneMultiplier: number,
	waxDrainMultiplier: number,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	-- PHASE 10 STUB — a tier's VISUAL identity, entirely separate from its difficulty dial.
	--
	-- Today every tier is "Neutral" and nothing reads this field, so it changes nothing for anybody.
	-- It exists so a later phase can give each cave a distinct look — the sketch on the table is
	-- Descent -> grassy/overgrown, Deep -> ice — without that phase having to first invent a place to
	-- put the idea. See `NEUTRAL_BIOME` below for the four hook points a future phase would consume it
	-- at, and for the documentation conflict that must be resolved before any of them are written.
	--
	-- WHAT THIS FIELD MAY NEVER DO: change difficulty, reward, threat behaviour, hazard density, or
	-- what a floor is worth. Look and feel only. The moment a biome makes a cave easier or richer, it
	-- has become a second difficulty axis competing with the multipliers above, and the tier model
	-- stops being readable.
	biomeId: string,
}

-- The placeholder every tier ships with. One shared value rather than three distinct ones, so that a
-- consumer added later branches IDENTICALLY for all three caves until somebody deliberately changes a
-- row — which is what makes this stub a guaranteed no-op rather than a change waiting to be noticed.
--
-- ================================ FUTURE PHASE: READ THIS FIRST ================================
--
-- BLOCKER, NOT A DETAIL: "multiple biomes" is currently on the NEVER list in BOTH authority documents
-- (DESIGN.md §16, GAME-BRIEF.md §19), and ART-BIBLE.md §12 states the caves are "never a themed
-- biome, never decorated" — the grey-rock-with-variance look is presented there as a deliberate style
-- law, not a budget compromise. Adding real biome content therefore requires those three documents to
-- be amended by the project owner FIRST. Scaffolding the field is safe because it renders nothing;
-- filling it in is a product decision that this file cannot make on its own.
--
-- THE FOUR HOOK POINTS, in the order a real biome would touch them:
--
--   1. `server/EnvironmentSetup.applyCaveTier` — the global Atmosphere retint. The cheapest and most
--      visible hook: fog colour and decay already vary per tier here, so a biome's hue would land in
--      the same two property writes with no new system at all.
--   2. `server/RunOrchestrator` (where `applyCaveTier` is called at run start) — the one place a run
--      learns which tier it is. Anything that must be chosen ONCE per expedition rather than per
--      floor (a skybox, a global particle emitter, an ambience track) belongs at that call site.
--   3. `server/FloorBuilder` (WALL_COLOR / ROCK_COLOR / TERRAIN_COLOR / TERRAIN_MATERIAL) — the rock
--      palette itself, which is currently three module-level constants. Turning those into a
--      per-biome lookup is the single largest visual change available and the one most likely to
--      violate ART-BIBLE §4's cool-slate palette, so it needs the art rules amended, not bent.
--   4. `Config/Floors.caveDressing` / `caveMoss` — room-generation FLAVOUR (moss density, formation
--      mix, dressing weights). Data-only, and the correct home for "a grassy cave has more moss".
--      Anything here must stay collision-neutral and must not move a threat, hazard, or deposit.
local NEUTRAL_BIOME = "Neutral"

local CaveTiers: { CaveTier } = {
	{
		id = 1,
		displayName = "The Shallows",
		-- Free forever, and never purchasable. Whatever else happens to a player's balance, there is
		-- always a cave they can walk into with nothing, which is what stops a bad streak in a paid
		-- cave from locking someone out of the game entirely.
		entryFee = 0,
		permanentUnlockPrice = 0,
		startDepth = 1,
		-- This keeps early one-threat floors intact but reduces later two-threat floors to one,
		-- making the introductory expedition genuinely sparse.
		threatBudgetMultiplier = 0.6,
		-- The baseline the whole value curve is authored against. An average 4-5 floor run mining
		-- around three seams earns roughly 145 here, which is what sets every other number in the
		-- economy: two and a half such runs buy one descent into The Descent.
		payoutPermille = 1000,
		-- Baseline falling-dripstone rate (DripstoneRules.targetCount is unscaled at this tier).
		dripstoneMultiplier = 1,
		-- Baseline wax economy: every candle's effective burn rate is unscaled at this tier.
		waxDrainMultiplier = 1,
		-- Phase 2 (wax pacing correction): all three tiers are 1 now (see below). A flat per-tier tax
		-- on every drain component doesn't scale with the depth actually reached and isn't read or
		-- managed by the player like a threat or hazard is — it just duplicates the difficulty Descent
		-- and Deep already get from higher threatBudgetMultiplier, dripstoneMultiplier, and more
		-- floors. Removing it keeps tier difficulty coming from things a player can read and respond
		-- to. See TUNING.md "the wax pacing budget model".
		-- Matches the default project Atmosphere: the lightest, least oppressive shade of cave.
		atmosphereColor = Color3.new(0.62, 0.66, 0.74),
		atmosphereDecay = Color3.new(0.22, 0.24, 0.3),
		-- Phase 10 stub. The free cave is the one most likely to STAY neutral grey rock even if the
		-- other two are eventually themed: it is what a new player is taught the game's look on.
		biomeId = NEUTRAL_BIOME,
	},
	{
		id = 2,
		displayName = "The Descent",
		-- Two and a half average Shallows runs. Deliberately a number you have to decide to spend
		-- rather than one you accumulate without noticing.
		entryFee = 350,
		-- Fifteen descents' worth. At the profit a competent Descent run actually turns, this is
		-- roughly ten good runs away — far enough to be a goal, close enough to be a real one.
		permanentUnlockPrice = 5250,
		startDepth = 1,
		-- Slightly more threats than the original neutral 1.0 budget.
		threatBudgetMultiplier = 1.1,
		-- Tuned so an average 4-5 floor run here roughly REPAYS the fee and no more (~360 against a
		-- 350 admission). The profit is entirely in the floors past 8, which is the whole proposition:
		-- you are not buying a better living, you are buying access to a bigger gamble.
		payoutPermille = 2500,
		-- Slightly more falling dripstones than The Shallows.
		dripstoneMultiplier = 1.2,
		-- Phase 2: was 1.08. See the Shallows comment above — tier difficulty now comes only from
		-- threatBudgetMultiplier/dripstoneMultiplier/rewardMultiplier, never a flat drain tax.
		waxDrainMultiplier = 1,
		-- A visibly darker, cooler shade of cave than The Shallows.
		atmosphereColor = Color3.new(0.5, 0.53, 0.59),
		atmosphereDecay = Color3.new(0.18, 0.19, 0.24),
		-- Phase 10 stub. Sketched future direction: grassy/overgrown. Deliberately NOT set yet — the
		-- value here renders nothing, and picking a theme is a product decision blocked on the
		-- documentation conflict recorded at NEUTRAL_BIOME above.
		biomeId = NEUTRAL_BIOME,
	},
	{
		id = 3,
		displayName = "The Deep",
		entryFee = 1000,
		permanentUnlockPrice = 15000,
		startDepth = 1,
		-- Slightly more threats than the original 1.2 budget.
		threatBudgetMultiplier = 1.35,
		-- An average 4-5 floor run here LOSES money (~650 against a 1000 admission). That is not a
		-- tuning accident: The Deep is priced for players who reliably get past floor 7, and anyone
		-- who cannot should be able to feel that in their balance rather than be told it.
		payoutPermille = 4500,
		-- Noticeably more falling dripstones than The Descent.
		dripstoneMultiplier = 1.45,
		-- Phase 2: was 1.18. See the Shallows comment above.
		waxDrainMultiplier = 1,
		-- The darkest shade of cave: same hue as the other tiers, driven toward black.
		atmosphereColor = Color3.new(0.37, 0.4, 0.44),
		atmosphereDecay = Color3.new(0.13, 0.14, 0.18),
		-- Phase 10 stub. Sketched future direction: ice. Note for whoever takes it: an ice cave is the
		-- riskiest of the sketches against ART-BIBLE §4, because ice reads as bright and reflective and
		-- this game's entire visual grammar is "light is the only source of visual information". A
		-- self-lit cave would undo that, so ice here would have to mean dark wet-black ice catching the
		-- flame, not a white cavern.
		biomeId = NEUTRAL_BIOME,
	},
}

return CaveTiers
