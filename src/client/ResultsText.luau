--!strict
-- Run text + the end-of-run screen. Transient beats (countdown, floor, messages) and the live
-- brazier preview are styled overlays; the results card is a lit cave panel that reveals with a
-- soft rise. It also owns the "Results" cursor release, and clears it defensively on every path
-- back to play or lobby so a finished run can never strand the player with a free cursor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Config = require(ReplicatedStorage.Shared.Config)
local CargoRules = require(ReplicatedStorage.Shared.Logic.CargoRules)
local AudioCues = require(script.Parent.AudioCues)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)

local ResultsText = {}

local player = Players.LocalPlayer
local palette = UITheme.palette
local EXPEDITION_ATTRIBUTE = "WickInExpedition"

local transientLabel: TextLabel? = nil
local previewLabel: TextLabel? = nil
local resultsBackdrop: Frame? = nil
local card: CanvasGroup? = nil
local cardScale: UIScale? = nil
local lobbyButton: TextButton? = nil
local watchButton: TextButton? = nil
-- True while a dead player has dismissed their own card to go and watch the party as a ghost
-- (server/SpectatorService). The card comes back by itself when the expedition resolves, because that
-- is when its restart and lobby buttons start mattering again — a ghost must never have to find a way
-- to reopen the only screen that can get them out of the run.
local watchingAsGhost = false
local outcomeLabel: TextLabel? = nil
local flavorLabel: TextLabel? = nil
local deathHintLabel: TextLabel? = nil
local statsLabel: TextLabel? = nil
local debugLabel: TextLabel? = nil
local clearAt = 0

local TRANSIENT_SECONDS = 4

-- The results card sits directly on top of near-black gameplay (a burnt-out cave, often the
-- darkest moment of a run). palette.panelRaised reads fine as a raised panel inside the lit
-- lobby, but here it was barely brighter than the void behind it, so the card and its text read
-- as one dark smear. These are brighter than the shared palette on purpose, scoped to this card.
local CARD_TOP = Color3.fromRGB(78, 62, 58)
local CARD_MID = Color3.fromRGB(46, 38, 42)
local CARD_BOTTOM = Color3.fromRGB(31, 25, 28)

local function hideResults()
	watchingAsGhost = false
	CursorController.setReleased("Results", false)
	if card ~= nil then
		card.Visible = false
	end
	if resultsBackdrop ~= nil then
		resultsBackdrop.Visible = false
	end
end

local function hidePreview()
	if previewLabel ~= nil then
		previewLabel.Visible = false
	end
end

