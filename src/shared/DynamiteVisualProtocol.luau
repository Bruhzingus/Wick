--!strict
-- The tag/attribute contract between server-built blast doors and the client that decorates them.
--
-- WHY A PROTOCOL AND NOT A REMOTE. The socket marker — the yellow stick outline showing where your own
-- charge goes — is PER PLAYER: it exists only for someone who is actually carrying dynamite. A server
-- that built it would build it for everybody, and a remote that announced every door on every floor to
-- every client would be a stream of messages saying something that never changes.
--
-- So the door publishes what it IS, once, as attributes, and `client/DynamiteController` decides what
-- to draw from that plus the dynamiteCharges it already receives in `StateSync`. This is the same
-- shape `LightVisualProtocol` and `MiningVisualProtocol` already use, for the same reason.
--
-- NOTHING HERE IS AUTHORITY. A client that lies about these attributes gets a wrongly drawn marker and
-- nothing else: `server/DynamiteService` re-reads the door from its own registry before it accepts a
-- placement, a lighting, or a break.

local DynamiteVisualProtocol = {}

-- On the door MODEL. `client/DynamiteController` watches for these.
DynamiteVisualProtocol.doorTag = "WickBlastDoor"

DynamiteVisualProtocol.attributes = {
	-- Which floor this door belongs to. A client only decorates doors on the floor it is standing on;
	-- without this a player on floor 3 would light up markers two floors below them through the rock.
	depth = "WickBlastDoorDepth",
	-- Room-local socket anchor, in world space, published as the attachment below rather than as a
	-- vector attribute. This flag only says the socket is still empty and may be filled.
	open = "WickBlastDoorOpen",
	-- True once somebody has seated a charge. The marker hides and the real charge is visible instead,
	-- so two players cannot both be told to put a stick in the same hole.
	charged = "WickBlastDoorCharged",
	-- The cave family's door style ("Rock"/"MossRock"/"Ice"), for presentation that wants to match the
	-- break debris to the rock. Never read as gameplay.
	style = "WickBlastDoorStyle",
}

-- Child of the door model: where a charge is seated, and where the marker is drawn.
DynamiteVisualProtocol.socketAttachmentName = "BlastDoorSocket"

return DynamiteVisualProtocol
