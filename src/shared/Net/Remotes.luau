--!strict
-- The single source of truth for every remote: names and payload shapes. The server creates the
-- folder on require; clients wait for it. No other file may call Instance.new("RemoteEvent").
-- Payloads cross the network untyped; receivers must validate (see server services).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

local FOLDER_NAME = "WickRemotes"

export type RemoteName =
	"SetBurnRate" -- C->S: number (target burn rate; server clamps)
	| "ToolUse" -- C->S: toolId string, aimPoint Vector3? (Decoy only)
	| "ActionFeedback" -- S->C: actionId string, accepted boolean, cooldown end/duration, denial reason?
	| "StateSync" -- S->C: { StateEntry } (see below)
	| "BasinOffers" -- S->C: { { id, displayName, toolId?, waxGranted } }
	| "BasinChoose" -- C->S: number (offer index)
	| "RestartRun" -- C->S: no payload; request an immediate restart after the run is over
	| "ReturnToLobby" -- C->S: no payload; resolved survivor leaves early, or the resolved party reopens the lobby
	| "LobbyAction" -- C->S: action "sync"|"ready"|"tier"|"start", optional value
	| "LobbyState" -- S->C: party, readiness, cave tiers, currency, and lobby status
	| "ShopAction" -- C->S: shop intent plus an id/depth; never a client-authored price
	| "ShopState" -- S->C: server-authored Lamp Network/Cave Access snapshot and action result
	| "TutorialHint" -- S->C: hintId string after authoritative teachable contact
	-- C->S: lurker proxy BasePart, camera position Vector3, camera look Vector3. The ONLY client
	-- report the Ashamed Lurker accepts, because Roblox does not replicate a player's camera. The
	-- server validates position, distance, lane, angle and line of sight before it counts.
	| "LurkerGaze"
	-- C->S: action "engage"|"strike"|"disengage", deposit BasePart (engage) or shared click timestamp
	-- (strike). The server validates every rule and accepts the timestamp only through
	-- MiningRules.resolveInputClock's narrow rewind window; no phase, accuracy, or progress is sent.
	| "MineStrike"
	-- S->C: kind "engaged"|"strikeResolved"|"disengaged"|"depleted", payload table. Every sweep
	-- carries one server timestamp plus its band centre, and every client evaluates the same rail
	-- locally — the same pattern the dripstone and elevator use instead of replicating motion.
	| "MineState"
	-- C->S: no payload. Ring the Signal Bell (Config/LampNetwork.bell). The server owns the wax cost,
	-- the cooldown, whether this player owns the node at all, and who hears it; the client asks and
	-- nothing more.
	| "BellRing"
	-- C->S: action "follow"|"release". The whole spectator input surface: a ghost asks to attach to the
	-- next living teammate, or to none. It never names a target, a position or a floor — the server owns
	-- the cycle order (Logic/SpectatorRules.nextFollowTarget) and every anchor it produces.
	| "SpectatorAction"
	-- S->C, AND ONLY TO PLAYERS WHO ARE DEAD: a ghost's follow status plus the new teammate footfalls it
	-- is allowed to see. The one-way audience IS the feature rather than an optimisation — a living
	-- client never receives a sample, so "you can only see where your teammates walked" is not something
	-- a modified client can turn into a map of the party.
	| "SpectatorState"
	-- `basinChoice` acknowledges whether the server committed the pending private offer. The client
	-- never closes optimistically: accepted closes it; a retryable proximity rejection leaves it open.
	| "RunEvent" -- S->C: kind string, payload table (floor/results/basinChoice/elevatorRide/lurkerGrab/mineImpact/etc.)

-- A display-only projection of a server-owned cooldown. `endsAt` is expressed in
-- Workspace:GetServerTimeNow() space, which is shared between server and clients.
export type ActionCooldown = {
	endsAt: number,
	duration: number,
}

-- One player's replicated projection. Everything a client may render; nothing it may decide.
export type StateEntry = {
	playerId: number,
	wax: number,
	maxWax: number,
	burnRate: number,
	waxTypeId: Types.WaxTypeId,
	freeToolCharges: { [Types.ToolId]: number },
	actionCooldowns: { [string]: ActionCooldown },
	isLit: boolean,
	isCupping: boolean,
	isFlaring: boolean,
	height: number,
	depth: number,
	alive: boolean,
	finished: boolean,
	snuffed: boolean,
	-- PHASE 8 cargo (Config/Extraction). A carried COUNT, and deliberately ONLY a count: the currency
	-- value of a bag is revealed at a brazier and nowhere else, so that the decision to turn back is
	-- made at the exit rather than continuously recalculated in the dark. Replicated so the readout
	-- cannot drift from the server's cargo, which is the only cargo there is.
	rawWax: number,
	water: Types.WaterAssessment,
	-- Sacrifice-owned client-side effects. The server still owns every rule; these fields render the
	-- nearby-threat cue and permanent vision costs.
	canHearThreats: boolean,
	peripheralDarkness: number,
	sightBrightness: number,
	sightSaturation: number,
}

-- What one ghost is told about its own spectating (server/SpectatorService -> client/SpectatorController).
-- Sent only to dead players. `samples` carries the footfalls this ghost has not seen yet — never the
-- whole buffer — except when `reset` is true, which means "forget every mark you are drawing and take
-- these instead" (a new ghost, or a ghost that just followed the party onto another floor).
export type SpectatorPayload = {
	targetId: number?, -- who this ghost is following; nil = roaming free
	targetName: string?, -- resolved server-side so the readout works for a ghost with no target loaded
	followable: number, -- how many teammates are still down there to follow
	depth: number, -- the floor the ghost is on; changes when following carries it down after the party
	reset: boolean,
	samples: { Types.SpectatorSample },
}

local NAMES: { RemoteName } = {
	"SetBurnRate",
	"ToolUse",
	"ActionFeedback",
	"StateSync",
	"BasinOffers",
	"BasinChoose",
	"RestartRun",
	"ReturnToLobby",
	"LobbyAction",
	"LobbyState",
	"ShopAction",
	"ShopState",
	"TutorialHint",
	"LurkerGaze",
	"MineStrike",
	"MineState",
	"BellRing",
	"SpectatorAction",
	"SpectatorState",
	"RunEvent",
}

local Remotes = {}

local folder: Folder? = nil

local function ensureFolder(): Folder
	if folder ~= nil then
		return folder
	end
	if RunService:IsServer() then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		for _, name in NAMES do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = created
		end
		created.Parent = ReplicatedStorage
		folder = created
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	return folder :: Folder
end

function Remotes.get(name: RemoteName): RemoteEvent
	local container = ensureFolder()
	if RunService:IsServer() then
		return container:FindFirstChild(name) :: RemoteEvent
	end
	return container:WaitForChild(name) :: RemoteEvent
end

return Remotes
