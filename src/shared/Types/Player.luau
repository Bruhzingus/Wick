--!strict
-- Player-domain types. All player state is keyed by PlayerId — never singletons (ARCHITECTURE invariant).

local Wax = require(script.Parent.Wax)
local Tool = require(script.Parent.Tool)
local Sacrifice = require(script.Parent.Sacrifice)
local Mining = require(script.Parent.Mining)

-- Roblox userId. Every per-player table in the game is keyed by this.
export type PlayerId = number

-- Coarse movement state inferred server-side from measured speed; drives movement drain.
export type MovementMode = "Idle" | "Walk" | "Run"

-- Everything tracked about one player during a run. Server-authoritative; mutated only via
-- the server PlayerState store. The client receives a read-only projection over StateSync.
export type PlayerRunState = {
	playerId: PlayerId,
	wax: Wax.WaxState,
	burnRate: Wax.BurnRate, -- current dial setting (server-clamped)
	candle: Wax.CandleModifierState, -- roguelike modifiers collected this run (Logic/CandleModifiers)
	isLit: boolean,
	litChangedAt: number, -- os.clock() of the last lit/unlit transition
	snuffedAt: number?, -- set only in the involuntary snuffed death state; nil otherwise
	isCupping: boolean,
	flareEndsAt: number, -- os.clock() until which this player's flare burst is live (0 = none)
	lightSuppressedUntil: number, -- os.clock() until which an environmental partial-snuff is active
	lightSuppressionMultiplier: number, -- authoritative output multiplier while suppression is active
	-- Short, server-owned enemy exclusion used only while a committed elevator ride prevents the
	-- player from responding and immediately after its lower gate opens. Environmental hazards and
	-- wax drain are unchanged; this is not general invulnerability.
	threatProtectedUntil: number,
	position: Vector3, -- server-sampled from the character each tick
	currentHeight: number, -- authoritative body height; load-bearing for the water rule
	depth: number, -- current floor of THIS expedition (1-based ordinal; not a difficulty input)
	startDepth: number, -- absolute global depth this expedition began at (Logic/DepthRules)
	waxLedger: Wax.WaxLedger, -- internal per-run wax accounting; never replicated, never persisted
	alive: boolean, -- false once terminally dead; THE flag every system reads to refuse a ghost an action
	finished: boolean, -- true once this player lit a brazier
	movementMode: MovementMode,
	nextToolUse: { [Tool.ToolId]: number }, -- os.clock() each tool is next usable
	freeToolCharges: { [Tool.ToolId]: number }, -- loot-granted activations consumed before wax
	matchCharges: number, -- solo-run self-relight consumables, consumed only after an involuntary snuff
	-- STICKS OF DYNAMITE CARRIED (Config/Dynamite). A consumable count, exactly like `matchCharges`
	-- above and deliberately NOT a meter: it has no maximum the HUD draws, nothing drains it over time,
	-- and no rule anywhere converts it to or from wax. Wax remains the only resource
	-- (ARCHITECTURE invariant); this is a number of objects in a bag.
	dynamiteCharges: number,
	isSoloRun: boolean, -- fixed from the starting expedition roster; Match never enables multiplayer revives
	sacrifices: { Sacrifice.SacrificeId }, -- taken this run, in order
	modifiers: Sacrifice.SacrificeModifiers, -- derived live effects of those sacrifices
	nextBasinPenalty: number, -- grant divisor for the next Basin visit only; reset each exchange, never stacks
	basinUsedAtDepth: { [number]: boolean }, -- one exchange per Basin per floor
	-- True while a mining swing is open. Lives on the state rather than inside MiningService so
	-- MovementService keeps deciding speed from state alone (and so the two never require each other).
	isSwinging: boolean,
	-- HELD BY A LONGARM (Config/Longarm.holdSeconds). Exactly the same arrangement as `isSwinging`
	-- above and for exactly the same reason: a grab has to stop the player moving, and the one rule
	-- MovementService will not bend is that speed is a function of state and nothing else. So the
	-- creature writes a flag here and refreshes, rather than reaching for a speed setter that would
	-- become a second source of truth the moment anything else also wanted one.
	--
	-- IT IS NOT A DEATH SENTENCE. The hold is 1.4 seconds and is followed by a 6-second window in
	-- which that Longarm ignores this player entirely; the flag is cleared by whichever comes first,
	-- the creature's own release or its destruction.
	isHeldByEnemy: boolean,
	-- BOWED TOWARD A WALL LAMP, lighting it (Config/WallLamp, server/WallLampService). The third
	-- member of the family above and written for exactly the same reason: lighting a lamp roots you,
	-- and MovementService decides speed from state alone.
	--
	-- IT IS A FLAG AND NOT A TIME, unlike `trippedUntil` below, because the thing that sets it also
	-- owns every way it ends: the player completes the hold, cancels it, walks into it, dies, or the
	-- hold expires on the service's own sweep. There is no path where nobody is responsible for
	-- clearing it.
	isLightingLamp: boolean,
	-- FACE DOWN ON THE FLOOR, having run into a Knotwalker's tripwire (Config/Tripwire). The third
	-- member of the family above, written by `server/TripwireService` and read by nothing but
	-- MovementService — same arrangement, same reason.
	--
	-- A TIME RATHER THAN A FLAG, unlike the two above it. Both of those are cleared by the thing that
	-- set them, and a creature that is destroyed mid-hold has an explicit release path. Nothing owns a
	-- fall: the wire that tripped you is already burnt, and the creature standing over you neither
	-- caused the stun nor ends it. So it expires on its own clock — os.clock() to get up at, 0 when
	-- standing — and a player cannot be left prone by anything failing to clean up after itself.
	trippedUntil: number,
	-- PHASE 6 mining, debug only. Run-scoped, never persisted, never converted to currency or wax:
	-- these two exist purely so a playtest can answer "did they mine, and how deep". Reset with the
	-- rest of the run state; deliberately NOT part of the wax ledger or the reward formula.
	depositsMinedThisRun: number,
	depositsMinedAtDepths: { number }, -- global depth of each depleted deposit, in order
	-- PHASE 8 cargo (Config/Extraction). Run-scoped like everything above it: wiped on reset, never
	-- replicated as a meter, and with no path from here to `wax` — cargo cannot keep anyone alive.
	-- Only its VALUE ever reaches a profile, and only through an extraction. Mutated ONLY through
	-- `server/ExtractionService`.
	rawWax: Mining.RawWaxRun,
}

-- One recorded footfall of a LIVING runner, replicated only to players who are dead (DESIGN §7).
-- Sampled from the server's own `PlayerRunState.position`, never from a client claim, so a ghost's
-- one sense cannot be forged and a living player never receives one of these at all.
export type SpectatorSample = {
	ownerId: PlayerId,
	position: Vector3,
	depth: number, -- the floor it was recorded on; a ghost only ever sees its own floor's samples
	at: number, -- Workspace:GetServerTimeNow() — shared clock, so clients can age it themselves
	seq: number, -- monotonic per server; lets a ghost's client dedupe and key its markers
}

-- A terminally dead player's spectral form (DESIGN §7, §21 Q8): a translucent candle that walks,
-- follows a living teammate, and sheds almost no light. Values in Config/Spectator.
export type SpectatorState = {
	playerId: PlayerId,
	targetId: PlayerId?, -- the living runner being followed; nil = roaming free
	lightGoesOutAt: number, -- Workspace:GetServerTimeNow() after which the faint glow is gone
	nextAnchorAt: number, -- server-clock floor on the next follow pull (grace + cooldown)
	depth: number, -- the floor the ghost is on; changes when following carries it down
}

return {}
