--!strict
--[[
	DataScope - Roblox DataStore Editor
	A clean rewrite using Vide and functional programming

	Original concept by pinehappi
	Rewritten with:
	- Vide for reactive UI
	- Functional programming patterns
	- Search bar with multiple modes when viewing keys
	- Hook system for compression/decompression
]]

-- Services
local RunService = game:GetService("RunService")

-- Only run in Studio
if not RunService:IsStudio() then
	return
end

-- Only run in Edit mode (not Play or Run mode)
if not RunService:IsEdit() then
	return
end

-- Plugin setup
local toolbar = plugin:CreateToolbar("DataScope")
local button = toolbar:CreateButton(
	"DataScope",
	"Open DataScope - DataStore Editor",
	"rbxassetid://6034509993",
	"DataScope"
)

-- Create widget
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false, -- Initially disabled
	false, -- Override previous state
	400, -- Default width
	600, -- Default height
	300, -- Min width
	400 -- Min height
)

local widget = plugin:CreateDockWidgetPluginGui("DataScope", widgetInfo)
widget.Title = "DataScope"
widget.Name = "DataScope"

-- Require modules
local Vide = require(script.Parent.Packages.Vide)
local App = require(script.Parent.ui.App)
local Store = require(script.Parent.core.Store)
local Theme = require(script.Parent.ui.Theme)
local BuiltInHooks = require(script.Parent.hooks.BuiltInHooks)
local Settings = require(script.Parent.settings.Settings)

-- Initialize
local initialized = false
local appInstance: (() -> ())? = nil

local function initialize()
	if initialized then
		return
	end
	initialized = true

	-- Store plugin reference for export functionality
	Store.plugin = plugin

	-- Register built-in hooks
	BuiltInHooks.registerAll()

	-- Load settings
	Settings.load(plugin)

	-- Apply saved theme
	local theme = Theme.get()
	local settings = Store.settings()
	theme.setPreset(settings.themePreset)
	theme.setAccent(settings.themeAccent)

	-- Mount app
	appInstance = Vide.mount(function()
		return App({ parent = widget })
	end)

	print("[DataScope] Initialized")
end

local function cleanup()
	if appInstance then
		appInstance() -- Vide.mount returns a cleanup function
		appInstance = nil
	end

	-- Save settings
	Settings.save(plugin)
end

-- Toggle button
button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

-- Widget enabled state
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)

	if widget.Enabled then
		initialize()
	end
end)

-- Initial state
button:SetActive(widget.Enabled)
if widget.Enabled then
	initialize()
end

-- Cleanup on unload
plugin.Unloading:Connect(cleanup)
