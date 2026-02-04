--!strict
--[[
	Functional Programming Utilities
	Pure functions for data transformation and composition
]]

local Functional = {}

-- Identity function
function Functional.identity<T>(x: T): T
	return x
end

-- Constant function
function Functional.constant<T>(x: T): () -> T
	return function()
		return x
	end
end

-- Compose functions right to left: compose(f, g)(x) = f(g(x))
function Functional.compose<A, B, C>(f: (B) -> C, g: (A) -> B): (A) -> C
	return function(x: A): C
		return f(g(x))
	end
end

-- Pipe functions left to right: pipe(f, g)(x) = g(f(x))
function Functional.pipe<A, B, C>(f: (A) -> B, g: (B) -> C): (A) -> C
	return function(x: A): C
		return g(f(x))
	end
end

-- Pipe value through multiple functions
function Functional.pipeValue<T>(value: T, ...: (any) -> any): any
	local result: any = value
	for _, fn in { ... } do
		result = fn(result)
	end
	return result
end

-- Map over array
function Functional.map<T, U>(arr: { T }, fn: (T, number) -> U): { U }
	local result = {}
	for i, v in arr do
		result[i] = fn(v, i)
	end
	return result
end

-- Filter array
function Functional.filter<T>(arr: { T }, predicate: (T, number) -> boolean): { T }
	local result = {}
	for i, v in arr do
		if predicate(v, i) then
			table.insert(result, v)
		end
	end
	return result
end

-- Reduce array
function Functional.reduce<T, U>(arr: { T }, fn: (U, T, number) -> U, initial: U): U
	local result = initial
	for i, v in arr do
		result = fn(result, v, i)
	end
	return result
end

-- Find in array
function Functional.find<T>(arr: { T }, predicate: (T, number) -> boolean): T?
	for i, v in arr do
		if predicate(v, i) then
			return v
		end
	end
	return nil
end

-- Find index in array
function Functional.findIndex<T>(arr: { T }, predicate: (T, number) -> boolean): number?
	for i, v in arr do
		if predicate(v, i) then
			return i
		end
	end
	return nil
end

-- Check if any element matches
function Functional.some<T>(arr: { T }, predicate: (T, number) -> boolean): boolean
	for i, v in arr do
		if predicate(v, i) then
			return true
		end
	end
	return false
end

-- Check if all elements match
function Functional.every<T>(arr: { T }, predicate: (T, number) -> boolean): boolean
	for i, v in arr do
		if not predicate(v, i) then
			return false
		end
	end
	return true
end

-- Flatten nested array one level
function Functional.flatten<T>(arr: { { T } }): { T }
	local result = {}
	for _, inner in arr do
		for _, v in inner do
			table.insert(result, v)
		end
	end
	return result
end

-- FlatMap (map then flatten)
function Functional.flatMap<T, U>(arr: { T }, fn: (T, number) -> { U }): { U }
	return Functional.flatten(Functional.map(arr, fn))
end

