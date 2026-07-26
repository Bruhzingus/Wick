--!strict
-- Player-domain types. All player state is keyed by PlayerId — never singletons (ARCHITECTURE invariant).

local Wax = require(script.Parent.Wax)
local Tool = require(script.Parent.Tool)
local Sacrifice = require(script.Parent.Sacrifice)

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
	waxTypeId: Wax.WaxTypeId, -- active burn profile
	isLit: boolean,
	unlitByChoice: boolean, -- true when out via the SNUFF tool (self-relightable); false when snuffed by the world
	litChangedAt: number, -- os.clock() of the last lit/unlit transition (gates self-relight delay)
	snuffedAt: number?, -- set only in the involuntary snuffed death state; nil otherwise
	isCupping: boolean,
	flareEndsAt: number, -- os.clock() until which this player's flare burst is live (0 = none)
	lightSuppressedUntil: number, -- os.clock() until which an environmental partial-snuff is active
	lightSuppressionMultiplier: number, -- authoritative output multiplier while suppression is active
	position: Vector3, -- server-sampled from the character each tick
	currentHeight: number, -- authoritative body height; load-bearing for the water rule
	depth: number, -- current floor of THIS expedition (1-based ordinal; not a difficulty input)
	startDepth: number, -- absolute global depth this expedition began at (Logic/DepthRules)
	waxLedger: Wax.WaxLedger, -- internal per-run wax accounting; never replicated, never persisted
	alive: boolean, -- false once a wisp
	finished: boolean, -- true once this player lit a brazier
	movementMode: MovementMode,
	sprinting: boolean,
	nextToolUse: { [Tool.ToolId]: number }, -- os.clock() each tool is next usable
	freeToolCharges: { [Tool.ToolId]: number }, -- loot-granted activations consumed before wax
	matchCharges: number, -- solo-run self-relight consumables, consumed only after an involuntary snuff
	isSoloRun: boolean, -- fixed from the starting expedition roster; Match never enables multiplayer revives
	sacrifices: { Sacrifice.SacrificeId }, -- taken this run, in order
	modifiers: Sacrifice.SacrificeModifiers, -- derived live effects of those sacrifices
	nextBasinPenalty: number, -- grant divisor for the next Basin visit only; reset each exchange, never stacks
	basinUsedAtDepth: { [number]: boolean }, -- one exchange per Basin per floor
}

-- A burned-out player's spectral form (DESIGN §21 Q8). Faint light, no interactions.
export type WispState = {
	playerId: PlayerId,
	position: Vector3,
	expiresAt: number, -- os.clock() after which the wisp goes still and dark
}

return {}
