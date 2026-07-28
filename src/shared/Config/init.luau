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
	Extraction = require(script.Extraction),
	Sound = require(script.Sound),
	Vines = require(script.Vines),
	AshamedLurker = require(script.AshamedLurker),
	StoneWarden = require(script.StoneWarden),
	Version = require(script.Version),
	DripTrail = require(script.DripTrail),
	Basin = require(script.Basin),
	Brazier = require(script.Brazier),
	WaxTypes = require(script.WaxTypes),
	Depth = require(script.Depth),
	Floors = require(script.Floors),
	Run = require(script.RunSettings),
	Death = require(script.Death),
	Loot = require(script.Loot),
	Remains = require(script.Remains),
	Feel = require(script.Feel),
	Audio = require(script.Audio),
	Security = require(script.Security),
	Lobby = require(script.Lobby),
	CaveTiers = require(script.CaveTiers),
	LampNetwork = require(script.LampNetwork),
	LobbyRoom = require(script.LobbyRoom),
}