-- Take first n elements
function Functional.take<T>(arr: { T }, n: number): { T }
	local result = {}
	for i = 1, math.min(n, #arr) do
		result[i] = arr[i]
	end
	return result
end

-- Skip first n elements
function Functional.skip<T>(arr: { T }, n: number): { T }
	local result = {}
	for i = n + 1, #arr do
		table.insert(result, arr[i])
	end
	return result
end

-- Reverse array
function Functional.reverse<T>(arr: { T }): { T }
	local result = {}
	for i = #arr, 1, -1 do
		table.insert(result, arr[i])
	end
	return result
end

-- Sort array (immutable)
function Functional.sort<T>(arr: { T }, comparator: ((T, T) -> boolean)?): { T }
	local result = table.clone(arr)
	table.sort(result, comparator)
	return result
end

-- Unique values
function Functional.unique<T>(arr: { T }): { T }
	local seen = {}
	local result = {}
	for _, v in arr do
		local key = tostring(v)
		if not seen[key] then
			seen[key] = true
			table.insert(result, v)
		end
	end
	return result
end

-- Group by key function
function Functional.groupBy<T, K>(arr: { T }, keyFn: (T) -> K): { [K]: { T } }
	local result: { [any]: { T } } = {}
	for _, v in arr do
		local key = keyFn(v)
		if not result[key] then
			result[key] = {}
		end
		table.insert(result[key], v)
	end
	return result :: any
end

-- Partition array by predicate
function Functional.partition<T>(arr: { T }, predicate: (T) -> boolean): ({ T }, { T })
	local pass, fail = {}, {}
	for _, v in arr do
		if predicate(v) then
			table.insert(pass, v)
		else
			table.insert(fail, v)
		end
	end
	return pass, fail
end

-- Zip two arrays
function Functional.zip<A, B>(a: { A }, b: { B }): { { A | B } }
	local result = {}
	local len = math.min(#a, #b)
	for i = 1, len do
		result[i] = { a[i], b[i] }
	end
	return result
end

-- Deep clone a table
function Functional.deepClone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in value :: any do
		result[k] = Functional.deepClone(v)
	end
	return result :: any
end

-- Shallow merge tables (right wins)
function Functional.merge<T>(...: { [string]: T }): { [string]: T }
	local result = {}
	for _, t in { ... } do
		for k, v in t do
			result[k] = v
		end
	end
	return result
end

-- Deep merge tables
function Functional.deepMerge<T>(...: { [string]: T }): { [string]: T }
	local result: { [string]: any } = {}
	for _, t in { ... } do
		for k, v in t :: any do
			if type(v) == "table" and type(result[k]) == "table" then
				result[k] = Functional.deepMerge(result[k], v)
			else
				result[k] = Functional.deepClone(v)
			end
		end
	end
	return result :: any
end

-- Get nested value by path
function Functional.getPath(obj: any, path: { string | number }): any
	local current = obj
	for _, key in path do
		if type(current) ~= "table" then
			return nil
		end
		current = current[key]
	end
	return current
end

-- Set nested value by path (immutable)
function Functional.setPath<T>(obj: T, path: { string | number }, value: any): T
	if #path == 0 then
		return value :: any
	end

	local result = Functional.deepClone(obj)
	local current: any = result

	for i = 1, #path - 1 do
		local key = path[i]
		if type(current[key]) ~= "table" then
			current[key] = {}
		else
			current[key] = Functional.deepClone(current[key])
		end
		current = current[key]
	end

	current[path[#path]] = value
	return result
end

-- Delete nested value by path (immutable)
function Functional.deletePath<T>(obj: T, path: { string | number }): T
	if #path == 0 then
		return obj
	end

	local result = Functional.deepClone(obj)
	local current: any = result

	for i = 1, #path - 1 do
		local key = path[i]
		if type(current[key]) ~= "table" then
			return result
		end
		current[key] = Functional.deepClone(current[key])
		current = current[key]
	end

	local lastKey = path[#path]
	if type(lastKey) == "number" then
		table.remove(current, lastKey)
	else
		current[lastKey] = nil
	end

	return result
end

-- Keys of table
function Functional.keys<K, V>(t: { [K]: V }): { K }
	local result: { any } = {}
	for k in t do
		table.insert(result, k)
	end
	return result :: any
end

-- Values of table
function Functional.values<K, V>(t: { [K]: V }): { V }
	local result = {}
	for _, v in t do
		table.insert(result, v)
	end
	return result
end

-- Entries of table
function Functional.entries<K, V>(t: { [K]: V }): { { K | V } }
	local result: { any } = {}
	for k, v in t do
		table.insert(result, { k, v })
	end
	return result
end

-- From entries to table
function Functional.fromEntries<K, V>(entries: { { K | V } }): { [K]: V }
	local result: { [any]: any } = {}
	for _, entry in entries do
		result[entry[1]] = entry[2]
	end
	return result :: any
end

-- Map over object values
function Functional.mapValues<K, V, U>(t: { [K]: V }, fn: (V, K) -> U): { [K]: U }
	local result: { [any]: any } = {}
	for k, v in t do
		result[k] = fn(v, k)
	end
	return result :: any
end

-- Pick keys from object
function Functional.pick<K, V>(t: { [K]: V }, keys: { K }): { [K]: V }
	local result: { [any]: any } = {}
	for _, k in keys do
		result[k] = (t :: any)[k]
	end
	return result :: any
end

-- Omit keys from object
function Functional.omit<V>(t: { [string]: V }, keys: { string }): { [string]: V }
	local result: { [string]: V } = {}
	local omitSet: { [string]: boolean } = {}
	for _, k in keys do
		omitSet[k] = true
	end
	for k, v in t do
		if not omitSet[k] then
			result[k] = v
		end
	end
	return result
end

-- Memoize function
function Functional.memoize<A, R>(fn: (A) -> R): (A) -> R
	local cache: { [any]: any } = {}
	return function(arg: A): R
		local key = tostring(arg)
		if cache[key] == nil then
			cache[key] = fn(arg)
		end
		return cache[key]
	end
end

-- Debounce function
function Functional.debounce<T...>(fn: (T...) -> (), delay: number): (T...) -> ()
	local lastCall = 0
	local scheduled = false
	local args: { any } = {}

	return function(...: T...)
		args = { ... }
		lastCall = os.clock()

		if not scheduled then
			scheduled = true
			task.delay(delay, function()
				scheduled = false
				if os.clock() - lastCall >= delay then
					fn(table.unpack(args))
				end
			end)
		end
	end
end

-- Throttle function
function Functional.throttle<T...>(fn: (T...) -> (), interval: number): (T...) -> ()
	local lastCall = 0

	return function(...: T...)
		local now = os.clock()
		if now - lastCall >= interval then
			lastCall = now
			fn(...)
		end
	end
end

-- Curry a two-argument function
function Functional.curry2<A, B, C>(fn: (A, B) -> C): (A) -> (B) -> C
	return function(a: A)
		return function(b: B)
			return fn(a, b)
		end
	end
end

-- Partial application
function Functional.partial<A, B, C>(fn: (A, B) -> C, a: A): (B) -> C
	return function(b: B): C
		return fn(a, b)
	end
end

-- Not predicate
function Functional.negate<T>(predicate: (T) -> boolean): (T) -> boolean
	return function(x: T): boolean
		return not predicate(x)
	end
end

-- Deep equality check
function Functional.deepEquals(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	-- Both are tables
	local aKeys = {}
	for k in a do
		aKeys[k] = true
	end
	for k in b do
		if not aKeys[k] then
			return false -- b has a key that a doesn't
		end
	end
	for k, v in a do
		if not Functional.deepEquals(v, b[k]) then
			return false
		end
	end
	return true
end

-- Is nil check
function Functional.isNil(x: any): boolean
	return x == nil
end

-- Is not nil check
function Functional.isNotNil(x: any): boolean
	return x ~= nil
end

-- Is empty (nil, empty string, empty table)
function Functional.isEmpty(x: any): boolean
	if x == nil then
		return true
	end
	if type(x) == "string" then
		return x == ""
	end
	if type(x) == "table" then
		return next(x) == nil
	end
	return false
end

-- Default value if nil
function Functional.default<T>(value: T?, defaultValue: T): T
	if value == nil then
		return defaultValue
	end
	return value
end

-- Clamp number
function Functional.clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

-- Lerp
function Functional.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Range generator
function Functional.range(start: number, stop: number?, step: number?): { number }
	local result = {}
	local actualStart = stop and start or 1
	local actualStop = stop or start
	local actualStep = step or 1

	for i = actualStart, actualStop, actualStep do
		table.insert(result, i)
	end
	return result
end

return Functional