local function overlayLabel(gui: ScreenGui, name: string, position: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = UITheme.font.heading
	label.TextColor3 = palette.text
	label.TextScaled = true
	label.Text = ""
	label.Visible = false
	label.Parent = gui
	UITheme.stroke(label, Color3.fromRGB(0, 0, 0), 2, 0.35)
	return label
end

local function showTransient(text: string)
	local label = transientLabel
	if label ~= nil then
		label.Text = text
		label.Visible = true
		label.TextTransparency = 0
		clearAt = os.clock() + TRANSIENT_SECONDS
		task.delay(TRANSIENT_SECONDS, function()
			if os.clock() >= clearAt and label ~= nil then
				label.Visible = false
			end
		end)
	end
end

local function cardLabel(parent: Instance, font: Enum.Font, color: Color3, height: number, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = ""
	label.Size = UDim2.new(1, 0, 0, height)
	label.LayoutOrder = order
	label.Parent = parent
	UITheme.stroke(label, Color3.fromRGB(0, 0, 0), 1.25, 0.55)
	return label
end

local function buildCard(gui: ScreenGui)
	-- Unlike the lobby, this overlay sits on top of live (often near-black) gameplay, not a
	-- backdrop of its own. Without a dimming wash behind it, the panel had nothing to contrast
	-- against and read as barely-there. Toggled alongside the card in hideResults/revealCard.
	local backdrop = UITheme.backdrop(gui, 0.1)
	backdrop.Visible = false
	resultsBackdrop = backdrop

	-- A CanvasGroup is needed to fade the whole card, but it must stay visually bare: a
	-- UIGradient parented to it is composited over every descendant and dims the card's text and
	-- buttons along with its background. Put the lit-stone surface in a child instead.
	local group = Instance.new("CanvasGroup")
	group.Name = "Results"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.46)
	group.Size = UDim2.fromScale(0.42, 0.6)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Visible = false
	group.Parent = gui
	cardScale = UITheme.scale(group, 1)
	-- `0.42` of a phone's width is under 380 units and its stats block does not fit in that; the card
	-- is allowed to take most of a small screen and is stopped from becoming a billboard on a large one.
	local cardSize = Instance.new("UISizeConstraint")
	cardSize.MinSize = Vector2.new(300, 300)
	cardSize.MaxSize = Vector2.new(620, 700)
	cardSize.Parent = group

	-- A SCROLLER, not a plain frame. The card stacks an outcome, a flavour line, an optional death
	-- hint, a stats block and up to three buttons — roughly 550 units of content against a phone
	-- viewport only about 410 units tall in total, so BACK TO LOBBY sat below the bottom edge of the
	-- screen on the one card whose entire job is getting the player out of a finished run.
	local surface = Instance.new("ScrollingFrame")
	surface.Name = "Surface"
	surface.Size = UDim2.fromScale(1, 1)
	surface.BackgroundColor3 = CARD_MID
	surface.BackgroundTransparency = 0
	surface.BorderSizePixel = 0
	surface.ScrollBarThickness = 5
	surface.ScrollBarImageColor3 = palette.stroke
	surface.AutomaticCanvasSize = Enum.AutomaticSize.Y
	surface.CanvasSize = UDim2.new()
	surface.ZIndex = 1
	surface.Parent = group
	UITheme.corner(surface, 16)
	UITheme.stroke(surface, palette.stroke, 2, 0.15)
	UITheme.uniformPadding(surface, 28)

	local sheen = Instance.new("UIGradient")
	sheen.Rotation = 90
	sheen.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CARD_TOP),
		ColorSequenceKeypoint.new(0.16, CARD_MID),
		ColorSequenceKeypoint.new(1, CARD_BOTTOM),
	})
	sheen.Parent = surface

	local layout = UITheme.listLayout(surface, 10)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top

	outcomeLabel = cardLabel(surface, UITheme.font.display, palette.gold, 50, 1)

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(0.5, 0, 0, 2)
	divider.BackgroundColor3 = palette.ember
	divider.BackgroundTransparency = 0.3
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 2
	divider.Parent = surface
	UITheme.corner(divider, 1)

	flavorLabel = cardLabel(surface, UITheme.font.fine, palette.text, 30, 3)
	-- Only populated on death, when `Config.Feel.deathHints` has a line for what killed this player
	-- (Config/Feel.deathHints). Player-facing, unlike `debugLabel` below, so it is not gated behind
	-- `showDeathDebug`.
	deathHintLabel = cardLabel(surface, UITheme.font.fine, palette.text, 44, 4)
	if deathHintLabel ~= nil then
		deathHintLabel.Visible = false
	end
	statsLabel = cardLabel(surface, UITheme.font.body, palette.text, 116, 5)
	debugLabel = cardLabel(surface, UITheme.font.fine, palette.textDim, 34, 6)
	if debugLabel ~= nil then
		debugLabel.Visible = false
	end

	local restart = UITheme.button(surface, "RESTART RUN")
	restart.instance.Size = UDim2.new(1, 0, 0, 46)
	restart.instance.LayoutOrder = 8
	restart.instance.Activated:Connect(function()
		-- The next server event is a countdown, so release the menu claim before asking the server
		-- to restart. First-person input must not wait for a round trip.
		UITheme.flash(restart.instance, palette.chip)
		hideResults()
		Remotes.get("RestartRun"):FireServer()
	end)

	-- THE SPECTATOR'S DISMISS. A death card that cannot be put down would make the ghost body behind it
	-- pointless: the party is still in the room, and watching them is the whole of what is left to do.
	-- Shown only while somebody is still down there (`partyStillInside`).
	local watch = UITheme.button(surface, "WATCH THE PARTY")
	watch.instance.Size = UDim2.new(1, 0, 0, 46)
	watch.instance.LayoutOrder = 7
	watch.instance.Visible = false
	watchButton = watch.instance
	watch.instance.Activated:Connect(function()
		UITheme.flash(watch.instance, palette.chip)
		hideResults()
		-- Set after the hide: `hideResults` is the one place the flag is cleared, so every other path
		-- back to play or lobby drops it without having to know this button exists.
		watchingAsGhost = true
	end)

	local lobby = UITheme.button(surface, "BACK TO LOBBY")
	lobby.instance.Size = UDim2.new(1, 0, 0, 46)
	lobby.instance.LayoutOrder = 9
	lobbyButton = lobby.instance
	lobby.instance.Activated:Connect(function()
		-- Keep the result card open until LobbyState or the teleport screen confirms the transition.
		-- While another runner is unresolved this is the explicit early-extraction choice, and the
		-- label above states the pending group credit it forfeits.
		UITheme.flash(lobby.instance, palette.chip)
		Remotes.get("ReturnToLobby"):FireServer()
	end)
