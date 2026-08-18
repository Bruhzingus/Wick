--!strict
-- Wax Grub tuning, ported from shared/Enemies/WaxGrub.luau. Tier 1 swarm scavenger:
-- a hazard, never a fight. Stomping scares it off; it never dies to a footstep.
--
-- LIGHT REACTION IS A DELIBERATE DEVIATION FROM THE PACK. The pack's own module reads
-- `flareThreshold` against continuous ambient brightness (`setIllumination(playerBrightness)`
-- every frame). This game already has four DarkHunter creatures that flee ambient light
-- (DarkCrawler, VoidFly, Knotwalker, Calver) — a fifth would read as more of the same. The
-- integration layer must instead feed the grub's `setIllumination` a spike value (1.0) only
-- while a player's flare is actually burning (mirrors ThreatService's own
-- `repelsAmbusher = state.isLit and state.flareEndsAt > now`), and 0 otherwise. `flareThreshold`
-- below still does its job unchanged inside the pack module — only what gets fed to it changes.
--
-- TRAIL FOLLOWING IS NEW, NOT IN THE PACK. When not fleeing or latched, a grub should drift
-- toward the nearest live drip-trail point (server/DripTrailService.getTrail(), the same
-- involuntary wax breadcrumbs dark-hunters already read) rather than wandering blind. This
-- reuses sensory input the game already produces; it does not require a new perception system.
--
-- STOMPING IS THE ANSWER TO A LATCHED ONE, and it is the ONLY answer the player has: there is no
-- attack in this game, and a grub riding your boot cannot be outrun. A grub on the floor still
-- scatters from a single footfall; one that has already latched takes `shakeStompsMin`..Max of them,
-- rolled per latch, so shaking it off is a short scramble rather than one reflex.
--
-- AND IT EATS WHAT IT CATCHES UP TO. Reaching a drop is not the end of the interest — the grub
-- parks over it and chews for `eatSeconds` (server/EnemySystem/WaxGrubBehavior), then removes it
-- from the trail via `DripTrailService.consume` and picks whatever is now nearest. Without this a
-- grub just idled beside a drop until the drop's own 35s lifetime expired on its own, which reads
-- as a creature ignoring the thing it was drawn to.

local Types = require(script.Parent.Parent.Types)

export type WaxGrubConfig = {
	health: number,
	speed: number,
	fleeSpeed: number,
	drainPerSecond: number,
	-- Fed a flare-spike value, not ambient brightness. See header.
	flareThreshold: number,
	stompFleeSeconds: number,
	attackRange: number,
	senseRange: number,
	-- NEW. Slower than ordinary wander speed — "follow trails slowly" was explicit. Starting
	-- value only; tune against playtest, not a value carried over from the pack.
	trailFollowSpeed: number,
	-- Seconds spent chewing through one caught-up-to wax drop before it is removed from the trail
	-- and the grub retargets whatever is now nearest. ~1s per the design brief: long enough to read
	-- as an event, short enough that a brood clears a trail rather than camping on it.
	eatSeconds: number,
	broodMin: number,
	broodMax: number,
	-- How close a landing foot has to be to scare a grub. Generous relative to the body (a grub is
	-- about a stud wide) because the alternative is a player stamping repeatedly on something they can
	-- see and feeling nothing happen — the gesture is what matters, not the precision.
	stompRadius: number,
	-- HOW MANY STOMPS SHAKE A LATCHED GRUB OFF, rolled per latch. A grub on the FLOOR still goes on
	-- one footfall (it is scared, not hurt); one that has already committed to your candle has to be
	-- fought off, and a random count inside this range is what stops that fight from being a single
	-- reflex the player stops noticing. Kept short: the grub drains slowly enough (see
	-- `drainPerSecond`) that three landings is a moment of panic, not a wax cost worth fearing.
	shakeStompsMin: number,
	shakeStompsMax: number,
	-- How long before the same player is told again, in plain text, that stomping is the answer. The
	-- one-shot teaching line (Config/Feel.itemHints.WaxGrub) fires once per player EVER, so without a
	-- repeating nudge a returning player who latches on floor 9 has nothing on screen telling them
	-- what to do. Long enough that a brood does not narrate itself.
	shakeHintCooldownSeconds: number,
	-- What a stick of dynamite does to one grub (Config/Dynamite.threat explains the shape). One
	-- point-blank stick removes it, same as an ordinary threat row.
	blast: Types.BlastProfile,
}

local WaxGrub: WaxGrubConfig = {
	health = 12,
	speed = 6,
	fleeSpeed = 11,
	-- OWNER TUNING: a half-wax player must survive at least 12s latched to one grub. Half of
	-- `Config.Wax.maxWax` (1.3) is 0.65, so this needs to be no higher than 0.65/12 ≈ 0.054; 0.05
	-- lands just under that with a little margin (13s from half wax, ~26s from a full candle). Down
	-- from 0.2, which killed a half-wax candle in ~3.25s — a single grub is a nuisance to shake off,
	-- not something that can end a run on its own before a player even reacts.
	drainPerSecond = 0.05,
	flareThreshold = 0.72,
	stompFleeSeconds = 4.5,
	attackRange = 3.2,
	senseRange = 14,
	trailFollowSpeed = 4,
	eatSeconds = 1,
	-- SMALLER THAN THE PACK'S 4-8, deliberately. Owner decision: a brood is a nuisance the player
	-- routes around, and eight of them in a room this dark stops reading as individual creatures and
	-- starts reading as a carpet. It is also the cheaper half of the performance budget the pack's own
	-- checklist worries about (a brood plus two Longarms in the boss chamber).
	broodMin = 2,
	broodMax = 5,
	stompRadius = 4.5,
	shakeStompsMin = 1,
	shakeStompsMax = 3,
	shakeHintCooldownSeconds = 60,
	blast = { hitPoints = 1, staggerSeconds = 6 },
}

return WaxGrub
