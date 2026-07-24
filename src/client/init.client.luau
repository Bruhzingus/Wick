--!strict
-- Client boot: pure wiring. Starts each controller once; no logic lives here.

local CameraController = require(script.CameraController)
local DialController = require(script.DialController)
local MovementController = require(script.MovementController)
local ToolController = require(script.ToolController)
local WaxBar = require(script.WaxBar)
local BasinPrompt = require(script.BasinPrompt)
local ResultsText = require(script.ResultsText)

CameraController.start()
DialController.start()
MovementController.start()
ToolController.start()
WaxBar.start()
BasinPrompt.start()
ResultsText.start()