end

local function revealCard()
	local group = card
	local scale = cardScale
	if group == nil or scale == nil then
		return
	end
	CursorController.setReleased("Results", true)
	if resultsBackdrop ~= nil then
		resultsBackdrop.Visible = true
	end
	group.Visible = true
	group.GroupTransparency = 1
	group.Position = UDim2.fromScale(0.5, 0.5)
	scale.Scale = 0.92
	TweenService:Create(group, UITheme.motion.fade, { GroupTransparency = 0 }):Play()
	TweenService:Create(group, UITheme.motion.rise, { Position = UDim2.fromScale(0.5, 0.46) }):Play()
	TweenService:Create(scale, UITheme.motion.rise, { Scale = 1 }):Play()
end

local function showResults(payload: { [string]: any })
	AudioCues.stop("Water")
	watchingAsGhost = false
	local watch = watchButton
	if watch ~= nil then
		-- Only a death with teammates still in the cave has anything to watch. A survivor's card and the
		-- last player's card both keep the two exits and nothing else.
		watch.Visible = payload.survived ~= true and payload.partyStillInside == true
	end
	if payload.survived then
		AudioCues.play("BrazierCommit")
	elseif payload.deathCause == "BurnOut" then
		AudioCues.play("DeathBurnOut")
	else
		AudioCues.play("DeathSnuffed")
	end
	hidePreview()
	local button = lobbyButton
	if button ~= nil then
		local pendingBonus = math.max(0, math.floor(tonumber(payload.pendingPartyBonus) or 0))
		if payload.partyStillInside == true then
			button.Text = if pendingBonus > 0
				then string.format("EXTRACT EARLY · FORFEIT +%d", pendingBonus)
				else "EXTRACT EARLY TO LOBBY"
		else
			button.Text = "BACK TO LOBBY"
		end
	end

	local outcome = outcomeLabel
	local flavor = flavorLabel
	local deathHint = deathHintLabel
	local stats = statsLabel
	local debug = debugLabel
	if outcome == nil or flavor == nil or deathHint == nil or stats == nil or debug == nil then
		return
	end

	-- PHASE 6 mining readout. Appended to whichever debug line the outcome already builds, so the
	-- count never appears next to the reward arithmetic and can never be mistaken for part of it.
	local mined = tonumber(payload.depositsMined) or 0
	local minedDepths = ""
	if typeof(payload.depositsMinedAtDepths) == "table" then
		local parts: { string } = {}
		for _, entry in payload.depositsMinedAtDepths :: { any } do
			table.insert(parts, tostring(tonumber(entry) or 0))
		end
		if #parts > 0 then
			minedDepths = " (depth " .. table.concat(parts, ", ") .. ")"
		end
	end
	local miningLine =
		string.format("debug · %d deposit%s mined%s", mined, if mined == 1 then "" else "s", minedDepths)

	-- PHASE 8 cargo accounting, on its own line. No longer a "test score": this IS the money now, so
	-- the headline number moved up into `stats` and what remains here is where the wax came from and
	-- what happened to the grams that did not make it out.
	local rawWax = payload.rawWax
	local rawWaxLine: string? = nil
	local extractedGrams = 0
	local droppedGrams = 0
	if typeof(rawWax) == "table" then
		extractedGrams = tonumber(rawWax.extracted) or 0
		droppedGrams = tonumber(rawWax.dropped) or 0
		local lost = tonumber(rawWax.lost) or 0
		local acquired = tonumber(rawWax.acquired) or 0
		local origins = tostring(rawWax.originDepths or "none")
		if acquired > 0 then
			rawWaxLine = string.format(
				"raw wax · %s mined from depth %s · %s out, %s left behind, %s shattered",
				CargoRules.formatGrams(acquired),
				origins,
				CargoRules.formatGrams(extractedGrams),
				CargoRules.formatGrams(droppedGrams),
				CargoRules.formatGrams(lost)
			)
		end
	end
	if rawWaxLine ~= nil then
		miningLine = miningLine .. "\n" .. rawWaxLine
	end

	if payload.survived then
		outcome.Text = "LIGHT DELIVERED"
		outcome.TextColor3 = palette.gold
		flavor.Text = "You carried the light home."
		deathHint.Visible = false
		-- Leftover wax is reported as what it now is — fuel you did not need — and is deliberately NOT
		-- adjacent to the reward, because it no longer contributes to it.
		local bonus = if typeof(rawWax) == "table" then tonumber(rawWax.partyBonus) or 0 else 0
		stats.Text = string.format(
			"Floor %d reached\n%s raw wax extracted\nEarned   +%d%s\nBalance   %d\n%.2f wax left in the candle",
			payload.depthReached or 0,
			CargoRules.formatGrams(extractedGrams),
			payload.reward or 0,
			if bonus > 0 then string.format("  (+%d party)", bonus) else "",
			payload.balance or 0,
			payload.waxDelivered or 0
		)
		debug.Text = miningLine
		debug.Visible = mined > 0 or rawWaxLine ~= nil
	else
		local burnedOut = payload.deathCause == "BurnOut"
		outcome.Text = if burnedOut then "BURNED OUT" else "SNUFFED"
		outcome.TextColor3 = palette.danger
		flavor.Text = if burnedOut then "Your wax ran dry in the deep." else "The dark reached in and took your flame."

		-- The "next time" line (Config/Feel.deathHints), keyed by which threat/hazard actually did
		-- this. Falls back to the raw cause ("BurnOut") when nothing more specific caused it, and
		-- disappears entirely if neither key has an authored line — this is a real player-facing
		-- element, unlike `debug` below, so it never depends on `showDeathDebug`.
		local hints = Config.Feel.deathHints
		local hintText = if hints.enabled
			then hints.messages[payload.deathSourceId] or hints.messages[payload.deathCause]
			else nil
		deathHint.Text = hintText or ""
		deathHint.Visible = hintText ~= nil

		-- What the party can still salvage is the one hopeful number on a death card, so it is stated
		-- plainly rather than buried in the debug line.
		stats.Text = if droppedGrams > 0
			then string.format(
				"Floor %d reached\nNothing delivered.\n%s raw wax lies with your remains.",
				payload.depthReached or 0,
				CargoRules.formatGrams(droppedGrams)
			)
			else string.format("Floor %d reached\nNothing delivered.", payload.depthReached or 0)

		local info = payload.deathDebug
		if Config.Feel.debug.showDeathDebug and typeof(info) == "table" then
			debug.Text = string.format(
				"debug · %s · wax %.3f/%.3f · burn %.2f · %s",
				tostring(info.trigger or "Unknown"),
				tonumber(info.waxRemaining) or 0,
				tonumber(info.maxWax) or 0,
				tonumber(info.burnRate) or 0,
				tostring(info.movementMode or "Unknown")
			) .. "\n" .. miningLine
			debug.Visible = true
		else
			debug.Text = miningLine
			debug.Visible = mined > 0 or rawWaxLine ~= nil
		end
	end

	revealCard()
