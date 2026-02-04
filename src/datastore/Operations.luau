--!strict
--[[
	DataStore Operations
	Pure functions for DataStore interactions
]]

local DataStoreService = game:GetService("DataStoreService")

local Types = require(script.Parent.Parent.core.Types)
local Functional = require(script.Parent.Parent.utils.Functional)

type ConnectionInfo = Types.ConnectionInfo
type KeyInfo = Types.KeyInfo
type OrderedKeyInfo = Types.OrderedKeyInfo
type VersionInfo = Types.VersionInfo
type KeyData = Types.KeyData
type JSONValue = Types.JSONValue

export type Result<T> = {
	success: true,
	value: T,
} | {
	success: false,
	error: string,
}

local Operations = {}

-- Helper to wrap pcall results
local function wrapResult<T>(success: boolean, result: T | string): Result<T>
	if success then
		return { success = true, value = result :: T }
	else
		return { success = false, error = result :: string }
	end
end

-- Get a DataStore instance
function Operations.getDataStore(info: ConnectionInfo): Result<DataStore | OrderedDataStore>
	if info.datastoreType == "Ordered" then
		local success, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(info.name, info.scope)
		end)
		return wrapResult(success, result)
	else
		local options: DataStoreOptions? = nil
		if info.allScopes then
			options = Instance.new("DataStoreOptions")
			options.AllScopes = true
		end

		local success, result = pcall(function()
			if options then
				return DataStoreService:GetDataStore(info.name, "", options)
			elseif info.scope then
				return DataStoreService:GetDataStore(info.name, info.scope)
			else
				return DataStoreService:GetDataStore(info.name)
			end
		end)
		return wrapResult(success, result)
	end
end

-- List all DataStores
function Operations.listDataStores(prefix: string?, cursor: string?): Result<{ datastores: { string }, cursor: string? }>
	local success, result = pcall(function()
		local pages = DataStoreService:ListDataStoresAsync(prefix, nil, cursor)
		local items = pages:GetCurrentPage()

		local datastores: { string } = {}
		for _, item in items do
			table.insert(datastores, item.DataStoreName)
		end

		local nextCursor: string? = nil
		if not pages.IsFinished then
			-- We need to advance to get the cursor for next page
			pcall(function()
				pages:AdvanceToNextPageAsync()
			end)
			nextCursor = "has_more" -- Placeholder, actual cursor management happens at a higher level
		end

		return { datastores = datastores, cursor = nextCursor }
	end)

	return wrapResult(success, result)
end

-- List keys in a DataStore
function Operations.listKeys(
	datastore: DataStore,
	prefix: string?,
	cursor: string?
): Result<{ keys: { KeyInfo }, cursor: string? }>
	local success, result = pcall(function()
		local pages = datastore:ListKeysAsync(prefix, nil, cursor)
		local items = pages:GetCurrentPage()

		local keys: { KeyInfo } = {}
		for _, item in items do
			-- ListKeysAsync only returns DataStoreKey with KeyName property
			table.insert(keys, {
				key = item.KeyName,
			})
		end

		local nextCursor: string? = nil
		if not pages.IsFinished then
			nextCursor = "has_more"
		end

		return { keys = keys, cursor = nextCursor }
	end)

	return wrapResult(success, result)
end

-- List keys in an Ordered DataStore
function Operations.listOrderedKeys(
	datastore: OrderedDataStore,
	ascending: boolean,
	minValue: number?,
	maxValue: number?,
	pageSize: number?
): Result<{ keys: { OrderedKeyInfo }, hasMore: boolean }>
	local success, result = pcall(function()
		local pages = datastore:GetSortedAsync(ascending, pageSize or 100, minValue, maxValue)
		local items = pages:GetCurrentPage()

		local keys: { OrderedKeyInfo } = {}
		for _, item in items do
			table.insert(keys, {
				key = item.key,
				value = item.value,
			})
		end

		return { keys = keys, hasMore = not pages.IsFinished }
	end)

	return wrapResult(success, result)
end

-- Get a key's value
function Operations.getKey(datastore: DataStore, key: string): Result<KeyData>
	local success, result = pcall(function()
		local value, keyInfo = datastore:GetAsync(key)
		return {
			value = value,
			keyInfo = keyInfo,
			userIds = keyInfo and keyInfo:GetUserIds() or nil,
			metadata = keyInfo and keyInfo:GetMetadata() or nil,
		}
	end)

	return wrapResult(success, result)
end

-- Get a specific version of a key
function Operations.getKeyVersion(datastore: DataStore, key: string, version: string): Result<KeyData>
	local success, result = pcall(function()
		local value, keyInfo = datastore:GetVersionAsync(key, version)
		return {
			value = value,
			keyInfo = keyInfo,
			userIds = keyInfo and keyInfo:GetUserIds() or nil,
			metadata = keyInfo and keyInfo:GetMetadata() or nil,
		}
	end)

	return wrapResult(success, result)
