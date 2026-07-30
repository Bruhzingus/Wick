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
	-- On every Lamp Network housing. THE ONE PIECE OF HUB GEOMETRY THAT IS RENDERED PER VIEWER:
	-- ownership is per-player but the room is shared, so the server builds every housing dark and
	-- client/LampNetworkController lights only the ones its own player owns. There is no server-side
	-- lit state, because there is no single answer to "is this lamp lit" in a room with four people
	-- in it.
	lampHousingTag = "WickLampHousing",
	attributes = {
		tierId = "WickElevatorTierId",
		-- The stable Config/LampNetwork node id, written on each housing and on its sign so the
		-- client can match replicated ownership to geometry without depending on build order.
		lampNodeId = "WickLampNodeId",
		-- Set on run candles and ghost candles by CharacterService; absent on the lobby's Roblox avatar.
		-- client/CameraController keys the first-person/third-person switch off this rather than off
		-- WickInExpedition, so the camera changes exactly when the body does.
		runBody = "WickRunBody",
		-- Set only on the cosmetic, non-draining candle used during the elevator ride. The real run
		-- candle has runBody but not rideBody.
		rideBody = "WickElevatorRideBody",
		-- Set only on the translucent ghost candle a terminally dead player walks around in
		-- (server/CharacterService.spawnSpectator). It carries runBody too — a ghost is still viewed in
		-- first person from its own flame — so this is what tells the two apart. Presentation only: every
		-- rule that stops a ghost acting reads `PlayerRunState.alive`, never a tag.
		spectatorBody = "WickSpectatorBody",
	},
}

return table.freeze(LobbyVisualProtocol)
