--!strict
--[[
	Built-in Compression Hooks
	Common compression/serialization formats
]]

local HttpService = game:GetService("HttpService")
local EncodingService = game:GetService("EncodingService")

local Types = require(script.Parent.Parent.core.Types)

type HookConfig = Types.HookConfig
type HookContext = Types.HookContext
type JSONValue = Types.JSONValue

local BuiltInHooks = {}

-- JSON String Hook
-- Handles data stored as JSON-encoded strings
BuiltInHooks.JSONString = {
	name = "JSON String",
	description = "Decode/encode JSON strings stored in DataStore",
	priority = 10,

	canHandle = function(data: any, _context: HookContext): boolean
		if type(data) ~= "string" then
			return false
		end
		-- Check if it looks like JSON
		local trimmed = string.gsub(data, "^%s*", "")
		return string.sub(trimmed, 1, 1) == "{" or string.sub(trimmed, 1, 1) == "["
	end,

	decompress = function(data: buffer | string, _context: HookContext): JSONValue
		if type(data) ~= "string" then
			error("Expected string data")
		end
		return HttpService:JSONDecode(data)
	end,

	compress = function(data: JSONValue, _context: HookContext): buffer | string
		return HttpService:JSONEncode(data)
	end,
}

-- Base64 Buffer Hook
-- Handles buffers stored as base64 strings
BuiltInHooks.Base64Buffer = {
	name = "Base64 Buffer",
	description = "Decode/encode base64-encoded buffer data",
	priority = 5,

	canHandle = function(data: any, _context: HookContext): boolean
		if type(data) ~= "string" then
			return false
		end
		-- Check if it looks like base64 (alphanumeric + /+ with optional = padding)
		return string.match(data, "^[A-Za-z0-9+/]+=*$") ~= nil and #data % 4 == 0 and #data >= 4
	end,

	decompress = function(data: buffer | string, _context: HookContext): JSONValue
		if type(data) ~= "string" then
			error("Expected string data")
		end
		-- Decode base64 to buffer, then try to decode as JSON
		local decoded = buffer.fromstring(data) -- This is simplified; real base64 would need proper decoding
		local str = buffer.tostring(decoded)

		-- Try to parse as JSON
		local success, result = pcall(function()
			return HttpService:JSONDecode(str)
		end)

		if success then
			return result
		else
			return str
		end
	end,

	compress = function(data: JSONValue, _context: HookContext): buffer | string
		local json = HttpService:JSONEncode(data)
		return json -- Simplified; real implementation would base64 encode
	end,
}

-- Compressed JSON Hook (using simple compression marker)
-- Detects data that starts with a compression marker
BuiltInHooks.CompressedJSON = {
	name = "Compressed JSON",
	description = "Handle compressed JSON data (LZ4/ZLIB markers)",
	priority = 15,

	canHandle = function(data: any, _context: HookContext): boolean
		if typeof(data) ~= "buffer" then
			return false
		end
		-- Check for common compression magic bytes
		local size = buffer.len(data)
		if size < 4 then
			return false
		end

		local b1 = buffer.readu8(data, 0)
		local b2 = buffer.readu8(data, 1)

		-- LZ4 magic: 0x04 0x22
		if b1 == 0x04 and b2 == 0x22 then
			return true
		end

		-- ZLIB magic: 0x78 (0x01, 0x9C, 0xDA)
		if b1 == 0x78 and (b2 == 0x01 or b2 == 0x9C or b2 == 0xDA) then
			return true
		end

		return false
	end,

	decompress = function(data: buffer | string, _context: HookContext): JSONValue
		if typeof(data) ~= "buffer" then
			error("Expected buffer data")
		end

		-- Note: Actual decompression would require a compression library
		-- This is a placeholder that returns the buffer info
		return {
			["__compressed"] = true,
			["__size"] = buffer.len(data),
			["__note"] = "Compression hooks need a decompression library",
		}
	end,

	compress = function(data: JSONValue, _context: HookContext): buffer | string
		-- Placeholder
		return HttpService:JSONEncode(data)
	end,
}

-- MessagePack-like Hook
-- Detects MessagePack-encoded data
BuiltInHooks.MessagePack = {
	name = "MessagePack",
	description = "Handle MessagePack-encoded data",
	priority = 8,

	canHandle = function(data: any, _context: HookContext): boolean
		if typeof(data) ~= "buffer" then
			return false
		end
		local size = buffer.len(data)
		if size < 1 then
			return false
		end

		local b1 = buffer.readu8(data, 0)
		-- MessagePack type markers for maps and arrays
		return (b1 >= 0x80 and b1 <= 0x8f) -- fixmap
			or (b1 >= 0x90 and b1 <= 0x9f) -- fixarray
			or b1 == 0xde
			or b1 == 0xdf -- map16/map32
			or b1 == 0xdc
			or b1 == 0xdd -- array16/array32
	end,

	decompress = function(data: buffer | string, _context: HookContext): JSONValue
		if typeof(data) ~= "buffer" then
			error("Expected buffer data")
		end

		-- Placeholder - actual MessagePack decoding would need implementation
		return {
			["__messagepack"] = true,
			["__size"] = buffer.len(data),
			["__note"] = "MessagePack decoding requires a decoder library",
		}
	end,

	compress = function(data: JSONValue, _context: HookContext): buffer | string
		return HttpService:JSONEncode(data)
	end,
}

