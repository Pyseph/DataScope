--!strict
--[[
	Key View Loader
	Applies hook detection/decompression to key data for UI display.
]]

local Types = require(script.Parent.Parent.core.Types)
local Functional = require(script.Parent.Parent.utils.Functional)
local HookManager = require(script.Parent.Parent.hooks.HookManager)

type KeyData = Types.KeyData
type HookContext = Types.HookContext

export type PreparedKeyData = {
	keyData: KeyData,
	rawSize: number?,
	hookName: string?,
}

local KeyViewLoader = {}

local function computeRawSize(rawValue: any): number?
	if typeof(rawValue) == "buffer" then
		return buffer.len(rawValue)
	elseif type(rawValue) == "string" then
		return #rawValue
	end

	local sizeSuccess, encoded = pcall(function()
		return game:GetService("HttpService"):JSONEncode(rawValue)
	end)
	if sizeSuccess then
		return #encoded
	end

	return nil
end

function KeyViewLoader.prepare(rawKeyData: KeyData, context: HookContext, setActiveHook: boolean?): PreparedKeyData
	local rawValue = rawKeyData.value
	local rawSize = computeRawSize(rawValue)
	local hook = HookManager.findHookForData(rawValue, context)
	local hookName: string? = nil
	local finalKeyData = Functional.deepClone(rawKeyData)

	if hook then
		local decompressed, resolvedHookName = HookManager.decompress(rawValue, context, hook.name)
		finalKeyData.value = decompressed
		hookName = resolvedHookName
	end

	if setActiveHook then
		HookManager.setActiveHook(hookName)
	end

	return {
		keyData = finalKeyData,
		rawSize = rawSize,
		hookName = hookName,
	}
end

return KeyViewLoader
