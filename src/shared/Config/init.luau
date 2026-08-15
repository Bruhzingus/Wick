--!strict
-- Aggregated config index — the tuning surface (DESIGN §19). Every number a designer wants to change lives
-- under one of these tables. `require(ReplicatedStorage.Shared.Config).Wax.startingWax`, etc.
-- See TUNING.md for the full value list grouped by the feel-question each answers.

return {
	Wax = require(script.Wax),
	Light = require(script.Light),
	Movement = require(script.Movement),
	Character = require(script.Character),
	Tools = require(script.Tools),
	Threats = require(script.Threats),
	Hazards = require(script.Hazards),
	Mining = require(script.Mining),
	Dynamite = require(script.Dynamite),
	Extraction = require(script.Extraction),
	Sound = require(script.Sound),
	Vines = require(script.Vines),
	Icicles = require(script.Icicles),
	AshamedLurker = require(script.AshamedLurker),
	StoneWarden = require(script.StoneWarden),
	DeadCandle = require(script.DeadCandle),
	Version = require(script.Version),
	DripTrail = require(script.DripTrail),
	Basin = require(script.Basin),
	Brazier = require(script.Brazier),
	-- The three per-floor fixtures' presentation. Each is deliberately separate from the file that
	-- owns its RULES (Basin's pool, Brazier's payout, RunOrchestrator's descent), because those three
	-- are design surface and these are art direction, and they are retuned by different people for
	-- different reasons.
	Cauldron = require(script.Cauldron),
	Lantern = require(script.Lantern),
	DescentLadder = require(script.DescentLadder),
	CandleModifiers = require(script.CandleModifiers),
	Depth = require(script.Depth),
	Floors = require(script.Floors),
	Run = require(script.RunSettings),
	Death = require(script.Death),
	Spectator = require(script.Spectator),
	Loot = require(script.Loot),
	Remains = require(script.Remains),
	Feel = require(script.Feel),
	Audio = require(script.Audio),
	Security = require(script.Security),
	Lobby = require(script.Lobby),
	CaveTiers = require(script.CaveTiers),
	CaveFamilies = require(script.CaveFamilies),
	Ore = require(script.Ore),
	MineRelics = require(script.MineRelics),
	MossFire = require(script.MossFire),
	LampNetwork = require(script.LampNetwork),
	LobbyRoom = require(script.LobbyRoom),
	Diagnostics = require(script.Diagnostics),
	DevTestRoom = require(script.DevTestRoom),
}
