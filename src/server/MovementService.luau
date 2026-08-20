--!strict
-- Server authority for the resulting always-run walk-speed decision.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)

local MovementService = {}

-- WHO IS HOLDING THE DEVELOPER SPRINT KEY. Kept here rather than on `PlayerRunState` on purpose: this
-- is not a property of a candle in a run, it is a debug camera speed that exists only while somebody
-- is inside the test laboratory and holding V, and putting it on run state would mean every consumer
-- of that state had to know a laboratory exists. `DevTestRoomService` owns when it is set and drops it
-- on every session close.
local devSuperSprint: { [Types.PlayerId]: boolean } = {}

-- The multiplier a player's speed is currently scaled by for the developer sprint, or 1.
--
-- Public because `MovementSanityService` needs the same number: its correction threshold is derived
-- from `Config.Movement.runSpeed`, so a player moving at four times it is indistinguishable from a
-- speed exploit and gets rubber-banded back on every sample.
function MovementService.devSuperSprintMultiplier(playerId: Types.PlayerId): number
	if not devSuperSprint[playerId] then
		return 1
	end
	return math.max(Config.DevTestRoom.session.superSprintMultiplier, 1)
end

function MovementService.setDevSuperSprint(playerId: Types.PlayerId, active: boolean)
	if devSuperSprint[playerId] == active or (not active and devSuperSprint[playerId] == nil) then
		return
	end
	devSuperSprint[playerId] = if active then true else nil
	MovementService.refresh(playerId)
end

-- The one place a player's current speed is decided, from state alone.
local function speedFor(playerId: Types.PlayerId, state: Types.PlayerRunState): number
	if not state.alive or state.finished or state.snuffedAt ~= nil then
		return 0
	end
	-- HELD IN A LONGARM'S FIST. Nothing else in the game stops a living player outright — a mining
	-- swing only slows you, and being slowed is always escapable by walking. This is the one hold, it
	-- lasts 1.4 seconds, and it is followed by a grace window the creature enforces on itself.
	if state.isHeldByEnemy then
		return 0
	end
	-- FACE DOWN, having run into a tripwire (Config/Tripwire). The second hold, and the only one a
	-- player brings on themselves: 1 to 3 seconds by how fast they hit the wire, cleared by its own
	-- clock rather than by whatever laid the trap. `TripwireService.tick` refreshes this the moment it
	-- lapses, so nothing here has to watch it.
	if state.trippedUntil > os.clock() then
		return 0
	end
	-- PINNED BY AN AMBUSH (Config/AshamedLurker.trigger.grabStunSeconds). The fourth hold, and the
	-- shortest: a creature reached out of an archway, took most of your wax and let go, and this is the
	-- moment you spend looking at the arm that did it. Like the fall above, it ends on its own clock.
	if state.stunnedUntil > os.clock() then
		return 0
	end
	-- BOWED TOWARD A WALL LAMP, lighting it (Config/WallLamp). The third hold, and the only one the
	-- player chose: it lasts as long as they keep choosing it, and the client cancels the moment they
	-- ask to move — so unlike the two above, this is a root they walk out of rather than wait out.
	--
	-- ROOTING IS THE ENTIRE PRICE OF A LAMP. Lighting costs no wax, so what it costs is a couple of
	-- seconds standing still in the dark next to a light you are about to switch on. A version of this
	-- that merely slowed you would not be a cost at all.
	if state.isLightingLamp then
		return 0
	end
	local speed = Config.Movement.runSpeed
	-- The MoveSpeed sacrifice slows the default run and every slower movement state alike.
	speed *= state.modifiers.moveSpeedMultiplier
	if state.isCupping then
		local multiplier = Config.Tools.Cup.speedMultiplier
		if multiplier ~= nil then
			speed *= multiplier * state.modifiers.cupSpeedMultiplier
		end
	end
	-- A mining swing is a movement commitment, not a freeze: you can always walk out of one (which
	-- cancels it), you simply cannot work a seam and reposition at the same time.
	if state.isSwinging then
		speed *= Config.Mining.deposit.movementSpeedMultiplier
	end
	-- LAST, so it scales whatever the state above arrived at rather than replacing it. A tester holding
	-- V while cupping still moves at cup speed times four, which is the honest reading of "four times as
	-- fast" — and the holds that return 0 outright have already returned.
	speed *= MovementService.devSuperSprintMultiplier(playerId)
	return speed
end

function MovementService.refresh(playerId: Types.PlayerId)
	local state = PlayerState.get(playerId)
	if state ~= nil then
		CharacterService.setWalkSpeed(playerId, speedFor(playerId, state))
	end
end

return MovementService
