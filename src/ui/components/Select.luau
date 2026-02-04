--!strict
--[[
	Select Component
	Dropdown select using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local indexes = Vide.indexes
local spring = Vide.spring

export type SelectOption<T> = {
	value: T,
	label: string,
	description: string?,
	icon: string?,
}

export type SelectProps<T> = {
	value: () -> T,
	options: { SelectOption<T> },
	onChange: (value: T) -> (),
	placeholder: string?,
	disabled: (() -> boolean)?,
	label: string?,
}

local function Select<T>(props: SelectProps<T>): Frame
	local theme = Theme.get()
	local isOpen = source(false)
	local isHovered = source(false)

	local disabled = props.disabled or function()
		return false
	end

	local selectedOption = derive(function(): SelectOption<T>?
		local currentValue = props.value()
		for _, option in props.options do
			if option.value == currentValue then
				return option
			end
		end
		return nil
	end)

	local displayText = derive(function()
		local selected = selectedOption()
		if selected then
			return selected.label
		end
		return props.placeholder or "Select..."
	end)

	local targetBorderColor = derive(function()
		local c = theme.colors()
		local isDisabled = disabled()
		
		if isDisabled then
			return c.border
		end
		if isOpen() then
			return c.accent
		end
		if isHovered() then
			return c.borderHover
		end
		return c.border
	end)
	
	local borderColor = spring(targetBorderColor, 0.15)

	local OptionItem = function(option: SelectOption<T>, index: number): TextButton
		local itemHovered = source(false)

		local isSelected = derive(function()
			return props.value() == option.value
		end)
		
		local targetBackgroundColor = derive(function()
			local c = theme.colors()
			if isSelected() then
				return c.accent
			end
			if itemHovered() then
				return c.backgroundTertiary
			end
			return c.backgroundSecondary
		end)
		
		local backgroundColor = spring(targetBackgroundColor, 0.1)

		return create "TextButton" {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, if option.description then 48 else 36),
			BackgroundColor3 = backgroundColor,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,

			Activated = function()
				props.onChange(option.value)
				isOpen(false)
			end,

			MouseEnter = function()
				itemHovered(true)
			end,

			MouseLeave = function()
				itemHovered(false)
			end,

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
					Padding = UDim.new(0, 8),
				},

				if option.icon
					then create "ImageLabel" {
						LayoutOrder = 1,
						Size = UDim2.fromOffset(16, 16),
						BackgroundTransparency = 1,
						Image = option.icon,
						ImageColor3 = function()
							local c = theme.colors()
							if isSelected() then
								return Color3.new(1, 1, 1)
							end
							return c.foreground
						end,
					}
					else nil,

				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(1, -24, 1, 0),
					BackgroundTransparency = 1,

					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					},

					create "TextLabel" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 18),
						BackgroundTransparency = 1,
						Text = option.label,
						TextColor3 = function()
							local c = theme.colors()
							if isSelected() then
								return Color3.new(1, 1, 1)
							end
							return c.foreground
						end,
						TextSize = theme.fontSize.normal,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.fontMedium,
					},

					if option.description
						then create "TextLabel" {
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 0, 14),
							BackgroundTransparency = 1,
							Text = option.description,
							TextColor3 = function()
								local c = theme.colors()
								if isSelected() then
									return Color3.fromRGB(220, 220, 220)
								end
								return c.foregroundMuted
							end,
							TextSize = theme.fontSize.small,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.font,
						}
						else nil,
				},

				-- Check mark for selected
				create "ImageLabel" {
					LayoutOrder = 3,
					Size = UDim2.fromOffset(14, 14),
					BackgroundTransparency = 1,
					Image = theme.icons.check,
					ImageColor3 = Color3.new(1, 1, 1),
					Visible = isSelected,
				},
			},
		}
	end

	return create "Frame" {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = false,

		create "UIListLayout" {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		},

		-- Label
		if props.label
			then create "TextLabel" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = props.label,
				TextColor3 = function()
					return theme.colors().foreground
				end,
				TextSize = theme.fontSize.normal,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = theme.fontMedium,
			}
			else nil,

		-- Select button
		create "TextButton" {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = function()
				local c = theme.colors()
				if disabled() then
					return c.backgroundTertiary
				end
				return c.backgroundSecondary
			end,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,

			Activated = function()
				if not disabled() then
					isOpen(not isOpen())
				end
			end,

			MouseEnter = function()
				if not disabled() then
					isHovered(true)
				end
			end,

			MouseLeave = function()
				isHovered(false)
			end,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.md),
			},

			create "UIStroke" {
				Color = borderColor,
				Thickness = 1,
			},

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
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
				},

				create "TextLabel" {
					Size = UDim2.new(1, -24, 1, 0),
					BackgroundTransparency = 1,
					Text = displayText,
					TextColor3 = function()
						local c = theme.colors()
						local selected = selectedOption()
						if disabled() or not selected then
							return c.foregroundMuted
						end
						return c.foreground
					end,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.font,
				},

				create "ImageLabel" {
					Size = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1,
					Image = theme.icons.chevronDown,
					ImageColor3 = function()
						return theme.colors().foregroundMuted
					end,
					Rotation = spring(function()
						return if isOpen() then 180 else 0
					end, 0.2),
				},
			},
		},

		-- Dropdown
		create "Frame" {
			LayoutOrder = 3,
			Position = UDim2.new(0, 0, 0, if props.label then 62 else 40),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = isOpen,
			ZIndex = 100,
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

			create "ScrollingFrame" {
				Size = UDim2.new(1, 0, 0, math.min(#props.options * 48, 240)),
				BackgroundTransparency = 1,
				ScrollBarThickness = 4,
				ScrollBarImageColor3 = function()
					return theme.colors().scrollbar
				end,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BorderSizePixel = 0,
				ZIndex = 100,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
				},

				unpack((function()
					local items = {}
					for i, option in props.options do
						table.insert(items, OptionItem(option, i))
					end
					return items
				end)()),
			},
		},
	}
end

return Select
