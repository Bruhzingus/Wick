--!strict
-- Small, upload-free symbols for the Lamp Network. Every mark is assembled from Roblox UI
-- primitives, so the shop stays crisp at any scale and never waits on an image asset. The drawings
-- communicate the job of a node; ownership/availability colour is supplied by LampTreeView.

local LampNodeIcons = {}

export type Icon = {
	instance: Frame,
	setColor: (color: Color3) -> (),
}

type PaintTarget = Frame | UIStroke

local function rounded(parent: GuiObject, position: UDim2, size: UDim2, radius: number): Frame
	local part = Instance.new("Frame")
	part.AnchorPoint = Vector2.new(0.5, 0.5)
	part.Position = position
	part.Size = size
	part.BackgroundColor3 = Color3.new(1, 1, 1)
	part.BorderSizePixel = 0
	part.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = part
	return part
end

local function line(parent: GuiObject, position: UDim2, size: UDim2, rotation: number, paint: { PaintTarget }): Frame
	local part = rounded(parent, position, size, 1)
	part.Rotation = rotation
	table.insert(paint, part)
	return part
end

local function outline(parent: GuiObject, position: UDim2, size: UDim2, radius: number, paint: { PaintTarget }): Frame
	local shell = Instance.new("Frame")
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = position
	shell.Size = size
	shell.BackgroundTransparency = 1
	shell.BorderSizePixel = 0
	shell.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Parent = shell
	table.insert(paint, stroke)
	return shell
end

local function document(root: Frame, paint: { PaintTarget }, hard: boolean)
	outline(root, UDim2.fromScale(0.48, 0.5), UDim2.fromScale(0.54, 0.68), 0.1, paint)
	line(root, UDim2.fromScale(0.48, 0.39), UDim2.fromScale(0.3, 0.065), 0, paint)
	line(root, UDim2.fromScale(0.48, 0.54), UDim2.fromScale(0.3, 0.065), 0, paint)
	line(root, UDim2.fromScale(0.41, 0.69), UDim2.fromScale(0.16, 0.065), 0, paint)
	if hard then
		local seal = rounded(root, UDim2.fromScale(0.72, 0.72), UDim2.fromScale(0.24, 0.24), 1)
		table.insert(paint, seal)
		local cut = rounded(seal, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.38, 0.38), 1)
		cut.BackgroundColor3 = Color3.fromRGB(27, 22, 25)
	end
end

local function seam(root: Frame, paint: { PaintTarget }, offset: number)
	line(root, UDim2.fromScale(0.37 + offset, 0.28), UDim2.fromScale(0.08, 0.34), 28, paint)
	line(root, UDim2.fromScale(0.48 + offset, 0.5), UDim2.fromScale(0.08, 0.3), -36, paint)
	line(root, UDim2.fromScale(0.39 + offset, 0.72), UDim2.fromScale(0.08, 0.28), 32, paint)
end

local function rays(root: Frame, paint: { PaintTarget })
	for index = 0, 7 do
		local angle = index * 45
		local radians = math.rad(angle)
		local x = 0.5 + math.cos(radians) * 0.33
		local y = 0.5 + math.sin(radians) * 0.33
		line(root, UDim2.fromScale(x, y), UDim2.fromScale(0.24, 0.055), angle, paint)
	end
	local center = rounded(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.3, 0.3), 1)
	table.insert(paint, center)
end

local function build(root: Frame, iconId: string, paint: { PaintTarget })
	local key = string.lower(iconId)
	if key == "ledger" or key == "paytable" or key == "pay_table" then
		document(root, paint, false)
	elseif key == "contract" or key == "contractboard" or key == "contract_board" then
		document(root, paint, false)
		line(root, UDim2.fromScale(0.7, 0.66), UDim2.fromScale(0.08, 0.22), -38, paint)
		line(root, UDim2.fromScale(0.8, 0.58), UDim2.fromScale(0.08, 0.32), 45, paint)
	elseif key == "hardcontract" or key == "hard_contract" then
		document(root, paint, true)
	elseif key == "twinseam" or key == "twin_seam" then
		seam(root, paint, -0.14)
		seam(root, paint, 0.14)
	elseif key == "deepseam" or key == "deep_seam" then
		seam(root, paint, 0)
		line(root, UDim2.fromScale(0.7, 0.44), UDim2.fromScale(0.07, 0.34), 0, paint)
		line(root, UDim2.fromScale(0.64, 0.63), UDim2.fromScale(0.07, 0.22), -42, paint)
		line(root, UDim2.fromScale(0.76, 0.63), UDim2.fromScale(0.07, 0.22), 42, paint)
	elseif key == "brightseam" or key == "bright_seam" then
		rays(root, paint)
	elseif key == "dimseam" or key == "dim_seam" then
		seam(root, paint, 0.13)
		local moon = rounded(root, UDim2.fromScale(0.35, 0.48), UDim2.fromScale(0.42, 0.42), 1)
		table.insert(paint, moon)
		local cut = rounded(root, UDim2.fromScale(0.44, 0.39), UDim2.fromScale(0.36, 0.36), 1)
		cut.BackgroundColor3 = Color3.fromRGB(27, 22, 25)
	elseif key == "store" or key == "lockedstore" or key == "locked_store" then
		outline(root, UDim2.fromScale(0.5, 0.56), UDim2.fromScale(0.6, 0.58), 0.08, paint)
		line(root, UDim2.fromScale(0.5, 0.3), UDim2.fromScale(0.72, 0.08), 0, paint)
		line(root, UDim2.fromScale(0.5, 0.68), UDim2.fromScale(0.38, 0.06), 0, paint)
		local lock = outline(root, UDim2.fromScale(0.68, 0.65), UDim2.fromScale(0.22, 0.22), 0.2, paint)
		lock.BackgroundColor3 = Color3.fromRGB(27, 22, 25)
		line(root, UDim2.fromScale(0.68, 0.49), UDim2.fromScale(0.14, 0.17), 0, paint)
	elseif key == "wager" or key == "wagerboard" or key == "wager_board" then
		outline(root, UDim2.fromScale(0.47, 0.5), UDim2.fromScale(0.6, 0.6), 1, paint)
		outline(root, UDim2.fromScale(0.47, 0.5), UDim2.fromScale(0.32, 0.32), 1, paint)
		line(root, UDim2.fromScale(0.64, 0.34), UDim2.fromScale(0.08, 0.55), 45, paint)
		line(root, UDim2.fromScale(0.8, 0.18), UDim2.fromScale(0.22, 0.07), 0, paint)
		line(root, UDim2.fromScale(0.8, 0.18), UDim2.fromScale(0.07, 0.22), 0, paint)
	else
		-- A tiny flame is the safe fallback for future nodes: still on-theme, never a blank box.
		local body = rounded(root, UDim2.fromScale(0.5, 0.57), UDim2.fromScale(0.4, 0.52), 1)
		body.Rotation = 12
		table.insert(paint, body)
		local wick = line(root, UDim2.fromScale(0.5, 0.84), UDim2.fromScale(0.08, 0.22), 0, paint)
		wick.BackgroundTransparency = 0.25
	end
end

function LampNodeIcons.create(parent: GuiObject, iconId: string): Icon
	local root = Instance.new("Frame")
	root.Name = "Icon"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = root

	local paint: { PaintTarget } = {}
	build(root, iconId, paint)

	local function setColor(color: Color3)
		for _, target in paint do
			if target:IsA("UIStroke") then
				target.Color = color
			else
				target.BackgroundColor3 = color
			end
		end
	end

	return {
		instance = root,
		setColor = setColor,
	}
end

return LampNodeIcons
