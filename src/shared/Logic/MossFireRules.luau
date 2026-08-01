--!strict
-- Pure rules for Moss's flammable vegetation: what may carry a cluster, how a cluster catches, how
-- fire moves through it, and what standing beside it costs.
--
-- SERVER-AUTHORITATIVE BY CONSTRUCTION. Nothing here reads a client report, and there is deliberately
-- no function that takes "heat" or "am I being burned" as an input — the server computes exposure
-- from positions and flame state it already owns, and this module turns that into progress. A client
-- cannot light anything by saying it did.
--
-- The planner, the server service and the tests all read these, so what the player sees, what the
-- server charges them, and what a cold test asserts are one function evaluated three times.

local MossFireConfig = require(script.Parent.Parent.Config.MossFire)
local LightConfig = require(script.Parent.Parent.Config.Light)
local CaveFamilyRules = require(script.Parent.CaveFamilyRules)

local MossFireRules = {}

export type VegetationKind = MossFireConfig.VegetationKind
export type IgnitionIntensity = MossFireConfig.IgnitionIntensity

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

--------------------------------------------------------------------------------
-- Eligibility
--------------------------------------------------------------------------------

-- Only families whose environment declares it, and only at or below the configured chance. A family
-- that grows nothing flammable never plans a cluster at all rather than planning one and filtering
-- it out later.
function MossFireRules.isEligibleFamily(familyId: string?): boolean
	if not MossFireConfig.enabled then
		return false
	end
	return CaveFamilyRules.resolve(familyId).environment.flammableVegetation
end

