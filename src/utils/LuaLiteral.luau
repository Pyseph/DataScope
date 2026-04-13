--!strict
--[[
	LuaLiteral
	Parse, serialize, pretty-print, and syntax-highlight Lua table literals
]]

local Types = require(script.Parent.Parent.core.Types)

type JSONValue = Types.JSONValue

export type SyntaxColors = {
	keyword: string,
	string: string,
	number: string,
	boolean: string,
	operator: string,
	default: string,
}

local LuaLiteral = {}

-- Detect if a table value is an array (all numeric keys) or object
local function isArrayTable(value: any): boolean
	for k in value do
		if type(k) ~= "number" then
			return false
		end
	end
	return true
end

-- Serialize a JSONValue to a compact Lua literal string
function LuaLiteral.toLuaValue(value: JSONValue): string
	if value == nil then
		return "nil"
	elseif type(value) == "string" then
		return `"{string.gsub(string.gsub(value :: string, '\\', '\\\\'), '"', '\\"')}"`
	elseif type(value) == "boolean" or type(value) == "number" then
		return tostring(value)
	elseif typeof(value) == "buffer" then
		return `<buffer: {buffer.len(value :: buffer)} bytes>`
	elseif type(value) == "table" then
		local parts: { string } = {}
		local val = value :: any
		local isArray = isArrayTable(val)
		if isArray then
			for _, v in val do
				table.insert(parts, LuaLiteral.toLuaValue(v))
			end
		else
			for k, v in val do
				local keyStr = if string.match(k, "^[%a_][%w_]*$")
					then k
					else `["{k}"]`
				table.insert(parts, `{keyStr} = {LuaLiteral.toLuaValue(v)}`)
			end
		end
		return `\{{table.concat(parts, ", ")}\}`
	end
	return tostring(value)
end

-- Serialize a JSONValue to an indented multi-line Lua literal string
function LuaLiteral.toLuaValuePretty(value: JSONValue, indent: string?): string
	local currentIndent = indent or ""
	local nextIndent = currentIndent .. "    "

	if value == nil then
		return "nil"
	elseif type(value) == "string" then
		return `"{string.gsub(string.gsub(value :: string, '\\', '\\\\'), '"', '\\"')}"`
	elseif type(value) == "boolean" or type(value) == "number" then
		return tostring(value)
	elseif typeof(value) == "buffer" then
		return `<buffer: {buffer.len(value :: buffer)} bytes>`
	elseif type(value) == "table" then
		local val = value :: any
		-- Check if empty
		local count = 0
		for _ in val do
			count += 1
		end
		if count == 0 then
			return "{}"
		end

		local parts: { string } = {}
		local isArray = isArrayTable(val)
		if isArray then
			for _, v in val do
				table.insert(parts, nextIndent .. LuaLiteral.toLuaValuePretty(v, nextIndent))
			end
		else
			for k, v in val do
				local keyStr = if string.match(k, "^[%a_][%w_]*$")
					then k
					else `["{k}"]`
				table.insert(parts, `{nextIndent}{keyStr} = {LuaLiteral.toLuaValuePretty(v, nextIndent)}`)
			end
		end
		return `\{\n{table.concat(parts, ",\n")}\n{currentIndent}\}`
	end
	return tostring(value)
end

