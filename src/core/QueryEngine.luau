--!strict
--[[
	QueryEngine
	Lua-like expression parser and evaluator for cross-key DataStore queries.
	Standalone module — no UI or Store dependencies.

	Syntax examples:
		data.level > 10
		data.name:find("admin")
		#data.inventory.items > 5
		data.level > 10 and data.stats.exp >= 1000
		(data.level > 50 or data.badges.vip ~= nil)
		changed_since("level", 3600)
		had_value("status", "active", 7200)
]]

local Types = require(script.Parent.Types)
local Functional = require(script.Parent.Parent.utils.Functional)

type JSONValue = Types.JSONValue
type VersionInfo = Types.VersionInfo
type KeyData = Types.KeyData

local QueryEngine = {}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type Token = {
	type: string,
	value: any,
	pos: number,
}

export type ASTNode = {
	type: string,
	-- number
	numValue: number?,
	-- string
	strValue: string?,
	-- boolean
	boolValue: boolean?,
	-- identifier
	name: string?,
	-- fieldAccess
	object: ASTNode?,
	field: string?,
	-- indexAccess
	index: ASTNode?,
	-- methodCall / functionCall
	method: string?,
	args: { ASTNode }?,
	-- unaryOp
	op: string?,
	operand: ASTNode?,
	-- binaryOp
	left: ASTNode?,
	right: ASTNode?,
}

export type ParseResult = {
	success: boolean,
	ast: ASTNode?,
	error: string?,
	errorPos: number?,
}

export type VersionEntry = {
	version: VersionInfo,
	data: KeyData,
}

export type EvalContext = {
	data: JSONValue,
	metadata: { [string]: any }?,
	keyName: string,
	versions: { VersionEntry }?,
}

export type EvalResult = {
	success: boolean,
	value: any,
	error: string?,
	matchedPaths: { { string | number } }?,
}

--------------------------------------------------------------------------------
-- Tokenizer
--------------------------------------------------------------------------------

local KEYWORDS: { [string]: string } = {
	["and"] = "AND",
	["or"] = "OR",
	["not"] = "NOT",
	["true"] = "BOOLEAN",
	["false"] = "BOOLEAN",
	["nil"] = "NIL",
}

local SINGLE_CHARS: { [string]: string } = {
	["."] = "DOT",
	[":"] = "COLON",
	["#"] = "HASH",
	["("] = "LPAREN",
	[")"] = "RPAREN",
	["["] = "LBRACKET",
	["]"] = "RBRACKET",
	[","] = "COMMA",
}