end

-- Set a key's value
function Operations.setKey(
	datastore: DataStore,
	key: string,
	value: JSONValue,
	userIds: { number }?,
	metadata: { [string]: any }?
): Result<DataStoreKeyInfo>
	local success, result = pcall(function()
		local options: DataStoreSetOptions? = nil
		if metadata then
			options = Instance.new("DataStoreSetOptions")
			options:SetMetadata(metadata)
		end

		return datastore:SetAsync(key, value, userIds, options)
	end)

	return wrapResult(success, result)
end

-- Update a key's value with transform function
function Operations.updateKey(
	datastore: DataStore,
	key: string,
	transformFn: (JSONValue) -> JSONValue,
	userIds: { number }?
): Result<JSONValue>
	local success, result = pcall(function()
		return datastore:UpdateAsync(key, function(oldValue)
			return transformFn(oldValue), userIds
		end)
	end)

	return wrapResult(success, result)
end

-- Delete a key
function Operations.deleteKey(datastore: DataStore, key: string): Result<nil>
	local success, result = pcall(function()
		datastore:RemoveAsync(key)
		return nil
	end)

	return wrapResult(success, result)
end

-- Set an ordered key's value
function Operations.setOrderedKey(datastore: OrderedDataStore, key: string, value: number): Result<nil>
	local success, result = pcall(function()
		datastore:SetAsync(key, value)
		return nil
	end)

	return wrapResult(success, result)
end

-- Delete an ordered key
function Operations.deleteOrderedKey(datastore: OrderedDataStore, key: string): Result<nil>
	local success, result = pcall(function()
		datastore:RemoveAsync(key)
		return nil
	end)

	return wrapResult(success, result)
end

-- List versions of a key
function Operations.listVersions(
	datastore: DataStore,
	key: string,
	sortDirection: Enum.SortDirection?,
	minDate: number?,
	maxDate: number?
): Result<{ versions: { VersionInfo }, hasMore: boolean }>
	local success, result = pcall(function()
		local pages = datastore:ListVersionsAsync(key, sortDirection, minDate, maxDate)
		local items = pages:GetCurrentPage()

		local versions: { VersionInfo } = {}
		for _, item in items do
			table.insert(versions, {
				version = item.Version,
				createdTime = item.CreatedTime,
				isDeleted = item.IsDeleted,
			})
		end

		return { versions = versions, hasMore = not pages.IsFinished }
	end)

	return wrapResult(success, result)
end

-- Check budget for a request type
function Operations.hasBudget(requestType: Enum.DataStoreRequestType, count: number?): boolean
	local budget = DataStoreService:GetRequestBudgetForRequestType(requestType)
	return budget >= (count or 1)
end

-- Get current budget
function Operations.getBudget(requestType: Enum.DataStoreRequestType): number
	return DataStoreService:GetRequestBudgetForRequestType(requestType)
end

-- Validate DataStore name
function Operations.validateDataStoreName(name: string): (boolean, string?)
	if #name == 0 then
		return false, "Name cannot be empty"
	end
	if #name > 50 then
		return false, "Name cannot exceed 50 characters"
	end
	return true, nil
end

-- Validate scope
function Operations.validateScope(scope: string): (boolean, string?)
	if #scope > 50 then
		return false, "Scope cannot exceed 50 characters"
	end
	return true, nil
end

-- Validate key
function Operations.validateKey(key: string): (boolean, string?)
	if #key == 0 then
		return false, "Key cannot be empty"
	end
	if #key > 50 then
		return false, "Key cannot exceed 50 characters"
	end
	return true, nil
end

-- Validate all-scopes key format (scope/key)
function Operations.validateAllScopesKey(key: string): (boolean, string?)
	local slashPos = string.find(key, "/")
	if not slashPos then
		return false, "All-scopes key must be in format: scope/key"
	end
	local scope = string.sub(key, 1, slashPos - 1)
	local keyName = string.sub(key, slashPos + 1)

	local scopeValid, scopeError = Operations.validateScope(scope)
	if not scopeValid then
		return false, scopeError
	end

	local keyValid, keyError = Operations.validateKey(keyName)
	if not keyValid then
		return false, keyError
	end

	return true, nil
end

-- Parse all-scopes key
function Operations.parseAllScopesKey(key: string)
	local slashPos = string.find(key, "/")
	if not slashPos then
		return nil, nil
	end

	return string.sub(key, 1, slashPos - 1), string.sub(key, slashPos + 1)
end

return Operations
