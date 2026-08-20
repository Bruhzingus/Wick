-- REFERENCE ONLY.
-- Use the project's existing hitbox/damage utility if one exists.

local Workspace = game:GetService("Workspace")

local MeleeHitbox = {}

function MeleeHitbox.QueryBox(
    cframe: CFrame,
    size: Vector3,
    overlapParams: OverlapParams
): {BasePart}
    return Workspace:GetPartBoundsInBox(cframe, size, overlapParams)
end

-- At animation hit time:
-- 1. Read the relevant hand/hitbox Attachment.WorldCFrame.
-- 2. Build a box that extends through the claw rake path.
-- 3. Query parts.
-- 4. Resolve unique characters/players.
-- 5. Damage each eligible target ONCE for that swipe.
-- 6. Store per-swipe hit set so multiple body parts don't multiply damage.

return MeleeHitbox
