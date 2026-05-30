--!strict
--[[
	Browse View
	DataStore key browsing using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Store = require(script.Parent.Parent.Parent.core.Store)
local Types = require(script.Parent.Parent.Parent.core.Types)
local Operations = require(script.Parent.Parent.Parent.datastore.Operations)
local KeyViewLoader = require(script.Parent.Parent.Parent.datastore.KeyViewLoader)
local Functional = require(script.Parent.Parent.Parent.utils.Functional)
local Players = game:GetService("Players")

local Button = require(script.Parent.Parent.components.Button)
local Select = require(script.Parent.Parent.components.Select)
local TextInput = require(script.Parent.Parent.components.TextInput)
local VirtualizedList = require(script.Parent.Parent.components.VirtualizedList)
local Tooltip = require(script.Parent.Parent.components.Tooltip)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local show = Vide.show
local action = Vide.action

type KeyInfo = Types.KeyInfo

local function BrowseView(): Frame
	local theme = Theme.get()

	-- Local filter state
	local keyFilter = source("")
	local quickLoginLoading = source(false)

	local canQuickLogin = derive(function(): boolean
		local localPlayer = Players.LocalPlayer
		return localPlayer ~= nil and localPlayer.UserId > 0
	end)

	local keyTemplateOptions = derive(function(): { any }
		local options: { any } = {}
		for _, template in Store.settings().keyTemplates do
			table.insert(options, {
				value = template.id,
				label = template.label,
				description = template.template,
			})
		end
		return options
	end)

	-- Auto-lookup state for keys not in the loaded page
	local lookupStatus = source("idle" :: "idle" | "loading" | "found" | "not_found" | "error")
	local lookupKey = source(nil :: KeyInfo?)
	local lookupDebounce = source(0) -- counter to cancel stale lookups

	-- Filtered keys
	local filteredKeys = derive(function(): { KeyInfo }
		local keys = Store.keyList()
		local filter = string.lower(keyFilter())

		if #filter == 0 then
			return keys
		end

		return Functional.filter(keys, function(key)
			return string.find(string.lower(key.key), filter, 1, true) ~= nil
		end)
	end)

	-- Combined keys: filtered loaded keys + auto-looked-up key
	local displayKeys = derive(function(): { KeyInfo }
		local filtered = filteredKeys()
		local looked = lookupKey()
		local status = lookupStatus()

		-- If we have filtered results from the loaded list, just show those
		if #filtered > 0 then
			return filtered
		end

		-- If auto-lookup found a key, show it
		if status == "found" and looked then
			return { looked }
		end

		return filtered
	end)

	-- Auto-lookup: when filter has text but no loaded keys match, search the DataStore
	local function triggerAutoLookup(query: string)
		local connection = Store.connection()
		if not connection then
			return
		end

		-- Increment debounce counter to cancel any in-flight lookups
		local currentDebounce = lookupDebounce() + 1
		lookupDebounce(currentDebounce)

		-- Reset state
		lookupKey(nil)

		if #query == 0 then
			lookupStatus("idle")
			return
		end

		-- Check if the query already matches loaded keys
		local keys = Store.keyList()
		local lowerQuery = string.lower(query)
		for _, key in keys do
			if string.find(string.lower(key.key), lowerQuery, 1, true) then
				lookupStatus("idle")
				return -- loaded list has matches, no need to look up
			end
		end

		-- Debounce: wait before making the API call
		lookupStatus("loading")
		task.delay(0.5, function()
			-- Check if this lookup is still current
			if lookupDebounce() ~= currentDebounce then
				return
			end

			local dsResult = Operations.getDataStore(connection)
			if not dsResult.success then
				if lookupDebounce() == currentDebounce then
					lookupStatus("error")
				end
				return
			end

			local datastore = dsResult.value :: DataStore
			local keyResult = Operations.getKey(datastore, query)

			-- Check if still current after async call
			if lookupDebounce() ~= currentDebounce then
				return
			end

			if keyResult.success and keyResult.value.value ~= nil then
				lookupKey({ key = query } :: KeyInfo)
				lookupStatus("found")
			else
				lookupKey(nil)
				lookupStatus("not_found")
			end
		end)
	end

	-- Load keys from the connected DataStore
	local loadKeys = function()
		local connection = Store.connection()
		if not connection then
			return
		end

		Store.keyListLoading(true)
		Store.keyListError(nil)

		local dsResult = Operations.getDataStore(connection)
		if not dsResult.success then
			Store.keyListError(dsResult.error)
			Store.keyListLoading(false)
			return
		end

		if connection.datastoreType == "Ordered" then
			local datastore = dsResult.value :: OrderedDataStore
			local orderedResult = Operations.listOrderedKeys(
				datastore,
				Store.orderedAscending(),
				Store.orderedRangeMin(),
				Store.orderedRangeMax(),
				nil
			)

			if orderedResult.success then
				local keys: { KeyInfo } = {}
				for _, item in orderedResult.value.keys do
					table.insert(keys, {
						key = item.key,
						orderedValue = item.value,
					})
				end
				Store.keyList(keys)
				Store.hasMoreKeys(orderedResult.value.hasMore)
			else
				Store.keyListError(orderedResult.error)
			end
		else
			local datastore = dsResult.value :: DataStore
			local keysResult = Operations.listKeys(datastore, Store.keyPrefix() or nil, nil)

			if keysResult.success then
				Store.keyList(keysResult.value.keys)
				Store.hasMoreKeys(keysResult.value.cursor ~= nil)
			else
				Store.keyListError(keysResult.error)
			end
		end

		Store.keyListLoading(false)
	end

	-- Load a specific key
	local loadKey = function(keyName: string, requireExisting: boolean?)
		local connection = Store.connection()
		if not connection then
			return
		end

		Store.isLoadingKey(true)
		Store.keyError(nil)

		local dsResult = Operations.getDataStore(connection)
		if not dsResult.success then
			Store.keyError(dsResult.error)
			Store.isLoadingKey(false)
			return
		end

		local datastore = dsResult.value :: DataStore
		local keyResult = Operations.getKey(datastore, keyName)

		if keyResult.success and (not requireExisting or keyResult.value.value ~= nil) then
			local context = {
				datastoreName = connection.name,
				key = keyName,
				scope = connection.scope,
			}
			local prepared = KeyViewLoader.prepare(keyResult.value, context, true)
			Store.setCurrentKey(keyName, prepared.keyData, prepared.rawSize)
			if prepared.hookName then
				Store.showToast("info", `Auto-detected: {prepared.hookName}`)
			end

			Store.isReadOnly(false)
			Store.setView("editKey")
		else
			local errorMessage = if keyResult.success
				then `Key "{keyName}" does not exist`
				else keyResult.error
			Store.keyError(errorMessage)
			Store.showToast("error", `Failed to load key: {errorMessage}`)
		end

		Store.isLoadingKey(false)
	end

	local quickLoginIntoUserKey = function()
		local localPlayer = Players.LocalPlayer
		if not localPlayer or localPlayer.UserId <= 0 then
			Store.showToast("warning", "LocalPlayer is unavailable. Start a local play session and try again.")
			return
		end

		local userKey, errorMessage = Store.renderSelectedKeyTemplate(localPlayer.UserId)
		if not userKey then
			Store.showToast("warning", errorMessage or "Selected key template is invalid")
			return
		end

		keyFilter(userKey)
		triggerAutoLookup(userKey)

		quickLoginLoading(true)
		loadKey(userKey, true)
		quickLoginLoading(false)
	end

	-- Load keys when the view is first shown
	task.defer(function()
		if Store.connection() and #Store.keyList() == 0 then
			loadKeys()
		end
	end)

	-- Format timestamp
	local formatTime = function(timestamp: number?): string
		if not timestamp then
			return "N/A"
		end
		local date = os.date("*t", math.floor(timestamp / 1000))
		return string.format(
			"%04d-%02d-%02d %02d:%02d",
			date.year,
			date.month,
			date.day,
			date.hour,
			date.min
		)
	end

	-- Key row component (reactive index for pool-based virtualized list)
	local KeyRow = function(keyInfo: () -> KeyInfo?, index: () -> number): Frame
		local isHovered = source(false)

		return create "Frame" {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = function()
				local c = theme.colors()
				if isHovered() then
					return c.backgroundTertiary
				end
				if index() % 2 == 0 then
					return c.backgroundSecondary
				end
				return c.background
			end,
			BorderSizePixel = 0,
			Visible = function()
				return keyInfo() ~= nil
			end,

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
					local k = keyInfo()
					if k then
						loadKey(k.key)
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

					-- Key icon
					create "ImageLabel" {
						LayoutOrder = 1,
						Size = UDim2.fromOffset(20, 20),
						BackgroundTransparency = 1,
						Image = theme.icons.key,
						ImageColor3 = function()
							return theme.colors().foregroundSecondary
						end,
					},

					-- Key info
					create "Frame" {
						LayoutOrder = 2,
						Size = UDim2.new(1, -160, 1, 0),
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
							Text = function()
								local k = keyInfo()
								return if k then k.key else ""
							end,
							TextColor3 = function()
								return theme.colors().foreground
							end,
							TextSize = theme.fontSize.normal,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.fontMono,
							TextTruncate = Enum.TextTruncate.AtEnd,
						},

						-- Updated time label (always created, visibility controlled reactively)
						create "TextLabel" {
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 0, 14),
							BackgroundTransparency = 1,
							Visible = function()
								local k = keyInfo()
								return k ~= nil and k.updatedTime ~= nil
							end,
							Text = function()
								local k = keyInfo()
								return if k and k.updatedTime then `Updated: {formatTime(k.updatedTime)}` else ""
							end,
							TextColor3 = function()
								return theme.colors().foregroundMuted
							end,
							TextSize = theme.fontSize.small,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.font,
						},
					},

					-- Value badge for Ordered DataStores
					create "TextLabel" {
						LayoutOrder = 3,
						Size = UDim2.fromOffset(110, 24),
						Visible = function()
							local k = keyInfo()
							return k ~= nil and k.orderedValue ~= nil
						end,
						BackgroundColor3 = function()
							return theme.colors().backgroundTertiary
						end,
						Text = function()
							local k = keyInfo()
							return if k and k.orderedValue ~= nil then `Value: {k.orderedValue}` else ""
						end,
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.small,
						FontFace = theme.fontMono,

						create "UICorner" {
							CornerRadius = UDim.new(0, 4),
						},
					},

					-- Version badge (always created, visibility controlled reactively)
					create "TextLabel" {
						LayoutOrder = 4,
						Size = UDim2.fromOffset(90, 24),
						Visible = function()
							local k = keyInfo()
							return k ~= nil and k.version ~= nil
						end,
						BackgroundColor3 = function()
							return theme.colors().backgroundTertiary
						end,
						Text = function()
							local k = keyInfo()
							return if k and k.version then `v{string.sub(k.version, 1, 8)}` else ""
						end,
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.small,
						FontFace = theme.fontMono,

						create "UICorner" {
							CornerRadius = UDim.new(0, 4),
						},
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
						Store.disconnect()
					end,
					
					action(function(btn)
						Tooltip.addTooltip(btn, "Disconnect", "bottom")
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

				-- Title (fills available space)
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

					create "TextLabel" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 24),
						BackgroundTransparency = 1,
						Text = function()
							local conn = Store.connection()
							return if conn then conn.name else "DataStore"
						end,
						TextColor3 = function()
							return theme.colors().foreground
						end,
						TextSize = theme.fontSize.xl,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.fontBold,
						TextTruncate = Enum.TextTruncate.AtEnd,
					},

					create "TextLabel" {
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 0, 18),
						BackgroundTransparency = 1,
						Text = function()
							local conn = Store.connection()
							if not conn then
								return ""
							end
							local parts = { conn.datastoreType }
							if conn.scope then
								table.insert(parts, `Scope: {conn.scope}`)
							end
							if conn.allScopes then
								table.insert(parts, "All Scopes")
							end
							return table.concat(parts, " • ")
						end,
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.font,
					},
				},

				-- Refresh button
				create "Frame" {
					LayoutOrder = 3,
					Size = UDim2.fromOffset(36, 36),
					BackgroundTransparency = 1,

					Button({
						text = "",
						onClick = loadKeys,
						variant = "ghost",
						icon = theme.icons.refresh,
						disabled = Store.keyListLoading,
						tooltip = "Refresh keys",
					}),
				},

				-- Query button
				create "Frame" {
					LayoutOrder = 4,
					Size = UDim2.fromOffset(36, 36),
					BackgroundTransparency = 1,

					Button({
						text = "",
						onClick = function()
							Store.setView("query")
						end,
						variant = "ghost",
						icon = theme.icons.search,
						tooltip = "Cross-key Query",
					}),
				},

				-- Settings button
				create "Frame" {
					LayoutOrder = 5,
					Size = UDim2.fromOffset(36, 36),
					BackgroundTransparency = 1,

					Button({
						text = "",
						onClick = function()
							Store.setView("settings")
						end,
						variant = "ghost",
						icon = theme.icons.settings,
						tooltip = "Settings",
					}),
				},
			},
		},

		-- Filter bar
		create "Frame" {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 96),
			BackgroundTransparency = 1,
			ZIndex = 50,

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
			},

			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 50,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				},

				create "Frame" {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 36),
					BackgroundTransparency = 1,

					TextInput({
						value = keyFilter,
						onChange = function(value)
							keyFilter(value)
							triggerAutoLookup(value)
						end,
						placeholder = "Search keys...",
					}),
				},

				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 36),
					BackgroundTransparency = 1,
					ZIndex = 60,

					create "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
					},

					create "Frame" {
						LayoutOrder = 1,
						Size = UDim2.new(1, -180, 1, 0),
						BackgroundTransparency = 1,
						ZIndex = 60,

						Select({
							value = function()
								return Store.getSelectedKeyTemplateId()
							end,
							options = keyTemplateOptions(),
							onChange = function(value)
								local success, errorMessage = Store.selectKeyTemplateForCurrentStore(value)
								if not success then
									Store.showToast("warning", errorMessage or "Unable to select key template")
								end
							end,
							placeholder = "Template",
						}),
					},

					create "Frame" {
						LayoutOrder = 2,
						Size = UDim2.fromOffset(172, 36),
						BackgroundTransparency = 1,

						Button({
							text = function()
								if quickLoginLoading() then
									return "Opening..."
								end
								if not canQuickLogin() then
									return "No LocalPlayer"
								end
								return "Open My Key"
							end,
							onClick = quickLoginIntoUserKey,
							variant = "secondary",
							icon = theme.icons.key,
							disabled = function()
								return quickLoginLoading() or not canQuickLogin()
							end,
							tooltip = "Open the selected LocalPlayer key template",
							fullWidth = true,
						}),
					},
				},
			},
		},

		-- Key list
		create "Frame" {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 1, -160),
			BackgroundTransparency = 1,
			ZIndex = 1,
			
			-- Loading state
			show(Store.keyListLoading, function()
				return create "Frame" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,

					create "TextLabel" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "Loading keys...",
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.normal,
						FontFace = theme.font,
					},
				}
			end),
			
			-- Error state
			show(function()
				return Store.keyListError() ~= nil and not Store.keyListLoading()
			end, function()
				return create "Frame" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,

					create "TextLabel" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = function()
							return Store.keyListError() or ""
						end,
						TextColor3 = function()
							return theme.colors().error
						end,
						TextSize = theme.fontSize.normal,
						FontFace = theme.font,
						TextWrapped = true,
					},
				}
			end),
			
		-- Auto-lookup loading state (shown when searching DataStore)
		show(function()
			return lookupStatus() == "loading" and #displayKeys() == 0 and not Store.keyListLoading() and Store.keyListError() == nil
		end, function()
			return create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,

				create "TextLabel" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = function()
						return `Looking up "{keyFilter()}"...`
					end,
					TextColor3 = function()
						return theme.colors().foregroundMuted
					end,
					TextSize = theme.fontSize.normal,
					FontFace = theme.font,
				},
			}
		end),

		-- Empty state
		show(function()
			return #displayKeys() == 0 and not Store.keyListLoading() and Store.keyListError() == nil and lookupStatus() ~= "loading"
		end, function()
			return create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 12),
				},

				create "ImageLabel" {
					LayoutOrder = 1,
					Size = UDim2.fromOffset(48, 48),
					BackgroundTransparency = 1,
					Image = theme.icons.key,
					ImageColor3 = function()
						return theme.colors().foregroundMuted
					end,
				},

				create "TextLabel" {
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,
					Text = function()
						if #keyFilter() > 0 then
							local status = lookupStatus()
							if status == "not_found" then
								return `Key "{keyFilter()}" not found`
							elseif status == "error" then
								return `Failed to look up "{keyFilter()}"`
							end
							return "No keys match your search"
						end
						local conn = Store.connection()
						if conn and conn.datastoreType == "Ordered" then
							return "No keys found in this Ordered DataStore"
						end
						return "No keys found in this DataStore"
					end,
					TextColor3 = function()
						return theme.colors().foregroundMuted
					end,
					TextSize = theme.fontSize.normal,
					FontFace = theme.font,
				},

				-- Show Refresh when no filter is active
				show(function()
					return #keyFilter() == 0
				end, function()
					return Button({
						text = "Refresh",
						onClick = loadKeys,
						variant = "secondary",
					})
				end),
			}
		end),
			
			-- Virtualized key list
			show(function()
				return #displayKeys() > 0 and not Store.keyListLoading() and Store.keyListError() == nil
			end, function()
				return VirtualizedList({
					items = displayKeys,
					itemHeight = 52,
					renderItem = KeyRow,
				})
			end),
		},
	}
end

return BrowseView
