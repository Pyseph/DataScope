--!strict
--[[
	Connect View
	DataStore connection form using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Store = require(script.Parent.Parent.Parent.core.Store)
local Types = require(script.Parent.Parent.Parent.core.Types)
local Operations = require(script.Parent.Parent.Parent.datastore.Operations)

local Button = require(script.Parent.Parent.components.Button)
local TextInput = require(script.Parent.Parent.components.TextInput)
local Select = require(script.Parent.Parent.components.Select)
local Tabs = require(script.Parent.Parent.components.Tabs)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local indexes = Vide.indexes
local spring = Vide.spring

type ConnectionInfo = Types.ConnectionInfo
type DataStoreType = Types.DataStoreType

local function ConnectView(): Frame
	local theme = Theme.get()

	-- Get last used datastore name from history
	local function getLastDatastoreName(): string
		local history = Store.history()
		if #history > 0 then
			-- Get most recent entry (first in list)
			return history[1].connectionInfo.name or ""
		end
		return ""
	end

	-- Form state (pre-populate from last used)
	local datastoreType = source("Normal" :: DataStoreType)
	local datastoreName = source(getLastDatastoreName())
	local scope = source("")
	local allScopes = source(false)

	-- Validation
	local nameError = derive(function(): string?
		local name = datastoreName()
		if #name == 0 then
			return nil -- Don't show error for empty
		end
		local valid, err = Operations.validateDataStoreName(name)
		return if valid then nil else err
	end)

	local scopeError = derive(function(): string?
		local s = scope()
		if #s == 0 then
			return nil
		end
		local valid, err = Operations.validateScope(s)
		return if valid then nil else err
	end)

	local canConnect = derive(function(): boolean
		local name = datastoreName()
		local dsType = datastoreType()

		if #name == 0 then
			return false
		end
		if nameError() then
			return false
		end
		if scopeError() then
			return false
		end
		-- Ordered DataStore requires a scope
		if dsType == "Ordered" and #scope() == 0 then
			return false
		end
		return true
	end)

	local handleConnect = function()
		if not canConnect() then
			return
		end

		local connectionInfo: ConnectionInfo = {
			datastoreType = datastoreType(),
			name = datastoreName(),
			scope = if #scope() > 0 then scope() else nil,
			allScopes = allScopes(),
		}

		Store.isConnecting(true)
		Store.connectionError(nil)

		-- Attempt connection
		local result = Operations.getDataStore(connectionInfo)

		if result.success then
			Store.setConnection(connectionInfo)
			Store.setView("browse")
			Store.isConnecting(false)
		else
			Store.connectionError(result.error)
			Store.isConnecting(false)
			Store.showToast("error", `Connection failed: {result.error}`)
		end
	end

	-- DataStore type options
	local typeOptions = {
		{ value = "Normal" :: DataStoreType, label = "Normal DataStore", description = "Standard key-value storage" },
		{ value = "Ordered" :: DataStoreType, label = "Ordered DataStore", description = "Sorted by integer values" },
		{
			value = "Global" :: DataStoreType,
			label = "Global DataStore",
			description = "Access data across all scopes",
		},
	}

	-- History item component
	local HistoryItem =
		function(record: () -> Types.HistoryRecord, index: number, onSelect: (Types.HistoryRecord) -> ()): Frame
			local isHovered = source(false)
			local r = record()
			
			local targetBackgroundColor = derive(function()
				local c = theme.colors()
				if isHovered() then
					return c.backgroundTertiary
				end
				return c.backgroundSecondary
			end)
			
			local backgroundColor = spring(targetBackgroundColor, 0.1)
			local scale = spring(function()
				return if isHovered() then 1.01 else 1
			end, 0.15)

			return create "Frame" {
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, 64),
				BackgroundColor3 = backgroundColor,
				BorderSizePixel = 0,
				
				create "UIScale" {
					Scale = scale,
				},

				MouseEnter = function()
					isHovered(true)
				end,

				MouseLeave = function()
					isHovered(false)
				end,

				create "UICorner" {
					CornerRadius = UDim.new(0, theme.radius.md),
				},

				create "UIPadding" {
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
					PaddingTop = UDim.new(0, 12),
					PaddingBottom = UDim.new(0, 12),
				},

				create "TextButton" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "",

					Activated = function()
						onSelect(record())
					end,

					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
					},

					create "Frame" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 24),
						BackgroundTransparency = 1,

						create "UIListLayout" {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 8),
						},

						-- Type badge
						create "TextLabel" {
							Size = UDim2.fromOffset(60, 20),
							BackgroundColor3 = function()
								return theme.colors().accent
							end,
							Text = r.connectionInfo.datastoreType,
							TextColor3 = Color3.new(1, 1, 1),
							TextSize = theme.fontSize.small,
							FontFace = theme.fontMedium,

							create "UICorner" {
								CornerRadius = UDim.new(0, 4),
							},
						},

						-- Name
						create "TextLabel" {
							Size = UDim2.new(1, -100, 0, 24),
							BackgroundTransparency = 1,
							Text = r.connectionInfo.name,
							TextColor3 = function()
								return theme.colors().foreground
							end,
							TextSize = theme.fontSize.large,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.fontMedium,
							TextTruncate = Enum.TextTruncate.AtEnd,
						},

						-- Pin button
						create "ImageButton" {
							Size = UDim2.fromOffset(18, 18),
							BackgroundTransparency = 1,
							Image = theme.icons.pin,
							ImageColor3 = function()
								local c = theme.colors()
								if r.pinned then
									return c.accent
								end
								return c.foregroundMuted
							end,

							Activated = function()
								Store.toggleHistoryPin(index)
							end,
						},
					},

					create "TextLabel" {
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 0, 16),
						BackgroundTransparency = 1,
						Text = if r.connectionInfo.scope then `Scope: {r.connectionInfo.scope}` else "No scope",
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.font,
					},
				},
			}
		end

	-- Tabs for connect form vs history
	local tabs = {
		{ id = "connect", label = "Connect" },
		{ id = "history", label = "History" },
	}

	local selectHistoryRecord = function(record: Types.HistoryRecord)
		datastoreType(record.connectionInfo.datastoreType)
		datastoreName(record.connectionInfo.name)
		scope(record.connectionInfo.scope or "")
		allScopes(record.connectionInfo.allScopes)
		Store.setTab("connect")
	end

	return create "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return theme.colors().background
		end,
		BorderSizePixel = 0,

		create "UIPadding" {
			PaddingLeft = UDim.new(0, 24),
			PaddingRight = UDim.new(0, 24),
			PaddingTop = UDim.new(0, 24),
			PaddingBottom = UDim.new(0, 24),
		},

		create "Frame" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			create "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 24),
			},

			-- Header
			create "TextLabel" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundTransparency = 1,
				Text = "DataScope",
				TextColor3 = function()
					return theme.colors().foreground
				end,
				TextSize = theme.fontSize.xl,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = theme.fontBold,
			},

			-- Tabs
			create "Frame" {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundTransparency = 1,

				Tabs({
					tabs = tabs,
					activeTab = Store.currentTab,
					onTabChange = Store.setTab,
				}),
			},

			-- Content based on tab
			create "Frame" {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 1, -120),
				BackgroundTransparency = 1,

				-- Connect form
				create "ScrollingFrame" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ScrollBarThickness = 6,
					ScrollBarImageColor3 = function()
						return theme.colors().scrollbar
					end,
					CanvasSize = UDim2.new(0, 0, 0, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					BorderSizePixel = 0,
					Visible = function()
						return Store.currentTab() == "connect"
					end,

					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 16),
					},

					-- DataStore Type
					create "Frame" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,

						Select({
							value = datastoreType,
							options = typeOptions,
							onChange = function(value)
								datastoreType(value)
							end,
							label = "DataStore Type",
						}),
					},

					-- DataStore Name
					create "Frame" {
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,

						TextInput({
							value = datastoreName,
							onChange = function(value)
								datastoreName(value)
							end,
							placeholder = "Enter DataStore name...",
							label = "DataStore Name",
							validate = function(value)
								if #value == 0 then
									return true, nil
								end
								return Operations.validateDataStoreName(value)
							end,
						}),
					},

					-- Scope (optional for Normal, required for Ordered)
					create "Frame" {
						LayoutOrder = 3,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,

						TextInput({
							value = scope,
							onChange = function(value)
								scope(value)
							end,
							placeholder = "Enter scope (optional)...",
							label = function()
								if datastoreType() == "Ordered" then
									return "Scope (required)"
								end
								return "Scope (optional)"
							end :: any,
							validate = function(value)
								if #value == 0 then
									return true, nil
								end
								return Operations.validateScope(value)
							end,
						}),
					},

					-- All Scopes toggle (only for Normal DataStore)
					create "Frame" {
						LayoutOrder = 4,
						Size = UDim2.new(1, 0, 0, 32),
						BackgroundTransparency = 1,
						Visible = function()
							return datastoreType() == "Normal"
						end,

						create "UIListLayout" {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 8),
						},

						create "TextButton" {
							Size = UDim2.fromOffset(20, 20),
							BackgroundColor3 = function()
								local c = theme.colors()
								if allScopes() then
									return c.accent
								end
								return c.backgroundSecondary
							end,
							BorderSizePixel = 0,
							Text = "",

							Activated = function()
								allScopes(not allScopes())
							end,

							create "UICorner" {
								CornerRadius = UDim.new(0, 4),
							},

							create "UIStroke" {
								Color = function()
									local c = theme.colors()
									if allScopes() then
										return c.accent
									end
									return c.border
								end,
								Thickness = 1,
							},

							create "ImageLabel" {
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = UDim2.fromOffset(14, 14),
								BackgroundTransparency = 1,
								Image = theme.icons.check,
								ImageColor3 = Color3.new(1, 1, 1),
								Visible = allScopes,
							},
						},

						create "TextLabel" {
							Size = UDim2.new(1, -30, 1, 0),
							BackgroundTransparency = 1,
							Text = "Access all scopes",
							TextColor3 = function()
								return theme.colors().foreground
							end,
							TextSize = theme.fontSize.normal,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.font,
						},
					},

					-- Error message
					create "TextLabel" {
						LayoutOrder = 5,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Text = function()
							return Store.connectionError() or ""
						end,
						TextColor3 = function()
							return theme.colors().error
						end,
						TextSize = theme.fontSize.normal,
						TextWrapped = true,
						FontFace = theme.font,
						Visible = function()
							return Store.connectionError() ~= nil
						end,
					},

					-- Connect button
					create "Frame" {
						LayoutOrder = 6,
						Size = UDim2.new(1, 0, 0, 40),
						BackgroundTransparency = 1,

						Button({
							text = function()
								if Store.isConnecting() then
									return "Connecting..."
								end
								return "Connect"
							end,
							onClick = handleConnect,
							variant = "primary",
							disabled = function()
								return not canConnect() or Store.isConnecting()
							end,
							fullWidth = true,
						}),
					},
				},

				-- History list
				create "ScrollingFrame" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ScrollBarThickness = 6,
					ScrollBarImageColor3 = function()
						return theme.colors().scrollbar
					end,
					CanvasSize = UDim2.new(0, 0, 0, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					BorderSizePixel = 0,
					Visible = function()
						return Store.currentTab() == "history"
					end,

					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 12),
					},

					indexes(Store.history, function(record, index)
						return HistoryItem(record, index, selectHistoryRecord)
					end),

					-- Empty state
					create "TextLabel" {
						Size = UDim2.new(1, 0, 0, 80),
						BackgroundTransparency = 1,
						Text = "No connection history yet.\nConnect to a DataStore to see it here.",
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.normal,
						FontFace = theme.font,
						Visible = function()
							return #Store.history() == 0
						end,
					},
				},
			},
		},
	}
end

return ConnectView
