--!strict
-- The lobby/run presentation boundary contract — the small set of tags and attributes clients read
-- to tell the two modes apart and to drive the elevator ride. All of it is written once by the
-- server (LobbyRoomBuilder at build time, CharacterService at spawn time) and never changes at
-- runtime, unlike the dripstone hazard's protocol which carries live state.

local LobbyVisualProtocol = {
	-- On each server-built elevator car so every client can render the timestamped descent curve
	-- locally instead of displaying coarse replicated CFrame steps.
	carTag = "WickElevatorCar",
	-- On the in-car SurfaceGui backing: client/ElevatorController finds the one matching a
	-- countdown's tierId and writes the descent readout into it.
	readoutTag = "WickElevatorReadout",
	attributes = {
		tierId = "WickElevatorTierId",
		-- Set on candle and wisp models by CharacterService; absent on the lobby's Roblox avatar.
		-- client/CameraController keys the first-person/third-person switch off this rather than off
		-- WickInExpedition, so the camera changes exactly when the body does.
		runBody = "WickRunBody",
		-- Set only on the cosmetic, non-draining candle used during the elevator ride. The real run
		-- candle has runBody but not rideBody.
		rideBody = "WickElevatorRideBody",
	},
}

return table.freeze(LobbyVisualProtocol)
