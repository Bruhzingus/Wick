--!strict
-- Aggregated type index. `local Types = require(ReplicatedStorage.Shared.Types)` then `Types.WaxState`, etc.
-- Types only — this module has no runtime behaviour. Re-exports every domain type from one place.

local Player = require(script.Player)
local Wax = require(script.Wax)
local Tool = require(script.Tool)
local Threat = require(script.Threat)
local Hazard = require(script.Hazard)
local Light = require(script.Light)
local Sacrifice = require(script.Sacrifice)
local World = require(script.World)
local RunResult = require(script.RunResult)
local Loot = require(script.Loot)

-- Player
export type PlayerId = Player.PlayerId
export type PlayerRunState = Player.PlayerRunState
export type MovementMode = Player.MovementMode
export type WispState = Player.WispState

-- Wax
export type WaxAmount = Wax.WaxAmount
export type WaxState = Wax.WaxState
export type BurnRate = Wax.BurnRate
export type WaxTypeId = Wax.WaxTypeId
export type WaxTypeDef = Wax.WaxTypeDef

-- Tool
export type ToolId = Tool.ToolId
export type ToolDef = Tool.ToolDef

-- Threat
export type ThreatCategory = Threat.ThreatCategory
export type ThreatId = Threat.ThreatId
export type ThreatDef = Threat.ThreatDef
export type ThreatState = Threat.ThreatState
export type ThreatMode = Threat.ThreatMode
export type ContactEffect = Threat.ContactEffect

-- Loot
export type LootId = Loot.LootId
export type LootKind = Loot.LootKind
export type LootDef = Loot.LootDef

-- Hazard
export type HazardId = Hazard.HazardId
export type HazardDef = Hazard.HazardDef
export type WaterAssessment = Hazard.WaterAssessment

-- Light field
export type LightSource = Light.LightSource
export type LightSourceKind = Light.LightSourceKind
export type TrailPoint = Light.TrailPoint

-- Sacrifice
export type SacrificeId = Sacrifice.SacrificeId
export type SacrificeTarget = Sacrifice.SacrificeTarget
export type SacrificeDef = Sacrifice.SacrificeDef
export type ResolvedOffer = Sacrifice.ResolvedOffer
export type SacrificeModifiers = Sacrifice.SacrificeModifiers

-- World
export type RoomModuleId = World.RoomModuleId
export type RoomModuleDef = World.RoomModuleDef
export type Direction = World.Direction
export type RoomPlacement = World.RoomPlacement
export type ThreatSpawn = World.ThreatSpawn
export type LootSpawn = World.LootSpawn
export type HazardPlacement = World.HazardPlacement
export type FloorPlan = World.FloorPlan

-- Run
export type RunResult = RunResult.RunResult
export type DeathCause = RunResult.DeathCause

return {}
