--!strict
--[[
	DataScope Store
	Centralized reactive state management using Vide
]]

local Vide = require(script.Parent.Parent.Packages.Vide)
local Types = require(script.Parent.Types)
local Functional = require(script.Parent.Parent.utils.Functional)
local PatternMatcher = require(script.Parent.Parent.utils.PatternMatcher)
local QueryEngine = require(script.Parent.QueryEngine)
local Operations = require(script.Parent.Parent.datastore.Operations)
local KeyViewLoader = require(script.Parent.Parent.datastore.KeyViewLoader)

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
type DiffViewState = Types.DiffViewState

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
Store.currentView = source("connect") -- "connect" | "browse" | "editKey" | "versions" | "settings" | "ordered" | "query"
Store.previousView = source("browse") -- tracks where we came from for back navigation
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
Store.searchMode = source("all" :: "all" | "content" | "keys" | "values" | "type")
Store.useRegex = source(false)
Store.searchResults = source({} :: { { string | number } }) -- Array of paths that match
Store.currentSearchIndex = source(0)
Store.searchError = source("" :: string) -- Non-empty when regex is enabled with an invalid pattern

-- Version browsing state
Store.versionList = source({} :: { Types.VersionInfo })
Store.versionListLoading = source(false)
Store.hasMoreVersions = source(false)

-- Diff view state (used by EditKeyView when comparing two versions)
Store.diffView = source(nil :: DiffViewState?)

-- Query view state
Store.queryExpression = source("")
Store.queryKeyListText = source("")
Store.queryResults = source({} :: { Types.QueryResult })
Store.querySelectedIndex = source(0)
Store.queryIsRunning = source(false)
Store.queryCancelled = source(false)
Store.queryProgress = source(0)
Store.queryTotal = source(0)
Store.queryError = source(nil :: string?)
Store.queryVersionMode = source(false)
Store.queryVersionSeconds = source(3600)

-- History state
Store.history = source({} :: { HistoryRecord })
Store.onHistoryChanged = nil :: (() -> ())?

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
Store.querySelectedResult = nil :: any

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

	Store.querySelectedResult = derive(function()
		local results = Store.queryResults()
		local idx = Store.querySelectedIndex()
		if idx > 0 and idx <= #results then
			return results[idx]
		end
		return nil
	end)
end)

-- Actions
function Store.setView(view: string)
	Store.previousView(Store.currentView())
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
	Store.diffView(nil)
	Store.editedData(nil)
	Store.hasUnsavedChanges(false)
	Store.undoStack({})
	Store.redoStack({})
	Store.keyList({})
	Store.datastoreList({})
	Store.searchQuery("")
	Store.searchResults({})
	Store.currentSearchIndex(0)
	Store.queryExpression("")
	Store.queryKeyListText("")
	Store.queryResults({})
	Store.querySelectedIndex(0)
	Store.queryIsRunning(false)
	Store.queryCancelled(true)
	Store.queryProgress(0)
	Store.queryTotal(0)
	Store.queryError(nil)
	Store.queryVersionMode(false)
	Store.currentTab("connect")
	Store.setView("connect")
end

function Store.setCurrentKey(key: string?, data: KeyData?, rawSize: number?)
	Store.currentKey(key)
	Store.currentKeyData(data)
	Store.currentVersion(nil)
	Store.diffView(nil)
	
	local clonedValue = data and Functional.deepClone(data.value) or nil

	Store.editedData(clonedValue)
	Store.hasUnsavedChanges(false)
	Store.undoStack({})
	Store.redoStack({})
	Store.searchQuery("")
	Store.searchResults({})
	Store.currentSearchIndex(0)
	Store.rawDataSize(rawSize)
	Store.versionList({})
	Store.hasMoreVersions(false)
	Store.versionListLoading(false)
end

function Store.setDiffView(state: DiffViewState?)
	Store.diffView(state)
end

function Store.clearDiffView()
	Store.diffView(nil)
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
export type SearchMode = "all" | "content" | "keys" | "values" | "type" | "size"

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

