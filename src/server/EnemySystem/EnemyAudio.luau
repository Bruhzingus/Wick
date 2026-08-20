--!strict
-- The bridge between a pack body's state machine and this game's audio.
--
-- WHY THE PACK'S OWN SOUNDS ARE NOT USED. Every enemy module ships a `SOUNDS` table of raw asset ids
-- and an `EnemyKit.emitter()` that builds bare `Sound` instances parented to the creature. Those
-- tables are left empty on purpose (the modules run silent rather than erroring, which is documented
-- behaviour) because a bare Sound bypasses everything `Config/Audio` exists to provide: buses, voice
-- limits, ducking, the cave's own reverb, and occlusion.
--
-- OCCLUSION IS THE ONE THAT MATTERS. A Gnawer eating in the next room is the player's only warning
-- that the room is dangerous, and it has to sound like it is coming through rock or the warning reads
-- as "something is here" rather than "something is through there". `AudioCues` samples obstruction at
-- playback and filters the direct path while leaving the reverb tail intact; a raw Sound cannot.
--
-- SERVER-SIDE, VIA A REMOTE. Audio in this game is a client concern (`client/AudioCues`), so this
-- broadcasts the creature's position and the cue name, exactly as the dripstone and warden cues
-- already do, and every client plays it at the right place in its own mix.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local EnemyAudio = {}

-- Tag marking a body that currently wants a looping cue running on it. The client watches the tag
-- rather than being told to start and stop, so a player who walks into range of a Gnawer that has
-- been eating since the floor was built still hears it — a one-shot "start the loop" broadcast at
-- spawn time would only ever reach whoever was already listening.
local LOOP_TAG_PREFIX = "WickEnemyLoop_"

-- ONE OF THESE PER TRANSITION, CHOSEN AT RANDOM — as against STATE_CUES below, which plays every cue
-- it lists. For a beat that repeats often enough within one encounter that a single sample stops
-- registering: the Queen takes six sticks to kill, and hearing the same groan six times is how a
-- player learns to stop hearing it.
--
-- A state may appear in BOTH tables. The fixed list is the part of the event that is always the same
-- and the variant is the voice on top of it, which is the shape a layered hit wants.
local STATE_CUE_VARIANTS: { [string]: { [string]: { string } } } = {
	Queen = {
		hurt = { "QueenHurt", "QueenHurt2", "QueenHurt3" },
	},
}

