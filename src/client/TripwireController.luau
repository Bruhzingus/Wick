--!strict
-- Going down: what a tripwire looks like from inside the candle that hit it.
--
-- THE SERVER HAS ALREADY DECIDED EVERYTHING. Whether you were caught, how long you are down and what
-- it cost are settled in server/TripwireService before this file hears about it; the event carries the
-- duration so the view can be timed to the real stun rather than to a guess that drifts out of sync
-- with the movement lock. Nothing here can trip anybody, shorten a stun, or get anyone up early.
--
-- WHY THE CAMERA IS DRIVEN AND THE BODY IS NOT. The candle is a first-person body whose view comes
-- from the flame (client/CameraController), and it is a rigid rig rather than an avatar with a
-- ragdoll. Pitching the CAMERA face-down is the whole of "you fell headfirst" from the only viewpoint
-- that matters, and it costs nothing, replicates nothing and cannot desync — whereas actually
-- toppling the rig would be a physics state the server would then have to own and recover.
--
-- The takeover is submitted to client/CameraMotionController as a sustained contribution rather than
-- written here, so it sums with everything else moving the camera instead of multiplying into it and
-- so the reduced-motion setting can reach it. Roblox's Custom camera keeps running underneath, so
-- mouse look still works — you can look around from the floor, which is exactly what a player pinned
-- for three seconds wants to be able to do.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CameraMotionController = require(script.Parent.CameraMotionController)

local TripwireController = {}

local FALL_KEY = "TripwireFall"
local SCRABBLE_KEY = "TripwireScrabble"

-- HOW THE FALL IS SHAPED, in fractions of the stun the server sent. The drop is fast and the recovery
-- is slow, because that is the asymmetry the movement lock already has: you lose control instantly and
-- get it back gradually.
local DROP_SECONDS = 0.22
local RISE_SECONDS = 0.55
-- Face down, not quite flat. Slightly short of 90 degrees so the floor still reads as a floor rather
-- than as an untextured plane filling the screen.
local PITCH_DEGREES = 78
-- How far the view drops toward the rock. The candle's eye is around head height, so this is most of
-- the way down without putting the camera inside the terrain.
local DROP_STUDS = 2.2
-- A short scrabble while down: the small, irregular movement of somebody trying to get their hands
-- under them. Not a shake — being hit is the Lurker's language and this is not being hit.
local SCRABBLE_STUDS = 0.05
local SCRABBLE_DEGREES = 1.6
local SCRABBLE_FREQUENCY = 7

local fellAt = 0
local risesAt = 0
local seed = 0

-- 0 while standing, 1 while flat on the floor, easing in over the drop and out over the recovery.
local function fallenAmount(now: number): number
	if now < fellAt or now >= risesAt + RISE_SECONDS then
		return 0
	end
	if now < fellAt + DROP_SECONDS then
		local t = (now - fellAt) / DROP_SECONDS
		-- Fast out of the gate and settling at the end: a trip is a body being taken out from under
		-- itself, not a controlled lie-down.
		return 1 - (1 - t) * (1 - t)
	end
	if now < risesAt then
		return 1
	end
	local t = (now - risesAt) / RISE_SECONDS
	return 1 - t * t
end

local function onTrip(payload: { [string]: unknown })
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	-- EVERY CLIENT IS TOLD; ONLY THE VICTIM FALLS. The event is broadcast so teammates' own controllers
	-- can react to somebody else going down later without a second remote, and this is the filter.
	if payload.playerId ~= player.UserId then
		return
	end
	local seconds = if type(payload.seconds) == "number" then payload.seconds :: number else 1
	local now = os.clock()
	fellAt = now
	risesAt = now + math.max(seconds, 0.1)
	seed += 1
end

-- TWO CONTRIBUTIONS, NOT ONE, because they are two different things and a player who has turned the
-- camera down means different things by them. The FALL is posture: it is the only way a first-person
-- body with no third-person view can say "you are face down on the rock", so it survives even at the
-- lowest setting, just smaller. The SCRABBLE is a shake in everything but name — small, fast,
-- oscillating — and is scaled as one.
local function render()
	local now = os.clock()
	local amount = fallenAmount(now)
	if amount <= 0 then
		CameraMotionController.setSustained(FALL_KEY, nil)
		CameraMotionController.setSustained(SCRABBLE_KEY, nil)
		return
	end

	-- Down, then face-first. Submitted as a translation plus a pitch in the camera's own frame, so the
	-- view drops toward the rock rather than sliding along whatever direction it happens to face.
	CameraMotionController.setSustained(FALL_KEY, {
		x = 0,
		y = -DROP_STUDS * amount,
		z = 0,
		pitch = math.rad(-PITCH_DEGREES * amount),
		yaw = 0,
		roll = 0,
	}, "Posture")

	local phase = (now - fellAt) * SCRABBLE_FREQUENCY + seed * 2.17
	local scrabble = amount * amount
	CameraMotionController.setSustained(SCRABBLE_KEY, {
		x = math.sin(phase * 1.31) * SCRABBLE_STUDS * scrabble,
		y = math.cos(phase * 0.83) * SCRABBLE_STUDS * scrabble,
		z = 0,
		pitch = 0,
		yaw = 0,
		roll = math.rad(math.sin(phase * 0.61) * SCRABBLE_DEGREES * scrabble),
	})
end

function TripwireController.start()
	if not Config.Tripwire.enabled then
		return
	end
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: unknown)
		if kind == "tripwireTrip" and type(payload) == "table" then
			onTrip(payload :: { [string]: unknown })
		end
	end)

	-- Ahead of CameraMotionController's own step (+6), so the pose it computes is the one applied this
	-- frame rather than the one from last frame.
	RunService:BindToRenderStep("WickTripwire", Enum.RenderPriority.Camera.Value + 5, render)
end

return TripwireController
