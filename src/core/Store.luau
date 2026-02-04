--!strict
--[[
	DataScope Store
	Centralized reactive state management using Vide
]]

local Vide = require(script.Parent.Parent.Packages.Vide)
local Types = require(script.Parent.Types)
local Functional = require(script.Parent.Parent.utils.Functional)

local source = Vide.source
local derive = Vide.derive
local root = Vide.root

type ConnectionInfo = Types.ConnectionInfo
type KeyData = Types.KeyData
type HistoryRecord = Types.HistoryRecord
type Settings = Types.Settings
type Toast = Types.Toast
type UndoAction = Types.UndoAction
type JSONValue = Types.JSONValue

local MAX_UNDO_STACK = 64
local MAX_HISTORY_RECORDS = 32

-- Default settings
local defaultSettings: Settings = {
	themePreset = "Dark",
	themeAccent = "blue",
	hideGameName = true,
	highlightColors = "Default",
	useAlternatingKeyColors = true,
	listDeletedKeys = false,
	automaticallyList = true,
	clickToOpen = false,
	viewerMode = "Tree",
	bufferViewerMode = "Hex",
}

local Store = {}

-- Plugin reference (set from main.server.luau)
Store.plugin = nil :: Plugin?

-- Core reactive state
Store.currentView = source("connect") -- "connect" | "browse" | "editKey" | "versions" | "settings" | "ordered"
Store.currentTab = source("connect") -- "connect" | "list" | "history"

-- Connection state
Store.connection = source(nil :: ConnectionInfo?)
Store.isConnecting = source(false)
Store.connectionError = source(nil :: string?)

-- DataStore browsing state
Store.datastoreList = source({} :: { string })
Store.datastoreListLoading = source(false)
Store.datastoreListError = source(nil :: string?)
Store.datastorePrefix = source("")
Store.hasMoreDatastores = source(false)

-- Key browsing state
Store.keyList = source({} :: { Types.KeyInfo })
Store.keyListLoading = source(false)
Store.keyListError = source(nil :: string?)
Store.keyPrefix = source("")
Store.hasMoreKeys = source(false)

-- Ordered DataStore state
Store.orderedKeyList = source({} :: { Types.OrderedKeyInfo })
Store.orderedKeyListLoading = source(false)
Store.orderedRangeMin = source(nil :: number?)
Store.orderedRangeMax = source(nil :: number?)
Store.orderedAscending = source(false)

-- Current key editing state
Store.currentKey = source(nil :: string?)
Store.currentKeyData = source(nil :: KeyData?)
Store.currentVersion = source(nil :: string?)
Store.isLoadingKey = source(false)
Store.isSavingKey = source(false)
Store.keyError = source(nil :: string?)
Store.isReadOnly = source(false)
Store.rawDataSize = source(nil :: number?) -- Size of raw data before hook decompression

-- Editing state
Store.editedData = source(nil :: JSONValue)
Store.hasUnsavedChanges = source(false)
Store.undoStack = source({} :: { UndoAction })
Store.redoStack = source({} :: { UndoAction })

-- Search state
Store.searchQuery = source("")
Store.searchMode = source("all" :: "all" | "content" | "keys" | "values" | "type" | "regex")
Store.searchResults = source({} :: { { string | number } }) -- Array of paths that match
Store.currentSearchIndex = source(0)

-- Version browsing state
Store.versionList = source({} :: { Types.VersionInfo })
Store.versionListLoading = source(false)
Store.hasMoreVersions = source(false)

-- History state
Store.history = source({} :: { HistoryRecord })

-- Settings state
Store.settings = source(Functional.deepClone(defaultSettings))

-- Toast notifications
Store.toasts = source({} :: { Toast })

-- Modal state
Store.modalContent = source(nil :: (() -> Instance)?)

