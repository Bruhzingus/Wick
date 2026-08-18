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
	-- The Knotwalker's doorway trap. Separate from its row in `Threats` for the same reason the
	-- Lurker and the Warden own files: the row describes a body, and this describes a mechanism.
	Tripwire = require(script.Tripwire),
	AshamedLurker = require(script.AshamedLurker),
	StoneWarden = require(script.StoneWarden),
	WaxGrub = require(script.WaxGrub),
	StoneGnawer = require(script.StoneGnawer),
	Longarm = require(script.Longarm),
	GrubQueen = require(script.GrubQueen),
	DeadCandle = require(script.DeadCandle),
	Version = require(script.Version),
	DripTrail = require(script.DripTrail),
	Basin = require(script.Basin),
	Brazier = require(script.Brazier),
	-- The per-floor fixtures' presentation. Each is deliberately separate from the file that owns its
	-- RULES (Basin's pool, Brazier's payout, RunOrchestrator's descent), because those are design
	-- surface and these are art direction, and they are retuned by different people for different
	-- reasons. The Brazier is the one exception: its bowl lives in `Config/Brazier` beside its payout,
	-- because that fixture has exactly one job and nobody would ever change one without the other.
	Cauldron = require(script.Cauldron),
	-- The cave's lightable wall candles, and the crowned lamp that answers a floor. Unlike the three
	-- above, this one has a rule surface as well as a look — what a lit lamp is worth to threat
	-- perception — because a lamp being real light is the whole point of it.
	WallLamp = require(script.WallLamp),
	-- The hanging work lamp on the descent headframe, and nothing else any more.
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
