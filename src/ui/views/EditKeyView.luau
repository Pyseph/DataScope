--!strict
--[[
	Edit Key View
	Key data editor with search bar using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Store = require(script.Parent.Parent.Parent.core.Store)
local Types = require(script.Parent.Parent.Parent.core.Types)
local Operations = require(script.Parent.Parent.Parent.datastore.Operations)
local HookManager = require(script.Parent.Parent.Parent.hooks.HookManager)
local Functional = require(script.Parent.Parent.Parent.utils.Functional)
local JSON = require(script.Parent.Parent.Parent.utils.JSON)

local UserInputService = game:GetService("UserInputService")

local Button = require(script.Parent.Parent.components.Button)
local SearchBar = require(script.Parent.Parent.components.SearchBar)
local TreeView = require(script.Parent.Parent.components.TreeView)
local Tabs = require(script.Parent.Parent.components.Tabs)
local DataStats = require(script.Parent.Parent.components.DataStats)
local Tooltip = require(script.Parent.Parent.components.Tooltip)
local Breadcrumbs = require(script.Parent.Parent.components.Breadcrumbs)

local action = Vide.action

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local effect = Vide.effect
local spring = Vide.spring

type JSONValue = Types.JSONValue
type SearchMode = Store.SearchMode

local function EditKeyView(): Frame
	local theme = Theme.get()

	-- Local state
	local viewMode = source("tree" :: "tree" | "code")
	local expandRef: TreeView.TreeViewExpandRef = {}
	local codeEditorText = source("")
	local showDeleteConfirm = source(false)
	local scrollPath = source({} :: { string | number })
	local viewWidth = source(900)
	local isDiffMode = derive(function(): boolean
		return Store.diffView() ~= nil
	end)
	local isCompact = derive(function(): boolean
		return viewWidth() < 760
	end)
	local isTight = derive(function(): boolean
		return viewWidth() < 620
	end)
	local isUltraTight = derive(function(): boolean
		return viewWidth() < 520
	end)
	local metadataRowWeight = spring(function()
		return if isCompact() then 0 else 1
	end, 0.2)

	-- Search bar focus ref for Ctrl+F shortcut
	local searchFocusRef: SearchBar.SearchBarFocusRef = { focus = nil }

	-- Sync code editor with data
	local updateCodeEditor = function()
		local data = Store.editedData()
		if data == nil then
			codeEditorText("")
			return
		end

		local success, json = pcall(function()
			return game:GetService("HttpService"):JSONEncode(data)
		end)

		if success then
			-- Pretty print JSON
			local pretty = json
				:gsub(",", ",\n")
				:gsub("{", "{\n")
				:gsub("}", "\n}")
				:gsub("%[", "[\n")
				:gsub("%]", "\n]")
			codeEditorText(pretty)
		else
			codeEditorText(tostring(data))
		end
	end

	-- Save handler
	local handleSave = function()
		local connection = Store.connection()
		local keyName = Store.currentKey()
		local data = Store.editedData()

		if not connection or not keyName then
			return
		end

		Store.isSavingKey(true)

		-- Apply compression hook if active (use global HookManager state)
		local dataToSave = data
		local hookName = HookManager.getActiveHookName()
		if hookName then
			local context = {
				datastoreName = connection.name,
				key = keyName,
				scope = connection.scope,
			}
			local success, compressed = pcall(function()
				return HookManager.compress(data, context, hookName)
			end)
			if success then
				dataToSave = compressed
			else
				Store.showToast("error", `Compression failed: {compressed}`)
				Store.isSavingKey(false)
				return
			end
		end

		local dsResult = Operations.getDataStore(connection)
		if not dsResult.success then
			Store.showToast("error", `Failed to get DataStore: {dsResult.error}`)
			Store.isSavingKey(false)
			return
		end

		local datastore = dsResult.value :: DataStore
		local keyData = Store.currentKeyData()
		local userIds = keyData and keyData.userIds or nil

		local result = Operations.setKey(datastore, keyName, dataToSave, userIds)

		if result.success then
			Store.hasUnsavedChanges(false)
			Store.showToast("success", "Key saved successfully")

			-- Reload to get updated version info
			local reloadResult = Operations.getKey(datastore, keyName)
			if reloadResult.success then
				Store.currentKeyData(reloadResult.value)
			end
		else
			Store.showToast("error", `Failed to save: {result.error}`)
		end

		Store.isSavingKey(false)
	end

	-- Delete handler - shows confirmation
	local handleDelete = function()
		showDeleteConfirm(true)
	end

	-- Confirm delete - actually deletes
	local confirmDelete = function()
		local connection = Store.connection()
		local keyName = Store.currentKey()

		if not connection or not keyName then
			showDeleteConfirm(false)
			return
		end

		local dsResult = Operations.getDataStore(connection)
		if not dsResult.success then
			Store.showToast("error", `Failed to get DataStore: {dsResult.error}`)
			showDeleteConfirm(false)
			return
		end

		local datastore = dsResult.value :: DataStore
		local result = Operations.deleteKey(datastore, keyName)

		if result.success then
			Store.showToast("success", "Key deleted")
			showDeleteConfirm(false)
			Store.setView("browse")
		else
			Store.showToast("error", `Failed to delete: {result.error}`)
			showDeleteConfirm(false)
		end
	end

	local cancelDelete = function()
		showDeleteConfirm(false)
	end

	-- Toggle expand all / collapse all via TreeView's expandRef
	local expandAll = function()
		local data = Store.editedData()
		if expandRef.expandAll then
			task.defer(function()
				(expandRef.expandAll :: any)(data)
			end)
		end
	end

	local collapseAll = function()
		if expandRef.collapseAll then
			expandRef.collapseAll()
		end
	end

	-- Export handler
	local handleExport = function()
		local data = Store.editedData()
		local keyName = Store.currentKey()
		
		if data == nil then
			Store.showToast("error", "No data to export")
			return
		end
		
		-- Sanitize key name for file name
		local fileName = keyName or "ExportedData"
		fileName = fileName:gsub("[^%w%-_]", "_") -- Replace invalid chars with underscore
		
		local success, err = JSON.promptExport(data, fileName, Store.plugin)
		
		if success then
			Store.showToast("success", "Export saved! Check your file location.")
		else
			if err then
				Store.showToast("error", `Export failed: {err}`)
			end
		end
	end

	-- View tabs
	local viewTabs = {
		{ id = "tree", label = "Tree" },
		{ id = "code", label = "Code" },
	}
	local showToolbarTabs = derive(function(): boolean
		return not isUltraTight()
	end)
	local showExpandControls = derive(function(): boolean
		return viewMode() == "tree" and not isTight()
	end)
	local showUndoRedoControls = derive(function(): boolean
		return not isCompact()
	end)
	local showExportAction = derive(function(): boolean
		return not isTight()
	end)
	local showVersionsAction = derive(function(): boolean
		return not isUltraTight()
	end)
	local showDeleteAction = derive(function(): boolean
		return not isUltraTight()
	end)
	local showDividerAction = derive(function(): boolean
		return not isCompact()
	end)
	local toolbarTabsWidth = spring(function()
		return if showToolbarTabs() then 120 else 0
	end, 0.2)
	local toolbarExpandWidth = spring(function()
		return if showExpandControls() then 60 else 0
	end, 0.2)
	local toolbarUndoWidth = spring(function()
		return if showUndoRedoControls() then 60 else 0
	end, 0.2)
	local exportActionWidth = spring(function()
		return if showExportAction() then 72 else 0
	end, 0.2)
	local versionsActionWidth = spring(function()
		return if showVersionsAction() then 82 else 0
	end, 0.2)
	local deleteActionWidth = spring(function()
		return if showDeleteAction() then 28 else 0
	end, 0.2)
	local dividerActionWidth = spring(function()
		return if showDividerAction() then 1 else 0
	end, 0.2)
	local hasToolbarControls = derive(function(): boolean
		return toolbarTabsWidth() > 1 or toolbarExpandWidth() > 1 or toolbarUndoWidth() > 1
	end)

	effect(function()
		if isDiffMode() and viewMode() ~= "tree" then
			task.defer(function()
				viewMode("tree")
			end)
		end
	end)

	-- Auto-expand ancestor paths of diff nodes when entering diff mode so
	-- changes at any depth are immediately visible without manual expansion.
	effect(function()
		local diffView = Store.diffView()
		if not diffView then
			return
		end

		local newPaths: { [string]: boolean } = {}
		for pathKey in diffView.pathKinds do
			local searchFrom = 1
			while true do
				local dotPos = string.find(pathKey, ".", searchFrom, true)
				if not dotPos then
					break
				end
				newPaths[string.sub(pathKey, 1, dotPos - 1)] = true
				searchFrom = dotPos + 1
			end
		end

		if next(newPaths) and expandRef.setExpanded then
			task.defer(function()
				(expandRef.setExpanded :: any)(newPaths)
			end)
		end
	end)

	-- Format key metadata
	local keyMetadata = derive(function(): string
		local diffView = Store.diffView()
		if diffView then
			if isCompact() then
				return "Diff mode"
			end
			return `Diff mode • A {string.sub(diffView.versionA, 1, 10)}... -> B {string.sub(diffView.versionB, 1, 10)}...`
		end

		local keyData = Store.currentKeyData()
		if not keyData or not keyData.keyInfo then
			return ""
		end

		local info = keyData.keyInfo
		local parts = {}

		if info.CreatedTime then
			local date = os.date("*t", math.floor(info.CreatedTime / 1000))
			table.insert(
				parts,
				`Created: {date.year}-{string.format("%02d", date.month)}-{string.format("%02d", date.day)}`
			)
		end

		if info.UpdatedTime then
			local date = os.date("*t", math.floor(info.UpdatedTime / 1000))
			table.insert(
				parts,
				`Updated: {date.year}-{string.format("%02d", date.month)}-{string.format("%02d", date.day)}`
			)
		end

		if info.Version then
			table.insert(parts, `Version: {string.sub(info.Version, 1, 12)}`)
		end

		return table.concat(parts, " • ")
	end)

	-- Overlay frame for dropdown portals (rendered above everything)
	local rootAbsPos = source(Vector2.zero)
	local dropdownPortalFrame = create "Frame" {
		Name = "DropdownPortal",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
	}

	return create "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return theme.colors().background
		end,
		BorderSizePixel = 0,

		action(function(frame: Frame)
			viewWidth(frame.AbsoluteSize.X)
			rootAbsPos(frame.AbsolutePosition)
			frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				viewWidth(frame.AbsoluteSize.X)
			end)
			frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				rootAbsPos(frame.AbsolutePosition)
			end)

			-- Ctrl+F shortcut to focus search bar
			UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
				if gameProcessed then
					return
				end
				if input.KeyCode == Enum.KeyCode.F and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
					if searchFocusRef.focus then
						searchFocusRef.focus()
					end
				end
			end)
		end),

		-- Dropdown portal overlay (above all other content, outside layout)
		dropdownPortalFrame,

		-- Content frame with layout
		create "Frame" {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

		create "UIListLayout" {
			SortOrder = Enum.SortOrder.LayoutOrder,
		},

		-- Header
		create "Frame" {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = function()
				return theme.colors().backgroundSecondary
			end,
			BorderSizePixel = 0,

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
			},

			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 12),
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
						if isDiffMode() then
							Store.clearDiffView()
							Store.isReadOnly(false)
							Store.currentVersion(nil)
							local keyData = Store.currentKeyData()
							if keyData then
								Store.editedData(Functional.deepClone(keyData.value))
							end
							Store.setView("versions")
							return
						end

						if Store.hasUnsavedChanges() then
							-- TODO: Show confirmation modal
							Store.discardChanges()
						end
						-- Return to the view we came from (query or browse)
						local prev = Store.previousView()
						if prev == "query" then
							Store.setView("query")
						else
							Store.setView("browse")
						end
					end,
					
					action(function(btn)
						Tooltip.addTooltip(btn, "Back to key list", "bottom")
					end),

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

				-- Key name and metadata (fills available space)
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
					},

					create "TextBox" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 20),
						BackgroundTransparency = 1,
						Text = function()
							return Store.currentKey() or "Key"
						end,
						TextColor3 = function()
							return theme.colors().foreground
						end,
						TextSize = theme.fontSize.large,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.fontMono,
						TextEditable = false,
						ClearTextOnFocus = false,
						TextTruncate = Enum.TextTruncate.AtEnd,
					},

					create "TextLabel" {
						LayoutOrder = 2,
						Size = function()
							return UDim2.new(1, 0, 0, 16 * metadataRowWeight())
						end,
						BackgroundTransparency = 1,
						Text = keyMetadata,
						TextColor3 = function()
							return theme.colors().foregroundSecondary
						end,
						TextTransparency = function()
							return 1 - metadataRowWeight()
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.font,
						TextTruncate = Enum.TextTruncate.AtEnd,
					},
				},

				-- Unsaved indicator
				create "TextLabel" {
					LayoutOrder = 3,
					Size = UDim2.fromOffset(80, 24),
					BackgroundColor3 = function()
						return theme.colors().warning
					end,
					Text = "Unsaved",
					TextColor3 = Color3.new(0, 0, 0),
					TextSize = theme.fontSize.small,
					FontFace = theme.font,
					Visible = function()
						return Store.hasUnsavedChanges() and not isCompact()
					end,

					create "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},
				},

				-- Actions
				create "Frame" {
					LayoutOrder = 4,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 32),
					BackgroundTransparency = 1,

					create "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
					},

					-- Query button
					Button({
						text = "Query",
						onClick = function()
							local key = Store.currentKey()
							if key then
								Store.queryKeyListText(key)
							end
							Store.setView("query")
						end,
						variant = "ghost",
						size = "small",
						tooltip = "Query this key",
					}),

					-- Export button
					create "Frame" {
						Size = function()
							return UDim2.fromOffset(exportActionWidth(), 32)
						end,
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						Visible = function()
							return showExportAction() or exportActionWidth() > 1
						end,

						Button({
							text = "Export",
							onClick = handleExport,
							variant = "ghost",
							size = "small",
							tooltip = "Export to .luau file",
							fullWidth = true,
						}),
					},

					-- Versions button
					create "Frame" {
						Size = function()
							return UDim2.fromOffset(versionsActionWidth(), 32)
						end,
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						Visible = function()
							return showVersionsAction() or versionsActionWidth() > 1
						end,

						Button({
							text = "Versions",
							onClick = function()
								Store.setView("versions")
							end,
							variant = "ghost",
							size = "small",
							tooltip = "View version history",
							fullWidth = true,
						}),
					},

					-- Delete button
					create "Frame" {
						Size = function()
							return UDim2.fromOffset(deleteActionWidth(), 32)
						end,
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						Visible = function()
							return showDeleteAction() or deleteActionWidth() > 1
						end,

						Button({
							text = "",
							onClick = function()
								if not isDiffMode() then
									handleDelete()
								end
							end,
							variant = "ghost",
							icon = theme.icons.delete,
							size = "small",
							tooltip = "Delete this key",
							disabled = isDiffMode,
							fullWidth = true,
						}),
					},

					-- Divider
					create "Frame" {
						Size = function()
							return UDim2.fromOffset(dividerActionWidth(), 20)
						end,
						BackgroundColor3 = function()
							return theme.colors().border
						end,
						BorderSizePixel = 0,
						BackgroundTransparency = function()
							return if dividerActionWidth() > 0.5 then 0 else 1
						end,
						Visible = function()
							return showDividerAction() or dividerActionWidth() > 0.1
						end,
					},

					-- Save button
					Button({
						text = function()
							if Store.isSavingKey() then
								return "Saving..."
							end
							return "Save"
						end,
						onClick = handleSave,
						variant = function()
							return if Store.hasUnsavedChanges() then "primary" else "secondary"
						end :: any,
						size = "small",
						disabled = function()
							return isDiffMode() or not Store.hasUnsavedChanges() or Store.isSavingKey()
						end,
						tooltip = "Save changes (Ctrl+S)",
					}),
				},
			},
		},

		-- Toolbar (Search, View mode, Hooks)
		create "Frame" {
			Name = "Toolbar",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 48),
			BackgroundColor3 = function()
				return theme.colors().backgroundSecondary
			end,
			BorderSizePixel = 0,

			create "UIPadding" {
				PaddingLeft = function()
					return UDim.new(0, if hasToolbarControls() then 12 else 0)
				end,
				PaddingRight = function()
					return UDim.new(0, if hasToolbarControls() then 12 else 0)
				end,
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
			},

			create "Frame" {
				Name = "ToolbarContainer",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					Padding = function()
						return UDim.new(0, if hasToolbarControls() then 12 else 0)
					end,
				},

				-- Search bar
				create "Frame" {
					LayoutOrder = 1,
					Size = UDim2.new(0, 0, 1, 0),
					BackgroundTransparency = 1,

					create "UIFlexItem" {
						FlexMode = Enum.UIFlexMode.Fill,
					},

				SearchBar({
					value = Store.searchQuery,
					onChange = Store.setSearchQuery,
					mode = Store.searchMode,
					onModeChange = Store.setSearchMode,
					useRegex = Store.useRegex,
					onRegexToggle = function()
						Store.setUseRegex(not Store.useRegex())
					end,
					resultCount = Store.searchResultCount,
					currentResult = Store.currentSearchIndex,
					onNextResult = Store.nextSearchResult,
					onPrevResult = Store.prevSearchResult,
					onClear = function()
						Store.setSearchQuery("")
					end,
					focusRef = searchFocusRef,
					patternError = function(): string?
						if Store.useRegex() then
							local err = Store.searchError()
							return if err ~= "" then err else nil
						end
						return nil
					end,
					dropdownPortal = function(dropdown: Frame)
						dropdown.Parent = dropdownPortalFrame
					end,
				}),
				},

				create "Frame" {
					LayoutOrder = 3,
					Size = function()
						return UDim2.fromOffset(toolbarTabsWidth(), 32)
					end,
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Visible = function()
						return showToolbarTabs() or toolbarTabsWidth() > 1
					end,

					Tabs({
						tabs = viewTabs,
						activeTab = viewMode,
						onTabChange = function(tab)
							if isDiffMode() then
								viewMode("tree")
								return
							end
							viewMode(tab :: "tree" | "code")
							if tab == "code" then
								updateCodeEditor()
							end
						end,
					}),
				},

				create "Frame" {
					LayoutOrder = 4,
					Size = function()
						return UDim2.fromOffset(toolbarExpandWidth(), 32)
					end,
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Visible = function()
						return showExpandControls() or toolbarExpandWidth() > 1
					end,

					create "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 4),
					},

					create "ImageButton" {
						Size = UDim2.fromOffset(28, 28),
						BackgroundColor3 = function()
							return theme.colors().backgroundTertiary
						end,
						Image = "",

						Activated = expandAll,
						
						action(function(btn)
							Tooltip.addTooltip(btn, "Expand all", "bottom")
						end),

						create "UICorner" {
							CornerRadius = UDim.new(0, 4),
						},
						
						create "ImageLabel" {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromOffset(16, 16),
							BackgroundTransparency = 1,
							Image = theme.icons.expand,
							ImageColor3 = function()
								return theme.colors().foreground
							end,
						},
					},

					create "ImageButton" {
						Size = UDim2.fromOffset(28, 28),
						BackgroundColor3 = function()
							return theme.colors().backgroundTertiary
						end,
						Image = "",

						Activated = collapseAll,
						
						action(function(btn)
							Tooltip.addTooltip(btn, "Collapse all", "bottom")
						end),

						create "UICorner" {
							CornerRadius = UDim.new(0, 4),
						},
						
						create "ImageLabel" {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromOffset(16, 16),
							BackgroundTransparency = 1,
							Image = theme.icons.collapse,
							ImageColor3 = function()
								return theme.colors().foreground
							end,
						},
					},
				},

				create "Frame" {
					LayoutOrder = 5,
					Size = function()
						return UDim2.fromOffset(toolbarUndoWidth(), 32)
					end,
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Visible = function()
						return showUndoRedoControls() or toolbarUndoWidth() > 1
					end,

					create "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 4),
					},

					create "ImageButton" {
						Size = UDim2.fromOffset(28, 28),
						BackgroundColor3 = function()
							return theme.colors().backgroundTertiary
						end,
						BackgroundTransparency = function()
							return if Store.canUndo() then 0 else 0.5
						end,
						Image = "",

						Activated = function()
							if Store.canUndo() then
								Store.undo()
							end
						end,
						
						action(function(btn)
							Tooltip.addTooltip(btn, "Undo (Ctrl+Z)", "bottom")
						end),

						create "UICorner" {
							CornerRadius = UDim.new(0, 4),
						},
						
						create "ImageLabel" {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromOffset(16, 16),
							BackgroundTransparency = 1,
							Image = theme.icons.undo,
							ImageColor3 = function()
								local c = theme.colors()
								return if Store.canUndo() then c.foreground else c.foregroundMuted
							end,
						},
					},

					create "ImageButton" {
						Size = UDim2.fromOffset(28, 28),
						BackgroundColor3 = function()
							return theme.colors().backgroundTertiary
						end,
						BackgroundTransparency = function()
							return if Store.canRedo() then 0 else 0.5
						end,
						Image = "",

						Activated = function()
							if Store.canRedo() then
								Store.redo()
							end
						end,
						
						action(function(btn)
							Tooltip.addTooltip(btn, "Redo (Ctrl+Y)", "bottom")
						end),

						create "UICorner" {
							CornerRadius = UDim.new(0, 4),
						},
						
						create "ImageLabel" {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromOffset(16, 16),
							BackgroundTransparency = 1,
							Image = theme.icons.redo,
							ImageColor3 = function()
								local c = theme.colors()
								return if Store.canRedo() then c.foreground else c.foregroundMuted
							end,
						},
					},
				},
			},
		},

		-- Data Statistics Bar
		create "Frame" {
			Name = "StatsBar",
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = function()
				return theme.colors().backgroundTertiary
			end,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			
			DataStats.DataStats({
				data = Store.editedData,
				keyInfo = function()
					local keyData = Store.currentKeyData()
					if keyData and keyData.keyInfo then
						return keyData.keyInfo
					end
					return nil
				end,
				rawSize = Store.rawDataSize,
			}),
		},

		-- Content area
		create "Frame" {
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 1, -132), -- Adjusted for stats bar (104 + 28)
			BackgroundTransparency = 1,

			-- Tree View
			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = function()
						return viewMode() == "tree" or isDiffMode()
				end,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				},

				-- Breadcrumbs
				create "Frame" {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 24),
					BackgroundTransparency = 1,
					
					create "UIPadding" {
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
					},
					
					Breadcrumbs.BreadcrumbsCompact({
						path = function()
							local currentPath = scrollPath()
							if #currentPath == 0 then
								return currentPath
							end
							local parentPath = table.clone(currentPath)
							table.remove(parentPath, #parentPath)
							return parentPath
						end,
						onNavigate = function(path)
							-- Navigate to path (could scroll to it in future)
						end,
						rootLabel = "Data",
					}),
				},

				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 1, -32),
					BackgroundTransparency = 1,
					
					TreeView({
						data = Store.editedData,
						onValueChange = Store.updateEditedDataAtPath,
						onDelete = Store.deleteAtPath,
						onInsert = Store.insertAtPath,
						readOnly = Store.isReadOnly,
						searchQuery = Store.searchQuery,
						searchResults = Store.searchResults,
						currentSearchResult = Store.currentSearchResult,
						expandRef = expandRef,
						onScrollPathChange = function(path)
							scrollPath(path)
						end,
						useAlternatingColors = function()
							return Store.settings().useAlternatingKeyColors
						end,
						diffPathKinds = function()
							local diffView = Store.diffView()
							if diffView then
								return diffView.pathKinds
							end
							return {}
						end,
						visiblePathFilter = function()
							local diffView = Store.diffView()
							if diffView then
								return diffView.pathFilter
							end
							return {}
						end,
					}),
				},
			},

			-- Code View
			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = function()
					return viewMode() == "code" and not isDiffMode()
				end,

				create "UIPadding" {
					PaddingLeft = UDim.new(0, 12),
					PaddingRight = UDim.new(0, 12),
					PaddingTop = UDim.new(0, 12),
					PaddingBottom = UDim.new(0, 12),
				},

				create "ScrollingFrame" {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = function()
						return theme.colors().backgroundSecondary
					end,
					BorderSizePixel = 0,
					ScrollBarThickness = 8,
					ScrollBarImageColor3 = function()
						return theme.colors().scrollbar
					end,
					CanvasSize = UDim2.new(0, 0, 0, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.XY,

					create "UICorner" {
						CornerRadius = UDim.new(0, theme.radius.md),
					},

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
						PaddingTop = UDim.new(0, 12),
						PaddingBottom = UDim.new(0, 12),
					},

					create "TextBox" {
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Text = codeEditorText,
						TextColor3 = function()
							return theme.colors().foreground
						end,
						TextSize = theme.fontSize.normal,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						FontFace = theme.fontMono,
						MultiLine = true,
						TextWrapped = false,
						ClearTextOnFocus = false,
						TextEditable = function()
							return not Store.isReadOnly()
						end,

						FocusLost = function(rbx: TextBox)
							-- Try to parse and update data
							local text = rbx.Text
							local success, parsed = pcall(function()
								return game:GetService("HttpService"):JSONDecode(text)
							end)

							if success then
								Store.setEditedData(parsed)
							else
								Store.showToast("error", "Invalid JSON")
								updateCodeEditor() -- Reset to valid JSON
							end
						end,
					},
				},
			},
		},

		-- Delete confirmation modal overlay
		create "TextButton" {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			Visible = showDeleteConfirm,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 10,

			Activated = cancelDelete,

			-- Dialog box
			create "Frame" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(320, 160),
				BackgroundColor3 = function()
					return theme.colors().backgroundSecondary
				end,
				ZIndex = 11,

				create "UICorner" {
					CornerRadius = UDim.new(0, 8),
				},

				create "UIPadding" {
					PaddingLeft = UDim.new(0, 20),
					PaddingRight = UDim.new(0, 20),
					PaddingTop = UDim.new(0, 20),
					PaddingBottom = UDim.new(0, 20),
				},

				-- Title
				create "TextLabel" {
					Position = UDim2.new(0, 0, 0, 0),
					Size = UDim2.new(1, 0, 0, 24),
					BackgroundTransparency = 1,
					Text = "Delete Key?",
					TextColor3 = function()
						return theme.colors().foreground
					end,
					TextSize = theme.fontSize.large,
					FontFace = theme.font,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 12,
				},

				-- Message
				create "TextLabel" {
					Position = UDim2.new(0, 0, 0, 32),
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					Text = function()
						return `Are you sure you want to delete "{Store.currentKey() or ""}"? This cannot be undone.`
					end,
					TextColor3 = function()
						return theme.colors().foregroundMuted
					end,
					TextSize = theme.fontSize.normal,
					FontFace = theme.font,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 12,
				},

				-- Cancel button
				create "TextButton" {
					Position = UDim2.new(0.5, -70, 1, -40),
					Size = UDim2.fromOffset(60, 32),
					BackgroundColor3 = function()
						return theme.colors().backgroundTertiary
					end,
					Text = "Cancel",
					TextColor3 = function()
						return theme.colors().foreground
					end,
					TextSize = theme.fontSize.normal,
					FontFace = theme.font,
					ZIndex = 12,

					Activated = cancelDelete,

					create "UICorner" {
						CornerRadius = UDim.new(0, 6),
					},
				},

				-- Delete button
				create "TextButton" {
					Position = UDim2.new(0.5, 10, 1, -40),
					Size = UDim2.fromOffset(60, 32),
					BackgroundColor3 = function()
						return theme.colors().error
					end,
					Text = "Delete",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = theme.fontSize.normal,
					FontFace = theme.font,
					ZIndex = 12,

					Activated = confirmDelete,

					create "UICorner" {
						CornerRadius = UDim.new(0, 6),
					},
				},
			},
		},

		}, -- end Content frame
	}
end

return EditKeyView