-- Parse a Lua value literal string into a JSONValue
function LuaLiteral.parseLuaValue(input: string): (boolean, JSONValue)
	local pos = 1
	local len = #input

	local function skipWhitespace()
		while pos <= len do
			local ch = string.sub(input, pos, pos)
			if ch == " " or ch == "\t" or ch == "\n" or ch == "\r" then
				pos += 1
			else
				break
			end
		end
	end

	local parseValue: () -> (boolean, JSONValue)

	local function parseString(): (boolean, string)
		local quote = string.sub(input, pos, pos)
		if quote ~= '"' and quote ~= "'" then
			return false, ""
		end
		pos += 1
		local start = pos
		while pos <= len do
			local ch = string.sub(input, pos, pos)
			if ch == "\\" then
				pos += 2
			elseif ch == quote then
				local str = string.sub(input, start, pos - 1)
				str = string.gsub(str, "\\n", "\n")
				str = string.gsub(str, "\\t", "\t")
				str = string.gsub(str, "\\\\", "\\")
				str = string.gsub(str, "\\'", "'")
				str = string.gsub(str, '\\"', '"')
				pos += 1
				return true, str
			else
				pos += 1
			end
		end
		return false, ""
	end

	local function parseTable(): (boolean, JSONValue)
		if string.sub(input, pos, pos) ~= "{" then
			return false, nil
		end
		pos += 1
		skipWhitespace()

		if string.sub(input, pos, pos) == "}" then
			pos += 1
			return true, {}
		end

		local result: { [string]: JSONValue } = {}
		local arrayIndex = 0
		local isArray = true

		while pos <= len do
			skipWhitespace()
			if string.sub(input, pos, pos) == "}" then
				pos += 1
				if isArray and arrayIndex > 0 then
					local arr: { JSONValue } = {}
					for i = 1, arrayIndex do
						arr[i] = result[tostring(i)]
					end
					return true, arr
				end
				return true, result
			end

			local keyStart = pos
			local hasKey = false
			local key: string = ""

			if string.match(string.sub(input, pos, pos), "[%a_]") then
				local identEnd = pos
				while identEnd <= len and string.match(string.sub(input, identEnd, identEnd), "[%w_]") do
					identEnd += 1
				end
				local afterIdent = identEnd
				while afterIdent <= len do
					local ch = string.sub(input, afterIdent, afterIdent)
					if ch == " " or ch == "\t" then
						afterIdent += 1
					else
						break
					end
				end
				if string.sub(input, afterIdent, afterIdent) == "=" then
					key = string.sub(input, keyStart, identEnd - 1)
					pos = afterIdent + 1
					hasKey = true
					isArray = false
				end
			end

			if not hasKey and string.sub(input, pos, pos) == "[" then
				pos += 1
				skipWhitespace()
				local ch = string.sub(input, pos, pos)
				if ch == '"' or ch == "'" then
					local ok, strKey = parseString()
					if not ok then return false, nil end
					skipWhitespace()
					if string.sub(input, pos, pos) ~= "]" then return false, nil end
					pos += 1
					skipWhitespace()
					if string.sub(input, pos, pos) ~= "=" then return false, nil end
					pos += 1
					key = strKey
					hasKey = true
					isArray = false
				elseif tonumber(ch) or ch == "-" then
					local numStart = pos
					if ch == "-" then pos += 1 end
					while pos <= len and (tonumber(string.sub(input, pos, pos)) or string.sub(input, pos, pos) == ".") do
						pos += 1
					end
					local numKey = tonumber(string.sub(input, numStart, pos - 1))
					if not numKey then return false, nil end
					skipWhitespace()
					if string.sub(input, pos, pos) ~= "]" then return false, nil end
					pos += 1
					skipWhitespace()
					if string.sub(input, pos, pos) ~= "=" then return false, nil end
					pos += 1
					key = tostring(numKey)
					hasKey = true
					isArray = false
				else
					return false, nil
				end
			end

			skipWhitespace()

			local ok, val = parseValue()
			if not ok then return false, nil end

			if hasKey then
				result[key] = val
			else
				arrayIndex += 1
				result[tostring(arrayIndex)] = val
			end

			skipWhitespace()
			local sep = string.sub(input, pos, pos)
			if sep == "," or sep == ";" then
				pos += 1
			elseif sep ~= "}" then
				return false, nil
			end
		end

		return false, nil
	end

	parseValue = function(): (boolean, JSONValue)
		skipWhitespace()
		if pos > len then return false, nil end

		local ch = string.sub(input, pos, pos)

		if ch == "{" then
			return parseTable()
		end

		if ch == '"' or ch == "'" then
			return parseString()
		end

		local tokenStart = pos
		while pos <= len do
			local c = string.sub(input, pos, pos)
			if c == "," or c == ";" or c == "}" or c == " " or c == "\t" or c == "\n" or c == "\r" or c == "]" then
				break
			end
			pos += 1
		end

		local token = string.sub(input, tokenStart, pos - 1)
		if token == "" then return false, nil end

		if token == "nil" or token == "null" then
			return true, nil
		elseif token == "true" then
			return true, true
		elseif token == "false" then
			return true, false
		elseif tonumber(token) then
			return true, tonumber(token)
		end

		return false, nil
	end

	local ok, value = parseValue()
	if not ok then return false, nil end
	skipWhitespace()
	if pos <= len then return false, nil end
	return true, value
