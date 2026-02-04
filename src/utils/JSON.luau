--!strict
--[[
	JSON Utilities
	JSON parsing, formatting, and validation
]]

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Functional = require(script.Parent.Functional)

local JSON = {}

-- Encode value to JSON string
function JSON.encode(value: any): (boolean, string)
	local success, result = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	return success, result
end

-- Decode JSON string to value
function JSON.decode(json: string): (boolean, any)
	local success, result = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	return success, result
end

-- Pretty print JSON with indentation
function JSON.prettyPrint(value: any, indent: number?): (boolean, string)
	local indentStr = string.rep("  ", indent or 0)
	local nextIndent = (indent or 0) + 1

	if value == nil then
		return true, "null"
	elseif type(value) == "boolean" then
		return true, tostring(value)
	elseif type(value) == "number" then
		return true, tostring(value)
	elseif type(value) == "string" then
		-- Escape special characters
		local escaped = value
			:gsub("\\", "\\\\")
			:gsub('"', '\\"')
			:gsub("\n", "\\n")
			:gsub("\r", "\\r")
			:gsub("\t", "\\t")
		return true, `"{escaped}"`
	elseif typeof(value) == "buffer" then
		return true, `"<buffer: {buffer.len(value)} bytes>"`
	elseif type(value) == "table" then
		-- Check if array
		local isArray = true
		local maxIndex = 0
		for k, _ in value do
			if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
				isArray = false
				break
			end
			maxIndex = math.max(maxIndex, k)
		end

		-- Empty table
		if next(value) == nil then
			return true, "{}"
		end

		local parts = {}
		local nextIndentStr = string.rep("  ", nextIndent)

		if isArray then
			table.insert(parts, "[\n")
			for i = 1, maxIndex do
				local success, itemStr = JSON.prettyPrint(value[i], nextIndent)
				if not success then
					return false, itemStr
				end
				table.insert(parts, nextIndentStr)
				table.insert(parts, itemStr)
				if i < maxIndex then
					table.insert(parts, ",")
				end
				table.insert(parts, "\n")
			end
			table.insert(parts, indentStr)
			table.insert(parts, "]")
		else
			table.insert(parts, "{\n")

			local keys: { string } = {}
			for k in value do
				table.insert(keys, tostring(k))
			end
			table.sort(keys)

			for i, key in keys do
				local success, valueStr = JSON.prettyPrint(value[key], nextIndent)
				if not success then
					return false, valueStr
				end

				local escapedKey = key:gsub("\\", "\\\\"):gsub('"', '\\"')
				table.insert(parts, nextIndentStr)
				table.insert(parts, `"{escapedKey}": `)
				table.insert(parts, valueStr)
				if i < #keys then
					table.insert(parts, ",")
				end
				table.insert(parts, "\n")
			end
			table.insert(parts, indentStr)
			table.insert(parts, "}")
		end

		return true, table.concat(parts)
	else
		return false, `Unsupported type: {typeof(value)}`
	end
end

-- Validate JSON string
function JSON.validate(json: string): (boolean, string?)
	local success, result = pcall(function()
		HttpService:JSONDecode(json)
	end)

	if success then
		return true, nil
	else
		return false, result
	end
end

-- Calculate approximate byte size of JSON value
function JSON.byteSize(value: any): number
	local success, json = JSON.encode(value)
	if success then
		return #json
	end
	return 0
end

-- Format byte size as readable string
function JSON.formatByteSize(bytes: number): string
	if bytes < 1024 then
		return `{bytes} B`
	elseif bytes < 1024 * 1024 then
		return string.format("%.1f KB", bytes / 1024)
	else
		return string.format("%.1f MB", bytes / (1024 * 1024))
	end
end