-- The cues each creature plays when it ENTERS a state. Absent states are deliberately silent, and the
-- Longarm's `idle` and `move` are the loudest absence in the table: it is authored to give the player
-- nothing to hear until it has already committed, so it has no locomotion or idle voice at all.
--
-- A LIST PER STATE, because a grab is two sounds. `LongarmGrab` is the body — the wet grip and the
-- air knocked out — and `LongarmScream` is the voice over the top of it; SOUND.md specifies both, and
-- either one alone is half an event. They are separate rows rather than one pre-mixed asset so the
-- close-range contact and the floor-carrying jumpscare can keep their own ranges.
local STATE_CUES: { [string]: { [string]: { string } } } = {
	-- Every state this brain enters except `eat`, which is the looped cue below rather than a one-shot.
	-- `listen` is the one that carries the encounter: it fires on the transition out of `eat`, so the
	-- grinding stopping and the breath being drawn are the same beat, and that beat is the player's
	-- last quiet moment before a charge.
	Gnawer = {
		-- `hunt` is the one that fires from across the floor: the creature felt something break in
		-- another room and is walking to it. It is the player's only notice that a dripstone they
		-- dropped, or a stick they threw, has started something moving toward them.
		hunt = { "GnawerHunt" },
		listen = { "GnawerListen" },
		warn = { "GnawerWarn" },
		charge = { "GnawerCharge" },
		stagger = { "GnawerImpact" },
		hurt = { "GnawerHurt" },
		death = { "GnawerDeath" },
	},
	-- Every state this creature can enter that is not standing or walking. `reveal` is the important
	-- one: it is the unfold, the only warning it ever gives, and it was silent — leaving a purely
	-- visual tell on the one enemy designed to be behind you.
	-- `slash` and `strike` are the two attacks and they get two cues, because they are the only thing
	-- distinguishing "that cost you wax" from "that has hold of you" for anyone facing the wrong way.
	Longarm = {
		reveal = { "LongarmReveal" },
		-- Each attack is its own bright transient plus the shared body layer underneath it. Neither is
		-- played alone: on its own a single sharp crack reads as a plucked string rather than as an arm.
		slash = { "LongarmSlash", "LongarmBody" },
		strike = { "LongarmSnap", "LongarmBody" },
		hold = { "LongarmGrab", "LongarmScream" },
		flee = { "LongarmFlee" },
		hurt = { "LongarmHurt" },
		death = { "LongarmDeath" },
	},
	-- `bite` is the one she does at a specific player rather than at the room, and it is the only
	-- attack in the game that can take four fifths of a candle — so it gets a cue of its own rather
	-- than borrowing her call, which is a summon and means something else entirely.
	-- `hurt` layers OVER the churn rather than replacing it (the churn loop below deliberately keeps
	-- running through `hurt`): she is hit, not interrupted. `death` is the opposite — it is the one
	-- state absent from that loop, so her landmark drone stops dead underneath this cue.
	Queen = {
		call = { "QueenCall" },
		birth = { "QueenBirth" },
		bite = { "QueenBite" },
		death = { "QueenDeath" },
	},
	-- `attack` fires on every latch-on (WaxGrubBehavior: `self.body:setState("attack")`) — a real
	-- transition the state machine already makes, previously with no cue behind it. `eat` fires
	-- every time a grub locks onto a wax drop it has caught up to, including back-to-back bites,
	-- because WaxGrubBehavior always routes a finished bite through one tick of `idle` before the
	-- next one starts, so the state machine always re-enters `eat` rather than staying in it.
	-- `flee` is the stomp/flare response and the only one of these a player deliberately causes, so it
	-- is the loudest and widest of the four. `hurt` and `death` are held quiet on purpose: a brood is a
	-- nuisance, and eight death cues at threat volume would read as something far worse than it is.
	Grub = {
		attack = { "GrubAttack" },
		eat = { "GrubEat" },
		flee = { "GrubFlee" },
		hurt = { "GrubHurt" },
		death = { "GrubDeath" },
	},
	-- UNLITTIUS. Almost everything he does is announced by an explicit `EnemyAudio.play` on the
	-- authoritative beat that causes it (`UnlittiusBehavior`), because his cues have to land on the
	-- frame the damage does rather than on the frame a state changed — a boulder release and a claw
	-- contact are both mid-action beats that no state transition corresponds to.
	--
	-- THE DRIPSTONE CHARGE IS THE EXCEPTION AND BELONGS HERE, because it fires exactly when the action
	-- STARTS and is the front half of the telegraph. Putting it on the transition rather than on a beat
	-- means it cannot drift away from the animation's own arm raise.
	Unlittius = {
		Dripstone = { "UnlittiusDripstoneCharge" },
	},
}

