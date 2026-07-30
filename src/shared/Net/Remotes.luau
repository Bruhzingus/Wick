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
	| "MovementAction" -- C->S: action "SprintStart"|"SprintEnd"
	| "ActionFeedback" -- S->C: actionId string, accepted boolean, cooldown end/duration, denial reason?
	| "StateSync" -- S->C: { StateEntry } (see below)
	| "BasinOffers" -- S->C: { { id, displayName, toolId?, waxGranted } }
	| "BasinChoose" -- C->S: number (offer index)
	| "RestartRun" -- C->S: no payload; request an immediate restart after the run is over
	| "ReturnToLobby" -- C->S: no payload; leave resolved expedition and reopen tier selection
	| "LobbyAction" -- C->S: action "sync"|"ready"|"tier"|"start", optional value
	| "LobbyState" -- S->C: party, readiness, cave tiers, currency, and lobby status
	| "TutorialHint" -- S->C: hintId string after authoritative teachable contact
	-- C->S: lurker proxy BasePart, camera position Vector3, camera look Vector3. The ONLY client
	-- report the Ashamed Lurker accepts, because Roblox does not replicate a player's camera. The
	-- server validates position, distance, lane, angle and line of sight before it counts.
	| "LurkerGaze"
	-- C->S: action "engage"|"strike"|"disengage", deposit BasePart (engage only). The client reports
	-- only INTENT. It never sends a timing value: the server stamps each sweep's start in its own
	-- clock and measures the strike against it, so accuracy can never be forged (see MiningService).
	| "MineStrike"
	-- S->C: kind "engaged"|"strikeResolved"|"disengaged"|"depleted", payload table. Every sweep
	-- carries one server timestamp plus its band centre, and every client evaluates the same ring
	-- locally — the same pattern the dripstone and elevator use instead of replicating motion.
	-- C->S: no payload. Ring the Signal Bell (Config/LampNetwork.bell). The server owns the wax cost,
	-- the cooldown, whether this player owns the node at all, and who hears it; the client asks and
	-- nothing more.
	| "BellRing"
	| "MineState"
	| "RunEvent" -- S->C: kind string, payload table (elevatorRide/countdown/floor/preview/results/lurkerGrab)

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

local NAMES: { RemoteName } = {
	"SetBurnRate",
	"ToolUse",
	"MovementAction",
	"ActionFeedback",
	"StateSync",
	"BasinOffers",
	"BasinChoose",
	"RestartRun",
	"ReturnToLobby",
	"LobbyAction",
	"LobbyState",
	"TutorialHint",
	"LurkerGaze",
	"MineStrike",
	"MineState",
	"BellRing",
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
