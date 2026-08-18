--!strict
-- Build counter. AI AGENTS: if you make ANY change to this project — code, config, docs, anything —
-- bump `number` by exactly one as part of that same change, before you finish responding. Never
-- batch several changes under one bump, never skip it because the change seemed small. This is the
-- only thing that lets the small sign LobbyRoomBuilder mounts beside the how-to-play board name the
-- running build. Not a semantic version: just a monotonic count of changes.

export type VersionConfig = {
	number: number,
}

local Version: VersionConfig = {
	number = 142,
}

return Version
