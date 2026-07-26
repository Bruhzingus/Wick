--!strict
-- The Landing: the static mineshaft hub between runs. Unlike Config/Floors this is one fixed layout
-- built once at boot (server/LobbyRoomBuilder) — never seeded or regenerated per run, so every
-- player who returns from a cave and every player who joins afterwards stands in the same room.
-- Positions below are local offsets from `origin`; server/LobbyRoomBuilder resolves world position.

export type LobbyElevatorDef = {
	tierId: number,
	offset: Vector3,
}

export type LobbyLightingConfig = {
	lanternRange: number,
	lanternBrightness: number,
	ceilingLampRange: number,
	ceilingLampBrightness: number,
	elevatorLampRange: number,
	elevatorLampBrightness: number,
}

export type LobbyRoomConfig = {
	origin: Vector3,
	roomWidth: number, -- X extent of the hub floor
	roomDepth: number, -- Z extent of the hub floor
	wallHeight: number,
	floorThickness: number,
	wallThickness: number,
	beamSpacing: number, -- studs between ceiling support beams
	railSpacing: number, -- studs between mine-cart rail sleepers
	lighting: LobbyLightingConfig,
	spawnOffset: Vector3,
	spawnSpread: number, -- horizontal jitter so arrivals never stack inside one another
	fallRecoveryDrop: number, -- studs below the hub floor that counts as "fell down a shaft"
	walkSpeed: number,
	sprintSpeed: number,
	jumpPower: number,
	shopOffset: Vector3,
	shopPromptText: string,
	shopObjectText: string,
	shopMessage: string,
	elevators: { LobbyElevatorDef },
	elevatorCarWidth: number,
	elevatorCarDepth: number,
	elevatorCarHeight: number,
	elevatorGateThickness: number,
	elevatorZoneRadius: number, -- horizontal distance counting as "standing in this elevator"
	elevatorLeverPromptText: string,
	elevatorLeverObjectText: string,
	elevatorBoardWidth: number,
	elevatorBoardHeight: number,
	rideDistance: number, -- studs the car physically descends during the start countdown
	rideShaftDepth: number, -- how far the built shaft runs below the car's resting position
	rideShaftRibSpacing: number, -- studs between shaft wall ribs (the parallax that sells motion)
	rideShaftRibThickness: number,
	rideShaftRibOutset: number, -- distance from the car edge to a rib ring's outside edge
	rideShakeStuds: number, -- peak camera shake amplitude during the ride
	rideShakeHz: number,
	welcomeSignOffset: Vector3,
	welcomeSignText: string,
	howToPlayOffset: Vector3,
	howToPlayIntro: string,
	howToPlayRules: { string },
	boardWidth: number,
	boardHeight: number,
	leaderboardOffset: Vector3,
	leaderboardTitle: string,
	leaderboardRows: number,
	leaderboardRefreshSeconds: number,
	leaderboardEmptyText: string,
	leaderboardUnavailableText: string,
}

local LobbyRoom: LobbyRoomConfig = {
	-- Far above every cave floor (floor depth d sits at Y = -(d-1) * Floors.geometry.floorGap, and the
	-- tallest cavern roof tops out near Y = 58), with enough headroom below for the elevator shafts the
	-- descent ride travels down. The hub can never overlap procedurally built Terrain.
	origin = Vector3.new(0, 500, 0),
	roomWidth = 140,
	roomDepth = 104,
	wallHeight = 26,
	floorThickness = 2,
	wallThickness = 2,
	beamSpacing = 16,
	railSpacing = 6,
	-- Local pools keep the built hub readable without washing out its timber-and-stone contrast.
	-- The ceiling lamps overlap gently; posts and elevator bulbs only lift their immediate area.
	lighting = {
		lanternRange = 20,
		lanternBrightness = 0.45,
		ceilingLampRange = 42,
		ceilingLampBrightness = 0.8,
		elevatorLampRange = 18,
		elevatorLampBrightness = 0.55,
	},
	-- Near the entry wall, facing the elevators across the room.
	spawnOffset = Vector3.new(0, 0, -40),
	spawnSpread = 7,
	-- Deeper than a stumble off the spawn pad, shallower than the ride's own travel, so a rider is
	-- never mistaken for someone who fell down an open shaft.
	fallRecoveryDrop = 40,
	-- Lobby movement is presentation only (no PlayerState, so no wax cost); it just needs to feel
	-- good to cross a room this size. Sprint is deliberately faster than the run's own runSpeed.
	walkSpeed = 16,
	sprintSpeed = 30,
	-- The lobby avatar keeps a full jump; the run candle has only Config.Movement.hopPower.
	jumpPower = 48,
	shopOffset = Vector3.new(-52, 0, -6),
	shopPromptText = "Browse the shop",
	shopObjectText = "General Store",
	shopMessage = "The shop is still being stocked - check back soon.",
	-- One elevator per cave tier (Config.CaveTiers), spaced across the far wall.
	elevators = {
		{ tierId = 1, offset = Vector3.new(-34, 0, 40) },
		{ tierId = 2, offset = Vector3.new(0, 0, 40) },
		{ tierId = 3, offset = Vector3.new(34, 0, 40) },
	},
	elevatorCarWidth = 14,
	elevatorCarDepth = 14,
	elevatorCarHeight = 14,
	elevatorGateThickness = 0.5,
	-- Covers the whole car floor including its corners (half-diagonal of a 14x14 car is ~9.9).
	elevatorZoneRadius = 10,
	elevatorLeverPromptText = "Descend",
	elevatorLeverObjectText = "Control Lever",
	elevatorBoardWidth = 11,
	elevatorBoardHeight = 7,
	-- The ride is the loading transition: the car actually travels this far down its shaft over
	-- Config.Run.startCountdownSeconds before the cave replaces the lobby body.
	rideDistance = 220,
	rideShaftDepth = 260,
	rideShaftRibSpacing = 10,
	rideShaftRibThickness = 0.8,
	rideShaftRibOutset = 1.5,
	rideShakeStuds = 0.1,
	rideShakeHz = 5.5,
	welcomeSignOffset = Vector3.new(-24, 9, -50.5),
	welcomeSignText = "WICK\n\nYou are a living candle.\n\nYour wax is your health, your light, your fuel, "
		.. "and your clock — every second lit is a second spent. Descend, spend yourself wisely, and "
		.. "light a Brazier to carry home what is left of you.",
	howToPlayOffset = Vector3.new(24, 9, -50.5),
	howToPlayIntro = "HOW TO PLAY",
	-- Rendered in order as a numbered list. Keybinds are NOT written here — the builder pulls those
	-- live from Config.Feel.controls so signage can never drift from the real bindings.
	howToPlayRules = {
		"Pick an elevator. The leader's car sets the cave; stand in it together to ready up.",
		"Pull the lever to descend. The deeper the cave, the richer and the hungrier it is.",
		"Burn bright to see further. Burn low to last longer and stay hidden. That dial is the game.",
		"Water at flame height snuffs you instantly. Keep to dry ground whenever you can.",
		"Reach a Brazier and deliver your remaining wax to bank it. Die instead and you keep nothing.",
	},
	boardWidth = 22,
	boardHeight = 13,
	leaderboardOffset = Vector3.new(52, 9, -6),
	leaderboardTitle = "DEEPEST DESCENTS",
	leaderboardRows = 10,
	-- Cross-server standings are cheap to read but not free; once a minute is plenty for a hub.
	leaderboardRefreshSeconds = 60,
	leaderboardEmptyText = "No one has come back up yet.",
	leaderboardUnavailableText = "Standings are unavailable in Studio.",
}

return LobbyRoom
