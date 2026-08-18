--!strict
-- Pure rules for lighting a cave wall lamp: who may light one, how long they must hold it, what a
-- lit one is worth to threat perception, and how fast a floor's cascade runs.
--
-- NOTHING HERE TOUCHES A PLAYER, A PART, OR A ROBLOX SERVICE. Every function takes a plain record
-- rather than looking anything up, which is what lets the whole gate be tested cold against
-- hand-written states — including the ones a live server could never produce, like a finished player
-- standing at a lamp on a floor they are not on. `server/WallLampService` is the thin adapter that
-- reads the world and calls in here.
--
-- WHY THE REFUSALS ARE IDS AND NOT SENTENCES. The server never sends prose across the wire for these:
-- it sends nothing at all and the client's own prompt simply is not offered. The ids exist so the
-- refusal can be counted in telemetry and asserted in a test, which is the only place they are read.

local Types = require(script.Parent.Parent.Types)
local WallLampConfig = require(script.Parent.Parent.Config.WallLamp)

local WallLampRules = {}

export type LampVariant = WallLampConfig.WallLampVariant

-- Why a light attempt was refused. `nil` is the only success value.
export type Refusal = "disabled" | "alreadyLit" | "notAlive" | "finished" | "unlit" | "cupped" | "wrongFloor" | "tooFar"

-- Everything the decision depends on, and deliberately nothing else. If a field is not here, it
-- cannot influence whether a lamp lights.
export type LightRequest = {
	lampLit: boolean,
	lampDepth: number,
	alive: boolean,
	finished: boolean,
	-- Whether the player's own candle is burning. A LIT CANDLE IS THE ONLY IGNITION SOURCE IN THIS
	-- GAME: lamps take fire, they never give it. That is what keeps a lit floor from becoming a
	-- network of free relights and keeps bringing a teammate back something only a teammate can do.
	isLit: boolean,
	-- A cupped candle is a covered flame. You cannot light anything with a flame you are hiding, and
	-- refusing it here is what stops "go dark" being free at a lamp.
	isCupping: boolean,
	playerDepth: number,
	distance: number,
}

local function isFiniteNumber(value: unknown): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function WallLampRules.isEnabled(): boolean
	return WallLampConfig.enabled
end

-- How long this variant must be held. The room lamp's two seconds are the entire price of lighting a
-- room, so this is the number that decides whether lighting the cave is a habit or a commitment.
function WallLampRules.holdSecondsFor(variant: LampVariant): number
	local interaction = WallLampConfig.interaction
	local seconds = if variant == "Main" then interaction.mainHoldSeconds else interaction.roomHoldSeconds
	return math.max(seconds, 0)
end

-- The distance the SERVER accepts, which is the prompt's range plus the usual trust-boundary slack.
-- Clients are shown `promptRange`; a player who took one step during their own round trip is not a
-- cheater.
function WallLampRules.serverRange(): number
	local interaction = WallLampConfig.interaction
	return math.max(interaction.promptRange + interaction.positionToleranceStuds, 0)
end

-- May this player light this lamp right now?
--
-- ORDER IS DELIBERATE: the lamp's own state first, then the player's, then geometry. A player who is
-- dead at an already-lit lamp is told the lamp is lit, because that is the reason nothing would have
-- happened even if they were alive.
function WallLampRules.canLight(request: LightRequest): (boolean, Refusal?)
	if not WallLampConfig.enabled then
		return false, "disabled"
	end
	if request.lampLit then
		return false, "alreadyLit"
	end
	if not request.alive then
		return false, "notAlive"
	end
	if request.finished then
		return false, "finished"
	end
	if not request.isLit then
		return false, "unlit"
	end
	if request.isCupping then
		return false, "cupped"
	end
	if
		not isFiniteNumber(request.playerDepth)
		or not isFiniteNumber(request.lampDepth)
		or request.playerDepth ~= request.lampDepth
	then
		return false, "wrongFloor"
	end
	if not isFiniteNumber(request.distance) or request.distance > WallLampRules.serverRange() then
		return false, "tooFar"
	end
	return true, nil