local function tokenize(input: string): { Token }
	local tokens: { Token } = {}
	local pos = 1
	local len = #input

	while pos <= len do
		local ch = string.sub(input, pos, pos)

		-- Skip whitespace
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r" then
			pos += 1
			continue
		end

		-- Numbers and time durations (e.g. 1h, 30m, 2h30m, 1d12h)
		if ch >= "0" and ch <= "9" then
			local startPos = pos
			-- Try to parse as a time duration first
			local timePos = pos
			local totalSeconds = 0
			local isDuration = false
			local TIME_SUFFIXES: { [string]: number } = { d = 86400, h = 3600, m = 60, s = 1 }

			while timePos <= len do
				-- Read a number
				local numStart = timePos
				while timePos <= len do
					local c = string.sub(input, timePos, timePos)
					if c >= "0" and c <= "9" then
						timePos += 1
					else
						break
					end
				end

				if timePos == numStart then
					break -- No number found
				end

				-- Check for time suffix
				if timePos <= len then
					local suffix = string.lower(string.sub(input, timePos, timePos))
					local multiplier = TIME_SUFFIXES[suffix]
					if multiplier then
						local n = tonumber(string.sub(input, numStart, timePos - 1)) or 0
						totalSeconds += n * multiplier
						isDuration = true
						timePos += 1
						continue
					end
				end

				-- No suffix after this number segment — stop
				break
			end

			if isDuration then
				pos = timePos
				table.insert(tokens, { type = "NUMBER", value = totalSeconds, pos = startPos })
			else
				-- Regular number
				while pos <= len do
					local c = string.sub(input, pos, pos)
					if (c >= "0" and c <= "9") or c == "." then
						pos += 1
					else
						break
					end
				end
				local numStr = string.sub(input, startPos, pos - 1)
				local num = tonumber(numStr)
				table.insert(tokens, { type = "NUMBER", value = num or 0, pos = startPos })
			end
			continue
		end

		-- Strings (double or single quoted)
		if ch == '"' or ch == "'" then
			local quote = ch
			local startPos = pos
			pos += 1
			local parts: { string } = {}
			while pos <= len do
				local c = string.sub(input, pos, pos)
				if c == "\\" then
					pos += 1
					if pos <= len then
						local escaped = string.sub(input, pos, pos)
						if escaped == "n" then
							table.insert(parts, "\n")
						elseif escaped == "t" then
							table.insert(parts, "\t")
						else
							table.insert(parts, escaped)
						end
					end
				elseif c == quote then
					pos += 1
					break
				else
					table.insert(parts, c)
				end
				pos += 1
			end
			table.insert(tokens, { type = "STRING", value = table.concat(parts), pos = startPos })
			continue
		end

		-- Identifiers and keywords
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_" then
			local startPos = pos
			while pos <= len do
				local c = string.sub(input, pos, pos)
				if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" then
					pos += 1
				else
					break
				end
			end
			local word = string.sub(input, startPos, pos - 1)
			local kwType = KEYWORDS[word]
			if kwType then
				if kwType == "BOOLEAN" then
					table.insert(tokens, { type = "BOOLEAN", value = word == "true", pos = startPos })
				elseif kwType == "NIL" then
					table.insert(tokens, { type = "NIL", value = nil, pos = startPos })
				else
					table.insert(tokens, { type = kwType, value = word, pos = startPos })
				end
			else
				table.insert(tokens, { type = "IDENTIFIER", value = word, pos = startPos })
			end
			continue
		end

		-- Two-character operators
		if pos < len then
			local two = string.sub(input, pos, pos + 1)
			if two == ">=" then
				table.insert(tokens, { type = "OP_GTE", value = ">=", pos = pos })
				pos += 2
				continue
			elseif two == "<=" then
				table.insert(tokens, { type = "OP_LTE", value = "<=", pos = pos })
				pos += 2
				continue
			elseif two == "==" then
				table.insert(tokens, { type = "OP_EQ", value = "==", pos = pos })
				pos += 2
				continue
			elseif two == "~=" then
				table.insert(tokens, { type = "OP_NEQ", value = "~=", pos = pos })
				pos += 2
				continue
			end
		end

		-- Single-character operators
		if ch == ">" then
			table.insert(tokens, { type = "OP_GT", value = ">", pos = pos })
			pos += 1
			continue
		elseif ch == "<" then
			table.insert(tokens, { type = "OP_LT", value = "<", pos = pos })
			pos += 1
			continue
		end

		-- Single-character tokens
		local singleType = SINGLE_CHARS[ch]
		if singleType then
			table.insert(tokens, { type = singleType, value = ch, pos = pos })
			pos += 1
			continue
		end

		-- Minus (unary or not — parser handles context)
		if ch == "-" then
			table.insert(tokens, { type = "MINUS", value = "-", pos = pos })
			pos += 1
			continue
		end

		-- Unknown character — skip
		pos += 1
	end

	table.insert(tokens, { type = "EOF", value = nil, pos = pos })
	return tokens
end

--------------------------------------------------------------------------------
-- Parser (Recursive Descent)
--------------------------------------------------------------------------------

