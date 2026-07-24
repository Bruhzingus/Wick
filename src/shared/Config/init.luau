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
	DripTrail = require(script.DripTrail),
	Basin = require(script.Basin),
	Brazier = require(script.Brazier),
	WaxTypes = require(script.WaxTypes),
	Floors = require(script.Floors),
	Run = require(script.RunSettings),
	Death = require(script.Death),
}