end

-- Has a hold that began at `startedAt` run long enough to count, judged at `now`?
--
-- THE GRACE IS ONE ROUND TRIP AND NOT A DISCOUNT. A client reports its own completion, so the server
-- has to accept an arrival that is marginally early or it will refuse honest players on a bad
-- connection — and it has to refuse anything earlier than that or the hold is decorative. A forged
-- "I finished instantly" fails this by the whole hold duration.
function WallLampRules.holdSatisfied(variant: LampVariant, startedAt: number, now: number): boolean
	if not isFiniteNumber(startedAt) or not isFiniteNumber(now) then
		return false
	end
	local required = WallLampRules.holdSecondsFor(variant) - math.max(WallLampConfig.interaction.holdGraceSeconds, 0)
	return now - startedAt >= math.max(required, 0)
end

-- Has a begun hold been abandoned? A player who disconnected, died or walked out of range mid-light
-- never sends a cancel, so the server drops the record on its own rather than leaving a candle
-- leaning at a wall forever.
function WallLampRules.holdExpired(startedAt: number, now: number): boolean
	if not isFiniteNumber(startedAt) or not isFiniteNumber(now) then
		return true
	end
	return now - startedAt > math.max(WallLampConfig.interaction.holdExpirySeconds, 0)
end

-- Seconds between rooms in the floor-wide cascade, compressed so the whole answer fits inside
-- `maximumSeconds` no matter how many rooms the floor has.
--
-- WHY IT IS COMPRESSED RATHER THAN CAPPED BY COUNT. The player is STILL PLAYING while this runs — it
-- is a world event and not a cutscene — so the constraint that matters is how long the event lasts,
-- not how many lamps are in it. A twenty-room floor answers faster per room; it does not answer for
-- twenty times as long.
function WallLampRules.cascadeStepSeconds(lampCount: number): number
	local cascade = WallLampConfig.cascade
	if not isFiniteNumber(lampCount) or lampCount <= 0 then
		return 0
	end
	local available = math.max(cascade.maximumSeconds - math.max(cascade.leadSeconds, 0), 0)
	return math.min(math.max(cascade.stepSeconds, 0), available / lampCount)
end

function WallLampRules.cascadeLeadSeconds(): number
	return math.max(WallLampConfig.cascade.leadSeconds, 0)
end

-- WHAT A LIT LAMP IS TO A THREAT. This is the function that makes the lamps real rather than
-- decorative, and every field in it is load-bearing:
--
--   repelsDarkHunters = true   — the thing that lives in the dark will not stand in a lit room. This
--                                is what "light the way back for your friends" actually buys.
--   attractsDrawn     = true   — and the thing that comes TO light now has somewhere to go. Lighting
--                                a room does not make it safe; it changes which half of the taxonomy
--                                is a problem there. That trade is the whole cost of a free action.
--   forcesDarkHunterRetreat    — false, always. The panic retreat belongs to Flare alone (DESIGN §6).
--                                A fixture that could trigger it would be a permanent, free Flare
--                                bolted to a wall, and one lit room would disarm the counterplay the
--                                whole tool exists for.
--   ownerId           = nil    — nobody's flame. A lamp cannot be blamed on the player who lit it,
--                                cannot be snuffed with them, and does not follow them out.
function WallLampRules.lightSource(variant: LampVariant, position: Vector3): Types.LightSource
	local output = if variant == "Main" then WallLampConfig.mainOutput else WallLampConfig.roomOutput
	return {
		kind = "Lamp" :: Types.LightSourceKind,
		position = position,
		intensity = math.max(output.perception.intensity, 0),
		range = math.max(output.perception.range, 0),
		attractsDrawn = true,
		repelsDarkHunters = true,
		forcesDarkHunterRetreat = false,
		ownerId = nil,
	}
end

return WallLampRules