end

function ResultsText.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickText"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	transientLabel = overlayLabel(gui, "Transient", UDim2.fromScale(0.5, 0.14), UDim2.fromScale(0.6, 0.08))
	transientLabel.Font = UITheme.font.display
	transientLabel.TextColor3 = palette.gold
	previewLabel = overlayLabel(gui, "BrazierPreview", UDim2.fromScale(0.5, 0.86), UDim2.fromScale(0.72, 0.05))
	previewLabel.Font = UITheme.font.body
	buildCard(gui)
	card = gui:FindFirstChild("Results") :: CanvasGroup
	gui.Parent = player:WaitForChild("PlayerGui")

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		-- any: remote payloads are untyped at the boundary; fields are read defensively below.
		if kind == "countdown" then
			hideResults()
			showTransient(string.format("Descending in %d…", payload.seconds or 0))
		elseif kind == "floor" then
			hideResults()
			AudioCues.play("FloorEnter")
			showTransient(string.format("Floor %d", payload.depth or 0))
		elseif kind == "message" then
			showTransient(tostring(payload.text or ""))
		elseif kind == "brazierPreview" then
			local preview = previewLabel
			if preview ~= nil then
				if not preview.Visible then
					AudioCues.play("BrazierNear")
				end
				-- THE ONLY PLACE THE BAG'S VALUE IS SHOWN. In the cave the HUD carries a mass and nothing
				-- more, so the decision to turn back is made here, at the exit, with the real number in
				-- front of you rather than continuously recalculated in the dark.
				local grams = tonumber(payload.grams) or 0
				local bonus = tonumber(payload.potentialPartyBonus) or 0
				if grams <= 0 then
					preview.Text = "THE GAS LANTERN · you are carrying nothing to bank"
				else
					preview.Text = string.format(
						"THE GAS LANTERN · %s raw wax worth +%d%s",
						CargoRules.formatGrams(grams),
						payload.total or 0,
						if bonus > 0 then string.format("  (+%d more if everyone gets out)", bonus) else ""
					)
				end
				preview.Visible = true
			end
		elseif kind == "partyBonus" then
			if lobbyButton ~= nil then
				lobbyButton.Text = "BACK TO LOBBY"
			end
			showTransient(string.format("Everyone made it out.  +%d raw wax", payload.amount or 0))
		elseif kind == "runResolved" then
			if lobbyButton ~= nil then
				lobbyButton.Text = "BACK TO LOBBY"
			end
			-- The expedition is over, so there is nothing left to watch and the two exits matter again.
			-- A ghost gets its card back automatically rather than having to remember how to reopen it.
			if watchButton ~= nil then
				watchButton.Visible = false
			end
			if watchingAsGhost then
				watchingAsGhost = false
				revealCard()
			end
		elseif kind == "brazierPreviewClear" then
			hidePreview()
		elseif kind == "results" then
			showResults(payload)
		end
	end)

	-- Softlock guards: any return to lobby or drop out of the expedition tears down the results
	-- overlay and its cursor claim, even if the normal countdown/floor event never arrives.
	Remotes.get("LobbyState").OnClientEvent:Connect(function(state: { [string]: any })
		if state.inExpedition ~= true then
			hideResults()
			hidePreview()
		end
	end)
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		if player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
			hideResults()
			hidePreview()
		end
	end)
end

return ResultsText
