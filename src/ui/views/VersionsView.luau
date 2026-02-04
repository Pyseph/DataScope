--!strict
--[[
	Versions View
	Key version history browser using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Store = require(script.Parent.Parent.Parent.core.Store)
local Types = require(script.Parent.Parent.Parent.core.Types)
local Operations = require(script.Parent.Parent.Parent.datastore.Operations)

local Button = require(script.Parent.Parent.components.Button)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local indexes = Vide.indexes
local spring = Vide.spring

type VersionInfo = Types.VersionInfo

local function VersionsView(): Frame
	local theme = Theme.get()

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
		else
			Store.showToast("error", `Failed to load versions: {versionsResult.error}`)
		end

		Store.versionListLoading(false)
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
			Store.currentKeyData(keyResult.value)
			Store.currentVersion(version)
			Store.editedData(keyResult.value.value)
			Store.isReadOnly(true) -- Version data is read-only
			Store.hasUnsavedChanges(false)
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
			Size = UDim2.new(1, 0, 0, 60),
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
				PaddingRight = UDim.new(0, 16),
			},

			create "TextButton" {
				Size = UDim2.fromScale(1, 1),
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

		-- Version list
		create "ScrollingFrame" {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 1, -64),
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

			-- Loading state
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
