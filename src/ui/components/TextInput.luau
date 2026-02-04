--!strict
--[[
	TextInput Component
	Text input field with validation using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local spring = Vide.spring

export type TextInputProps = {
	value: () -> string,
	onChange: (value: string) -> (),
	placeholder: string?,
	disabled: (() -> boolean)?,
	validate: ((value: string) -> (boolean, string?))?,
	multiline: boolean?,
	password: boolean?,
	label: (string | () -> string)?,
	hint: string?,
	prefix: string?,
	suffix: string?,
}

local function TextInput(props: TextInputProps): Frame
	local theme = Theme.get()
	local isFocused = source(false)
	local isHovered = source(false)
	local validationError = source(nil :: string?)

	local disabled = props.disabled or function()
		return false
	end

	local targetBorderColor = derive(function()
		local c = theme.colors()
		local error = validationError()

		if error then
			return c.error
		end
		if disabled() then
			return c.border
		end
		if isFocused() then
			return c.accent
		end
		if isHovered() then
			return c.borderHover
		end
		return c.border
	end)
	
	local borderColor = spring(targetBorderColor, 0.15)

	local handleChange = function(text: string)
		if props.validate then
			local valid, error = props.validate(text)
			validationError(if valid then nil else error)
		end
		props.onChange(text)
	end

	local inputHeight = if props.multiline then 80 else 36
	local textBoxRef: TextBox? = nil

	return create "Frame" {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,

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

		-- Input container
		create "Frame" {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, inputHeight),
			BackgroundColor3 = function()
				local c = theme.colors()
				if disabled() then
					return c.backgroundTertiary
				end
				return c.backgroundSecondary
			end,
			BorderSizePixel = 0,

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
				Transparency = 0,
			},

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, if props.multiline then 8 else 0),
				PaddingBottom = UDim.new(0, if props.multiline then 8 else 0),
			},

			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				},

				-- Prefix
				if props.prefix
					then create "TextLabel" {
						LayoutOrder = 1,
						AutomaticSize = Enum.AutomaticSize.XY,
						BackgroundTransparency = 1,
						Text = props.prefix,
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.normal,
						FontFace = theme.font,
					}
					else nil,

				-- Text input
				if props.multiline
					then create "ScrollingFrame" {
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						ScrollBarThickness = 4,
						ScrollBarImageColor3 = function()
							return theme.colors().scrollbar
						end,
						CanvasSize = UDim2.new(0, 0, 0, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						BorderSizePixel = 0,

						create "TextBox" {
							Size = UDim2.fromScale(1, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							Text = props.value,
							PlaceholderText = props.placeholder or "",
							TextColor3 = function()
								return theme.colors().foreground
							end,
							PlaceholderColor3 = function()
								return theme.colors().foregroundMuted
							end,
							TextSize = theme.fontSize.normal,
							TextXAlignment = Enum.TextXAlignment.Left,
							TextYAlignment = Enum.TextYAlignment.Top,
							FontFace = theme.fontMono,
							TextEditable = function()
								return not disabled()
							end,
							ClearTextOnFocus = false,
							MultiLine = true,
							TextWrapped = true,

							Vide.action(function(instance)
								textBoxRef = instance
							end),

							FocusLost = function()
								isFocused(false)
								if textBoxRef then
									handleChange(textBoxRef.Text)
								end
							end,

							Focused = function()
								isFocused(true)
							end,

							Changed = function(property: string)
								if property == "Text" and textBoxRef then
									handleChange(textBoxRef.Text)
								end
							end,
						},
					}
					else create "TextBox" {
						LayoutOrder = 2,
						Size = UDim2.new(1, if props.prefix or props.suffix then -60 else 0, 1, 0),
						BackgroundTransparency = 1,
						Text = props.value,
						PlaceholderText = props.placeholder or "",
						TextColor3 = function()
							return theme.colors().foreground
						end,
						PlaceholderColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.normal,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = if props.password then theme.font else theme.fontMono,
						TextEditable = function()
							return not disabled()
						end,
						ClearTextOnFocus = false,

						Vide.action(function(instance)
							textBoxRef = instance
						end),

						FocusLost = function()
							isFocused(false)
							if textBoxRef then
								handleChange(textBoxRef.Text)
							end
						end,

						Focused = function()
							isFocused(true)
						end,
					},

				-- Suffix
				if props.suffix
					then create "TextLabel" {
						LayoutOrder = 3,
						AutomaticSize = Enum.AutomaticSize.XY,
						BackgroundTransparency = 1,
						Text = props.suffix,
						TextColor3 = function()
							return theme.colors().foregroundMuted
						end,
						TextSize = theme.fontSize.normal,
						FontFace = theme.font,
					}
					else nil,
			},
		},

		-- Validation error or hint
		create "TextLabel" {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = function()
				local error = validationError()
				if error then
					return error
				end
				return props.hint or ""
			end,
			TextColor3 = function()
				local error = validationError()
				local c = theme.colors()
				if error then
					return c.error
				end
				return c.foregroundMuted
			end,
			TextSize = theme.fontSize.small,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = theme.font,
			Visible = function()
				return validationError() ~= nil or props.hint ~= nil
			end,
		},
	}
end

return TextInput