function Store.setUseRegex(enabled: boolean)
	Store.useRegex(enabled)
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

	-- Regex toggle: compile pattern when enabled
	local useRegex = Store.useRegex()
	local compiled: PatternMatcher.CompiledPattern? = nil
	if useRegex then
		local c = PatternMatcher.compile(query)
		if not c.valid then
			Store.searchError(c.error or "Invalid pattern")
			Store.searchResults({})
			Store.currentSearchIndex(0)
			return
		end
		Store.searchError(c.warning or "")
		compiled = c
	else
		Store.searchError("")
	end

	-- ── Pre-compute mode flags (avoid string comparisons in hot loop) ──
	local M_ALL     = mode == "all"
	local M_KEYS    = mode == "keys"
	local M_VALUES  = mode == "values"
	local M_CONTENT = mode == "content"
	local M_TYPE    = mode == "type"
	local M_SIZE    = mode == "size"
	local M_REGEX   = useRegex and compiled ~= nil

	-- ── Cache stdlib functions as upvalues ──
	local sfind = string.find
	local slower = string.lower
	local stostring = tostring
	local ttype = type
	local pmTest = PatternMatcher.test

	-- ── Mutable path stack: push/pop instead of copy-per-node ──
	local pathStack: { string | number } = {}
	local depth = 0

	-- Snapshot current path (only called on match — the rare path)
	local function addMatch()
		results[#results + 1] = table.move(pathStack, 1, depth, 1, table.create(depth))
	end

	-- ── Size mode helpers ──
	local sizeOp: string? = nil
	local sizeVal1: number? = nil
	local sizeVal2: number? = nil
	if M_SIZE then
		local trimmed = query:gsub("%s+", "")
		local rMin, rMax = trimmed:match("^(%d+)%-(%d+)$")
		if not rMin then rMin, rMax = trimmed:match("^(%d+)%.%.(%d+)$") end
		if rMin and rMax then
			sizeOp = "range"
			sizeVal1 = tonumber(rMin)
			sizeVal2 = tonumber(rMax)
		else
			local op, num = trimmed:match("^([><=!]+)(%d+)$")
			if op and num then
				sizeOp = op
				sizeVal1 = tonumber(num)
			else
				local exact = tonumber(trimmed)
				if exact then
					sizeOp = "="
					sizeVal1 = exact
				end
			end
		end
	end

	local function countDescendants(value: any): number
		if ttype(value) ~= "table" then return 0 end
		local count = 0
		for _, v in value :: any do
			count += 1
			count += countDescendants(v)
		end
		return count
	end

	local function matchesSize(value: any): boolean
		if ttype(value) ~= "table" or not sizeOp or not sizeVal1 then return false end
		local count = countDescendants(value)
		if sizeOp == "range" then return sizeVal2 ~= nil and count >= sizeVal1 and count <= sizeVal2
		elseif sizeOp == ">" then return count > sizeVal1
		elseif sizeOp == ">=" then return count >= sizeVal1
		elseif sizeOp == "<" then return count < sizeVal1
		elseif sizeOp == "<=" then return count <= sizeVal1
		elseif sizeOp == "=" or sizeOp == "==" then return count == sizeVal1
		elseif sizeOp == "!=" or sizeOp == "~=" then return count ~= sizeVal1
		end
		return false
	end

	-- ── Type matching helper ──
	local function matchesType(value: any): boolean
		local valueType = ttype(value)
		if lowerQuery == "string" then return valueType == "string"
		elseif lowerQuery == "number" or lowerQuery == "int" or lowerQuery == "integer" then return valueType == "number"
		elseif lowerQuery == "boolean" or lowerQuery == "bool" then return valueType == "boolean"
		elseif lowerQuery == "table" or lowerQuery == "object" then
			return valueType == "table" and not Functional.isEmpty(value) and ttype(next(value :: any)) ~= "number"
		elseif lowerQuery == "array" or lowerQuery == "list" then
			return valueType == "table" and (Functional.isEmpty(value) or ttype(next(value :: any)) == "number")
		elseif lowerQuery == "null" or lowerQuery == "nil" then return value == nil
		elseif lowerQuery == "buffer" then return typeof(value) == "buffer"
		end
		return sfind(slower(typeof(value)), lowerQuery, 1, true) ~= nil
	end

	-- ── Main traversal ──
	local function searchNode(node: any)
		if ttype(node) ~= "table" then return end

		for k, v in node do
			depth += 1
			pathStack[depth] = k

			local hit = false
			local vIsTable = ttype(v) == "table"

			if M_ALL then
				local keyLower = slower(stostring(k))
				if M_REGEX then
					hit = pmTest(compiled :: any, keyLower)
					if not hit and not vIsTable then
						hit = pmTest(compiled :: any, slower(stostring(v)))
					end
				else
					hit = sfind(keyLower, lowerQuery, 1, true) ~= nil
					if not hit and not vIsTable then
						hit = sfind(slower(stostring(v)), lowerQuery, 1, true) ~= nil
					end
				end

			elseif M_KEYS then
				local keyLower = slower(stostring(k))
				hit = if M_REGEX
					then pmTest(compiled :: any, keyLower)
					else sfind(keyLower, lowerQuery, 1, true) ~= nil

			elseif M_VALUES then
				if not vIsTable then
					local valLower = slower(stostring(v))
					hit = if M_REGEX
						then pmTest(compiled :: any, valLower)
						else sfind(valLower, lowerQuery, 1, true) ~= nil
				end

			elseif M_CONTENT then
				if not vIsTable then
					local valLower = slower(stostring(v))
					hit = if M_REGEX
						then pmTest(compiled :: any, valLower)
						else sfind(valLower, lowerQuery, 1, true) ~= nil
				end

			elseif M_TYPE then
				hit = matchesType(v)

			elseif M_SIZE then
				hit = matchesSize(v)
			end

			if hit then
				addMatch()
			end

			searchNode(v)
			depth -= 1
		end
	end

	searchNode(data)
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
local function notifyHistoryChanged()
	if Store.onHistoryChanged then
		Store.onHistoryChanged()
	end
end

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
	notifyHistoryChanged()
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
	notifyHistoryChanged()
end

function Store.removeHistoryRecord(index: number)
	local historyVal = Store.history()
	if index < 1 or index > #historyVal then
		return
	end

	local newHistory = Functional.deepClone(historyVal)
	table.remove(newHistory, index)
	Store.history(newHistory)
	notifyHistoryChanged()
end

function Store.clearHistory()
	local historyVal = Store.history()
	-- Keep pinned items
	local pinned = Functional.filter(historyVal, function(r)
		return r.pinned
	end)
	Store.history(pinned)
	notifyHistoryChanged()
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

-- Query functions
function Store.startQuery()
	local expression = Store.queryExpression()
	local keyListText = Store.queryKeyListText()
	local connection = Store.connection()

	if not connection then
		Store.queryError("Not connected to a DataStore")
		return
	end

	-- Parse expression
	local parseResult = QueryEngine.parse(expression)
	if not parseResult.success or not parseResult.ast then
		Store.queryError(parseResult.error or "Invalid expression")
		return
	end

	local ast = parseResult.ast

	-- Parse key list (split by newlines and commas, trim whitespace)
	local keys: { string } = {}
	for line in string.gmatch(keyListText, "[^\n]+") do
		for key in string.gmatch(line, "[^,]+") do
			local trimmed = string.match(key, "^%s*(.-)%s*$")
			if trimmed and trimmed ~= "" then
				table.insert(keys, trimmed)
			end
		end
	end

	if #keys == 0 then
		Store.queryError("No keys provided")
		return
	end

	-- Get DataStore
	local dsResult = Operations.getDataStore(connection)
	if not dsResult.success then
		Store.queryError(`Failed to get DataStore: {dsResult.error}`)
		return
	end
	local datastore = dsResult.value :: DataStore

	-- Reset state
	Store.queryResults({})
	Store.querySelectedIndex(0)
	Store.queryProgress(0)
	Store.queryTotal(#keys)
	Store.queryError(nil)
	Store.queryIsRunning(true)
	Store.queryCancelled(false)

	local versionMode = Store.queryVersionMode()
	local versionSeconds = Store.queryVersionSeconds()

	task.spawn(function()
		for i, keyName in keys do
			-- Check cancellation
			if Store.queryCancelled() then
				break
			end

			-- Check budget with retry
			local budgetRetries = 0
			while not Operations.hasBudget(Enum.DataStoreRequestType.GetAsync) do
				if budgetRetries >= 10 then
					break
				end
				budgetRetries += 1
				task.wait(1 * budgetRetries)
			end

			-- Fetch key data
			local keyResult = Operations.getKey(datastore, keyName)
			if not keyResult.success then
				-- Add error result
				local results = Functional.deepClone(Store.queryResults())
				table.insert(results, {
					keyName = keyName,
					keyData = nil,
					matched = false,
					matchedPaths = nil,
					summary = "",
					error = keyResult.error or "Failed to fetch",
				} :: Types.QueryResult)
				Store.queryResults(results)
				Store.queryProgress(i)
				task.wait()
				continue
			end

			-- Decompress data via hook system before querying
			local rawKeyData = keyResult.value :: Types.KeyData
			local hookContext = {
				datastoreName = connection.name,
				key = keyName,
				scope = connection.scope,
			}
			local prepared = KeyViewLoader.prepare(rawKeyData, hookContext, false)
			local keyData = prepared.keyData

			-- Fetch versions if version mode is on
			local versions: { QueryEngine.VersionEntry }? = nil
			if versionMode then
				local now = os.time()
				local cutoff = now - versionSeconds
				local versionListResult = Operations.listVersions(datastore, keyName, Enum.SortDirection.Descending, cutoff * 1000)
				if versionListResult.success then
					local versionList = versionListResult.value :: { versions: { Types.VersionInfo }, hasMore: boolean }
					versions = {}
					for _, vInfo in versionList.versions do
						if Store.queryCancelled() then
							break
						end
						-- Wait for budget
						local vBudgetRetries = 0
						while not Operations.hasBudget(Enum.DataStoreRequestType.GetAsync) do
							if vBudgetRetries >= 5 then
								break
							end
							vBudgetRetries += 1
							task.wait(1)
						end
						local vResult = Operations.getKeyVersion(datastore, keyName, vInfo.version)
						if vResult.success then
							local vPrepared = KeyViewLoader.prepare(vResult.value :: Types.KeyData, hookContext, false)
							table.insert(versions :: any, {
								version = vInfo,
								data = vPrepared.keyData,
							})
						end
					end
				end
			end

			-- Evaluate expression
			local context: QueryEngine.EvalContext = {
				data = keyData.value,
				metadata = keyData.metadata,
				keyName = keyName,
				versions = versions,
			}

			local evalResult = QueryEngine.evaluate(ast, context)

			-- Build summary
			local summary = ""
			if evalResult.success then
				if evalResult.value then
					summary = "Matched"
				else
					summary = "No match"
				end
			else
				summary = evalResult.error or "Evaluation error"
			end

			-- Add result
			local results = Functional.deepClone(Store.queryResults())
			table.insert(results, {
				keyName = keyName,
				keyData = keyData,
				matched = evalResult.success and (if evalResult.value then true else false),
				matchedPaths = evalResult.matchedPaths,
				summary = summary,
				error = if not evalResult.success then evalResult.error else nil,
			} :: Types.QueryResult)
			Store.queryResults(results)
			Store.queryProgress(i)
			task.wait()
		end

		Store.queryIsRunning(false)
	end)
end

function Store.cancelQuery()
	Store.queryCancelled(true)
end

function Store.clearQuery()
	Store.queryResults({})
	Store.querySelectedIndex(0)
	Store.queryProgress(0)
	Store.queryTotal(0)
	Store.queryError(nil)
end

function Store.selectQueryResult(index: number)
	Store.querySelectedIndex(index)
end

-- Utility to get default settings
function Store.getDefaultSettings(): Settings
	return Functional.deepClone(defaultSettings)
end

return Store