-- Derived state (initialized in root scope)
Store.isModalOpen = nil :: any
Store.isConnected = nil :: any
Store.canUndo = nil :: any
Store.canRedo = nil :: any
Store.searchResultCount = nil :: any
Store.currentSearchResult = nil :: any

-- Initialize derived state in a stable scope
root(function()
	Store.isModalOpen = derive(function()
		return Store.modalContent() ~= nil
	end)

	Store.isConnected = derive(function()
		return Store.connection() ~= nil
	end)

	Store.canUndo = derive(function()
		return #Store.undoStack() > 0
	end)

	Store.canRedo = derive(function()
		return #Store.redoStack() > 0
	end)

	Store.searchResultCount = derive(function()
		return #Store.searchResults()
	end)

	Store.currentSearchResult = derive(function()
		local results = Store.searchResults()
		local index = Store.currentSearchIndex()
		if index > 0 and index <= #results then
			return results[index]
		end
		return nil
	end)
end)

-- Actions
function Store.setView(view: string)
	Store.currentView(view)
end

function Store.setTab(tab: string)
	Store.currentTab(tab)
end

function Store.setConnection(info: ConnectionInfo?)
	Store.connection(info)
	Store.connectionError(nil)
	if info then
		Store.addHistoryRecord(info)
	end
end

function Store.setConnectionError(error: string?)
	Store.connectionError(error)
end

function Store.disconnect()
	Store.connection(nil)
	Store.currentKey(nil)
	Store.currentKeyData(nil)
	Store.currentVersion(nil)
	Store.editedData(nil)
	Store.hasUnsavedChanges(false)
	Store.undoStack({})
	Store.redoStack({})
	Store.keyList({})
	Store.datastoreList({})
	Store.searchQuery("")
	Store.searchResults({})
	Store.currentSearchIndex(0)
	Store.setView("connect")
end

function Store.setCurrentKey(key: string?, data: KeyData?, rawSize: number?)
	Store.currentKey(key)
	Store.currentKeyData(data)
	Store.currentVersion(nil)
	Store.editedData(data and Functional.deepClone(data.value) or nil)
	Store.hasUnsavedChanges(false)
	Store.undoStack({})
	Store.redoStack({})
	Store.searchQuery("")
	Store.searchResults({})
	Store.currentSearchIndex(0)
	Store.rawDataSize(rawSize)
end

function Store.setEditedData(data: JSONValue)
	Store.editedData(data)
	Store.hasUnsavedChanges(true)
end

function Store.updateEditedDataAtPath(path: { string | number }, value: JSONValue)
	local currentData = Store.editedData()
	if currentData == nil then
		return
	end

	local oldValue = Functional.getPath(currentData, path)
	local newData = Functional.setPath(currentData, path, value)

	-- Push to undo stack
	local undoAction: UndoAction = {
		type = "set",
		path = path,
		oldValue = Functional.deepClone(oldValue),
		newValue = Functional.deepClone(value),
	}
	Store.pushUndo(undoAction)

	Store.editedData(newData)
	Store.hasUnsavedChanges(true)
end

function Store.deleteAtPath(path: { string | number })
	local currentData = Store.editedData()
	if currentData == nil then
		return
	end

	local oldValue = Functional.getPath(currentData, path)
	local newData = Functional.deletePath(currentData, path)

	local undoAction: UndoAction = {
		type = "delete",
		path = path,
		oldValue = Functional.deepClone(oldValue),
	}
	Store.pushUndo(undoAction)

	Store.editedData(newData)
	Store.hasUnsavedChanges(true)
end

function Store.insertAtPath(path: { string | number }, key: string | number, value: JSONValue)
	local currentData = Store.editedData()
	if currentData == nil then
		return
	end

	local targetPath = Functional.deepClone(path)
	table.insert(targetPath, key)

	local newData = Functional.setPath(currentData, targetPath, value)

	local undoAction: UndoAction = {
		type = "insert",
		path = targetPath,
		newValue = Functional.deepClone(value),
		newKey = key,
	}
	Store.pushUndo(undoAction)

	Store.editedData(newData)
	Store.hasUnsavedChanges(true)