-- Chance an eligible ORDINARY room carries a cluster at this depth. Protected rooms, the guaranteed
-- route, and every reserved footprint are excluded by the planner, not by this number.
function MossFireRules.chanceForDepth(globalDepth: number): number
	if not MossFireConfig.enabled then
		return 0
	end
	local depth = if isFiniteNumber(globalDepth) then math.max(1, math.floor(globalDepth)) else 1
	if depth < MossFireConfig.placement.minDepth then
		return 0
	end
	local rows = MossFireConfig.chanceByDepth
	if #rows == 0 then
		return 0
	end
	for _, row in rows do
		if depth <= row.maxDepth then
			return math.clamp(row.chance, 0, 1)
		end
	end
	return math.clamp(rows[#rows].chance, 0, 1)
end

--------------------------------------------------------------------------------
-- Vegetation kinds
--------------------------------------------------------------------------------

function MossFireRules.kindById(kindId: string?): VegetationKind?
	if typeof(kindId) ~= "string" then
		return nil
	end
	for _, kind in MossFireConfig.kinds do
		if kind.id == kindId then
			return kind
		end
	end
	return nil
end

-- The kind a node is. Anything unknown resolves to the first ordinary (non-quick) kind rather than
-- erroring: a floor built before a config change must still be burnable, and it must never resolve
-- to a QUICK kind by accident — that would make an unrecognised node the fastest thing in the room.
function MossFireRules.resolveKind(kindId: string?): VegetationKind
	local kind = MossFireRules.kindById(kindId)
	if kind ~= nil then
		return kind
	end
	for _, candidate in MossFireConfig.kinds do
		if not candidate.quick then
			return candidate
		end
	end
	return MossFireConfig.kinds[1]
end

function MossFireRules.selectKind(roll: number): VegetationKind
	local total = 0
	for _, kind in MossFireConfig.kinds do
		if kind.weight > 0 then
			total += kind.weight
		end
	end
	if total <= 0 then
		return MossFireConfig.kinds[1]
	end
	local target = math.clamp(if roll == roll then roll else 0, 0, 0.9999999) * total
	local cumulative = 0
	for _, kind in MossFireConfig.kinds do
		if kind.weight <= 0 then
			continue
		end
		cumulative += kind.weight
		if target < cumulative then
			return kind
		end
	end
	return MossFireConfig.kinds[#MossFireConfig.kinds]
end

function MossFireRules.burnSeconds(kind: VegetationKind, roll: number): number
	local clamped = math.clamp(if roll == roll then roll else 0, 0, 1)
	return kind.burnSecondsMin + (kind.burnSecondsMax - kind.burnSecondsMin) * clamped
end

-- How often fire tries to move on from a burning node. A quick-burning strand carries fire across a
-- cluster in a couple of seconds; ordinary growth creeps.
function MossFireRules.spreadInterval(kind: VegetationKind): number
	return if kind.quick
		then MossFireConfig.spread.quickIntervalSeconds
		else MossFireConfig.spread.normalIntervalSeconds
end

--------------------------------------------------------------------------------
-- Ignition
--------------------------------------------------------------------------------

-- WHAT MAY LIGHT SOMETHING. Deliberately a closed list, stated once:
--
--   * a player's UNCOVERED flame, at a burn rate above the low threshold;
--   * a burning Decoy;
--   * a Flare.
--
-- And what may not, each for its own reason: SNUFF is the absence of flame; a CUP-shielded flame is
-- a near-dark ember and contributes exactly zero however high the dial underneath it reads; mining
-- sparks are out of scope for this task; and a client-reported heat value is not evidence of
-- anything.
function MossFireRules.flameIgnites(isLit: boolean, isCupping: boolean, burnRate: number): boolean
	if not isLit or isCupping then
		return false
	end
	if not isFiniteNumber(burnRate) then
		return false
	end
	return burnRate >= LightConfig.maxBurnRate * MossFireConfig.ignition.lowBurnFraction
end

-- Ignition progress per second from a flame at this burn rate, interpolated CONTINUOUSLY between the
-- authored low/medium/high anchors rather than snapped to one of three cases — the dial is a
-- continuous control and holding it a little higher has to do a little more.
--
-- Returns 0 for anything below the low threshold, which is what makes a cupped or guttering candle
-- genuinely safe to carry past dry growth rather than merely slow.
function MossFireRules.flameProgressPerSecond(isLit: boolean, isCupping: boolean, burnRate: number): number
	if not MossFireRules.flameIgnites(isLit, isCupping, burnRate) then
		return 0
	end
	local ignition = MossFireConfig.ignition
	local low = LightConfig.maxBurnRate * ignition.lowBurnFraction
	local high = LightConfig.maxBurnRate * ignition.highBurnFraction
	local t = if high > low then math.clamp((burnRate - low) / (high - low), 0, 1) else 1
	-- Seconds-to-ignite is what the design states, so interpolate THAT and invert, rather than
	-- interpolating rates and getting a curve nobody authored. The medium anchor sits at the midpoint
	-- of the dial, so the curve passes through all three stated values.
	local seconds: number
	if t <= 0.5 then
		local local_ = t / 0.5
		seconds = ignition.lowExposureSeconds + (ignition.mediumExposureSeconds - ignition.lowExposureSeconds) * local_
	else
		local local_ = (t - 0.5) / 0.5
		seconds = ignition.mediumExposureSeconds
			+ (ignition.highExposureSeconds - ignition.mediumExposureSeconds) * local_
	end
	if seconds <= 0 then
		return 1
	end
	return 1 / seconds
end

-- A burning Decoy has no dial to read, so it contributes as a fixed intensity.
function MossFireRules.intensityProgressPerSecond(intensity: IgnitionIntensity): number
	local ignition = MossFireConfig.ignition
	local seconds = if intensity == "High"
		then ignition.highExposureSeconds
		elseif intensity == "Low" then ignition.lowExposureSeconds
		else ignition.mediumExposureSeconds
	if seconds <= 0 then
		return 1
	end
	return 1 / seconds
end

function MossFireRules.decoyProgressPerSecond(): number
	return MossFireRules.intensityProgressPerSecond(MossFireConfig.ignition.decoyIntensity)
end

function MossFireRules.ignitionRange(): number
	return MossFireConfig.ignition.range
end

-- One tick of ignition progress. `progressPerSecond` is the SUM of every source currently in range
-- (zero if none), and `flare` is whether a real Flare is among them.
--
-- Decay is applied only when nothing is contributing, so a player who nearly lit something and
-- walked away has not left a primed trap for whoever comes through next.
function MossFireRules.stepIgnition(progress: number, dt: number, progressPerSecond: number, flare: boolean): number
	if flare and MossFireConfig.ignition.flareIgnitesImmediately then
		return 1
	end
	local current = if isFiniteNumber(progress) then math.clamp(progress, 0, 1) else 0
	local step = if isFiniteNumber(dt) then math.max(0, dt) else 0
	if progressPerSecond > 0 then
		return math.clamp(current + progressPerSecond * step, 0, 1)
	end
	return math.clamp(current - MossFireConfig.ignition.decayPerSecond * step, 0, 1)
end

function MossFireRules.hasCaught(progress: number): boolean
	return progress >= 1
end

--------------------------------------------------------------------------------
-- Spread
--------------------------------------------------------------------------------

export type Edge = { a: number, b: number }

-- Which nodes fire may move to from `nodeIndex`. CONNECTED NODES ONLY, and only within this cluster:
-- fire cannot jump to a wet wall, to unrelated dressing, or to another cluster across the room. The
-- graph is planned once and recorded, so what can burn is decided before a single Instance exists.
function MossFireRules.neighbours(edges: { Edge }, nodeIndex: number): { number }
	local found: { number } = {}
	for _, edge in edges do
		if edge.a == nodeIndex then
			table.insert(found, edge.b)
		elseif edge.b == nodeIndex then
			table.insert(found, edge.a)
		end
	end
	return found
end

-- Is every node reachable from every other? The planner guarantees this when it builds the graph;
-- the test suite re-derives it independently, because a cluster that is secretly two clusters would
-- silently halve how much of it ever burns.
function MossFireRules.isConnectedGraph(nodeCount: number, edges: { Edge }): boolean
	if nodeCount <= 0 then
		return false
	end
	if nodeCount == 1 then
		return true
	end
	local visited: { [number]: boolean } = { [1] = true }
	local queue = { 1 }
	local head = 1
	local reached = 1
	while head <= #queue do
		local index = queue[head]
		head += 1
		for _, neighbour in MossFireRules.neighbours(edges, index) do
			if not visited[neighbour] then
				visited[neighbour] = true
				reached += 1
				table.insert(queue, neighbour)
			end
		end
	end
	return reached == nodeCount
end

--------------------------------------------------------------------------------
-- Light and heat
--------------------------------------------------------------------------------

-- How bright a cluster is right now, 0..1, from how long it has been alight and how long it has
-- left. Fire reads as a thing with a life rather than a lamp switching on.
function MossFireRules.lightFraction(elapsed: number, duration: number): number
	local light = MossFireConfig.light
	if duration <= 0 then
		return 0
	end
	local age = math.clamp(elapsed, 0, duration)
	local rise = if light.riseSeconds > 0 then math.clamp(age / light.riseSeconds, 0, 1) else 1
	local remaining = duration - age
	local fade = if light.fadeSeconds > 0 then math.clamp(remaining / light.fadeSeconds, 0, 1) else 1
	return math.clamp(math.min(rise, fade), 0, 1)
end

function MossFireRules.lightIntensity(fraction: number): number
	return MossFireConfig.light.intensity * math.clamp(fraction, 0, 1)
end

function MossFireRules.lightRange(fraction: number): number
	return MossFireConfig.light.range * math.clamp(fraction, 0, 1)
end

-- Wax per second from ONE burning node at this distance. Two flat bands rather than a falloff curve,
-- because the player has to be able to read "too close" as a place rather than as a gradient.
function MossFireRules.heatPerSecond(distance: number): number
	local heat = MossFireConfig.heat
	if not isFiniteNumber(distance) or distance < 0 then
		return 0
	end
	if distance <= heat.nearRadius then
		return heat.nearWaxPerSecond
	elseif distance <= heat.farRadius then
		return heat.farWaxPerSecond
	end
	return 0
end

-- What one CLUSTER costs per second, given the distance to each of its burning nodes. Capped, so
-- standing in the middle of a large cluster is a bad decision rather than an instant death.
function MossFireRules.clusterHeatPerSecond(distances: { number }): number
	local total = 0
	for _, distance in distances do
		total += MossFireRules.heatPerSecond(distance)
	end
	return math.min(total, MossFireConfig.heat.clusterCapPerSecond)
end

-- THE centralized wax reason for every environmental fire. One string, in one place, so the run
-- summary can say what fire cost without the number being smeared across "Other".
function MossFireRules.waxReason(): string
	return "EnvironmentalFire"
end

--------------------------------------------------------------------------------
-- Limits
--------------------------------------------------------------------------------

function MossFireRules.maxActivePerFloor(): number
	return math.max(0, math.floor(MossFireConfig.placement.maxActiveClustersPerFloor))
end

function MossFireRules.maxPerRoom(): number
	return math.max(0, math.floor(MossFireConfig.placement.maxClustersPerRoom))
end

return MossFireRules