local function parse(tokens: { Token }): ParseResult
	local pos = 1

	local function peek(): Token
		return tokens[pos] or { type = "EOF", value = nil, pos = 0 }
	end

	local function advance(): Token
		local t = tokens[pos]
		pos += 1
		return t or { type = "EOF", value = nil, pos = 0 }
	end

	local function expect(tokenType: string): Token?
		local t = peek()
		if t.type == tokenType then
			return advance()
		end
		return nil
	end

	local function errorAt(msg: string): ParseResult
		local t = peek()
		return {
			success = false,
			ast = nil,
			error = msg,
			errorPos = t.pos,
		}
	end

	-- Forward declarations
	local parseExpression: () -> (ASTNode?, ParseResult?)

	local function parsePrimary(): (ASTNode?, ParseResult?)
		local t = peek()

		if t.type == "NUMBER" then
			advance()
			return { type = "number", numValue = t.value }, nil
		end

		if t.type == "STRING" then
			advance()
			return { type = "string", strValue = t.value }, nil
		end

		if t.type == "BOOLEAN" then
			advance()
			return { type = "boolean", boolValue = t.value }, nil
		end

		if t.type == "NIL" then
			advance()
			return { type = "nil" }, nil
		end

		if t.type == "IDENTIFIER" then
			advance()
			-- Check for function call: IDENT "(" arglist ")"
			if peek().type == "LPAREN" then
				advance() -- consume "("
				local args: { ASTNode } = {}
				if peek().type ~= "RPAREN" then
					local arg, err = parseExpression()
					if err then return nil, err end
					table.insert(args, arg :: ASTNode)
					while peek().type == "COMMA" do
						advance() -- consume ","
						arg, err = parseExpression()
						if err then return nil, err end
						table.insert(args, arg :: ASTNode)
					end
				end
				if not expect("RPAREN") then
					return nil, errorAt("Expected ')' after function arguments")
				end
				return { type = "functionCall", name = t.value, args = args }, nil
			end
			return { type = "identifier", name = t.value }, nil
		end

		if t.type == "LPAREN" then
			advance()
			local expr, err = parseExpression()
			if err then return nil, err end
			if not expect("RPAREN") then
				return nil, errorAt("Expected ')' after expression")
			end
			return expr, nil
		end

		return nil, errorAt(`Unexpected token: {t.type} '{tostring(t.value)}'`)
	end

	local function parseCallExpr(): (ASTNode?, ParseResult?)
		local node, err = parsePrimary()
		if err then return nil, err end

		while true do
			local t = peek()

			if t.type == "DOT" then
				advance()
				local fieldToken = expect("IDENTIFIER")
				if not fieldToken then
					return nil, errorAt("Expected field name after '.'")
				end

				-- Check for dot-accessed function call: obj.func(args)
				if peek().type == "LPAREN" then
					advance() -- consume "("
					local args: { ASTNode } = {}
					if peek().type ~= "RPAREN" then
						local arg, argErr = parseExpression()
						if argErr then return nil, argErr end
						table.insert(args, arg :: ASTNode)
						while peek().type == "COMMA" do
							advance()
							arg, argErr = parseExpression()
							if argErr then return nil, argErr end
							table.insert(args, arg :: ASTNode)
						end
					end
					if not expect("RPAREN") then
						return nil, errorAt("Expected ')' after function arguments")
					end
					-- Treat as a function call with a dotted name (e.g., math.abs)
					local parentName = if node and node.type == "identifier" then node.name else nil
					if parentName then
						return {
							type = "functionCall",
							name = parentName .. "." .. (fieldToken :: Token).value,
							args = args,
						}, nil
					end
				end

				node = { type = "fieldAccess", object = node, field = (fieldToken :: Token).value }

			elseif t.type == "COLON" then
				advance()
				local methodToken = expect("IDENTIFIER")
				if not methodToken then
					return nil, errorAt("Expected method name after ':'")
				end
				if not expect("LPAREN") then
					return nil, errorAt("Expected '(' after method name")
				end
				local args: { ASTNode } = {}
				if peek().type ~= "RPAREN" then
					local arg, argErr = parseExpression()
					if argErr then return nil, argErr end
					table.insert(args, arg :: ASTNode)
					while peek().type == "COMMA" do
						advance()
						arg, argErr = parseExpression()
						if argErr then return nil, argErr end
						table.insert(args, arg :: ASTNode)
					end
				end
				if not expect("RPAREN") then
					return nil, errorAt("Expected ')' after method arguments")
				end
				node = { type = "methodCall", object = node, method = (methodToken :: Token).value, args = args }

			elseif t.type == "LBRACKET" then
				advance()
				local indexExpr, indexErr = parseExpression()
				if indexErr then return nil, indexErr end
				if not expect("RBRACKET") then
					return nil, errorAt("Expected ']' after index")
				end
				node = { type = "indexAccess", object = node, index = indexExpr }
			else
				break
			end
		end

		return node, nil
	end

	local function parseUnary(): (ASTNode?, ParseResult?)
		local t = peek()

		if t.type == "NOT" then
			advance()
			local operand, err = parseUnary()
			if err then return nil, err end
			return { type = "unaryOp", op = "not", operand = operand }, nil
		end

		if t.type == "HASH" then
			advance()
			local operand, err = parseUnary()
			if err then return nil, err end
			return { type = "unaryOp", op = "#", operand = operand }, nil
		end

		if t.type == "MINUS" then
			advance()
			local operand, err = parseUnary()
			if err then return nil, err end
			return { type = "unaryOp", op = "-", operand = operand }, nil
		end

		return parseCallExpr()
	end

	local function parseComparison(): (ASTNode?, ParseResult?)
		local left, err = parseUnary()
		if err then return nil, err end

		local t = peek()
		if t.type == "OP_GT" or t.type == "OP_LT" or t.type == "OP_GTE"
			or t.type == "OP_LTE" or t.type == "OP_EQ" or t.type == "OP_NEQ" then
			local op = advance()
			local right, rightErr = parseUnary()
			if rightErr then return nil, rightErr end
			return { type = "binaryOp", op = op.value, left = left, right = right }, nil
		end

		return left, nil
	end

	local function parseAnd(): (ASTNode?, ParseResult?)
		local left, err = parseComparison()
		if err then return nil, err end

		while peek().type == "AND" do
			advance()
			local right, rightErr = parseComparison()
			if rightErr then return nil, rightErr end
			left = { type = "binaryOp", op = "and", left = left, right = right }
		end

		return left, nil
	end

	local function parseOr(): (ASTNode?, ParseResult?)
		local left, err = parseAnd()
		if err then return nil, err end

		while peek().type == "OR" do
			advance()
			local right, rightErr = parseAnd()
			if rightErr then return nil, rightErr end
			left = { type = "binaryOp", op = "or", left = left, right = right }
		end

		return left, nil
	end

	parseExpression = function(): (ASTNode?, ParseResult?)
		return parseOr()
	end

	local ast, err = parseExpression()
	if err then
		return err :: ParseResult
	end

	if peek().type ~= "EOF" then
		return errorAt(`Unexpected token after expression: {peek().type}`)
	end

	return {
		success = true,
		ast = ast,
		error = nil,
		errorPos = nil,
	}
