--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local ThreatBrain = require(script.Parent.Parent.Logic.ThreatBrain)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)

local function definitionFor(category: Types.ThreatCategory): Types.ThreatDef
	for _, def in ThreatsConfig.definitions do
		if def.category == category then
			return def
		end
	end
	error("missing threat definition for " .. category)
end

local function stateFor(def: Types.ThreatDef): Types.ThreatState
	return {
		id = def.id,
		category = def.category,
		position = Vector3.zero,
		homePosition = Vector3.zero,
		mode = "Wander",
		targetPosition = nil,
		targetPlayerId = nil,
		nextThinkAt = 0,
	}
end

local function light(
	position: Vector3,
	intensity: number,
	range: number,
	attractsDrawn: boolean,
	ownerId: number?
): Types.LightSource
	return {
		kind = "Flame",
		position = position,
		intensity = intensity,
		range = range,
		attractsDrawn = attractsDrawn,
		ownerId = ownerId,
	}
end

local suite: Harness.Suite = {
	name = "ThreatBrain",
	tests = {
		Harness.test("drawn seek an eligible light source and ignore cold wax", function()
			local def = definitionFor("Drawn")
			local state = stateFor(def)
			local cold = light(Vector3.new(1, 0, 0), 100, def.detectionRadius, false, 10)
			local warm = light(Vector3.new(2, 4, 0), 1, def.detectionRadius, true, 20)
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = { cold, warm },
				trail = {},
				now = 5,
				rng = Random.new(1),
			})

			Harness.equal(result.mode, "Seek")
			Harness.equal(result.targetPlayerId, warm.ownerId)
			Harness.vectorNear(result.targetPosition :: Vector3, Vector3.new(warm.position.X, 0, warm.position.Z))
			Harness.near(result.nextThinkAt, 5 + ThreatsConfig.behavior.repathIntervalSeconds)
		end),

		Harness.test("dark-hunters flee when local light crosses the repel threshold", function()
			local def = definitionFor("DarkHunter")
			local state = stateFor(def)
			local sensitivity = math.abs(def.lightResponse)
			local intensity = ThreatsConfig.behavior.repelLightThreshold / sensitivity + 1
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = { light(state.position, intensity, def.detectionRadius, true, 1) },
				trail = {},
				now = 0,
				rng = Random.new(2),
			})

			Harness.equal(result.mode, "Flee")
			Harness.vectorNear(result.targetPosition :: Vector3, state.position + Vector3.xAxis * def.detectionRadius)
			Harness.isNil(result.targetPlayerId)
		end),

		Harness.test("dark-hunters choose the nearest targetable dim player", function()
			local def = definitionFor("DarkHunter")
			local state = stateFor(def)
			local players: { ThreatBrain.PlayerSnapshot } = {
				{ playerId = 1, position = Vector3.new(2, 5, 0), lightLevel = 0, targetable = false },
				{ playerId = 2, position = Vector3.new(6, 5, 0), lightLevel = 0, targetable = true },
				{ playerId = 3, position = Vector3.new(4, 5, 0), lightLevel = 0, targetable = true },
			}
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = players,
				sources = {},
				trail = {},
				now = 0,
				rng = Random.new(3),
			})

			Harness.equal(result.mode, "Seek")
			Harness.equal(result.targetPlayerId, 3)
			Harness.vectorNear(result.targetPosition :: Vector3, Vector3.new(4, 0, 0))
		end),

		Harness.test("dark-hunters follow the freshest trail point in range when prey is absent", function()
			local def = definitionFor("DarkHunter")
			local state = stateFor(def)
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = {},
				trail = {
					{ position = Vector3.new(2, 8, 0), ownerId = 1, createdAt = 10 },
					{ position = Vector3.new(3, 8, 0), ownerId = 1, createdAt = 20 },
					{
						position = Vector3.new(def.detectionRadius + 1, 0, 0),
						ownerId = 1,
						createdAt = 30,
					},
				},
				now = 0,
				rng = Random.new(4),
			})

			Harness.equal(result.mode, "Seek")
			Harness.vectorNear(result.targetPosition :: Vector3, Vector3.new(3, 0, 0))
			Harness.isNil(result.targetPlayerId)
		end),

		Harness.test("step uses mode speed and never overshoots a target", function()
			local def = definitionFor("Drawn")
			local state = stateFor(def)
			state.mode = "Seek"
			state.targetPosition = Vector3.new(1, 0, 0)
			Harness.vectorNear(ThreatBrain.step(state, def, 10), state.targetPosition)

			state.mode = "Wander"
			state.targetPosition = Vector3.new(100, 0, 0)
			local dt = 0.25
			local stepped = ThreatBrain.step(state, def, dt)
			Harness.near(
				(stepped - state.position).Magnitude,
				def.speed * ThreatsConfig.behavior.wanderSpeedFraction * dt
			)

			state.targetPosition = nil
			Harness.vectorNear(ThreatBrain.step(state, def, dt), state.position)
		end),
	},
}

return suite