end

function Store.pushUndo(action: UndoAction)
	local stack = Store.undoStack()
	local newStack = Functional.deepClone(stack)
	table.insert(newStack, action)

	-- Limit stack size
	while #newStack > MAX_UNDO_STACK do
		table.remove(newStack, 1)
	end

	Store.undoStack(newStack)
	Store.redoStack({}) -- Clear redo stack on new action
end

function Store.undo()
	local undoStackVal = Store.undoStack()
	if #undoStackVal == 0 then
		return
	end

	local action = undoStackVal[#undoStackVal]
	local newUndoStack = Functional.take(undoStackVal, #undoStackVal - 1)
	Store.undoStack(newUndoStack)

	local currentData = Store.editedData()
	local newData: JSONValue

	if action.type == "set" then
		newData = Functional.setPath(currentData, action.path, action.oldValue)
	elseif action.type == "delete" then
		newData = Functional.setPath(currentData, action.path, action.oldValue)
	elseif action.type == "insert" then
		newData = Functional.deletePath(currentData, action.path)
	else
		return
	end

	-- Push to redo stack
	local redoStackVal = Store.redoStack()
	local newRedoStack = Functional.deepClone(redoStackVal)
	table.insert(newRedoStack, action)
	Store.redoStack(newRedoStack)

	Store.editedData(newData)
	
	-- Check if we're back to the original state
	local keyData = Store.currentKeyData()
	local originalValue = keyData and keyData.value or nil
	Store.hasUnsavedChanges(not Functional.deepEquals(newData, originalValue))
end

function Store.redo()
	local redoStackVal = Store.redoStack()
	if #redoStackVal == 0 then
		return
	end

	local action = redoStackVal[#redoStackVal]
	local newRedoStack = Functional.take(redoStackVal, #redoStackVal - 1)
	Store.redoStack(newRedoStack)

	local currentData = Store.editedData()
	local newData: JSONValue

	if action.type == "set" then
		newData = Functional.setPath(currentData, action.path, action.newValue)
	elseif action.type == "delete" then
		newData = Functional.deletePath(currentData, action.path)
	elseif action.type == "insert" then
		newData = Functional.setPath(currentData, action.path, action.newValue)
	else
		return
	end

	-- Push back to undo stack
	local undoStackVal = Store.undoStack()
	local newUndoStack = Functional.deepClone(undoStackVal)
	table.insert(newUndoStack, action)
	Store.undoStack(newUndoStack)

	Store.editedData(newData)
	
	-- Check if we're back to the original state
	local keyData = Store.currentKeyData()
	local originalValue = keyData and keyData.value or nil
	Store.hasUnsavedChanges(not Functional.deepEquals(newData, originalValue))
end

function Store.discardChanges()
	local keyData = Store.currentKeyData()
	if keyData then
		Store.editedData(Functional.deepClone(keyData.value))
	end
	Store.hasUnsavedChanges(false)
	Store.undoStack({})
	Store.redoStack({})
end

-- Search functions
export type SearchMode = "all" | "content" | "keys" | "values" | "type" | "regex" | "size"

function Store.setSearchMode(mode: SearchMode)
	Store.searchMode(mode)
	-- Re-run search with new mode (deferred to avoid reactive scope conflicts)
	local query = Store.searchQuery()
	if query ~= "" then
		task.defer(function()
			Store.performSearch(query)
		end)
	end
end

function Store.setSearchQuery(query: string)
	Store.searchQuery(query)
	-- Defer search to avoid updating sources while a reactive scope is active
	task.defer(function()
		Store.performSearch(query)
	end)
end

function Store.performSearch(query: string)
	if query == "" then
		Store.searchResults({})
		Store.currentSearchIndex(0)
		return
	end

	local data = Store.editedData()
	if data == nil then
		Store.searchResults({})
		Store.currentSearchIndex(0)
		return
	end

	local results: { { string | number } } = {}
	local mode = Store.searchMode()
	local lowerQuery = string.lower(query)

	-- For regex mode, compile the pattern
	local regexPattern: string? = nil
	if mode == "regex" then
		local success, _ = pcall(function()
			string.find("test", query)
		end)
		if success then
			regexPattern = query
		end
	end

	-- Size matching helpers
	local function countDescendants(value: any): number
		if type(value) ~= "table" then
			return 0
		end
		local count = 0
		for _, v in value :: any do
			count += 1
			count += countDescendants(v)
		end
		return count
	end

	-- Parse size query: >100, <50, >=100, <=50, 10-100, 50
	local sizeOperator: string? = nil
	local sizeValue1: number? = nil
	local sizeValue2: number? = nil -- For range queries
	if mode == "size" then
		local trimmedQuery = query:gsub("%s+", "") -- Remove whitespace
		
		-- Check for range (e.g., "10-100" or "10..100")
		local rangeMin, rangeMax = trimmedQuery:match("^(%d+)%-(%d+)$")
		if not rangeMin then
			rangeMin, rangeMax = trimmedQuery:match("^(%d+)%.%.(%d+)$")
		end
		
		if rangeMin and rangeMax then
			sizeOperator = "range"
			sizeValue1 = tonumber(rangeMin)
			sizeValue2 = tonumber(rangeMax)
		else
			-- Check for comparison operators
			local op, num = trimmedQuery:match("^([><=!]+)(%d+)$")
			if op and num then
				sizeOperator = op
				sizeValue1 = tonumber(num)
			else
				-- Just a number means exact match
				local exactNum = tonumber(trimmedQuery)
				if exactNum then
					sizeOperator = "="
					sizeValue1 = exactNum
				end
			end
		end
	end

	local function matchesSize(value: any): boolean
		if type(value) ~= "table" then
			return false -- Size only applies to tables
		end
		if not sizeOperator or not sizeValue1 then
			return false
		end
		
		local count = countDescendants(value)
		
		if sizeOperator == "range" and sizeValue2 then
			return count >= sizeValue1 and count <= sizeValue2
		elseif sizeOperator == ">" then
			return count > sizeValue1
		elseif sizeOperator == ">=" then
			return count >= sizeValue1
		elseif sizeOperator == "<" then
			return count < sizeValue1
		elseif sizeOperator == "<=" then
			return count <= sizeValue1
		elseif sizeOperator == "=" or sizeOperator == "==" then
			return count == sizeValue1
		elseif sizeOperator == "!=" or sizeOperator == "~=" then
			return count ~= sizeValue1
		end
		
		return false
	end

	-- Type matching helper
	local function matchesType(value: any): boolean
		local typeStr = string.lower(typeof(value))
		local valueType = type(value)

		-- Handle specific type queries
		if lowerQuery == "string" then
			return valueType == "string"
		elseif lowerQuery == "number" or lowerQuery == "int" or lowerQuery == "integer" then
			return valueType == "number"
		elseif lowerQuery == "boolean" or lowerQuery == "bool" then
			return valueType == "boolean"
		elseif lowerQuery == "table" or lowerQuery == "object" then
			return valueType == "table" and not Functional.isEmpty(value) and type(next(value :: any)) ~= "number"
		elseif lowerQuery == "array" or lowerQuery == "list" then
			return valueType == "table" and (Functional.isEmpty(value) or type(next(value :: any)) == "number")
		elseif lowerQuery == "null" or lowerQuery == "nil" then
			return value == nil
		elseif lowerQuery == "buffer" then
			return typeof(value) == "buffer"
		end

		return string.find(typeStr, lowerQuery, 1, true) ~= nil
	end

	-- Content matching - exact substring match in serialized form
	local function matchesContent(value: any): boolean
		if type(value) == "table" then
			-- For content mode, serialize the table and search
			local success, json = pcall(function()
				return game:GetService("HttpService"):JSONEncode(value)
			end)
			if success then
				return string.find(string.lower(json), lowerQuery, 1, true) ~= nil
			end
			return false
		else
			local valueStr = tostring(value)
			return string.find(string.lower(valueStr), lowerQuery, 1, true) ~= nil
		end
	end

	-- Key matching
	local function matchesKey(key: string | number): boolean
		local keyStr = string.lower(tostring(key))
		if mode == "regex" and regexPattern then
			return string.find(keyStr, regexPattern) ~= nil
		end
		return string.find(keyStr, lowerQuery, 1, true) ~= nil
	end

	-- Value matching (leaf values only)
	local function matchesValue(value: any): boolean
		if type(value) == "table" then
			return false -- Only match leaf values in "values" mode
		end
		local valueStr = string.lower(tostring(value))
		if mode == "regex" and regexPattern then
			return string.find(valueStr, regexPattern) ~= nil
		end
		return string.find(valueStr, lowerQuery, 1, true) ~= nil
	end

	local function searchNode(value: any, path: { string | number })
		if type(value) == "table" then
			-- For content mode, check if the entire table matches
			if mode == "content" then
				if matchesContent(value) then
					-- Check if this specific node matches, not just children
					local tableJson = game:GetService("HttpService"):JSONEncode(value)
					if string.find(string.lower(tableJson), lowerQuery, 1, true) then
						-- Add if it's a direct match at this level
						local directMatch = false
						for k, v in value do
							if type(v) ~= "table" then
								if string.find(string.lower(tostring(v)), lowerQuery, 1, true) then
									directMatch = true
									break
								end
							end
							if string.find(string.lower(tostring(k)), lowerQuery, 1, true) then
								directMatch = true
								break
							end
						end
						if directMatch and #path > 0 then
							table.insert(results, Functional.deepClone(path))
						end
					end
				end
			end

			for k, v in value do
				local newPath = Functional.deepClone(path)
				table.insert(newPath, k)

				local shouldAdd = false

				if mode == "all" then
					-- Match both keys and values
					if matchesKey(k) or (type(v) ~= "table" and matchesValue(v)) then
						shouldAdd = true
					end
				elseif mode == "keys" then
					if matchesKey(k) then
						shouldAdd = true
					end
				elseif mode == "values" then
					if type(v) ~= "table" and matchesValue(v) then
						shouldAdd = true
					end
				elseif mode == "type" then
					if matchesType(v) then
						shouldAdd = true
					end
				elseif mode == "content" then
					-- For content, match values directly
					if type(v) ~= "table" and matchesContent(v) then
						shouldAdd = true
					end
				elseif mode == "regex" and regexPattern then
					local keyStr = tostring(k)
					local valueStr = if type(v) ~= "table" then tostring(v) else ""
					if string.find(keyStr, regexPattern) or string.find(valueStr, regexPattern) then
						shouldAdd = true
					end
				elseif mode == "size" then
					if matchesSize(v) then
						shouldAdd = true
					end
				end

				if shouldAdd then
					-- Check not already added
					local alreadyAdded = Functional.some(results, function(r)
						if #r ~= #newPath then
							return false
						end
						for i, p in r do
							if p ~= newPath[i] then
								return false
							end
						end
						return true
					end)
					if not alreadyAdded then
						table.insert(results, newPath)
					end
				end

				-- Recurse into children
				searchNode(v, newPath)
			end
		end
	end

	searchNode(data, {})
	Store.searchResults(results)
	Store.currentSearchIndex(if #results > 0 then 1 else 0)
end

function Store.prevSearchResult()
	local results = Store.searchResults()
	local current = Store.currentSearchIndex()
	if #results == 0 then
		return
	end

	local prev = current - 1
	if prev < 1 then
		prev = #results
	end
	Store.currentSearchIndex(prev)
end

function Store.nextSearchResult()
	local results = Store.searchResults()
	local current = Store.currentSearchIndex()
	if #results == 0 then
		return
	end

	local next = current + 1
	if next > #results then
		next = 1
	end
	Store.currentSearchIndex(next)
end

-- History functions
function Store.addHistoryRecord(connectionInfo: ConnectionInfo)
	local historyVal = Store.history()
	local newHistory = Functional.filter(historyVal, function(record)
		return record.connectionInfo.name ~= connectionInfo.name
			or record.connectionInfo.scope ~= connectionInfo.scope
			or record.connectionInfo.datastoreType ~= connectionInfo.datastoreType
	end)

	table.insert(newHistory, 1, {
		connectionInfo = connectionInfo,
		timestamp = os.time(),
		pinned = false,
	})

	-- Sort: pinned first, then by timestamp
	table.sort(newHistory, function(a, b)
		if a.pinned ~= b.pinned then
			return a.pinned
		end
		return a.timestamp > b.timestamp
	end)

	-- Limit history
	while #newHistory > MAX_HISTORY_RECORDS do
		-- Remove oldest unpinned
		for i = #newHistory, 1, -1 do
			if not newHistory[i].pinned then
				table.remove(newHistory, i)
				break
			end
		end
	end

	Store.history(newHistory)
end

function Store.toggleHistoryPin(index: number)
	local historyVal = Store.history()
	if index < 1 or index > #historyVal then
		return
	end

	local newHistory = Functional.deepClone(historyVal)
	newHistory[index].pinned = not newHistory[index].pinned

	-- Re-sort
	table.sort(newHistory, function(a, b)
		if a.pinned ~= b.pinned then
			return a.pinned
		end
		return a.timestamp > b.timestamp
	end)

	Store.history(newHistory)
end

function Store.removeHistoryRecord(index: number)
	local historyVal = Store.history()
	if index < 1 or index > #historyVal then
		return
	end

	local newHistory = Functional.deepClone(historyVal)
	table.remove(newHistory, index)
	Store.history(newHistory)
end

function Store.clearHistory()
	local historyVal = Store.history()
	-- Keep pinned items
	local pinned = Functional.filter(historyVal, function(r)
		return r.pinned
	end)
	Store.history(pinned)
end

-- Settings functions
function Store.updateSetting<T>(key: string, value: T)
	local settingsVal = Store.settings()
	local newSettings = Functional.deepClone(settingsVal)
	;(newSettings :: any)[key] = value
	Store.settings(newSettings)
end

function Store.resetSettings()
	Store.settings(Functional.deepClone(defaultSettings))
end

-- Toast functions
local toastIdCounter = 0

function Store.showToast(toastType: Types.ToastType, message: string, duration: number?)
	toastIdCounter += 1
	local id = tostring(toastIdCounter)

	local toast: Toast = {
		id = id,
		type = toastType,
		message = message,
		duration = duration or 5,
	}

	local toastsVal = Store.toasts()
	local newToasts = Functional.deepClone(toastsVal)
	table.insert(newToasts, toast)
	Store.toasts(newToasts)

	-- Auto-remove after duration
	task.delay(toast.duration :: number, function()
		Store.dismissToast(id)
	end)

	return id
end

function Store.dismissToast(id: string)
	local toastsVal = Store.toasts()
	local newToasts = Functional.filter(toastsVal, function(t)
		return t.id ~= id
	end)
	Store.toasts(newToasts)
end

-- Modal functions
function Store.openModal(content: () -> Instance)
	Store.modalContent(content)
end

function Store.closeModal()
	Store.modalContent(nil)
end

-- Utility to get default settings
function Store.getDefaultSettings(): Settings
	return Functional.deepClone(defaultSettings)
end

return Store