end

-- Escape HTML special characters for RichText
local function escapeHtml(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function colorWrap(text: string, color: string): string
	return `<font color="{color}">{escapeHtml(text)}</font>`
end

-- Syntax-highlight a Lua table literal, returning RichText
function LuaLiteral.highlightLuaLiteral(text: string, colors: SyntaxColors): string
	local parts: { string } = {}
	local pos = 1
	local len = #text

	while pos <= len do
		local ch = string.sub(text, pos, pos)

		-- Whitespace: preserve as-is
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r" then
			local start = pos
			while pos <= len do
				local c = string.sub(text, pos, pos)
				if c == " " or c == "\t" or c == "\n" or c == "\r" then
					pos += 1
				else
					break
				end
			end
			table.insert(parts, string.sub(text, start, pos - 1))

		-- Strings
		elseif ch == '"' or ch == "'" then
			local quote = ch
			local start = pos
			pos += 1
			while pos <= len do
				local c = string.sub(text, pos, pos)
				if c == "\\" then
					pos += 2
				elseif c == quote then
					pos += 1
					break
				else
					pos += 1
				end
			end
			table.insert(parts, colorWrap(string.sub(text, start, pos - 1), colors.string))

		-- Braces, brackets, commas, semicolons
		elseif ch == "{" or ch == "}" or ch == "[" or ch == "]" or ch == "," or ch == ";" then
			table.insert(parts, colorWrap(ch, colors.operator))
			pos += 1

		-- Equals sign
		elseif ch == "=" then
			table.insert(parts, colorWrap(ch, colors.operator))
			pos += 1

		-- Identifiers and keywords
		elseif string.match(ch, "[%a_]") then
			local start = pos
			while pos <= len and string.match(string.sub(text, pos, pos), "[%w_]") do
				pos += 1
			end
			local word = string.sub(text, start, pos - 1)
			if word == "true" or word == "false" then
				table.insert(parts, colorWrap(word, colors.boolean))
			elseif word == "nil" or word == "null" then
				table.insert(parts, colorWrap(word, colors.keyword))
			else
				table.insert(parts, colorWrap(word, colors.default))
			end

		-- Numbers (including negative)
		elseif tonumber(ch) or (ch == "-" and pos + 1 <= len and tonumber(string.sub(text, pos + 1, pos + 1))) or ch == "." then
			local start = pos
			if ch == "-" then pos += 1 end
			while pos <= len do
				local c = string.sub(text, pos, pos)
				if tonumber(c) or c == "." or c == "e" or c == "E" or c == "x" or c == "X"
					or ((c == "+" or c == "-") and pos > 1 and string.match(string.sub(text, pos - 1, pos - 1), "[eE]")) then
					pos += 1
				else
					break
				end
			end
			table.insert(parts, colorWrap(string.sub(text, start, pos - 1), colors.number))

		-- Anything else (unexpected chars)
		else
			table.insert(parts, escapeHtml(ch))
			pos += 1
		end
	end

	return table.concat(parts)
end

return LuaLiteral
