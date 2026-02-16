--!strict
--[[
	Diff Utilities
	Computes developer-friendly structural diffs between two JSON-like values.
]]

local Types = require(script.Parent.Parent.core.Types)

type JSONValue = Types.JSONValue

export type DiffKind = "added" | "removed" | "changed" | "type_changed"

export type DiffEntry = {
	path: { string | number },
	pathText: string,
	kind: DiffKind,
	before: JSONValue,
	after: JSONValue,
	beforeType: string,
	afterType: string,
}

local Diff = {}

local function getValueType(value: any): string
	local t = typeof(value)
	if t ~= "table" then
		return t
	end

	local firstKey = next(value)
	if firstKey == nil then
		return "table"
	end

	if type(firstKey) == "number" then
		return "array"
	end

	return "object"
end

local function countKeys(value: any): number
	if type(value) ~= "table" then
		return 0
	end

	local count = 0
	for _ in value do
		count += 1
	end
	return count
end

local function valuesEqual(a: any, b: any): boolean
	local typeA = typeof(a)
	local typeB = typeof(b)
	if typeA ~= typeB then
		return false
	end

	if typeA == "buffer" then
		local lenA = buffer.len(a)
		local lenB = buffer.len(b)
		if lenA ~= lenB then
			return false
		end

		for i = 0, lenA - 1 do
			if buffer.readu8(a, i) ~= buffer.readu8(b, i) then
				return false
			end
		end
		return true
	end

	return a == b
end

local function formatPath(path: { string | number }): string
	if #path == 0 then
		return "(root)"
	end

	local parts = {}
	for index, segment in path do
		if type(segment) == "number" then
			table.insert(parts, `[{segment}]`)
		else
			local safeIdentifier = string.match(segment, "^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
			if safeIdentifier then
				if index == 1 then
					table.insert(parts, segment)
				else
					table.insert(parts, "." .. segment)
				end
			else
				local escaped = string.gsub(segment, '"', '\\"')
				table.insert(parts, `["{escaped}"]`)
			end
		end
	end

	return table.concat(parts, "")
end

local function clonePathWith(path: { string | number }, key: string | number): { string | number }
	local newPath = table.clone(path)
	table.insert(newPath, key)
	return newPath
end

local function sortedKeys(value: { [any]: any }): { string | number }
	local numericKeys = {} :: { number }
	local otherKeys = {} :: { string | number }

	for key in value do
		if type(key) == "number" then
			table.insert(numericKeys, key)
		else
			table.insert(otherKeys, key)
		end
	end

	table.sort(numericKeys)
	table.sort(otherKeys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local result = {} :: { string | number }
	for _, key in numericKeys do
		table.insert(result, key)
	end
	for _, key in otherKeys do
		table.insert(result, key)
	end
	return result
end

local function pushEntry(
	entries: { DiffEntry },
	path: { string | number },
	kind: DiffKind,
	beforeValue: JSONValue,
	afterValue: JSONValue
)
	table.insert(entries, {
		path = path,
		pathText = formatPath(path),
		kind = kind,
		before = beforeValue,
		after = afterValue,
		beforeType = getValueType(beforeValue),
		afterType = getValueType(afterValue),
	})
end

local function walkDiff(beforeValue: JSONValue, afterValue: JSONValue, path: { string | number }, entries: { DiffEntry })
	if beforeValue == nil and afterValue ~= nil then
		pushEntry(entries, path, "added", beforeValue, afterValue)
		return
	end

	if beforeValue ~= nil and afterValue == nil then
		pushEntry(entries, path, "removed", beforeValue, afterValue)
		return
	end

	local beforeType = getValueType(beforeValue)
	local afterType = getValueType(afterValue)

	if beforeType ~= afterType then
		pushEntry(entries, path, "type_changed", beforeValue, afterValue)
		return
	end

	if typeof(beforeValue) == "table" and typeof(afterValue) == "table" then
		local beforeTable = beforeValue :: { [any]: any }
		local afterTable = afterValue :: { [any]: any }

		local visited = {} :: { [string]: boolean }
		for _, key in sortedKeys(beforeTable) do
			local keyTag = tostring(key) .. ":" .. typeof(key)
			visited[keyTag] = true

			if afterTable[key] == nil then
				pushEntry(entries, clonePathWith(path, key), "removed", beforeTable[key], nil)
			else
				walkDiff(beforeTable[key], afterTable[key], clonePathWith(path, key), entries)
			end
		end

		for _, key in sortedKeys(afterTable) do
			local keyTag = tostring(key) .. ":" .. typeof(key)
			if not visited[keyTag] and beforeTable[key] == nil then
				pushEntry(entries, clonePathWith(path, key), "added", nil, afterTable[key])
			end
		end

		return
	end

	if not valuesEqual(beforeValue, afterValue) then
		pushEntry(entries, path, "changed", beforeValue, afterValue)
	end
end

function Diff.compute(beforeValue: JSONValue, afterValue: JSONValue): { DiffEntry }
	local entries = {} :: { DiffEntry }
	walkDiff(beforeValue, afterValue, {}, entries)

	table.sort(entries, function(a, b)
		if a.pathText == b.pathText then
			return a.kind < b.kind
		end
		return a.pathText < b.pathText
	end)

	return entries
end

function Diff.previewValue(value: JSONValue, maxLength: number?): string
	local limit = maxLength or 80

	if value == nil then
		return "nil"
	end

	local valueType = typeof(value)
	if valueType == "string" then
		local raw = value :: string
		local escaped = raw:gsub("\n", "\\n")
		if #escaped > limit then
			return `"{string.sub(escaped, 1, limit)}..."`
		end
		return `"{escaped}"`
	elseif valueType == "buffer" then
		return `<buffer {buffer.len(value :: buffer)} bytes>`
	elseif valueType == "table" then
		local tableValue = value :: { [any]: any }
		local keyCount = countKeys(tableValue)
		local tableType = getValueType(tableValue)
		if tableType == "array" then
			return `<array {keyCount} items>`
		end
		return `<object {keyCount} keys>`
	end

	return tostring(value)
end

return Diff
