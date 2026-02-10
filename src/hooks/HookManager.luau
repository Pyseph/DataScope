--!strict
--[[
	Hook Manager
	Manages compression/decompression hooks for DataStore values

	Hooks allow users to:
	- Decompress data before displaying in the editor
	- Compress data before saving back to DataStore
	- Support custom serialization formats
]]

local Types = require(script.Parent.Parent.core.Types)
local Functional = require(script.Parent.Parent.utils.Functional)

type HookConfig = Types.HookConfig
type HookContext = Types.HookContext
type JSONValue = Types.JSONValue
type DecompressHook = Types.DecompressHook
type CompressHook = Types.CompressHook

local HookManager = {}

-- Registered hooks sorted by priority (higher = runs first)
local registeredHooks: { HookConfig } = {}

-- Active hook for current editing session
local activeHookName: string? = nil

-- Register a new hook
function HookManager.register(config: HookConfig)
	-- Validate config
	assert(config.name and #config.name > 0, "Hook must have a name")
	assert(config.decompress or config.compress, "Hook must have at least a decompress or compress function")

	-- Remove existing hook with same name
	HookManager.unregister(config.name)

	-- Set default priority
	local hookWithPriority = Functional.deepClone(config)
	hookWithPriority.priority = config.priority or 0

	-- Insert sorted by priority (descending)
	local inserted = false
	for i, hook in registeredHooks do
		if (hookWithPriority.priority :: number) > (hook.priority :: number) then
			table.insert(registeredHooks, i, hookWithPriority)
			inserted = true
			break
		end
	end

	if not inserted then
		table.insert(registeredHooks, hookWithPriority)
	end
end

-- Unregister a hook by name
function HookManager.unregister(name: string)
	registeredHooks = Functional.filter(registeredHooks, function(hook)
		return hook.name ~= name
	end)

	if activeHookName == name then
		activeHookName = nil
	end
end

-- Get all registered hooks
function HookManager.getHooks(): { HookConfig }
	return Functional.deepClone(registeredHooks)
end

-- Get hook by name
function HookManager.getHook(name: string): HookConfig?
	return Functional.find(registeredHooks, function(hook)
		return hook.name == name
	end)
end

-- Set the active hook for editing
function HookManager.setActiveHook(name: string?)
	if name then
		local hook = HookManager.getHook(name)
		if not hook then
			error(`Hook "{name}" not found`)
		end
	end
	activeHookName = name
end

-- Get the active hook name
function HookManager.getActiveHookName(): string?
	return activeHookName
end

-- Get the active hook
function HookManager.getActiveHook(): HookConfig?
	if activeHookName then
		return HookManager.getHook(activeHookName)
	end
	return nil
end

-- Find the best hook that can handle the data
function HookManager.findHookForData(data: any, context: HookContext): HookConfig?
	for i, hook in registeredHooks do
		if hook.canHandle then
			local success, canHandle = pcall(hook.canHandle, data, context)
			if success and canHandle then
				return hook
			end
		end
	end
	return nil
end

-- Decompress data using the active hook or auto-detect
function HookManager.decompress(data: any, context: HookContext, hookName: string?): (JSONValue, string?)
	local hook: HookConfig?

	if hookName then
		hook = HookManager.getHook(hookName)
	elseif activeHookName then
		hook = HookManager.getHook(activeHookName)
	else
		hook = HookManager.findHookForData(data, context)
	end

	if not hook then
		return data, nil
	end

	if not hook.decompress then
		return data, nil
	end

	local success, result = pcall(hook.decompress, data, context)
	
	if success then
		return result, hook.name
	else
		-- Decompression failed, return original data
		warn(`[DataScope] Hook "{hook.name}" decompress failed: {result}`)
		return data, nil
	end
end

-- Compress data using the specified hook
function HookManager.compress(data: JSONValue, context: HookContext, hookName: string?): any
	local hook: HookConfig?

	if hookName then
		hook = HookManager.getHook(hookName)
	elseif activeHookName then
		hook = HookManager.getHook(activeHookName)
	end

	if not hook then
		-- No hook, return data as-is
		return data
	end

	if not hook.compress then
		return data
	end

	local success, result = pcall(hook.compress, data, context)
	if success then
		return result
	else
		error(`[DataScope] Hook "{hook.name}" compress failed: {result}`)
	end
end

-- Clear all hooks
function HookManager.clearAll()
	registeredHooks = {}
	activeHookName = nil
end

-- Load hooks from ModuleScripts in a container
function HookManager.loadFromContainer(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") then
			local success, hookModule = pcall(require, child)
			if success then
				if type(hookModule) == "table" then
					-- Check if it's a valid hook config
					if hookModule.name and (hookModule.decompress or hookModule.compress) then
						HookManager.register(hookModule :: HookConfig)
					elseif hookModule.hooks and type(hookModule.hooks) == "table" then
						-- Module exports multiple hooks
						for _, hook in hookModule.hooks do
							if hook.name and (hook.decompress or hook.compress) then
								HookManager.register(hook)
							end
						end
					end
				end
			else
				warn(`[DataScope] Failed to load hook module "{child.Name}": {hookModule}`)
			end
		end
	end
end

return HookManager
