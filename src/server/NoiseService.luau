--!strict
-- The authoritative noise registry: the sound field's equivalent of LightSources. Emitters call
-- `emit`; ThreatService reads `events` and filters them exactly like light sources and trail points.
-- Nothing here decides anything — the tuning is Config/Sound and the perception is Logic/SoundField.
--
-- Every emitter is a site that ALREADY knew the event happened (a resolved strike, an impact, a
-- curtain catching), so wiring one is a single call rather than a new system watching the world.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local SoundField = require(ReplicatedStorage.Shared.Logic.SoundField)

local NoiseService = {}

-- Live events, oldest first, so expiry and the overflow drop are both a scan from the front.
local events: { Types.NoiseEvent } = {}
-- Per-player throttle for continuous emitters (sprinting). Keyed by player and kind so a future
-- continuous emitter cannot starve this one.
local nextEmitAt: { [string]: number } = {}

-- Emit one noise into the field. Returns the event so a caller can log it; ignoring it is normal.
function NoiseService.emit(kind: Types.NoiseKind, position: Vector3, ownerId: Types.PlayerId?): Types.NoiseEvent?
	local event = SoundField.eventFor(kind, position, os.clock(), ownerId)
	if event == nil then
		return nil
	end
	table.insert(events, event)
	-- Overflow drops the OLDEST rather than refusing the newest: a field under pressure loses
	-- resolution on history, never on what is happening right now.
	while #events > Config.Sound.maxLiveEvents do
		table.remove(events, 1)
	end
	return event
end

-- Emit at most one event of this kind per player per `intervalSeconds`. For emitters attached to a
-- continuous state (sprinting) rather than to a discrete moment.
function NoiseService.emitThrottled(
	kind: Types.NoiseKind,
	position: Vector3,
	ownerId: Types.PlayerId,
	intervalSeconds: number
): Types.NoiseEvent?
	local key = ownerId .. ":" .. kind
	local now = os.clock()
	if now < (nextEmitAt[key] or 0) then
		return nil
	end
	nextEmitAt[key] = now + math.max(intervalSeconds, 0)
	return NoiseService.emit(kind, position, ownerId)
end

-- Drop everything that has finished decaying. Called once per server tick, before perception runs.
function NoiseService.tick()
	local now = os.clock()
	for index = #events, 1, -1 do
		if SoundField.isExpired(events[index], now) then
			table.remove(events, index)
		end
	end
end

function NoiseService.events(): { Types.NoiseEvent }
	return events
end

function NoiseService.clear(playerId: Types.PlayerId)
	for index = #events, 1, -1 do
		if events[index].ownerId == playerId then
			table.remove(events, index)
		end
	end
	for key in nextEmitAt do
		if key:sub(1, #tostring(playerId) + 1) == playerId .. ":" then
			nextEmitAt[key] = nil
		end
	end
end

function NoiseService.reset()
	table.clear(events)
	table.clear(nextEmitAt)
end

return NoiseService
