--!strict
-- Movement tuning. Moveset is run/dodge/slide only (DESIGN §5). Moving fast burns faster.

local Types = require(script.Parent.Parent.Types)

export type DrainThresholds = {
	runAtFractionOfRunSpeed: number,
	walkAtFractionOfWalkSpeed: number,
}

export type MovementConfig = {
	walkSpeed: number,
	runSpeed: number,
	dodgeDistance: number,
	dodgeSpeed: number,
	dodgeCooldown: number,
	slideDuration: number,
	slideSpeed: number,
	slideCooldown: number,
	walkWaxPerSecond: Types.WaxAmount,
	runWaxPerSecond: Types.WaxAmount,
	dodgeWaxCost: Types.WaxAmount,
	slideWaxCost: Types.WaxAmount,
	drainThresholds: DrainThresholds,
}

-- All wax costs below are further scaled by Config/Wax.movementCostMultiplier.
local Movement: MovementConfig = {
	-- Walk speed (studs/s). Higher = cover ground faster (easier), but see walk cost.
	walkSpeed = 8,
	-- Run speed (studs/s), held sprint. Higher = faster escape, but higher wax burn (speed is a purchase).
	runSpeed = 16,
	-- Dodge dash distance (studs). Longer = more escape utility = easier. Shortened by the Dodge sacrifice.
	dodgeDistance = 12,
	-- Dodge dash speed (studs/s). Distance / speed = how long the dash lasts.
	dodgeSpeed = 40,
	-- Seconds between dodges. Longer = harder: less escape available.
	dodgeCooldown = 1.5,
	-- Slide duration (seconds). Longer = more distance per slide.
	slideDuration = 0.6,
	-- Slide peak speed (studs/s).
	slideSpeed = 22,
	-- Seconds between slides. Longer = harder.
	slideCooldown = 2.5,
	-- Wax drained per second while walking. Higher = harder.
	walkWaxPerSecond = 0.001,
	-- Wax drained per second while running. Higher = harder.
	runWaxPerSecond = 0.004,
	-- Wax spent per dodge. Higher = harder.
	dodgeWaxCost = 0.01,
	-- Wax spent per slide. Higher = harder.
	slideWaxCost = 0.008,
	-- The server infers Idle/Walk/Run from MEASURED speed (never client claims); these set the cutoffs.
	drainThresholds = {
		-- Speed >= runSpeed * this counts as running (charges runWaxPerSecond).
		runAtFractionOfRunSpeed = 0.75,
		-- Speed >= walkSpeed * this counts as walking; below is idle.
		walkAtFractionOfWalkSpeed = 0.25,
	},
}

return Movement