end

--------------------------------------------------------------------------------
-- Evaluator
--------------------------------------------------------------------------------

local function evaluate(ast: ASTNode, context: EvalContext): EvalResult
	local matchedPaths: { { string | number } } = {}

	-- Helper: resolve a path string like "stats.level" to an array path
	local function resolvePathString(pathStr: string): { string | number }
		local parts: { string | number } = {}
		for part in string.gmatch(pathStr, "[^%.]+") do
			local num = tonumber(part)
			if num then
				table.insert(parts, num)
			else
				table.insert(parts, part)
			end
		end
		return parts
	end

	-- Version-aware helpers
	local function getVersionsInWindow(seconds: number): { VersionEntry }
		if not context.versions then
			return {}
		end
		local now = os.time()
		local cutoff = now - seconds
		local result: { VersionEntry } = {}
		for _, entry in context.versions do
			if entry.version.createdTime >= cutoff then
				table.insert(result, entry)
			end
		end
		return result
	end

	local function evalNode(node: ASTNode, currentPath: { string | number }?): any
		if node.type == "number" then
			return node.numValue

		elseif node.type == "string" then
			return node.strValue

		elseif node.type == "boolean" then
			return node.boolValue

		elseif node.type == "nil" then
			return nil

		elseif node.type == "identifier" then
			local name = node.name
			if name == "data" then
				return context.data
			elseif name == "metadata" then
				return context.metadata
			elseif name == "keyName" then
				return context.keyName
			end
			error(`Unknown variable: {name}`)

		elseif node.type == "fieldAccess" then
			local obj = evalNode(node.object :: ASTNode, currentPath)
			if type(obj) ~= "table" then
				return nil
			end
			local field = node.field :: string
			local value = (obj :: any)[field]

			-- Track path for highlighting
			local newPath: { string | number } = if currentPath then Functional.deepClone(currentPath) else {}

			-- Build path from the object chain
			if node.object and (node.object :: ASTNode).type == "identifier" and (node.object :: ASTNode).name == "data" then
				newPath = { field }
			elseif currentPath then
				table.insert(newPath, field)
			end

			if value ~= nil and #newPath > 0 then
				table.insert(matchedPaths, newPath)
			end

			return value

		elseif node.type == "indexAccess" then
			local obj = evalNode(node.object :: ASTNode, currentPath)
			if type(obj) ~= "table" then
				return nil
			end
			local idx = evalNode(node.index :: ASTNode, nil)
			return (obj :: any)[idx]

		elseif node.type == "methodCall" then
			local obj = evalNode(node.object :: ASTNode, currentPath)
			local method = node.method :: string
			local args = node.args :: { ASTNode }

			if type(obj) == "string" then
				if method == "find" then
					local pattern = evalNode(args[1], nil)
					local init = if #args >= 2 then evalNode(args[2], nil) else nil
					local plain = if #args >= 3 then evalNode(args[3], nil) else nil
					return string.find(obj, tostring(pattern), init, plain)
				elseif method == "lower" then
					return string.lower(obj)
				elseif method == "upper" then
					return string.upper(obj)
				elseif method == "len" then
					return #obj
				elseif method == "sub" then
					local i = evalNode(args[1], nil)
					local j = if #args >= 2 then evalNode(args[2], nil) else nil
					return string.sub(obj, i, j)
				elseif method == "match" then
					local pattern = evalNode(args[1], nil)
					return string.match(obj, tostring(pattern))
				elseif method == "gsub" then
					local pattern = evalNode(args[1], nil)
					local repl = evalNode(args[2], nil)
					return string.gsub(obj, tostring(pattern), tostring(repl))
				end
			end

			error(`Unknown method: {method}`)

		elseif node.type == "functionCall" then
			local name = node.name :: string
			local args = node.args :: { ASTNode }

			-- Built-in functions
			if name == "type" then
				local val = evalNode(args[1], nil)
				return type(val)

			elseif name == "tonumber" then
				local val = evalNode(args[1], nil)
				return tonumber(val)

			elseif name == "tostring" then
				local val = evalNode(args[1], nil)
				return tostring(val)

			elseif name == "math.abs" then
				return math.abs(evalNode(args[1], nil))
			elseif name == "math.floor" then
				return math.floor(evalNode(args[1], nil))
			elseif name == "math.ceil" then
				return math.ceil(evalNode(args[1], nil))
			elseif name == "math.max" then
				local a = evalNode(args[1], nil)
				local b = evalNode(args[2], nil)
				return math.max(a, b)
			elseif name == "math.min" then
				local a = evalNode(args[1], nil)
				local b = evalNode(args[2], nil)
				return math.min(a, b)

			-- Version-aware functions
			elseif name == "changed_since" then
				local pathStr = tostring(evalNode(args[1], nil))
				local seconds = tonumber(evalNode(args[2], nil)) or 3600
				local path = resolvePathString(pathStr)
				local currentValue = Functional.getPath(context.data, path)
				local versions = getVersionsInWindow(seconds)
				for _, entry in versions do
					local oldValue = Functional.getPath(entry.data.value, path)
					if not Functional.deepEquals(currentValue, oldValue) then
						table.insert(matchedPaths, path)
						return true
					end
				end
				return false

			elseif name == "had_value" then
				local pathStr = tostring(evalNode(args[1], nil))
				local targetValue = evalNode(args[2], nil)
				local seconds = tonumber(if #args >= 3 then evalNode(args[3], nil) else 3600) or 3600
				local path = resolvePathString(pathStr)
				local versions = getVersionsInWindow(seconds)
				for _, entry in versions do
					local oldValue = Functional.getPath(entry.data.value, path)
					if Functional.deepEquals(oldValue, targetValue) then
						table.insert(matchedPaths, path)
						return true
					end
				end
				return false

			elseif name == "version_count" then
				return if context.versions then #context.versions else 0

			elseif name == "version_diff" then
				local pathStr = tostring(evalNode(args[1], nil))
				local path = resolvePathString(pathStr)
				if context.versions and #context.versions > 0 then
					local latestVersion = context.versions[1]
					local currentValue = Functional.getPath(context.data, path)
					local oldValue = Functional.getPath(latestVersion.data.value, path)
					local kind = if Functional.deepEquals(currentValue, oldValue)
						then "unchanged"
						elseif oldValue == nil then "added"
						elseif currentValue == nil then "removed"
						else "changed"
					if kind ~= "unchanged" then
						table.insert(matchedPaths, path)
					end
					return { before = oldValue, after = currentValue, kind = kind }
				end
				return { before = nil, after = Functional.getPath(context.data, path), kind = "unknown" }
			end

			error(`Unknown function: {name}`)

		elseif node.type == "unaryOp" then
			local op = node.op :: string
			if op == "not" then
				local val = evalNode(node.operand :: ASTNode, currentPath)
				return not val
			elseif op == "#" then
				local val = evalNode(node.operand :: ASTNode, currentPath)
				if type(val) == "table" then
					local count = 0
					for _ in val :: any do
						count += 1
					end
					return count
				elseif type(val) == "string" then
					return #val
				end
				return 0
			elseif op == "-" then
				local val = evalNode(node.operand :: ASTNode, currentPath)
				return -(val :: number)
			end

		elseif node.type == "binaryOp" then
			local op = node.op :: string

			-- Short-circuit for and/or
			if op == "and" then
				local leftVal = evalNode(node.left :: ASTNode, currentPath)
				if not leftVal then
					return leftVal
				end
				return evalNode(node.right :: ASTNode, currentPath)
			elseif op == "or" then
				local leftVal = evalNode(node.left :: ASTNode, currentPath)
				if leftVal then
					return leftVal
				end
				return evalNode(node.right :: ASTNode, currentPath)
			end

			local leftVal = evalNode(node.left :: ASTNode, currentPath)
			local rightVal = evalNode(node.right :: ASTNode, currentPath)

			if op == ">" then return (leftVal :: number) > (rightVal :: number)
			elseif op == "<" then return (leftVal :: number) < (rightVal :: number)
			elseif op == ">=" then return (leftVal :: number) >= (rightVal :: number)
			elseif op == "<=" then return (leftVal :: number) <= (rightVal :: number)
			elseif op == "==" then return Functional.deepEquals(leftVal, rightVal)
			elseif op == "~=" then return not Functional.deepEquals(leftVal, rightVal)
			end
		end

		return nil
	end

	-- Track paths through field access chains
	-- We need a smarter approach: intercept fieldAccess nodes to build paths
	-- Reset matchedPaths (already empty from initialization)

	local success, result = pcall(function()
		return evalNode(ast, nil)
	end)

	if not success then
		return {
			success = false,
			value = nil,
			error = tostring(result),
			matchedPaths = nil,
		}
	end

	-- Deduplicate matched paths
	local seen: { [string]: boolean } = {}
	local uniquePaths: { { string | number } } = {}
	for _, path in matchedPaths do
		local key = table.concat(Functional.map(path, function(p)
			return tostring(p)
		end), ".")
		if not seen[key] then
			seen[key] = true
			table.insert(uniquePaths, path)
		end
	end

	return {
		success = true,
		value = result,
		error = nil,
		matchedPaths = uniquePaths,
	}
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function QueryEngine.parse(expression: string): ParseResult
	if expression == "" then
		return {
			success = false,
			ast = nil,
			error = "Empty expression",
			errorPos = 1,
		}
	end

	local tokens = tokenize(expression)
	return parse(tokens)
end

function QueryEngine.evaluate(ast: ASTNode, context: EvalContext): EvalResult
	return evaluate(ast, context)
end

function QueryEngine.query(expression: string, context: EvalContext): EvalResult
	local parseResult = QueryEngine.parse(expression)
	if not parseResult.success or not parseResult.ast then
		return {
			success = false,
			value = nil,
			error = parseResult.error,
			matchedPaths = nil,
		}
	end

	return QueryEngine.evaluate(parseResult.ast, context)
end

function QueryEngine.validate(expression: string): ParseResult
	return QueryEngine.parse(expression)
end

-- Produce a RichText-highlighted version of an expression string.
-- Color map keys: keyword, string, number, boolean, operator, builtin, default
export type SyntaxColors = {
	keyword: string,
	string: string,
	number: string,
	boolean: string,
	operator: string,
	builtin: string,
	default: string,
}

local BUILTIN_NAMES: { [string]: boolean } = {
	type = true, tonumber = true, tostring = true, math = true,
	changed_since = true, had_value = true, version_count = true, version_diff = true,
}

function QueryEngine.highlight(expression: string, colors: SyntaxColors): string
	-- Tokenize, then rebuild the string with color tags, preserving all whitespace
	local tokens = tokenize(expression)
	local parts: { string } = {}
	local lastEnd = 1

	local function escape(s: string): string
		s = string.gsub(s, "&", "&amp;")
		s = string.gsub(s, "<", "&lt;")
		s = string.gsub(s, ">", "&gt;")
		return s
	end

	local function colored(text: string, hex: string): string
		return `<font color="{hex}">{escape(text)}</font>`
	end

	for _, token in tokens do
		-- Append any whitespace/gaps between tokens as-is
		if token.pos > lastEnd then
			table.insert(parts, escape(string.sub(expression, lastEnd, token.pos - 1)))
		end

		local tokenText: string
		local tokenEnd: number

		local tt = token.type
		if tt == "STRING" then
			-- Find the closing quote to get original text including quotes
			local startCh = string.sub(expression, token.pos, token.pos)
			local searchFrom = token.pos + 1
			while searchFrom <= #expression do
				local c = string.sub(expression, searchFrom, searchFrom)
				if c == "\\" then
					searchFrom += 2
				elseif c == startCh then
					searchFrom += 1
					break
				else
					searchFrom += 1
				end
			end
			tokenText = string.sub(expression, token.pos, searchFrom - 1)
			tokenEnd = searchFrom
			table.insert(parts, colored(tokenText, colors.string))
		elseif tt == "NUMBER" then
			-- Use original text to preserve formatting (e.g. "3.0", "2h30m")
			local endPos = token.pos
			while endPos <= #expression do
				local c = string.lower(string.sub(expression, endPos, endPos))
				if (c >= "0" and c <= "9") or c == "." or c == "d" or c == "h" or c == "m" or c == "s" then
					endPos += 1
				else
					break
				end
			end
			tokenText = string.sub(expression, token.pos, endPos - 1)
			tokenEnd = endPos
			table.insert(parts, colored(tokenText, colors.number))
		elseif tt == "BOOLEAN" then
			tokenText = if token.value then "true" else "false"
			tokenEnd = token.pos + #tokenText
			table.insert(parts, colored(tokenText, colors.boolean))
		elseif tt == "NIL" then
			tokenText = "nil"
			tokenEnd = token.pos + 3
			table.insert(parts, colored(tokenText, colors.boolean))
		elseif tt == "AND" or tt == "OR" or tt == "NOT" then
			tokenText = string.lower(token.value :: string)
			tokenEnd = token.pos + #tokenText
			table.insert(parts, colored(tokenText, colors.keyword))
		elseif tt == "IDENTIFIER" then
			local name = token.value :: string
			tokenText = name
			tokenEnd = token.pos + #name
			if BUILTIN_NAMES[name] then
				table.insert(parts, colored(tokenText, colors.builtin))
			else
				table.insert(parts, `<font color="{colors.default}">{escape(tokenText)}</font>`)
			end
		elseif tt == "OP_GT" or tt == "OP_LT" or tt == "OP_GTE" or tt == "OP_LTE" or tt == "OP_EQ" or tt == "OP_NEQ" then
			-- Reconstruct operator text from type
			local opMap: { [string]: string } = {
				OP_GT = ">", OP_LT = "<", OP_GTE = ">=", OP_LTE = "<=",
				OP_EQ = "==", OP_NEQ = "~=",
			}
			tokenText = opMap[tt] or "?"
			tokenEnd = token.pos + #tokenText
			table.insert(parts, colored(tokenText, colors.operator))
		elseif tt == "HASH" then
			tokenText = "#"
			tokenEnd = token.pos + 1
			table.insert(parts, colored(tokenText, colors.operator))
		elseif tt == "MINUS" then
			tokenText = "-"
			tokenEnd = token.pos + 1
			table.insert(parts, colored(tokenText, colors.operator))
		else
			-- DOT, COLON, LPAREN, RPAREN, LBRACKET, RBRACKET, COMMA, EOF, etc.
			local charMap: { [string]: string } = {
				DOT = ".", COLON = ":", LPAREN = "(", RPAREN = ")",
				LBRACKET = "[", RBRACKET = "]", COMMA = ",",
			}
			tokenText = charMap[tt] or ""
			tokenEnd = token.pos + #tokenText
			if #tokenText > 0 then
				table.insert(parts, `<font color="{colors.default}">{escape(tokenText)}</font>`)
			end
		end

		lastEnd = tokenEnd
	end

	-- Append any trailing text
	if lastEnd <= #expression then
		table.insert(parts, escape(string.sub(expression, lastEnd)))
	end

	return table.concat(parts)
end

return QueryEngine
