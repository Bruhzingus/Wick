-- REFERENCE ONLY.
-- Server-authoritative logic idea for the two-shot boulder burst.
-- Adapt to existing WICK damage, character, FX, and scheduling systems.

local Workspace = game:GetService("Workspace")

local BoulderBurst = {}

local function horizontal(v: Vector3): Vector3
    return Vector3.new(v.X, 0, v.Z)
end

local function predictedTarget(root: BasePart, leadTime: number): Vector3
    local velocity = horizontal(root.AssemblyLinearVelocity)

    -- Clamp prediction so unusually high velocity does not create absurd aim.
    local maxPredictSpeed = 30
    if velocity.Magnitude > maxPredictSpeed then
        velocity = velocity.Unit * maxPredictSpeed
    end

    return root.Position + velocity * leadTime
end

function BoulderBurst.ComputeDirection(origin: Vector3, targetRoot: BasePart, leadTime: number): Vector3
    local point = predictedTarget(targetRoot, leadTime)
    local delta = point - origin

    if delta.Magnitude < 0.001 then
        return Vector3.zAxis
    end

    return delta.Unit
end

-- Suggested projectile simulation:
--
-- previousPosition = position
-- nextPosition = position + direction * speed * dt
-- result = Workspace:Spherecast(
--     previousPosition,
--     projectileRadius,
--     nextPosition - previousPosition,
--     raycastParams
-- )
--
-- If result:
--     resolve player/world hit ON SERVER
-- else:
--     position = nextPosition
--
-- Clients only render/interpolate the visual boulder.

return BoulderBurst