-- Check if string is a valid Lua identifier
local function isValidIdentifier(str: string): boolean
	if type(str) ~= "string" or #str == 0 then
		return false
	end
	-- Must start with letter or underscore, followed by letters, numbers, or underscores
	if not string.match(str, "^[a-zA-Z_][a-zA-Z0-9_]*$") then
		return false
	end
	-- Check for Lua keywords
	local keywords = {
		["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
		["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
		["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
		["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
		["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
		["while"] = true, ["continue"] = true,
	}
	return not keywords[str]
end

-- Convert value to Luau source code
function JSON.toLuau(value: any, indent: number?): (boolean, string)
	local indentLevel = indent or 0
	local indentStr = string.rep("\t", indentLevel)
	local nextIndent = indentLevel + 1
	local nextIndentStr = string.rep("\t", nextIndent)

	if value == nil then
		return true, "nil"
	elseif type(value) == "boolean" then
		return true, tostring(value)
	elseif type(value) == "number" then
		-- Handle special numbers
		if value ~= value then -- NaN
			return true, "0/0"
		elseif value == math.huge then
			return true, "math.huge"
		elseif value == -math.huge then
			return true, "-math.huge"
		end
		return true, tostring(value)
	elseif type(value) == "string" then
		-- Escape special characters for Lua string
		local escaped = value
			:gsub("\\", "\\\\")
			:gsub('"', '\\"')
			:gsub("\n", "\\n")
			:gsub("\r", "\\r")
			:gsub("\t", "\\t")
			:gsub("\0", "\\0")
		return true, `"{escaped}"`
	elseif typeof(value) == "buffer" then
		-- Export buffer as base64 comment + placeholder
		local len = buffer.len(value)
		return true, `nil --[[ buffer: {len} bytes ]]`
	elseif type(value) == "table" then
		-- Check if empty table
		if next(value) == nil then
			return true, "{}"
		end

		-- Check if array (sequential integer keys starting at 1)
		local isArray = true
		local maxIndex = 0
		local count = 0
		for k, _ in value do
			count += 1
			if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
				isArray = false
				break
			end
			maxIndex = math.max(maxIndex, k)
		end
		-- Also verify no gaps
		if isArray and maxIndex ~= count then
			isArray = false
		end

		local parts = {}
		table.insert(parts, "{\n")

		if isArray then
			-- Array format: { value1, value2, ... }
			for i = 1, maxIndex do
				local success, itemStr = JSON.toLuau(value[i], nextIndent)
				if not success then
					return false, itemStr
				end
				table.insert(parts, nextIndentStr)
				table.insert(parts, itemStr)
				if i < maxIndex then
					table.insert(parts, ",")
				end
				table.insert(parts, "\n")
			end
		else
			-- Dictionary format: { key = value, ["key-2"] = value2, ... }
			-- Sort keys for consistent output
			local keys: { any } = {}
			for k in value do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				-- Numbers first, then strings
				if type(a) == "number" and type(b) == "number" then
					return a < b
				elseif type(a) == "number" then
					return true
				elseif type(b) == "number" then
					return false
				else
					return tostring(a) < tostring(b)
				end
			end)

			for i, key in keys do
				local success, valueStr = JSON.toLuau(value[key], nextIndent)
				if not success then
					return false, valueStr
				end

				table.insert(parts, nextIndentStr)
				
				-- Format key appropriately
				if type(key) == "number" then
					table.insert(parts, `[{key}] = `)
				elseif isValidIdentifier(key) then
					table.insert(parts, `{key} = `)
				else
					-- Need bracket notation with escaped string
					local escapedKey = tostring(key)
						:gsub("\\", "\\\\")
						:gsub('"', '\\"')
						:gsub("\n", "\\n")
					table.insert(parts, `["{escapedKey}"] = `)
				end
				
				table.insert(parts, valueStr)
				if i < #keys then
					table.insert(parts, ",")
				end
				table.insert(parts, "\n")
			end
		end

		table.insert(parts, indentStr)
		table.insert(parts, "}")
		return true, table.concat(parts)
	else
		return false, `Unsupported type: {typeof(value)}`
	end
end

-- Maximum source size for ModuleScript direct assignment (Roblox limit is 200KB)
local MAX_DIRECT_SOURCE_SIZE = 199000

-- Export value to ModuleScript with Luau syntax
-- For large files, uses ScriptEditorService to bypass the 200KB limit
function JSON.exportToModule(value: any, name: string?): (ModuleScript?, string?)
	local success, luauStr = JSON.toLuau(value)
	if not success then
		return nil, `Failed to format data: {luauStr}`
	end

	local moduleName = name or "ExportedData"
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	local source = `--!strict\n--[[\n\tExported from DataScope\n\tKey: {moduleName}\n\tDate: {timestamp}\n]]\n\nreturn {luauStr}\n`
	
	local moduleScript = Instance.new("ModuleScript")
	moduleScript.Name = moduleName
	
	-- Check if source is too large for direct assignment
	if #source > MAX_DIRECT_SOURCE_SIZE then
		-- Use ScriptEditorService to bypass the limit
		-- First set a placeholder source
		moduleScript.Source = `-- Large export ({math.floor(#source / 1024)}KB) - Loading via ScriptEditorService...`
		
		-- Parent it first so ScriptEditorService can access it
		moduleScript.Parent = game:GetService("ServerStorage")
		
		-- Use ScriptEditorService to update the source (can handle larger content)
		local updateSuccess, updateErr = pcall(function()
			ScriptEditorService:UpdateSourceAsync(moduleScript, function()
				return source
			end)
		end)
		
		if not updateSuccess then
			moduleScript:Destroy()
			return nil, `Failed to write large export via ScriptEditorService: {updateErr}`
		end
		
		-- Unparent so caller can manage it
		moduleScript.Parent = nil
	else
		moduleScript.Source = source
	end

	return moduleScript, nil
end

-- Export value and prompt user to save (requires plugin reference)
function JSON.promptExport(value: any, name: string?, pluginRef: Plugin?): (boolean, string?)
	local moduleScript, exportErr = JSON.exportToModule(value, name)
	if not moduleScript then
		return false, exportErr or "Failed to create export module"
	end
	
	-- Parent to a temporary location
	moduleScript.Parent = game:GetService("ServerStorage")
	Selection:Set({ moduleScript })
	
	-- Use plugin API to prompt save if available
	if pluginRef then
		local success, err = pcall(function()
			-- Use the async version of the API
			pluginRef:PromptSaveSelection(name or "ExportedData")
		end)
		
		-- Clean up the temporary module after save prompt
		task.delay(1, function()
			if moduleScript and moduleScript.Parent then
				moduleScript:Destroy()
			end
		end)
		
		if success then
			return true, nil :: string?
		else
			return false, tostring(err)
		end
	else
		-- Fallback: just leave it in ServerStorage
		return true, "Export created in ServerStorage (no plugin reference for file save)"
	end
end

-- Import from selected ModuleScript
function JSON.importFromSelection(): (boolean, any, string?)
	local selected = Selection:Get()
	if #selected == 0 then
		return false, nil, "No selection"
	end

	local moduleScript = selected[1]
	if not moduleScript:IsA("ModuleScript") then
		return false, nil, "Selected item is not a ModuleScript"
	end

	local success, result = pcall(function()
		return require(moduleScript)
	end)

	if success then
		return true, result, nil
	else
		return false, nil, `Failed to load module: {result}`
	end
end

-- Deep diff two JSON values
function JSON.diff(a: any, b: any, path: { string }?): { { path: { string }, type: string, oldValue: any, newValue: any } }
	local currentPath = path or {}
	local differences = {}

	if type(a) ~= type(b) then
		table.insert(differences, {
			path = currentPath,
			type = "type_change",
			oldValue = a,
			newValue = b,
		})
		return differences
	end

	if type(a) == "table" then
		-- Check all keys in a
		for k, v in a do
			local newPath = Functional.deepClone(currentPath)
			table.insert(newPath, tostring(k))

			if b[k] == nil then
				table.insert(differences, {
					path = newPath,
					type = "removed",
					oldValue = v,
					newValue = nil,
				})
			else
				local subDiffs = JSON.diff(v, b[k], newPath)
				for _, diff in subDiffs do
					table.insert(differences, diff)
				end
			end
		end

		-- Check for new keys in b
		for k, v in b do
			if a[k] == nil then
				local newPath = Functional.deepClone(currentPath)
				table.insert(newPath, tostring(k))
				table.insert(differences, {
					path = newPath,
					type = "added",
					oldValue = nil,
					newValue = v,
				})
			end
		end
	elseif a ~= b then
		table.insert(differences, {
			path = currentPath,
			type = "changed",
			oldValue = a,
			newValue = b,
		})
	end

	return differences
end

return JSON
