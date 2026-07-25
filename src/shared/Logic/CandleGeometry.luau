--!strict
-- Pure: wax units -> normalized body dimensions. The single source of the shrink rule; both the visual
-- body and the water lethality comparison read heights from here (never from a Part).

local Types = require(script.Parent.Parent.Types)
local CharacterConfig = require(script.Parent.Parent.Config.Character)
local WaxConfig = require(script.Parent.Parent.Config.Wax)

local CandleGeometry = {}

-- Body height for a wax value. Linear against the configured base capacity, not a player's live
-- ceiling: capacity tuning changes endurance without stretching the character model.
function CandleGeometry.heightForWax(current: Types.WaxAmount): number
	local t = math.clamp(current / WaxConfig.maxWax, 0, 1)
	return CharacterConfig.heightAtZeroWax + (CharacterConfig.heightAtFullWax - CharacterConfig.heightAtZeroWax) * t
end

-- World-space Y of the body's top, given the Y of the candle's base. The water rule's reference:
-- water reaching (a fraction of) this height is what kills.
function CandleGeometry.flameBaseY(baseY: number, height: number): number
	return baseY + height
end

-- World-space Y of the flame's centre (where the light lives) — above body, rim-embedded wick.
function CandleGeometry.flameCenterY(baseY: number, height: number): number
	return baseY + height + CharacterConfig.wickHeight + CharacterConfig.flameHeight / 2
end

return CandleGeometry
