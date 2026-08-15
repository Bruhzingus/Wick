--!strict
-- Pure geometry for THE DESCENT LEVER (see server/LobbyRoomBuilder.descentLever), split out so the
-- lever's rest pose and the throw it performs on itself when a descent starts
-- (client/ElevatorController) are computed from the exact same numbers and can never quietly drift
-- apart. Nothing here is driven by player input. Every position here is in the elevator car's own
-- local space — `+X` is into the east wall, `+Y` is up, `+Z` is the car's forward lane — so a car
-- built anywhere in the hub gets an identical lever for free, and the client can reconstruct the
-- handle's pose without ever asking the server where it is.
--
-- THE HANDLE IS A T-BAR ON TWO RAILS, NOT A SINGLE ROD: a panel bolted flat to the wall, two slim
-- rails hinged off it and projecting into the car, a crossbar tying their outer ends, and a red grip
-- through it. That is four moving parts rather than one, so the pose is published as a list
-- of named pieces (`handlePieces`) instead of a fixed pair — the builder creates exactly that list
-- and both animators write back to exactly that list, which is what stops a new piece from being
-- added to the lever and then silently left behind when the switch throws.

local LeverGeometry = {}

-- The handle's two named poses, as rotations about the hinge's Z axis. `0` holds the rails straight
-- out of the wall; NEGATIVE rakes them up and POSITIVE swings them down past horizontal. Exported so
-- the builder (rest pose) and the ride renderer (the throw) share one definition of "up" and "down"
-- and can never disagree about either. The thrown angle is bounded by the floor, not by taste: the
-- crossbar's lower tip has to still clear it (see `pivotY` below).
LeverGeometry.REST_ANGLE = math.rad(-30)
LeverGeometry.THROWN_ANGLE = math.rad(50)
-- How long the throw takes once a descent actually starts. Short enough to read as the machinery
-- committing in one motion rather than a slow mechanical swing — the gate is already sliding shut by
-- the time it settles.
LeverGeometry.THROW_DURATION = 0.35

-- Rail length from the hinge. The one handle dimension the outside world asks about (the panel is
-- sized around it), so it lives up here; the rest are local to `handlePieces`.
LeverGeometry.ARM_LENGTH = 1.9

export type Layout = {
	-- The dark backing the painted plate sits on, oversized just enough to leave a rim all round. One
	-- extra part, and the reason the panel reads as a mounted fixture instead of a rectangle of paint
	-- lying on the wall.
	rimOffset: Vector3,
	rimSize: Vector3,
	plateOffset: Vector3,
	plateSize: Vector3,
	-- Brass bolt heads, in reading order (bottom row first). Two flanking columns of three, never a
	-- middle one: the plate's centre line belongs to the hinge and the lamp. Round and SMALL — the
	-- rhythm of the fixings is what the eye reads at this size, not their individual shapes.
	boltOffsets: { Vector3 },
	boltSize: Vector3,
	-- The two cheeks the hinge pin runs between, and the pin itself. A pair of thin plates rather
	-- than one block, so the rails stay visible where they meet the panel.
	cheekOffsets: { Vector3 },
	cheekSize: Vector3,
	pinOffset: Vector3,
	pinSize: Vector3,
	-- The lamp's dark surround. Without it a bare neon disc on a flat panel just blows out.
	bezelOffset: Vector3,
	bezelSize: Vector3,
	lampOffset: Vector3,
	lampSize: Vector3,
	-- The hinge the whole handle swings around, in car-local space. `handlePieces` takes this
	-- directly.
	pivotOffset: Vector3,
}

-- One piece of the moving handle. `cylinder` is geometry, not decoration: a Roblox cylinder runs
-- along its own X, so a piece flagged here has already had that axis turned onto its length and the
-- builder must not rotate it again.
export type Piece = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	cylinder: boolean,
}