-- Looping cues, keyed by the state they should be running during. Anything not listed stops the loop.
local LOOP_STATES: { [string]: { cue: string, states: { [string]: boolean } } } = {
	-- `move` IS INCLUDED DELIBERATELY. A grazing Gnawer alternates between standing and chewing (`eat`)
	-- and walking a few studs to the next spot (`move`), every four to seven seconds. Keying the loop to
	-- `eat` alone would cut the room's danger signal out and back in on that cadence — both a stutter in
	-- the one cue SOUND.md calls the creature's whole fairness, and a voice destroyed and rebuilt every
	-- few seconds. A body this heavy dragging itself over rock grinds either way; what must never
	-- happen is the loop going quiet while the creature is still calmly occupying the room.
	--
	-- `listen` is pointedly NOT here: the grinding stopping IS the tell.
	GnawerEat = { cue = "GnawerEat", states = { eat = true, move = true } },
	GrubIdle = { cue = "GrubIdle", states = { idle = true, move = true } },
	-- Every state she has. The churn is her body working and it does not stop because she is moving or
	-- biting — a gap in it would read as the landmark going quiet, which is what her death sounds like.
	QueenChurn = {
		cue = "QueenChurn",
		states = { idle = true, crawl = true, birth = true, call = true, hurt = true, bite = true },
	},
	-- UNLITTIUS' PRESENCE. Every state he has EXCEPT the banish, which is the whole point: the bed of
	-- stone under tension is the sound of him holding the chamber, and the moment it stops is the
	-- moment he stops holding it. Naming the states rather than excluding one keeps that explicit —
	-- a future action added without a row here goes quiet, which is a visible bug rather than a silent
	-- one.
	--
	-- The action names are `UnlittiusVisualProtocol.actions`, capitalised, because those are what the
	-- behaviour actually sets on the model; the pack's own creatures use lowercase state names and the
	-- two vocabularies must not be confused.
	UnlittiusTension = {
		cue = "UnlittiusTension",
		states = {
			Idle = true,
			Dripstone = true,
			BoulderBurst = true,
			SummonGnawers = true,
			Melee = true,
			Recoil = true,
		},
	},
}

local function broadcast(model: Model, cueName: string)
	local root = model.PrimaryPart
	if root == nil then
		return
	end
	Remotes.get("RunEvent"):FireAllClients("enemyCue", {
		cue = cueName,
		position = root.Position,
	})
end

