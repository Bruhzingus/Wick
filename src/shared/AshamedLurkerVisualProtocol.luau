--!strict
-- Replicated presentation contract for the Ashamed Lurker. The server owns one invisible anchored
-- proxy part per creature and changes only these attributes; every client builds and animates the
-- detailed body locally around it (the same split ThreatVisualProtocol uses for creatures).
-- No gameplay decision travels through this contract.

local AshamedLurkerVisualProtocol = {
	tag = "WickAshamedLurker",
	states = {
		-- Clinging to the springer, arm across the trap lane.
		dormant = "Dormant",
		-- Mid-lunge. The server has already scheduled the grab check.
		triggered = "Triggered",
		-- Caught staring: eye darts, arms cover the face, body withdraws into the arch.
		ashamed = "Ashamed",
		-- Gone from this arch. It reappears at another one when the server moves the proxy.
		hidden = "Hidden",
	},
	attributes = {
		state = "WickLurkerState",
		-- Workspace:GetServerTimeNow() when the state was entered, so late joiners and distant
		-- clients rebuilding after a cull start the animation at the right offset.
		stateStartedAt = "WickLurkerStateStartedAt",
		trapSide = "WickLurkerTrapSide",
		doorWidth = "WickLurkerDoorWidth",
		doorHeight = "WickLurkerDoorHeight",
		visualSeed = "WickLurkerVisualSeed",
		-- Increments every time the server moves the proxy to a different arch. Clients rebuild the
		-- body on a change rather than sliding it across the floor.
		site = "WickLurkerSite",
		depth = "WickLurkerDepth",
		-- WHICH CAVE'S ROCK the socket and back plates imitate. Presentation only, and the one thing
		-- about this creature a family changes: its flesh is identical everywhere, but the stone it
		-- hides against has to be the stone that is actually there or the ambush does not work.
		familyId = "WickLurkerFamily",
	},
}

return table.freeze(AshamedLurkerVisualProtocol)
