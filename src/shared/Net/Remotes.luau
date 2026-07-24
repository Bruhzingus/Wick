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
	| "ToolUse" -- C->S: toolId string, aimPoint Vector3? (Cast only)
	| "MovementAction" -- C->S: action "Dodge"|"Slide"|"SprintStart"|"SprintEnd", direction Vector3?
	| "MovementApproved" -- S->C: action "Dodge", direction Vector3, speed number, duration number
	| "StateSync" -- S->C: { StateEntry } (see below)
	| "BasinOffers" -- S->C: { { id, displayName, toolId?, waxGranted } }
	| "BasinChoose" -- C->S: number (offer index)
	| "RestartRun" -- C->S: no payload; request an immediate restart after the run is over
	| "ReturnToLobby" -- C->S: no payload; leave resolved expedition and reopen tier selection
	| "LobbyAction" -- C->S: action "sync"|"ready"|"tier"|"start", optional value
	| "LobbyState" -- S->C: party, readiness, cave tiers, currency, and lobby status
	| "RunEvent" -- S->C: kind string, payload table (countdown/floor/preview/death/results text data)

-- One player's replicated projection. Everything a client may render; nothing it may decide.
export type StateEntry = {
	playerId: number,
	wax: number,
	maxWax: number,
	burnRate: number,
	waxTypeId: Types.WaxTypeId,
	freeToolCharges: { [Types.ToolId]: number },
	isLit: boolean,
	isCupping: boolean,
	height: number,
	depth: number,
	alive: boolean,
	finished: boolean,
	snuffed: boolean,
	inDraft: boolean,
	water: Types.WaterAssessment,
}

local NAMES: { RemoteName } = {
	"SetBurnRate",
	"ToolUse",
	"MovementAction",
	"MovementApproved",
	"StateSync",
	"BasinOffers",
	"BasinChoose",
	"RestartRun",
	"ReturnToLobby",
	"LobbyAction",
	"LobbyState",
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
