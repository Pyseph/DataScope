--!strict
--[[
	SearchBar Component
	Search input with mode selection and result navigation using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local action = Vide.action
local spring = Vide.spring

export type SearchMode = "all" | "content" | "keys" | "values" | "type" | "regex" | "size"

export type SearchBarProps = {
	value: () -> string,
	onChange: (value: string) -> (),
	mode: () -> SearchMode,
	onModeChange: (mode: SearchMode) -> (),
	placeholder: string?,
	resultCount: () -> number,
	currentResult: () -> number,
	onNextResult: () -> (),
	onPrevResult: () -> (),
	onClear: () -> (),
}

local SEARCH_MODES: { { id: SearchMode, label: string, description: string } } = {
	{ id = "all", label = "All", description = "Search keys and values" },
	{ id = "content", label = "Content", description = "Match content directly" },
	{ id = "keys", label = "Keys", description = "Search only keys" },
	{ id = "values", label = "Values", description = "Search only values" },
	{ id = "type", label = "Type", description = "Search by type (string, number, boolean, array, object, null, buffer)" },
	{ id = "regex", label = "Regex", description = "Search using Lua patterns" },
	{ id = "size", label = "Size", description = "Filter by descendant count (>100, <50, 10-100)" },
}

local function SearchBar(props: SearchBarProps): Frame
	local theme = Theme.get()
	local isFocused = source(false)
	local isHovered = source(false)
	local isModeDropdownOpen = source(false)

	local targetBorderColor = derive(function()
		local c = theme.colors()
		if isFocused() then
			return c.accent
		end
		if isHovered() then
			return c.borderHover
		end
		return c.border
	end)
	
	local borderColor = spring(targetBorderColor, 0.15)

	local hasResults = derive(function()
		return props.resultCount() > 0
	end)

	local hasValue = derive(function()
		return #props.value() > 0
	end)

	local resultText = derive(function()
		local count = props.resultCount()
		local current = props.currentResult()
		if count == 0 and hasValue() then
			return "No results"
		elseif count > 0 then
			return `{current}/{count}`
		end
		return ""
	end)

	local currentModeLabel = derive(function()
		local mode = props.mode()
		for _, m in SEARCH_MODES do
			if m.id == mode then
				return m.label
			end
		end
		return "All"
	end)

	local placeholderText = derive(function()
		local mode = props.mode()
		if mode == "type" then
			return "Type: string, number, boolean, array, object, null..."
		elseif mode == "regex" then
			return "Lua pattern (e.g., %d+, ^prefix)"
		elseif mode == "content" then
			return "Search content directly..."
		elseif mode == "keys" then
			return "Search keys..."
		elseif mode == "values" then
			return "Search values..."
		elseif mode == "size" then
			return "Descendants: >100, <50, 10-100, =50..."
		end
		return props.placeholder or "Search..."
	end)

	local IconButton = function(icon: string, onClick: () -> (), enabled: () -> boolean): ImageButton
		local btnHovered = source(false)
		
		local targetBgTransparency = derive(function()
			return if btnHovered() and enabled() then 0 else 1
		end)
		
		local bgTransparency = spring(targetBgTransparency, 0.1)

		return create "ImageButton" {
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = function()
				return theme.colors().backgroundTertiary
			end,
			BackgroundTransparency = bgTransparency,
			Image = icon,
			ImageColor3 = function()
				local c = theme.colors()
				if enabled() then
					return c.foreground
				end
				return c.foregroundMuted
			end,
			AutoButtonColor = false,

			Activated = function()
				if enabled() then
					onClick()
				end
			end,

			MouseEnter = function()
				btnHovered(true)
			end,

			MouseLeave = function()
				btnHovered(false)
			end,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.sm),
			},
		}
	end

	-- Mode dropdown item
	local ModeItem = function(modeInfo: { id: SearchMode, label: string, description: string }): TextButton
		local itemHovered = source(false)

		local isSelected = derive(function()
			return props.mode() == modeInfo.id
		end)
		
		local targetBackgroundColor = derive(function()
			local c = theme.colors()
			if itemHovered() then
				return c.backgroundTertiary
			end
			return c.backgroundSecondary
		end)
		
		local backgroundColor = spring(targetBackgroundColor, 0.1)

		return create "TextButton" {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,

			Activated = function()
				props.onModeChange(modeInfo.id)
				isModeDropdownOpen(false)
			end,

			MouseEnter = function()
				itemHovered(true)
			end,

			MouseLeave = function()
				itemHovered(false)
			end,

			-- Background frame for hover/selected states
			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = backgroundColor,
				BackgroundTransparency = function()
					-- Selected items have subtle transparent background
					if isSelected() then
						return 0.85
					end
					return 0
				end,
				BorderSizePixel = 0,
				ZIndex = 100,
				
				create "UICorner" {
					CornerRadius = UDim.new(0, 6),
				},
				
				-- Accent stroke for selected item
				create "UIStroke" {
					Color = function()
						return theme.colors().accent
					end,
					Transparency = function()
						if isSelected() then
							return 0.3
						end
						return 1 -- Invisible when not selected
					end,
					Thickness = 1,
				},
			},

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
			},

			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 101,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				},

				create "TextLabel" {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 18),
					BackgroundTransparency = 1,
					Text = modeInfo.label,
					TextColor3 = function()
						local c = theme.colors()
						if isSelected() then
							return c.accent
						end
						return c.foreground
					end,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMedium,
					ZIndex = 101,
				},

				create "TextLabel" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 14),
					BackgroundTransparency = 1,
					Text = modeInfo.description,
					TextColor3 = function()
						local c = theme.colors()
						if isSelected() then
							return c.accent
						end
						return c.foregroundMuted
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.font,
					ZIndex = 101,
				},
			},
		}
	end

	return create "Frame" {
		Name = "SearchBar",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		ClipsDescendants = false,

		create "UIPadding" {
			Name = "UIPadding",
			PaddingLeft = UDim.new(0, 24),
		},

		-- Main search bar
		create "Frame" {
			Name = "SearchBarContainer",
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = function()
				return theme.colors().backgroundSecondary
			end,
			BorderSizePixel = 0,
			ClipsDescendants = true,

			MouseEnter = function()
				isHovered(true)
			end,

			MouseLeave = function()
				isHovered(false)
			end,

			create "UIListLayout" {
				Name = "UIListLayout",
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
			},
			
			create "UIPadding" {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			},

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.md),
			},

			create "UIStroke" {
				Color = borderColor,
				Thickness = 1,
			},

			-- Left Group (Icon + Mode)
			create "Frame" {
				Name = "LeftGroup",
				LayoutOrder = 1,
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				},

				-- Search icon
				create "ImageLabel" {
					Name = "SearchIcon",
					LayoutOrder = 1,
					Size = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1,
					Image = theme.icons.search,
					ImageColor3 = function()
						return theme.colors().foregroundMuted
					end,

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 8),
					},
				},

				-- Mode selector button
				create "TextButton" {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(76, 26),
					BackgroundColor3 = function()
						local c = theme.colors()
						if isModeDropdownOpen() then
							return c.accent
						end
						return c.backgroundTertiary
					end,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,

					Activated = function()
						isModeDropdownOpen(not isModeDropdownOpen())
					end,

					create "UICorner" {
						CornerRadius = UDim.new(0, theme.radius.sm),
					},

					create "Frame" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,

						create "UIListLayout" {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							Padding = UDim.new(0, 4),
						},

						create "TextLabel" {
							AutomaticSize = Enum.AutomaticSize.X,
							Size = UDim2.new(0, 0, 1, 0),
							BackgroundTransparency = 1,
							Text = currentModeLabel,
							TextColor3 = function()
								local c = theme.colors()
								if isModeDropdownOpen() then
									return Color3.new(1, 1, 1)
								end
								return c.foreground
							end,
							TextSize = theme.fontSize.small,
							FontFace = theme.fontMedium,
						},

						create "ImageLabel" {
							Size = UDim2.fromOffset(10, 10),
							BackgroundTransparency = 1,
							Image = theme.icons.chevronDown,
							ImageColor3 = function()
								local c = theme.colors()
								if isModeDropdownOpen() then
									return Color3.new(1, 1, 1)
								end
								return c.foregroundMuted
							end,
							Rotation = spring(function()
								return if isModeDropdownOpen() then 180 else 0
							end, 0.2),
						},
					},
				},
			},

			-- Text input (Middle) - fills remaining space
			(function()
				local textBoxRef: TextBox? = nil
				return create "Frame" {
					Name = "SearchInputContainer",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 1,
					
					create "UIFlexItem" {
						FlexMode = Enum.UIFlexMode.Fill,
					},
					
					create "TextBox" {
						Name = "SearchInput",
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = props.value,
						PlaceholderText = placeholderText,
						TextColor3 = function()
							return theme.colors().foreground
						end,
						PlaceholderColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.normal,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.font,
						ClearTextOnFocus = false,
						ClipsDescendants = true,

						action(function(instance)
							textBoxRef = instance
						end),

						FocusLost = function()
							isFocused(false)
							if textBoxRef then
								props.onChange(textBoxRef.Text)
							end
						end,

						Focused = function()
							isFocused(true)
							isModeDropdownOpen(false)
						end,
					},
				}
			end)(),

			-- Right Group (Count + Nav + Clear)
			create "Frame" {
				Name = "RightGroup",
				LayoutOrder = 3,
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				},

				-- Result count
				create "TextLabel" {
					LayoutOrder = 1,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.new(0, 0, 1, 0),
					BackgroundTransparency = 1,
					Text = resultText,
					TextColor3 = function()
						local c = theme.colors()
						if hasResults() then
							return c.foregroundSecondary
						elseif hasValue() then
							return c.warning
						end
						return c.foregroundMuted
					end,
					TextSize = theme.fontSize.small,
					FontFace = theme.font,
					Visible = hasValue,
				},

				-- Navigation buttons
				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(56, 24),
					BackgroundTransparency = 1,
					Visible = hasResults,

					create "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 4),
					},

					IconButton(theme.icons.chevronUp, props.onPrevResult, hasResults),
					IconButton(theme.icons.chevronDown, props.onNextResult, hasResults),
				},

				-- Clear button
				create "Frame" {
					LayoutOrder = 3,
					Size = UDim2.fromOffset(24, 24),
					BackgroundTransparency = 1,

					IconButton(theme.icons.clear, props.onClear, hasValue),
				},
			},
		},

		-- Mode dropdown
		create "Frame" {
			Position = UDim2.new(0, 34, 0, 42),
			Size = UDim2.fromOffset(220, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = function()
				return theme.colors().backgroundSecondary
			end,
			BorderSizePixel = 0,
			Visible = isModeDropdownOpen,
			ZIndex = 100,
			ClipsDescendants = true,
			Active = true,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.md),
			},

			create "UIStroke" {
				Color = function()
					return theme.colors().border
				end,
				Thickness = 1,
			},

			create "UIPadding" {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
			},

			create "Frame" {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex = 100,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
				},

				unpack((function()
					local items = {}
					for i, modeInfo in SEARCH_MODES do
						local item = ModeItem(modeInfo)
						item.LayoutOrder = i
						item.ZIndex = 100
						table.insert(items, item)
					end
					return items
				end)()),
			},
		},
	}
end

return SearchBar
