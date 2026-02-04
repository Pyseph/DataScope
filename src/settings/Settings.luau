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

-- Load settings from plugin storage
function Settings.load(plugin: Plugin)
	-- Load settings
	local savedSettings = plugin:GetSetting(SETTINGS_KEY)
	if savedSettings then
		local success, parsed = pcall(function()
			return HttpService:JSONDecode(savedSettings)
		end)

		if success and type(parsed) == "table" then
			local defaults = Store.getDefaultSettings()
			local merged = Functional.merge(defaults, parsed)
			Store.settings(merged)
		end
	end

	-- Load history
	local savedHistory = plugin:GetSetting(HISTORY_KEY)
	if savedHistory then
		local success, parsed = pcall(function()
			return HttpService:JSONDecode(savedHistory)
		end)

		if success and type(parsed) == "table" then
			Store.history(parsed)
		end
	end
end

-- Save settings to plugin storage
function Settings.save(plugin: Plugin)
	-- Save settings
	local settings = Store.settings()
	local success, json = pcall(function()
		return HttpService:JSONEncode(settings)
	end)

	if success then
		plugin:SetSetting(SETTINGS_KEY, json)
	end

	-- Save history
	local history = Store.history()
	local historySuccess, historyJson = pcall(function()
		return HttpService:JSONEncode(history)
	end)

	if historySuccess then
		plugin:SetSetting(HISTORY_KEY, historyJson)
	end
end

-- Clear all saved data
function Settings.clear(plugin: Plugin)
	plugin:SetSetting(SETTINGS_KEY, nil)
	plugin:SetSetting(HISTORY_KEY, nil)
	Store.resetSettings()
	Store.clearHistory()
end

return Settings