-- EVERY PIECE IS DERIVED FROM THE FACE OF THE ONE BEHIND IT rather than from its own hand-picked
-- offset, so nothing ends up hovering a fraction of a stud off its neighbour. `halfCarWidth` is the
-- only input because every car in the hub is built to the same width
-- (Config.LobbyRoom.elevatorCarWidth), so one layout serves all of them.
function LeverGeometry.layout(halfCarWidth: number): Layout
	local floorY = 0.4 -- top face of the platform: the plane a rider stands on
	local wallX = halfCarWidth - 0.25 -- inner face of the east wall
	local laneZ = 2 -- forward of the gate and clear of the back-wall readout

	-- SIZED TO A HAND, NOT TO THE WALL. A rider is about five studs tall, so a panel much past four is
	-- no longer a switch somebody installed — it is architecture, and it flattens into a slab of
	-- colour the moment anyone stands near it. Everything here is small and thin on purpose; the
	-- object earns its legibility from the red grip's silhouette, not from covering the wall.
	local rimDepth = 0.15
	local plateDepth, plateHeight, plateWidth = 0.3, 4, 3.2
	local plateFrontX = wallX - rimDepth - plateDepth
	-- The panel hangs at head height and carries most of its mass ABOVE the hinge — the handle swings
	-- down through the space it leaves clear beneath.
	local plateCentreY = floorY + 4.3
	-- Chest height on a standing rider: a switch a person could have thrown, rather than a ceiling
	-- fixture. Also what keeps the thrown handle clear of the floor.
	local pivotY = floorY + 3.2

	-- THE HINGE STANDS PROUD OF THE PANEL, and this is structural rather than decorative: the rails
	-- are offset ABOVE AND BELOW the hinge line, so as they swing their inner ends sweep backward
	-- toward the wall by up to (rail offset + half thickness) x sin(angle) — a little under half a
	-- stud at `THROWN_ANGLE`. A hinge mounted flat on the panel would post the lower rail's inner
	-- corner straight through it and into the wall behind. The cheeks buy the clearance.
	local hingeStandoff = 0.65
	local pivotX = plateFrontX - hingeStandoff

	local boltOffsets: { Vector3 } = {}
	-- Three rows of two, climbing the panel on either side of its centre line, half proud of the
	-- face. Inset from the edges by more than their own width, so they read as fixings rather than as
	-- a border.
	for _, rowY in { plateCentreY - 1.55, plateCentreY, plateCentreY + 1.55 } do
		for _, columnZ in { laneZ - 1.25, laneZ + 1.25 } do
			table.insert(boltOffsets, Vector3.new(plateFrontX, rowY, columnZ))
		end
	end

	local lampY = plateCentreY + 1.2

	return {
		rimOffset = Vector3.new(wallX - rimDepth / 2, plateCentreY, laneZ),
		rimSize = Vector3.new(rimDepth, plateHeight + 0.45, plateWidth + 0.45),
		plateOffset = Vector3.new(wallX - rimDepth - plateDepth / 2, plateCentreY, laneZ),
		plateSize = Vector3.new(plateDepth, plateHeight, plateWidth),
		boltOffsets = boltOffsets,
		boltSize = Vector3.new(0.16, 0.34, 0.34),
		cheekOffsets = {
			Vector3.new(plateFrontX - hingeStandoff / 2, pivotY, laneZ - 0.52),
			Vector3.new(plateFrontX - hingeStandoff / 2, pivotY, laneZ + 0.52),
		},
		cheekSize = Vector3.new(hingeStandoff, 1, 0.22),
		-- The pin lies along the swing axis and runs right through both cheeks, so the joint reads as
		-- a hinge from any angle rather than as the handle simply ending at the wall.
		pinOffset = Vector3.new(pivotX, pivotY, laneZ),
		pinSize = Vector3.new(1.26, 0.42, 0.42),
		-- On the centre line above the hinge, in the channel the bolt columns leave clear: the one
		-- part of this object that changes, kept clear of everything that does not.
		bezelOffset = Vector3.new(plateFrontX, lampY, laneZ),
		bezelSize = Vector3.new(0.12, 0.9, 0.9),
		lampOffset = Vector3.new(plateFrontX - 0.06, lampY, laneZ),
		lampSize = Vector3.new(0.16, 0.55, 0.55),
		pivotOffset = Vector3.new(pivotX, pivotY, laneZ),
	}
end

-- The moving handle's car-local pose with the rails raked to `angle` radians around `pivotOffset`.
-- Everything is composed from the hinge outward — rake to `angle`, then run out along the raked
-- axis — so the angle is the only number any pose (or a frame mid-throw) ever has to touch.
--
-- THE SWING IS VERTICAL AND THE SILHOUETTE IS WIDE. The rails project into the car, which on their
-- own would read as a rod pointing at the rider; the crossbar and the red grip cross that line, so
-- the handle stays a recognisable shape from anywhere in the car and its travel is a plain
-- up-and-down sweep no matter where you are standing when it goes.
function LeverGeometry.handlePieces(pivotOffset: Vector3, angle: number): { Piece }
	local length = LeverGeometry.ARM_LENGTH
	local railThickness = 0.28
	local railSpacing = 0.42 -- each rail's offset above/below the hinge line
	local crossbarThickness = 0.3
	local gripRadius = 0.25

	-- Rotating about Z sweeps the rails (which run along -X) through the vertical plane that comes
	-- out of the wall. Positive `angle` therefore carries them downward.
	local pivotFrame = CFrame.new(pivotOffset) * CFrame.Angles(0, 0, angle)
	local railSize = Vector3.new(length, railThickness, railThickness)
	local crossbarX = -(length - crossbarThickness / 2)

	return {
		{
			name = "LeverRailUpper",
			size = railSize,
			cframe = pivotFrame * CFrame.new(-length / 2, railSpacing, 0),
			cylinder = false,
		},
		{
			name = "LeverRailLower",
			size = railSize,
			cframe = pivotFrame * CFrame.new(-length / 2, -railSpacing, 0),
			cylinder = false,
		},
		{
			-- Just long enough to overhang both rails, which is what makes the pair read as one
			-- ladder rather than as two loose bars.
			name = "LeverCrossbar",
			size = Vector3.new(crossbarThickness, 1.5, crossbarThickness),
			cframe = pivotFrame * CFrame.new(crossbarX, 0, 0),
			cylinder = false,
		},
		{
			-- The grip runs ACROSS the car, through the crossbar's outer half so the two read as
			-- bolted together. Longer than the handle is wide and the only warm colour on the object:
			-- it is the silhouette that has to carry from across the car, so everything behind it is
			-- kept slim enough not to compete.
			name = "LeverGrip",
			size = Vector3.new(2.4, gripRadius * 2, gripRadius * 2),
			cframe = pivotFrame
				* CFrame.new(crossbarX - crossbarThickness / 2, 0, 0)
				* CFrame.Angles(0, math.rad(90), 0),
			cylinder = true,
		},
	}
end

return LeverGeometry
