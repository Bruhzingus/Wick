--!strict
-- THE ECHO LOCK (Config/LampNetwork.generation.echoLock, LAMP-NETWORK.md N5). Server authority over
-- the barred loop doorway: whether a ring reached it, and the bars climbing once one did.
--
-- WHY THIS IS A SERVICE AND NOT A PROXIMITY PROMPT. The gate has no interaction of its own — there is
-- nothing to hold, press, or carry. It answers exactly one thing, a Signal Bell paid for and rung
-- nearby, which makes the second node the player bought the key to the first. Everything that decides
-- whether a ring counts lives in Logic/EchoGateRules, so what a cold test asserts and what a live
-- server opens are one function.
--
-- THERE IS NO REMOTE IN THIS FILE, and that is structural rather than incidental. A client cannot ask
-- for a gate: it can only ask SignalBellService to ring, which charges wax, enforces a cooldown,
-- re-reads node ownership, and feeds the noise field before it ever calls in here. Every gate this
-- module opens was therefore paid for at the bell.
--
-- ONCE OPEN, ALWAYS OPEN. A lifted gate is never re-barred for the rest of the floor. Re-sealing it
-- would turn a bought shortcut into a toll, and the wax was already spent on the ring.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EchoGateRules = require(ReplicatedStorage.Shared.Logic.EchoGateRules)
local FloorBuilder = require(script.Parent.FloorBuilder)
local Telemetry = require(script.Parent.Telemetry)

local EchoGateService = {}

type Runtime = FloorBuilder.EchoGateRuntime & {
	-- nil until a ring reached it. From that moment the lift needs nobody present: the bell was the
	-- whole interaction, and a party that rang and walked on should find the way open behind them.
	opening: boolean,
	-- 0..1 of the way through `liftStuds`. Never decreases.
	progress: number,
	-- Where each bar started, so the lift is applied to the authored position rather than accumulated
	-- frame by frame — accumulation would drift the bars by whatever the frame times happened to be.
	restY: { number },
}

local runtimesByDepth: { [number]: { Runtime } } = {}

function EchoGateService.registerFloor(depth: number, inputs: { FloorBuilder.EchoGateRuntime })
	local floorRuntimes: { Runtime } = {}
	for _, input in inputs do
		local restY: { number } = {}
		for index, bar in input.bars do
			restY[index] = bar.Position.Y
		end
		table.insert(floorRuntimes, {
			model = input.model,
			barrier = input.barrier,
			bars = input.bars,
			depth = input.depth,
			position = input.position,
			liftStuds = input.liftStuds,
			openSeconds = input.openSeconds,
			opening = false,
			progress = 0,
			restY = restY,
		})
	end
	runtimesByDepth[depth] = floorRuntimes
end

-- A paid ring, at a position on a floor. Opens every gate within range on THAT floor and reports how
-- many started moving, for the bell's telemetry.
--
-- COLLISION IS DROPPED THE INSTANT A RING IS ANSWERED, before a single bar has moved. The barrier is
-- anchored, and riding it up through a player standing in the opening would fire them into the arch —
-- so the thing that blocks stops blocking immediately and the bars catch up over `openSeconds`. Half a
-- second of walking through bars that are already visibly climbing is the cheap failure here; being
-- launched into rock is not.
function EchoGateService.ringAt(depth: number, position: Vector3): number
	if not Config.LampNetwork.enabled or not Config.LampNetwork.generation.enabled then
		return 0
	end
	local floorRuntimes = runtimesByDepth[depth]
	if floorRuntimes == nil then
		return 0
	end

	local opened = 0
	for _, runtime in floorRuntimes do
		if runtime.opening or runtime.model.Parent == nil then
			continue
		end
		if not EchoGateRules.withinRingRange(position, runtime.position) then
			continue
		end
		runtime.opening = true
		runtime.barrier.CanCollide = false
		opened += 1
		Telemetry.event("echo_gate_opened", nil, { depth = depth })
	end
	return opened
end

function EchoGateService.tick(dt: number)
	for _, floorRuntimes in runtimesByDepth do
		for _, runtime in floorRuntimes do
			if not runtime.opening or runtime.progress >= 1 or runtime.model.Parent == nil then
				continue
			end
			-- A zero or negative `openSeconds` is a config that wants the gate open now, not one that
			-- wants a division by zero.
			runtime.progress = if runtime.openSeconds > 0
				then math.min(runtime.progress + dt / runtime.openSeconds, 1)
				else 1

			local lifted = runtime.liftStuds * runtime.progress
			for index, bar in runtime.bars do
				if bar.Parent == nil then
					continue
				end
				local rest = runtime.restY[index]
				if rest ~= nil then
					bar.Position = Vector3.new(bar.Position.X, rest + lifted, bar.Position.Z)
				end
			end
			if runtime.progress >= 1 then
				-- The barrier has been non-colliding since the ring; destroying it here only stops an
				-- opened floor from carrying a part that can never do anything again.
				runtime.barrier:Destroy()
			end
		end
	end
end

function EchoGateService.reset()
	table.clear(runtimesByDepth)
end

-- Test and diagnostic read: is every gate on this floor open? Never read by gameplay — nothing in the
-- game may branch on a shortcut existing, or the Echo Lock would have become required progression.
function EchoGateService.allOpen(depth: number): boolean
	local floorRuntimes = runtimesByDepth[depth]
	if floorRuntimes == nil then
		return true
	end
	for _, runtime in floorRuntimes do
		if not runtime.opening then
			return false
		end
	end
	return true
end

return EchoGateService