-- Zstd Compressed Data Field Hook
-- Handles tables with a .Data field containing Zstd-compressed JSON buffer
BuiltInHooks.ZstdDataField = {
	name = "Zstd Data Field",
	description = "Decompress .Data buffer field using Zstd, then parse as JSON",
	priority = 25,

	canHandle = function(data: any, _context: HookContext): boolean
		if type(data) ~= "table" then
			return false
		end
		-- Check if it has a Data field that is a buffer
		if typeof(data.Data) ~= "buffer" then
			return false
		end
		-- Check for Zstd magic bytes (0x28 0xB5 0x2F 0xFD)
		local buf = data.Data
		if buffer.len(buf) < 4 then
			return false
		end
		local b1 = buffer.readu8(buf, 0)
		local b2 = buffer.readu8(buf, 1)
		local b3 = buffer.readu8(buf, 2)
		local b4 = buffer.readu8(buf, 3)
		return b1 == 0x28 and b2 == 0xB5 and b3 == 0x2F and b4 == 0xFD
	end,

	decompress = function(data: buffer | string, _context: HookContext): JSONValue
		if type(data) ~= "table" then
			error("Expected table with Data field")
		end

		local tableData = data :: any
		local result = {}

		-- Copy all fields
		for key, value in tableData do
			if key == "Data" and typeof(value) == "buffer" then
				-- Decompress the Data field
				local decompressed = EncodingService:DecompressBuffer(value, Enum.CompressionAlgorithm.Zstd)
				local jsonString = buffer.tostring(decompressed)
				local parsed = HttpService:JSONDecode(jsonString)
				result[key] = parsed
			else
				result[key] = value
			end
		end

		return result
	end,

	compress = function(data: JSONValue, _context: HookContext): buffer | string
		if type(data) ~= "table" then
			return data
		end

		local tableData = data :: any
		local result = {}

		-- Copy all fields
		for key, value in tableData do
			if key == "Data" then
				-- Compress the Data field back
				local jsonString = HttpService:JSONEncode(value)
				local jsonBuffer = buffer.fromstring(jsonString)
				local compressed = EncodingService:CompressBuffer(jsonBuffer, Enum.CompressionAlgorithm.Zstd)
				result[key] = compressed
			else
				result[key] = value
			end
		end

		return result :: any
	end,
}

-- Zstd Buffer Hook
-- Handles raw Zstd-compressed buffers containing JSON
BuiltInHooks.ZstdBuffer = {
	name = "Zstd Buffer",
	description = "Decompress Zstd buffer and parse as JSON",
	priority = 22,

	canHandle = function(data: any, _context: HookContext): boolean
		if typeof(data) ~= "buffer" then
			return false
		end
		-- Check for Zstd magic bytes (0x28 0xB5 0x2F 0xFD)
		if buffer.len(data) < 4 then
			return false
		end
		local b1 = buffer.readu8(data, 0)
		local b2 = buffer.readu8(data, 1)
		local b3 = buffer.readu8(data, 2)
		local b4 = buffer.readu8(data, 3)
		return b1 == 0x28 and b2 == 0xB5 and b3 == 0x2F and b4 == 0xFD
	end,

	decompress = function(data: buffer | string, _context: HookContext): JSONValue
		if typeof(data) ~= "buffer" then
			error("Expected buffer data")
		end

		local decompressed = EncodingService:DecompressBuffer(data, Enum.CompressionAlgorithm.Zstd)
		local jsonString = buffer.tostring(decompressed)
		return HttpService:JSONDecode(jsonString)
	end,

	compress = function(data: JSONValue, _context: HookContext): buffer | string
		local jsonString = HttpService:JSONEncode(data)
		local jsonBuffer = buffer.fromstring(jsonString)
		return EncodingService:CompressBuffer(jsonBuffer, Enum.CompressionAlgorithm.Zstd)
	end,
}

-- Profile Service Hook
-- Common format used by ProfileService
BuiltInHooks.ProfileService = {
	name = "ProfileService",
	description = "Handle ProfileService data format",
	priority = 20,

	canHandle = function(data: any, _context: HookContext): boolean
		if type(data) ~= "table" then
			return false
		end
		-- ProfileService stores data with specific keys
		return data.Data ~= nil and data.MetaData ~= nil
	end,

	decompress = function(data: buffer | string, _context: HookContext): JSONValue
		-- ProfileService data is already in table format, just return it
		return data :: any
	end,

	compress = function(data: JSONValue, _context: HookContext): buffer | string
		return data :: any
	end,
}

-- Get all built-in hooks as a list
function BuiltInHooks.getAll(): { HookConfig }
	return {
		BuiltInHooks.JSONString,
		BuiltInHooks.Base64Buffer,
		BuiltInHooks.CompressedJSON,
		BuiltInHooks.MessagePack,
		BuiltInHooks.ZstdDataField,
		BuiltInHooks.ZstdBuffer,
		BuiltInHooks.ProfileService,
	}
end

-- Register all built-in hooks with the HookManager
function BuiltInHooks.registerAll()
	local HookManager = require(script.Parent.HookManager)
	for _, hook in BuiltInHooks.getAll() do
		HookManager.register(hook)
	end
end

return BuiltInHooks
