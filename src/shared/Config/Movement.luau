--!strict
-- Movement tuning. The hop is terrain recovery; running is the only fast movement mode.

local Types = require(script.Parent.Parent.Types)

export type DrainThresholds = {
	runAtFractionOfRunSpeed: number,
	walkAtFractionOfWalkSpeed: number,
}

export type MovementConfig = {
	walkSpeed: number,
	runSpeed: number,
	hopPower: number,
	walkWaxPerSecond: Types.WaxAmount,
	runWaxPerSecond: Types.WaxAmount,
	drainThresholds: DrainThresholds,
}

-- All wax costs below are further scaled by Config/Wax.movementCostMultiplier.
local Movement: MovementConfig = {
	-- Walk speed (studs/s). Higher = cover ground faster (easier), but see walk cost.
	walkSpeed = 8,
	-- Default run speed (studs/s). Higher = faster escape, but higher wax burn (speed is a purchase).
	runSpeed = 16,
	-- Low grounded hop for clearing small cracks and terrain seams. Higher makes the candle more
	-- athletic.
	hopPower = 30,
	-- Wax drained per second while walking. Higher = harder.
	walkWaxPerSecond = 0.001,
	-- Wax drained per second while running. Higher = harder.
	runWaxPerSecond = 0.004,
	-- The server infers Idle/Walk/Run from MEASURED speed (never client claims); these set the cutoffs.
	drainThresholds = {
		-- Speed >= runSpeed * this counts as running (charges runWaxPerSecond).
		runAtFractionOfRunSpeed = 0.75,
		-- Speed >= walkSpeed * this counts as walking; below is idle.
		walkAtFractionOfWalkSpeed = 0.25,
	},
}

return Movement
