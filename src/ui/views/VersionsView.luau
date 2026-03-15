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

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local indexes = Vide.indexes
local spring = Vide.spring

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

	local function pathToKey(path: { string | number }): string
		local parts = {}
		for _, p in path do
			table.insert(parts, tostring(p))
		end
		return table.concat(parts, ".")
	end

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
	): (any, { [string]: DiffFieldKind }, { [string]: boolean }, number)
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

				-- Show nested contents of the new (after) value if it's a container
				local branchValue = entry.after
				if type(branchValue) == "table" then
					addNestedPaths(pathFilter, entry.path, branchValue)
				end
			end
		end

		return diffData, pathKinds, pathFilter, focusedCount
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
		local diffData, pathKinds, pathFilter, focusedCount = buildDiffProjection(preparedB, entries)
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
				Size = UDim2.new(1, -84, 1, 0),
				BackgroundTransparency = 1,
				Text = "",

				Activated = function()
					if not v.isDeleted then
						loadVersion(v.version)
					end
				end,

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

					create "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},
				},
			},
		}
	end

	return create "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return theme.colors().background
		end,
		BorderSizePixel = 0,

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
					Size = UDim2.fromOffset(36, 36),
					BackgroundColor3 = function()
						return theme.colors().backgroundTertiary
					end,
					Image = theme.icons.back,
					ImageColor3 = function()
						return theme.colors().foreground
					end,

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
						CornerRadius = UDim.new(0, 8),
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
						variant = "ghost",
						size = "small",
						disabled = function()
							return compareLoading() or (compareVersionA() == nil and compareVersionB() == nil)
						end,
						fullWidth = true,
					}),
				},
			},
		},

		-- Version list
		create "ScrollingFrame" {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 1, -174),
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
	}
end

return VersionsView