-- A one-shot cue at this creature's position, if the state it just entered has one.
function EnemyAudio.onStateChange(model: Model, creature: string, _previousState: string, nextState: string)
	local fixed = STATE_CUES[creature]
	if fixed ~= nil then
		local cueNames = fixed[nextState]
		if cueNames ~= nil then
			for _, cueName in cueNames do
				broadcast(model, cueName)
			end
		end
	end
	-- Exactly one of the alternatives, if this transition has any. Rolled per event rather than per
	-- body: two hits on the same creature should not be able to settle into a pattern either.
	local variants = STATE_CUE_VARIANTS[creature]
	local choices = if variants ~= nil then variants[nextState] else nil
	if choices ~= nil and #choices > 0 then
		broadcast(model, choices[math.random(1, #choices)])
	end
	EnemyAudio.syncLoops(model, nextState)
end

function EnemyAudio.play(model: Model, cueName: string)
	broadcast(model, cueName)
end

-- A CUE AT A PLACE THAT IS NOT THE CREATURE. Everything above emits from a body's own root, which is
-- right for a voice and wrong for an event: a boulder lands where it lands, a summoned Gnawer breaks
-- the floor where it surfaces, and a god being pressed into the ceiling is a sound coming from
-- overhead. Playing all of those from the boss's chest collapses a whole encounter into one point
-- source and throws away the only spatial information the player has in a dark room.
function EnemyAudio.playAt(position: Vector3, cueName: string, pitch: number?, level: number?)
	Remotes.get("RunEvent"):FireAllClients("enemyCue", {
		cue = cueName,
		position = position,
		-- Optional per-play multipliers on top of the cue row's own randomisation. Nil for almost every
		-- cue in the game; used by a voice that has to get lower as its owner is weakened.
		pitch = pitch,
		level = level,
	})
end

-- ONE OF A SET OF VARIATIONS, walked rather than rolled. `index` is a running counter from the
-- caller, so consecutive plays are always DIFFERENT recordings — a random pick would sometimes serve
-- the same clip twice in a row, which is exactly the repetition the variations exist to hide.
--
-- The set is named `Base`, `BaseB`, `BaseC`, ... which keeps every variation discoverable from the
-- base name in `Config/Audio` and lets a set be extended without touching a call site.
local VARIATION_SUFFIX = { "", "B", "C", "D" }

function EnemyAudio.playVariantAt(position: Vector3, baseName: string, count: number, index: number)
	local slot = (math.floor(index) % math.max(math.min(count, #VARIATION_SUFFIX), 1)) + 1
	EnemyAudio.playAt(position, baseName .. VARIATION_SUFFIX[slot])
end

-- The last state this module actually reacted to, per body. Weak-keyed so a destroyed creature does
-- not pin its own model in memory.
local lastObserved: { [Model]: string } = setmetatable({}, { __mode = "k" }) :: any

-- OBSERVE THE BODY, DO NOT TRUST A CALLER'S SNAPSHOT. Call this as often as you like, from anywhere in
-- a behaviour's frame: it diffs against what it last saw and is a no-op when nothing has changed.
--
-- WHY THIS EXISTS, because the obvious alternative is what was here before and it silently removed most
-- of the game's creature audio. Every behaviour used to do this:
--
--     local previousState = self.body.state   -- snapshot
--     self.body:step(dt)                      -- pack timeouts run
--     if self.body.state ~= previousState then ... end
--
-- ...and then, LATER IN THE SAME FRAME, run the logic that actually starts an attack. A Longarm decides
-- to strike, slash, grab or reveal at lines 404/432/585 of its behaviour — all well past that
-- comparison at 467. The transition therefore happened after the only thing watching for it had already
-- run, and by the next frame `previousState` was initialised to the NEW state, so the change was never
-- observed at all. Every Longarm attack cue was unreachable: the creature attacked in total silence.
-- The same held for the grub's `attack` and `eat`.
--
-- The Grub Queen was the one creature this did not affect, purely because her movement state is set
-- BEFORE her comparison rather than after — which is why she spent so long being the only audible thing
-- in the cave and made every other fault look like an asset problem.
--
-- Diffing against stored state rather than a per-frame snapshot makes the observation independent of
-- where in the frame the change happened, which is the only property that actually fixes this.
function EnemyAudio.observe(model: Model, creature: string, state: string)
	local previous = lastObserved[model]
	if previous == state then
		return
	end
	lastObserved[model] = state
	if previous == nil then
		-- First sighting is the spawn state, not a transition into it: start its loops, fire nothing.
		EnemyAudio.syncLoops(model, state)
		return
	end
	EnemyAudio.onStateChange(model, creature, previous, state)
end

-- Start a looping cue on this body. Idempotent: the tag is the state, so re-adding it is free.
function EnemyAudio.attachLoop(model: Model, loopId: string)
	local definition = LOOP_STATES[loopId]
	if definition == nil then
		return
	end
	model:SetAttribute("WickLoopCue", definition.cue)
	CollectionService:AddTag(model, LOOP_TAG_PREFIX .. definition.cue)
end

-- Turn every registered loop on this body on or off according to the state it is now in.
function EnemyAudio.syncLoops(model: Model, state: string)
	for _, definition in LOOP_STATES do
		local tag = LOOP_TAG_PREFIX .. definition.cue
		local wanted = definition.states[state] == true and model:GetAttribute("WickLoopCue") == definition.cue
		local tagged = CollectionService:HasTag(model, tag)
		if wanted and not tagged then
			CollectionService:AddTag(model, tag)
		elseif not wanted and tagged then
			CollectionService:RemoveTag(model, tag)
		end
	end
end

function EnemyAudio.stopAll(model: Model)
	for _, definition in LOOP_STATES do
		CollectionService:RemoveTag(model, LOOP_TAG_PREFIX .. definition.cue)
	end
end

function EnemyAudio.loopTagFor(cueName: string): string
	return LOOP_TAG_PREFIX .. cueName
end

function EnemyAudio.loopCues(): { string }
	local names: { string } = {}
	for _, definition in LOOP_STATES do
		table.insert(names, definition.cue)
	end
	return names
end

return EnemyAudio
