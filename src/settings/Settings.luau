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

-- Save is blocked when the prior load found data it could not decode. This
-- prevents a corrupt/unreadable payload from being silently overwritten by
-- defaults on the next save. Reset by Settings.clear (user-initiated wipe).
local canSaveSettings = true
local canSaveHistory = true

-- Decode a stored value. Handles three shapes:
--   1. table (current format — plugin:SetSetting round-trips tables as maps)
--   2. JSON string (legacy format from v2.1.0 and earlier)
--   3. anything else → nil (caller treats as unreadable)
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

-- Plugin:SetSetting stores data as JSON-with-string-keys, so Lua arrays come
-- back as maps keyed by "1", "2", … Reconstruct a contiguous array from that
-- shape. Already-array inputs (legacy JSON-string path) pass through unchanged.
local function normalizeArray(t: { [any]: any }): { any }
	if t[1] ~= nil then
		return t :: any
	end
	local result: { any } = {}
	local i = 1
	while t[tostring(i)] ~= nil do
		result[i] = t[tostring(i)]
		i += 1
	end
	return result
end

-- Write with read-back verification. The docs warn that SetSetting can
-- silently fail (e.g. when multiple plugin instances read/write concurrently);
-- we read back and structurally compare to detect it. The read-back is
-- normalized first because round-tripping an array produces a string-keyed map.
local function setSettingVerified(plugin: Plugin, key: string, value: any, isArray: boolean): boolean
	plugin:SetSetting(key, value)
	local readBack = plugin:GetSetting(key)
	if value == nil then
		return readBack == nil
	end
	if readBack == nil then
		return false
	end
	local normalized: any = if isArray and type(readBack) == "table" then normalizeArray(readBack) else readBack
	return Functional.deepEquals(normalized, value)
end

-- Load settings from plugin storage
function Settings.load(plugin: Plugin)
	local rawSettings = plugin:GetSetting(SETTINGS_KEY)
	if rawSettings ~= nil then
		local decoded = decodeSaved(rawSettings)
		if decoded then
			local defaults = Store.getDefaultSettings()
			local merged = Store.normalizeSettings(Functional.merge(defaults, decoded))
			Store.settings(merged)
		else
			canSaveSettings = false
			warn("[DataScope] Saved settings are unreadable; settings save disabled to avoid overwriting recoverable data. Use 'Clear saved data' to reset.")
		end
	end

	local rawHistory = plugin:GetSetting(HISTORY_KEY)
	if rawHistory ~= nil then
		local decoded = decodeSaved(rawHistory)
		if decoded then
			Store.history(normalizeArray(decoded) :: any)
		else
			canSaveHistory = false
			warn("[DataScope] Saved history is unreadable; history save disabled to avoid overwriting recoverable data. Use 'Clear saved data' to reset.")
		end
	end
end

-- Save all settings to plugin storage
function Settings.save(plugin: Plugin)
	if canSaveSettings then
		local settings = Store.normalizeSettings(Store.settings())
		Store.settings(settings)
		local ok, err = pcall(function()
			if not setSettingVerified(plugin, SETTINGS_KEY, settings, false) then
				error("write verification failed (possibly a concurrent plugin instance)")
			end
		end)
		if not ok then
			warn("[DataScope] Failed to save settings:", err)
		end
	end

	Settings.saveHistory(plugin)
end

-- Save only history to plugin storage
function Settings.saveHistory(plugin: Plugin)
	if not canSaveHistory then
		return
	end
	local history = Store.history()
	local ok, err = pcall(function()
		if not setSettingVerified(plugin, HISTORY_KEY, history, true) then
			error("write verification failed (possibly a concurrent plugin instance)")
		end
	end)
	if not ok then
		warn("[DataScope] Failed to save history:", err)
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

	canSaveSettings = true
	canSaveHistory = true
end

return Settings
