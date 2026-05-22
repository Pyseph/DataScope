--!strict
--[[
	Settings Module
	Persistence for user settings
]]

local Store = require(script.Parent.Parent.core.Store)
local Functional = require(script.Parent.Parent.utils.Functional)

local HttpService = game:GetService("HttpService")

local SETTINGS_KEY = "DataScope_Settings"
local HISTORY_KEY = "DataScope_History"

local Settings = {}

-- Helper to decode a saved value that may be a JSON string or a raw table
local function decodeSaved(saved: any): { [string]: any }?
	if type(saved) == "table" then
		return saved
	end
	if type(saved) == "string" then
		local success, parsed = pcall(function()
			return HttpService:JSONDecode(saved)
		end)
		if success and type(parsed) == "table" then
			return parsed
		end
	end
	return nil
end

-- Load settings from plugin storage
function Settings.load(plugin: Plugin)
	-- Load settings
	local rawSettings = plugin:GetSetting(SETTINGS_KEY)
	local savedSettings = decodeSaved(rawSettings)
	if savedSettings then
		local defaults = Store.getDefaultSettings()
		local merged = Store.normalizeSettings(Functional.merge(defaults, savedSettings))
		Store.settings(merged)
	end

	-- Load history
	local rawHistory = plugin:GetSetting(HISTORY_KEY)
	local savedHistory = decodeSaved(rawHistory)
	if savedHistory then
		Store.history(savedHistory :: any)
	end
end

-- Save all settings to plugin storage
function Settings.save(plugin: Plugin)
	local settings = Store.normalizeSettings(Store.settings())
	Store.settings(settings)
	pcall(function()
		plugin:SetSetting(SETTINGS_KEY, HttpService:JSONEncode(settings))
	end)

	Settings.saveHistory(plugin)
end

-- Save only history to plugin storage
function Settings.saveHistory(plugin: Plugin)
	local history = Store.history()
	local success, result = pcall(function()
		local json = HttpService:JSONEncode(history)
		plugin:SetSetting(HISTORY_KEY, json)
	end)

	if not success then
		warn("[DataScope] Failed to save history:", result)
	end
end

-- Clear all saved data
function Settings.clear(plugin: Plugin)
	local previousSettingsChanged = Store.onSettingsChanged
	local previousHistoryChanged = Store.onHistoryChanged
	Store.onSettingsChanged = nil
	Store.onHistoryChanged = nil

	plugin:SetSetting(SETTINGS_KEY, nil)
	plugin:SetSetting(HISTORY_KEY, nil)
	Store.resetSettings()
	Store.clearHistory()

	Store.onSettingsChanged = previousSettingsChanged
	Store.onHistoryChanged = previousHistoryChanged
end

return Settings
