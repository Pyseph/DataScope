--!strict
--[[
	Versions View
	Key version history browser + diff launcher.
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Store = require(script.Parent.Parent.Parent.core.Store)
local Types = require(script.Parent.Parent.Parent.core.Types)
local Operations = require(script.Parent.Parent.Parent.datastore.Operations)
local Functional = require(script.Parent.Parent.Parent.utils.Functional)
local Diff = require(script.Parent.Parent.Parent.utils.Diff)
local KeyViewLoader = require(script.Parent.Parent.Parent.datastore.KeyViewLoader)

local Button = require(script.Parent.Parent.components.Button)
local Modal = require(script.Parent.Parent.components.Modal)
local Tooltip = require(script.Parent.Parent.components.Tooltip)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local indexes = Vide.indexes
local spring = Vide.spring
local action = Vide.action

type VersionInfo = Types.VersionInfo
type KeyData = Types.KeyData
type DiffEntry = Diff.DiffEntry
type DiffFieldKind = Types.DiffFieldKind

local function VersionsView(): Frame
	local theme = Theme.get()
	local compareVersionA = source(nil :: string?)
	local compareVersionB = source(nil :: string?)
	local compareLoading = source(false)
	local versionDataCache = source({} :: { [string]: KeyData })

	-- Restore confirmation state
	local restoreConfirmVersion = source(nil :: VersionInfo?)
	local isRestoring = source(false)

	-- Field history scanner state
	type ScanResult = {
		newerVersion: VersionInfo,
		olderVersion: VersionInfo,
		entry: DiffEntry,
	}
	local trackPath = source("")
	local isScanning = source(false)
	local scanCancelled = source(false)
	local scanResults = source({} :: { ScanResult })
	local scanProgress = source(0)
	local scanTotal = source(0)
	local hasScanned = source(false)
	local scanVersionCount = source(0) -- total version pairs compared so far

	-- Load versions
	local loadVersions = function()
		local connection = Store.connection()
		local keyName = Store.currentKey()

		if not connection or not keyName then
			return
		end

		Store.versionListLoading(true)

		local dsResult = Operations.getDataStore(connection)
		if not dsResult.success then
			Store.showToast("error", `Failed to get DataStore: {dsResult.error}`)
			Store.versionListLoading(false)
			return
		end

		local datastore = dsResult.value :: DataStore
		local versionsResult = Operations.listVersions(datastore, keyName, Enum.SortDirection.Descending)

		if versionsResult.success then
			Store.versionList(versionsResult.value.versions)
			Store.hasMoreVersions(versionsResult.value.hasMore)
			versionDataCache({})
		else
			Store.showToast("error", `Failed to load versions: {versionsResult.error}`)
		end

		Store.versionListLoading(false)
	end

	local function getVersionById(versionId: string?): VersionInfo?
		if not versionId then
			return nil
		end
		for _, version in Store.versionList() do
			if version.version == versionId then
				return version
			end
		end
		return nil
	end

	local function getVersionData(versionId: string): (boolean, KeyData?, string?)
		local cache = versionDataCache()
		local cached = cache[versionId]
		if cached then
			return true, cached, nil
		end

		local connection = Store.connection()
		local keyName = Store.currentKey()
		if not connection or not keyName then
			return false, nil, "No active DataStore connection"
		end

		local dsResult = Operations.getDataStore(connection)
		if not dsResult.success then
			return false, nil, dsResult.error
		end

		local datastore = dsResult.value :: DataStore
		local keyResult = Operations.getKeyVersion(datastore, keyName, versionId)
		if not keyResult.success then
			return false, nil, keyResult.error
		end

		local newCache = Functional.deepClone(cache)
		newCache[versionId] = keyResult.value
		versionDataCache(newCache)

		return true, keyResult.value, nil
	end

	local function restoreVersion(versionId: string)
		local connection = Store.connection()
		local keyName = Store.currentKey()
		if not connection or not keyName then
			Store.showToast("error", "No active DataStore connection")
			return
		end

		isRestoring(true)
		local ok, data, err = getVersionData(versionId)
		if not ok or not data then
			Store.showToast("error", err or "Failed to load version data")
			isRestoring(false)
			return
		end

		local dsResult = Operations.getDataStore(connection)
		if not dsResult.success then
			Store.showToast("error", `Failed to get DataStore: {dsResult.error}`)
			isRestoring(false)
			return
		end

		local datastore = dsResult.value :: DataStore
		local setResult = Operations.setKey(datastore, keyName, data.value, data.userIds, data.metadata)
		isRestoring(false)

		if not setResult.success then
			Store.showToast("error", `Restore failed: {setResult.error}`)
			return
		end

		Store.showToast("success", "Version restored successfully")
		restoreConfirmVersion(nil)
		loadVersions()
	end

	local function getPreparedVersionData(versionId: string, setActiveHook: boolean?): (boolean, KeyData?, string?)
		local ok, rawData, err = getVersionData(versionId)
		if not ok or not rawData then
			return false, nil, err or "Failed to load key version"
		end

		local connection = Store.connection()
		local keyName = Store.currentKey()
		if not connection or not keyName then
			return false, nil, "No active DataStore connection"
		end

		local context = {
			datastoreName = connection.name,
			key = keyName,
			scope = connection.scope,
		}
		local prepared = KeyViewLoader.prepare(rawData, context, setActiveHook)
		return true, prepared.keyData, nil
	end

	local pathToKey = Functional.pathToKey

	local function setPathValue(rootValue: any, path: { string | number }, value: any): any
		if #path == 0 then
			return value
		end

		local result = if type(rootValue) == "table" then Functional.deepClone(rootValue) else {}
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

	local function buildDiffProjection(
		versionBData: KeyData,
		entries: { DiffEntry }
	): (any, { [string]: DiffFieldKind }, { [string]: boolean }, { [string]: JSONValue }, number)
		local function addNestedPaths(pathFilter: { [string]: boolean }, basePath: { string | number }, value: any)
			if type(value) ~= "table" then
				return
			end

			for key, child in value do
				local childPath = table.clone(basePath)
				table.insert(childPath, key)
				local childKey = pathToKey(childPath)
				pathFilter[childKey] = true
				addNestedPaths(pathFilter, childPath, child)
			end
		end

		local diffData = Functional.deepClone(versionBData.value)
		local pathKinds = {} :: { [string]: DiffFieldKind }
		local pathFilter = {} :: { [string]: boolean }
		local pathBeforeValues = {} :: { [string]: JSONValue }
		local focusedCount = 0

		for _, entry in entries do
			if entry.kind == "added" then
				focusedCount += 1
				local entryPathKey = pathToKey(entry.path)
				pathKinds[entryPathKey] = "added"
				pathFilter[entryPathKey] = true

				local branchValue = entry.after
				if type(branchValue) == "table" then
					addNestedPaths(pathFilter, entry.path, branchValue)
				end
			elseif entry.kind == "removed" then
				focusedCount += 1
				local entryPathKey = pathToKey(entry.path)
				pathKinds[entryPathKey] = "removed"
				pathFilter[entryPathKey] = true
				diffData = setPathValue(diffData, entry.path, entry.before)

				local branchValue = entry.before
				if type(branchValue) == "table" then
					addNestedPaths(pathFilter, entry.path, branchValue)
				end
			elseif entry.kind == "changed" or entry.kind == "type_changed" then
				focusedCount += 1
				local entryPathKey = pathToKey(entry.path)
				pathKinds[entryPathKey] = "changed"
				pathFilter[entryPathKey] = true
				pathBeforeValues[entryPathKey] = entry.before

				-- Show nested contents of the new (after) value if it's a container
				local branchValue = entry.after
				if type(branchValue) == "table" then
					addNestedPaths(pathFilter, entry.path, branchValue)
				end
			end
		end

		return diffData, pathKinds, pathFilter, pathBeforeValues, focusedCount
	end

	local function openDiffInEditor()
		local versionA = compareVersionA()
		local versionB = compareVersionB()
		if not versionA or not versionB then
			return
		end

		compareLoading(true)
		local okA, preparedA, errA = getPreparedVersionData(versionA, false)
		if not okA or not preparedA then
			Store.showToast("error", errA or "Failed to prepare Version A")
			compareLoading(false)
			return
		end

		local okB, preparedB, errB = getPreparedVersionData(versionB, false)
		if not okB or not preparedB then
			Store.showToast("error", errB or "Failed to prepare Version B")
			compareLoading(false)
			return
		end

		local entries = Diff.compute(preparedA.value, preparedB.value)
		local diffData, pathKinds, pathFilter, pathBeforeValues, focusedCount = buildDiffProjection(preparedB, entries)
		if focusedCount == 0 then
			Store.showToast("info", "No differences found between the selected versions")
			compareLoading(false)
			return
		end

		Store.currentKeyData(preparedB)
		Store.currentVersion(versionB)
		Store.editedData(diffData)
		Store.isReadOnly(true)
		Store.hasUnsavedChanges(false)
		Store.setDiffView({
			versionA = versionA,
			versionB = versionB,
			pathKinds = pathKinds,
			pathFilter = pathFilter,
			pathBeforeValues = pathBeforeValues,
		})
		Store.setView("editKey")
		Store.showToast("info", `Opened diff view with {focusedCount} changed field{if focusedCount == 1 then "" else "s"}`)
		compareLoading(false)
	end

	local function setCompareSlot(slot: "A" | "B", version: VersionInfo)
		if version.isDeleted then
			Store.showToast("warning", "Deleted versions cannot be compared")
			return
		end

		if slot == "A" then
			if compareVersionA() == version.version then
				compareVersionA(nil)
			else
				compareVersionA(version.version)
			end
		else
			if compareVersionB() == version.version then
				compareVersionB(nil)
			else
				compareVersionB(version.version)
			end
		end

		Store.clearDiffView()
	end

	local function swapComparedVersions()
		local a = compareVersionA()
		local b = compareVersionB()
		compareVersionA(b)
		compareVersionB(a)
	end

	local function clearComparedVersions()
		compareVersionA(nil)
		compareVersionB(nil)
	end

	local function pathMatchesQuery(entryKey: string, query: string): boolean
		-- Exact match or query is an ancestor prefix
		if entryKey == query or string.sub(entryKey, 1, #query + 1) == query .. "." then
			return true
		end
		-- query is a suffix (deeply nested field name or sub-path)
		if string.sub(entryKey, -#query) == query then
			local charBefore = string.sub(entryKey, -(#query + 1), -(#query + 1))
			if charBefore == "." or charBefore == "" then
				return true
			end
		end
		return false
	end

	local function startFieldScan()
		local currentPath = trackPath()
		if currentPath == "" or isScanning() then
			return
		end

		local versions = Store.versionList()
		if #versions < 2 then
			Store.showToast("info", "Need at least 2 versions to compare")
			return
		end

		isScanning(true)
		scanCancelled(false)
		scanResults({})
		scanProgress(0)
		scanTotal(#versions - 1)
		hasScanned(false)

		task.spawn(function()
			local scanned = 0
			for i = 1, #versions - 1 do
				if scanCancelled() then
					break
				end

				local newerVersion = versions[i]
				local olderVersion = versions[i + 1]

				local okNewer, dataNewer = getPreparedVersionData(newerVersion.version, false)
				local okOlder, dataOlder = getPreparedVersionData(olderVersion.version, false)

				if okNewer and okOlder and dataNewer and dataOlder then
					local entries = Diff.compute(dataOlder.value, dataNewer.value)
					for _, entry in entries do
						local entryKey = pathToKey(entry.path)
						if pathMatchesQuery(entryKey, currentPath) then
							local current = scanResults()
							local newResults = table.clone(current)
							table.insert(newResults, {
								newerVersion = newerVersion,
								olderVersion = olderVersion,
								entry = entry,
							})
							scanResults(newResults)
						end
					end
				end

				scanned += 1
				scanProgress(i)
				task.wait()
			end

		scanVersionCount(scanned)
		hasScanned(true)
		isScanning(false)
	end)
end

local function stopFieldScan()
	scanCancelled(true)
end

local function clearFieldScan()
	stopFieldScan()
	trackPath("")
	scanResults({})
	scanProgress(0)
	scanTotal(0)
	hasScanned(false)
	scanVersionCount(0)
end

-- Load the next page of versions (uses oldest known version's timestamp as upper bound)
local function loadMoreVersions(): boolean
	local connection = Store.connection()
	local keyName = Store.currentKey()
	if not connection or not keyName then
		return false
	end

	local currentVersions = Store.versionList()
	if #currentVersions == 0 then
		return false
	end

	local oldestVersion = currentVersions[#currentVersions]

	local dsResult = Operations.getDataStore(connection)
	if not dsResult.success then
		Store.showToast("error", `Failed to get DataStore: {dsResult.error}`)
		return false
	end

	local datastore = dsResult.value :: DataStore
	-- maxDate - 1 to exclude the oldest version we already have
	local result = Operations.listVersions(
		datastore,
		keyName,
		Enum.SortDirection.Descending,
		nil,
		oldestVersion.createdTime - 1
	)

	if result.success and #result.value.versions > 0 then
		local combined = table.clone(currentVersions)
		for _, v in result.value.versions do
			table.insert(combined, v)
		end
		Store.versionList(combined)
		Store.hasMoreVersions(result.value.hasMore)
		return true
	end

	Store.hasMoreVersions(false)
	return false
end

-- Continue scanning after loading another page of versions
local function extendScan()
	local currentPath = trackPath()
	if currentPath == "" or isScanning() then
		return
	end

	local prevCount = #Store.versionList()

	isScanning(true)
	scanCancelled(false)

	task.spawn(function()
		local loaded = loadMoreVersions()
		if not loaded then
			Store.showToast("info", "No more versions available to scan")
			isScanning(false)
			return
		end

		local versions = Store.versionList()
		scanTotal(#versions - 1)

		for i = prevCount, #versions - 1 do
			if scanCancelled() then
				break
			end

			local newerVersion = versions[i]
			local olderVersion = versions[i + 1]

			local okNewer, dataNewer = getPreparedVersionData(newerVersion.version, false)
			local okOlder, dataOlder = getPreparedVersionData(olderVersion.version, false)

			if okNewer and okOlder and dataNewer and dataOlder then
				local entries = Diff.compute(dataOlder.value, dataNewer.value)
				for _, entry in entries do
					local entryKey = pathToKey(entry.path)
					if pathMatchesQuery(entryKey, currentPath) then
						local current = scanResults()
						local newResults = table.clone(current)
						table.insert(newResults, {
							newerVersion = newerVersion,
							olderVersion = olderVersion,
							entry = entry,
						})
						scanResults(newResults)
					end
				end
			end

			scanProgress(i)
			task.wait()
		end

		scanVersionCount(#versions - 1)
		hasScanned(true)
		isScanning(false)
	end)
end

	-- Load a specific version
	local loadVersion = function(version: string)
		local connection = Store.connection()
		local keyName = Store.currentKey()

		if not connection or not keyName then
			return
		end

		Store.isLoadingKey(true)

		local dsResult = Operations.getDataStore(connection)
		if not dsResult.success then
			Store.showToast("error", `Failed to get DataStore: {dsResult.error}`)
			Store.isLoadingKey(false)
			return
		end

		local datastore = dsResult.value :: DataStore
		local keyResult = Operations.getKeyVersion(datastore, keyName, version)

		if keyResult.success then
			local context = {
				datastoreName = connection.name,
				key = keyName,
				scope = connection.scope,
			}
			local prepared = KeyViewLoader.prepare(keyResult.value, context, true)
			Store.currentKeyData(prepared.keyData)
			Store.currentVersion(version)
			Store.editedData(prepared.keyData.value)
			Store.isReadOnly(true) -- Version data is read-only
			Store.hasUnsavedChanges(false)
			Store.clearDiffView()
			Store.setView("editKey")
		else
			Store.showToast("error", `Failed to load version: {keyResult.error}`)
		end

		Store.isLoadingKey(false)
	end

	-- Load versions when view opens
	task.defer(function()
		if Store.connection() and Store.currentKey() and #Store.versionList() == 0 then
			loadVersions()
		end
	end)

	-- Format timestamp
	local formatTime = function(timestamp: number): string
		local date = os.date("*t", math.floor(timestamp / 1000))
		return string.format(
			"%04d-%02d-%02d %02d:%02d:%02d",
			date.year,
			date.month,
			date.day,
			date.hour,
			date.min,
			date.sec
		)
	end

	local formatVersionLabel = function(versionId: string?): string
		if not versionId then
			return "Not selected"
		end
		local v = getVersionById(versionId)
		if v then
			return `{string.sub(v.version, 1, 12)}... ({formatTime(v.createdTime)})`
		end
		return `{string.sub(versionId, 1, 12)}...`
	end

	-- Version row component
	local VersionRow = function(versionInfo: () -> VersionInfo, index: number): Frame
		local isHovered = source(false)
		local v = versionInfo()
		
		local targetBackgroundColor = derive(function()
			local c = theme.colors()
			if isHovered() then
				return c.backgroundTertiary
			end
			if index % 2 == 0 then
				return c.backgroundSecondary
			end
			return c.background
		end)
		
		local backgroundColor = spring(targetBackgroundColor, 0.1)

		return create "Frame" {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = backgroundColor,
			BorderSizePixel = 0,

			MouseEnter = function()
				isHovered(true)
			end,

			MouseLeave = function()
				isHovered(false)
			end,

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 10),
			},

			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
			},

			create "TextButton" {
				LayoutOrder = 1,
				Size = UDim2.new(1, if index > 1 and not v.isDeleted then -152 else -84, 1, 0),
				BackgroundTransparency = 1,
				Text = "",

				Activated = function()
					if not v.isDeleted then
						loadVersion(v.version)
					end
				end,

				action(function(btn: TextButton)
					local text = if v.isDeleted then "Deleted version" else "View this version"
					Tooltip.addTooltip(btn, text, "top", 0.4)
				end),

				create "Frame" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,

					create "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 16),
					},

					-- Version info
					create "Frame" {
						LayoutOrder = 1,
						Size = UDim2.new(1, if index == 1 then -190 else -120, 1, 0),
						BackgroundTransparency = 1,

						create "UIListLayout" {
							SortOrder = Enum.SortOrder.LayoutOrder,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 2),
						},

						create "TextLabel" {
							LayoutOrder = 1,
							Size = UDim2.new(1, 0, 0, 20),
							BackgroundTransparency = 1,
							Text = string.sub(v.version, 1, 16) .. "...",
							TextColor3 = function()
								local c = theme.colors()
								if v.isDeleted then
									return c.foregroundMuted
								end
								return c.foreground
							end,
							TextSize = theme.fontSize.normal,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.fontMono,
						},

						create "TextLabel" {
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 0, 16),
							BackgroundTransparency = 1,
							Text = formatTime(v.createdTime),
							TextColor3 = function()
								return theme.colors().foregroundMuted
							end,
							TextSize = theme.fontSize.small,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.font,
						},
					},

					-- Status badge
					create "Frame" {
						LayoutOrder = 2,
						Size = UDim2.fromOffset(80, 24),
						BackgroundColor3 = function()
							local c = theme.colors()
							if v.isDeleted then
								return c.error
							end
							return c.success
						end,
						BackgroundTransparency = 0.85, -- Subtle background
						
						create "UICorner" {
							CornerRadius = UDim.new(0, 4),
						},
						
						create "UIStroke" {
							Color = function()
								local c = theme.colors()
								if v.isDeleted then
									return c.error
								end
								return c.success
							end,
							Transparency = 0.5,
							Thickness = 1,
						},
						
						create "TextLabel" {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = if v.isDeleted then "Deleted" else "Active",
							TextColor3 = function()
								local c = theme.colors()
								if v.isDeleted then
									return c.error
								end
								return c.success
							end,
							TextSize = theme.fontSize.small,
							FontFace = theme.fontMedium,
						},
					},
					
					-- Current badge (for the first version)
					if index == 1 then create "Frame" {
						LayoutOrder = 3,
						Size = UDim2.fromOffset(70, 24),
						BackgroundColor3 = function()
							return theme.colors().accent
						end,
						BackgroundTransparency = 0.85,
						
						create "UICorner" {
							CornerRadius = UDim.new(0, 4),
						},
						
						create "UIStroke" {
							Color = function()
								return theme.colors().accent
							end,
							Transparency = 0.5,
							Thickness = 1,
						},
						
						create "TextLabel" {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = "Current",
							TextColor3 = function()
								return theme.colors().accent
							end,
							TextSize = theme.fontSize.small,
							FontFace = theme.fontMedium,
						},
					} else nil,

					-- Arrow
					create "ImageLabel" {
						LayoutOrder = 4,
						Size = UDim2.fromOffset(16, 16),
						BackgroundTransparency = 1,
						Image = theme.icons.chevronRight,
						ImageColor3 = function()
							return theme.colors().foregroundMuted
						end,
						Visible = not v.isDeleted,
					},
				},
			},

			-- Compare controls
			create "Frame" {
				LayoutOrder = 2,
				Size = UDim2.fromOffset(76, 32),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
				},

				create "TextButton" {
					LayoutOrder = 1,
					Size = UDim2.fromOffset(35, 26),
					BackgroundColor3 = function()
						local c = theme.colors()
						if v.isDeleted then
							return c.backgroundTertiary
						end
						if compareVersionA() == v.version then
							return c.accent
						end
						return c.backgroundTertiary
					end,
					BackgroundTransparency = function()
						return if v.isDeleted then 0.4 else 0
					end,
					BorderSizePixel = 0,
					Text = "A",
					TextColor3 = function()
						local c = theme.colors()
						if v.isDeleted then
							return c.foregroundMuted
						end
						if compareVersionA() == v.version then
							return Color3.new(1, 1, 1)
						end
						return c.foreground
					end,
					TextSize = theme.fontSize.small,
					FontFace = theme.fontBold,
					AutoButtonColor = false,

					Activated = function()
						setCompareSlot("A", v)
					end,

					action(function(btn: TextButton)
						Tooltip.addTooltip(btn, "Set as version A for comparison", "top", 0.4)
					end),

					create "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},
				},

				create "TextButton" {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(35, 26),
					BackgroundColor3 = function()
						local c = theme.colors()
						if v.isDeleted then
							return c.backgroundTertiary
						end
						if compareVersionB() == v.version then
							return c.accent
						end
						return c.backgroundTertiary
					end,
					BackgroundTransparency = function()
						return if v.isDeleted then 0.4 else 0
					end,
					BorderSizePixel = 0,
					Text = "B",
					TextColor3 = function()
						local c = theme.colors()
						if v.isDeleted then
							return c.foregroundMuted
						end
						if compareVersionB() == v.version then
							return Color3.new(1, 1, 1)
						end
						return c.foreground
					end,
					TextSize = theme.fontSize.small,
					FontFace = theme.fontBold,
					AutoButtonColor = false,

					Activated = function()
						setCompareSlot("B", v)
					end,

					action(function(btn: TextButton)
						Tooltip.addTooltip(btn, "Set as version B for comparison", "top", 0.4)
					end),

					create "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},
				},
			},

		-- Restore button (only for non-current, non-deleted versions)
		if index > 1 and not v.isDeleted then create "TextButton" {
			LayoutOrder = 3,
			Size = UDim2.fromOffset(60, 32),
			BackgroundColor3 = function()
				return theme.colors().warning
			end,
			BackgroundTransparency = 0.85,
			BorderSizePixel = 0,
			Text = "Restore",
			TextColor3 = function()
				return theme.colors().warning
			end,
			TextSize = theme.fontSize.small,
			FontFace = theme.fontLight,
			AutoButtonColor = false,

			Activated = function()
				restoreConfirmVersion(v)
			end,

			action(function(btn: TextButton)
				Tooltip.addTooltip(btn, "Restore this version as the current value", "top", 0.4)
			end),

			create "UICorner" {
				CornerRadius = UDim.new(0, 4),
			},
		 } else nil,
	}
end

	-- Scan result row component
	local ScanResultRow = function(result: () -> ScanResult, index: number): Frame
		return create "Frame" {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = function()
				local c = theme.colors()
				return if index % 2 == 0 then c.backgroundSecondary else c.background
			end,
			BorderSizePixel = 0,

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 10),
			},

			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
			},

			-- Kind badge
			create "Frame" {
				LayoutOrder = 1,
				Size = UDim2.fromOffset(22, 22),
				BackgroundColor3 = function()
					local c = theme.colors()
					local kind = result().entry.kind
					if kind == "added" then return c.success
					elseif kind == "removed" then return c.error
					else return c.warning end
				end,
				BackgroundTransparency = 0.8,

				create "UICorner" {
					CornerRadius = UDim.new(1, 0),
				},

				create "UIStroke" {
					Color = function()
						local c = theme.colors()
						local kind = result().entry.kind
						if kind == "added" then return c.success
						elseif kind == "removed" then return c.error
						else return c.warning end
					end,
					Transparency = 0.4,
					Thickness = 1,
				},

				create "TextLabel" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = function()
						local kind = result().entry.kind
						if kind == "added" then return "+"
						elseif kind == "removed" then return "-"
						else return "~" end
					end,
					TextColor3 = function()
						local c = theme.colors()
						local kind = result().entry.kind
						if kind == "added" then return c.success
						elseif kind == "removed" then return c.error
						else return c.warning end
					end,
					TextSize = theme.fontSize.small,
					FontFace = theme.fontBold,
				},
			},

			-- Path and before → after preview
			create "Frame" {
				LayoutOrder = 2,
				Size = UDim2.new(0, 100, 1, 0),
				BackgroundTransparency = 1,

				create "UIFlexItem" {
					FlexMode = Enum.UIFlexMode.Fill,
				},

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 2),
				},

				create "TextLabel" {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 18),
					BackgroundTransparency = 1,
					Text = function()
						return pathToKey(result().entry.path)
					end,
					TextColor3 = function()
						return theme.colors().foreground
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMono,
					TextTruncate = Enum.TextTruncate.AtEnd,
				},

				create "TextLabel" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					Text = function()
						local entry = result().entry
						local before = Diff.previewValue(entry.before, 35)
						local after = Diff.previewValue(entry.after, 35)
						return `{before} → {after}`
					end,
					TextColor3 = function()
						return theme.colors().foregroundMuted
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMono,
					TextTruncate = Enum.TextTruncate.AtEnd,
				},
			},

			-- Timestamp of the newer version
			create "TextLabel" {
				LayoutOrder = 3,
				Size = UDim2.fromOffset(128, 32),
				BackgroundTransparency = 1,
				Text = function()
					return formatTime(result().newerVersion.createdTime)
				end,
				TextColor3 = function()
					return theme.colors().foregroundMuted
				end,
				TextSize = theme.fontSize.small,
				TextXAlignment = Enum.TextXAlignment.Right,
				FontFace = theme.font,
			},

			-- Diff button
			create "Frame" {
				LayoutOrder = 4,
				Size = UDim2.fromOffset(52, 28),
				BackgroundTransparency = 1,

				Button({
					text = "Diff",
					onClick = function()
						local r = result()
						compareVersionA(r.olderVersion.version)
						compareVersionB(r.newerVersion.version)
						openDiffInEditor()
					end,
					variant = "secondary",
					size = "small",
					fullWidth = true,
				}),
			},
		}
	end

	return create "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return theme.colors().background
		end,
		BorderSizePixel = 0,

		create "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,

		create "UIListLayout" {
			SortOrder = Enum.SortOrder.LayoutOrder,
		},

		-- Header
		create "Frame" {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = function()
				return theme.colors().backgroundSecondary
			end,
			BorderSizePixel = 0,

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			},

			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 16),
				},

			-- Back button
			create "ImageButton" {
				LayoutOrder = 1,
				Size = UDim2.fromOffset(32, 32),
				BackgroundColor3 = function()
					return theme.colors().backgroundTertiary
				end,
				Image = "",

				Activated = function()
					Store.isReadOnly(false)
					Store.currentVersion(nil)
					-- Reload current version
					local keyData = Store.currentKeyData()
					if keyData then
						Store.editedData(keyData.value)
					end
					Store.setView("editKey")
				end,

				create "UICorner" {
					CornerRadius = UDim.new(0, 6),
				},

				create "ImageLabel" {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(18, 18),
					BackgroundTransparency = 1,
					Image = theme.icons.back,
					ImageColor3 = function()
						return theme.colors().foreground
					end,
				},
			},

				-- Title
				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(1, -160, 1, 0),
					BackgroundTransparency = 1,

					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					},

					create "TextLabel" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 24),
						BackgroundTransparency = 1,
						Text = "Version History",
						TextColor3 = function()
							return theme.colors().foreground
						end,
						TextSize = theme.fontSize.large,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.fontBold,
					},

					create "TextLabel" {
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 0, 18),
						BackgroundTransparency = 1,
						Text = function()
							return Store.currentKey() or ""
						end,
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.fontMono,
						TextTruncate = Enum.TextTruncate.AtEnd,
					},
				},

				-- Refresh button
				create "Frame" {
					LayoutOrder = 3,
					Size = UDim2.fromOffset(36, 36),
					BackgroundTransparency = 1,

					Button({
						text = "",
						onClick = loadVersions,
						variant = "ghost",
						icon = theme.icons.refresh,
						disabled = Store.versionListLoading,
					}),
				},
			},
		},

		-- Compare toolbar
		create "Frame" {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 112),
			BackgroundColor3 = function()
				return theme.colors().backgroundSecondary
			end,
			BorderSizePixel = 0,

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
			},

			create "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			},

			create "Frame" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,

				create "TextLabel" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "Pick two versions from the A/B buttons to instantly compare them.",
					TextColor3 = function()
						return theme.colors().foregroundMuted
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.font,
				},
			},

			create "Frame" {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				},

				create "TextLabel" {
					LayoutOrder = 1,
					Size = UDim2.new(0.5, -4, 1, 0),
					BackgroundColor3 = function()
						return theme.colors().backgroundTertiary
					end,
					Text = function()
						return `A: {formatVersionLabel(compareVersionA())}`
					end,
					TextColor3 = function()
						local c = theme.colors()
						if compareVersionA() then
							return c.foreground
						end
						return c.foregroundMuted
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMono,

					create "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					},
				},

				create "TextLabel" {
					LayoutOrder = 2,
					Size = UDim2.new(0.5, -4, 1, 0),
					BackgroundColor3 = function()
						return theme.colors().backgroundTertiary
					end,
					Text = function()
						return `B: {formatVersionLabel(compareVersionB())}`
					end,
					TextColor3 = function()
						local c = theme.colors()
						if compareVersionB() then
							return c.foreground
						end
						return c.foregroundMuted
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMono,

					create "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					},
				},
			},

			create "Frame" {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				},

				create "Frame" {
					LayoutOrder = 1,
					Size = UDim2.fromOffset(96, 32),
					BackgroundTransparency = 1,

					Button({
						text = function()
							return if compareLoading() then "Opening..." else "Open Diff"
						end,
						onClick = openDiffInEditor,
						variant = "primary",
						size = "small",
						disabled = function()
							return compareVersionA() == nil or compareVersionB() == nil or compareLoading()
						end,
						fullWidth = true,
					}),
				},

				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(72, 32),
					BackgroundTransparency = 1,

					Button({
						text = "Swap",
						onClick = swapComparedVersions,
						variant = "ghost",
						size = "small",
						disabled = function()
							return compareLoading() or (compareVersionA() == nil and compareVersionB() == nil)
						end,
						fullWidth = true,
					}),
				},

				create "Frame" {
					LayoutOrder = 3,
					Size = UDim2.fromOffset(72, 32),
					BackgroundTransparency = 1,

					Button({
						text = "Clear",
						onClick = clearComparedVersions,
						variant = "primary",
						size = "small",
						disabled = function()
							return compareLoading() or (compareVersionA() == nil and compareVersionB() == nil)
						end,
						fullWidth = true,
					}),
				},
			},
		},

		-- Field history track bar
		create "Frame" {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = function()
				return theme.colors().background
			end,
			BorderSizePixel = 0,

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
			},

			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
			},

			-- Path input
			create "Frame" {
				LayoutOrder = 1,
				Size = UDim2.new(0, 100, 1, 0),
				BackgroundColor3 = function()
					return theme.colors().backgroundSecondary
				end,
				BorderSizePixel = 0,

				create "UIFlexItem" {
					FlexMode = Enum.UIFlexMode.Fill,
				},

				create "UICorner" {
					CornerRadius = UDim.new(0, 6),
				},

				create "UIPadding" {
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
				},

				create "TextBox" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = function()
						return trackPath()
					end,
					PlaceholderText = "Track a field path, e.g. player.coins",
					PlaceholderColor3 = function()
						return theme.colors().foregroundMuted
					end,
					TextColor3 = function()
						return theme.colors().foreground
					end,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMono,
					ClearTextOnFocus = false,

					action(function(tb: TextBox)
						tb:GetPropertyChangedSignal("Text"):Connect(function()
							if tb:IsFocused() then
								trackPath(tb.Text)
							end
						end)
						tb.FocusLost:Connect(function(enterPressed: boolean)
							trackPath(tb.Text)
							if enterPressed then
								startFieldScan()
							end
						end)
					end),
				},
			},

			-- Progress indicator (visible while scanning)
			create "TextLabel" {
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = function()
					local total = scanTotal()
					if total == 0 then
						return "Scanning..."
					end
					return `{scanProgress()} / {total}`
				end,
				TextColor3 = function()
					return theme.colors().foregroundMuted
				end,
				TextSize = theme.fontSize.small,
				FontFace = theme.font,
				Visible = isScanning,
			},

			-- Scan / Stop / Clear button
			create "Frame" {
				LayoutOrder = 3,
				Size = UDim2.fromOffset(60, 32),
				BackgroundTransparency = 1,

				Button({
					text = function()
						if isScanning() then
							return "Stop"
						elseif hasScanned() then
							return "Clear"
						end
						return "Scan"
					end,
					onClick = function()
						if isScanning() then
							stopFieldScan()
						elseif hasScanned() then
							clearFieldScan()
						else
							startFieldScan()
						end
					end,
					variant = function()
						return if isScanning() then "secondary" else "primary"
					end :: any,
					size = "small",
					disabled = function()
						return not isScanning() and not hasScanned() and trackPath() == ""
					end,
					fullWidth = true,
				}),
			},
		},

		-- Version list / scan results
		create "ScrollingFrame" {
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 1, -218),
			BackgroundTransparency = 1,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = function()
				return theme.colors().scrollbar
			end,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BorderSizePixel = 0,

			create "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
			},

			-- Version list group (hidden while field history scan is active)
			create "Frame" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Visible = function()
					return not (isScanning() or hasScanned())
				end,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
				},

				create "Frame" {
					Size = UDim2.new(1, 0, 0, 60),
					BackgroundTransparency = 1,
					Visible = Store.versionListLoading,

					create "TextLabel" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "Loading versions...",
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.normal,
						FontFace = theme.font,
					},
				},

				-- Versions
				indexes(Store.versionList, function(versionInfo, index)
					return VersionRow(versionInfo, index)
				end),

				-- Empty state
				create "Frame" {
					Size = UDim2.new(1, 0, 0, 100),
					BackgroundTransparency = 1,
					Visible = function()
						return #Store.versionList() == 0 and not Store.versionListLoading()
					end,

					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
					},

					create "TextLabel" {
						LayoutOrder = 1,
						AutomaticSize = Enum.AutomaticSize.XY,
						BackgroundTransparency = 1,
						Text = "No versions found",
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.normal,
						FontFace = theme.font,
					},

					Button({
						text = "Refresh",
						onClick = loadVersions,
						variant = "secondary",
					}),
				},
			},

			-- Scan results group (shown while scanning or after scan)
			create "Frame" {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Visible = function()
					return isScanning() or hasScanned()
				end,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
				},

				-- Result rows
				indexes(scanResults, function(result, index)
					return ScanResultRow(result, index)
				end),

				-- Scanning in progress row (appears below results as they build up)
				create "Frame" {
					LayoutOrder = 10001,
					Size = UDim2.new(1, 0, 0, 48),
					BackgroundTransparency = 1,
					Visible = isScanning,

					create "TextLabel" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = function()
							local total = scanTotal()
							local progress = scanProgress()
							if total == 0 then
								return "Scanning versions..."
							end
							return `Scanning {progress} / {total} versions...`
						end,
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Center,
						FontFace = theme.font,
					},
				},

				-- No results state (after scan finishes with no matches)
				create "Frame" {
					LayoutOrder = 10002,
					Size = UDim2.new(1, 0, 0, 80),
					BackgroundTransparency = 1,
					Visible = function()
						return hasScanned() and not isScanning() and #scanResults() == 0
					end,

					create "TextLabel" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = function()
							return `No changes found for "{trackPath()}"`
						end,
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.normal,
						TextXAlignment = Enum.TextXAlignment.Center,
						FontFace = theme.font,
					},
				},

				-- Summary footer (version count + scan-more option)
				create "Frame" {
					LayoutOrder = 10003,
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					Visible = function()
						return hasScanned() and not isScanning()
					end,

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 12),
					},

					create "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 12),
					},

					create "TextLabel" {
						LayoutOrder = 1,
						Size = UDim2.new(0, 0, 1, 0),
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						Text = function()
							local count = scanVersionCount()
							local found = #scanResults()
							local plural = if count == 1 then "version" else "versions"
							return `Scanned {count} {plural} • {found} {if found == 1 then "change" else "changes"} found`
						end,
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.font,
					},

					create "Frame" {
						LayoutOrder = 2,
						Size = UDim2.fromOffset(110, 28),
						BackgroundTransparency = 1,
						Visible = Store.hasMoreVersions,

						Button({
							text = "Scan more",
							onClick = extendScan,
							variant = "ghost",
							size = "small",
							fullWidth = true,
						}),
					},

					create "TextLabel" {
						LayoutOrder = 3,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.new(0, 0, 1, 0),
						BackgroundTransparency = 1,
						Text = "All versions scanned",
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.font,
						Visible = function()
							return not Store.hasMoreVersions()
						end,
					},
				},
			},
		},
		},

	-- Restore confirmation modal
	Modal({
		isOpen = function()
			return restoreConfirmVersion() ~= nil
		end,
		onClose = function()
			if not isRestoring() then
				restoreConfirmVersion(nil)
			end
		end,
		title = "Restore Version",
		size = "small",
		closeOnBackdrop = true,
		children = {
			create "Frame" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				},

				-- Intro text with colored key name
				create "TextLabel" {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Text = function()
						local v = restoreConfirmVersion()
						if not v then return "" end
						local c = theme.colors().accent
						local h = string.format(
							"#%02X%02X%02X",
							math.round(c.R * 255),
							math.round(c.G * 255),
							math.round(c.B * 255)
						)
						return `This will overwrite the current value of <font color="{h}">&quot;{Store.currentKey()}&quot;</font> with the data from version:`
					end,
					TextColor3 = function()
						return theme.colors().foreground
					end,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					RichText = true,
					FontFace = theme.font,
				},

				-- Version ID code block
				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = function()
						return theme.colors().backgroundTertiary
					end,

					create "UICorner" {
						CornerRadius = UDim.new(0, theme.radius.sm),
					},

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
						PaddingTop = UDim.new(0, 8),
						PaddingBottom = UDim.new(0, 8),
					},

					create "TextLabel" {
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Text = function()
							local v = restoreConfirmVersion()
							return if v then v.version else ""
						end,
						TextColor3 = function()
							return theme.colors().accent
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextWrapped = true,
						FontFace = theme.fontMono,
					},
				},

				-- Warning
				create "TextLabel" {
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Text = "This action cannot be undone.",
					TextColor3 = function()
						return theme.colors().error
					end,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					FontFace = theme.font,
				},

				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 36),
					BackgroundTransparency = 1,

					create "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
					},

					Button({
						text = "Cancel",
						variant = "ghost",
						onClick = function()
							restoreConfirmVersion(nil)
						end,
						disabled = isRestoring,
					}),

					Button({
						text = function()
							return if isRestoring() then "Restoring..." else "Restore"
						end,
						variant = "danger",
						onClick = function()
							local v = restoreConfirmVersion()
							if v then
								task.spawn(restoreVersion, v.version)
							end
						end,
						disabled = isRestoring,
					}),
				},
			},
		},
	}),
	}
end

return VersionsView
