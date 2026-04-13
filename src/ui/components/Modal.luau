--!strict
--[[
	Modal Component
	Dialog overlay using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local spring = Vide.spring
local derive = Vide.derive

export type ModalProps = {
	isOpen: () -> boolean,
	onClose: () -> (),
	title: string?,
	children: { Instance },
	size: ("small" | "medium" | "large")?,
	closeOnBackdrop: boolean?,
}

local function Modal(props: ModalProps): Frame
	local theme = Theme.get()

	local sizes = {
		small = UDim2.fromOffset(360, 0),
		medium = UDim2.fromOffset(520, 0),
		large = UDim2.new(0.9, 0, 0.8, 0),
	}

	local maxWidths = {
		large = 720,
	}

	-- Large modals use fixed height (scale-based), others auto-size
	local isFixedHeight = (props.size == "large")
	local modalSize = sizes[props.size or "medium"]
	local maxWidth = maxWidths[props.size or "medium"]
	local closeOnBackdrop = if props.closeOnBackdrop == nil then true else props.closeOnBackdrop

	local isOpen = props.isOpen
	
	local transparency = spring(function()
		return if isOpen() then 0.5 else 1
	end, 0.2)
	
	local scale = spring(function()
		return if isOpen() then 1 else 0.9
	end, 0.25)
	
	local contentTransparency = spring(function()
		return if isOpen() then 0 else 1
	end, 0.15)
	
	local visible = derive(function()
		return isOpen() or transparency() < 0.99
	end)

	local isCloseHovered = source(false)
	local closeHover = spring(function()
		return if isCloseHovered() then 1 else 0
	end, 0.25)

	return create "Frame" {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = transparency,
		Visible = visible,
		ZIndex = 1000,

		InputBegan = function(input: InputObject)
			if closeOnBackdrop and input.UserInputType == Enum.UserInputType.MouseButton1 then
				props.onClose()
			end
		end,

		-- Modal content
		create "Frame" {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = modalSize,
			AutomaticSize = if isFixedHeight then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
			BackgroundColor3 = function()
				return theme.colors().background
			end,
			BackgroundTransparency = contentTransparency,
			BorderSizePixel = 0,
			ZIndex = 1001,

			InputBegan = function(input: InputObject)
				-- Prevent click through
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					-- Do nothing, stop propagation
				end
			end,
			
			create "UIScale" {
				Scale = scale,
			},

			if maxWidth then create "UISizeConstraint" {
				MaxSize = Vector2.new(maxWidth, math.huge),
			} else nil,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.lg),
			},

			create "UIStroke" {
				Color = function()
					return theme.colors().border
				end,
				Thickness = 1,
				Transparency = contentTransparency,
			},

			create "Frame" {
				Size = if isFixedHeight then UDim2.fromScale(1, 1) else UDim2.new(1, 0, 0, 0),
				AutomaticSize = if isFixedHeight then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
				},

				-- Header
				if props.title
					then create "Frame" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 44),
						BackgroundColor3 = function()
							return theme.colors().backgroundSecondary
						end,
						BackgroundTransparency = contentTransparency,
						BorderSizePixel = 0,

						create "UICorner" {
							CornerRadius = UDim.new(0, theme.radius.lg),
						},

						-- Only round top corners
						create "Frame" {
							Position = UDim2.new(0, 0, 0.5, 0),
							Size = UDim2.new(1, 0, 0.5, 0),
							BackgroundColor3 = function()
								return theme.colors().backgroundSecondary
							end,
							BackgroundTransparency = contentTransparency,
							BorderSizePixel = 0,
							ZIndex = 0,
						},

						create "UIPadding" {
							PaddingLeft = UDim.new(0, 20),
							PaddingRight = UDim.new(0, 20),
						},

						create "TextLabel" {
							Size = UDim2.new(1, -32, 1, 0),
							BackgroundTransparency = 1,
							Text = props.title,
							TextColor3 = function()
								return theme.colors().foreground
							end,
							TextTransparency = contentTransparency,
							TextSize = theme.fontSize.large,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.fontMedium,
						},

						-- Close button
						create "ImageButton" {
							AnchorPoint = Vector2.new(1, 0.5),
							Position = UDim2.new(1, 0, 0.5, 0),
							Size = UDim2.fromOffset(28, 28),
							BackgroundColor3 = function()
								return theme.colors().foreground
							end,
							BackgroundTransparency = function()
								return 1 - closeHover() * 0.1
							end,
							Image = theme.icons.close,
							ImageColor3 = function()
								return theme.colors().foregroundMuted:Lerp(theme.colors().foreground, closeHover())
							end,
							ImageTransparency = contentTransparency,

							MouseEnter = function()
								isCloseHovered(true)
							end,
							MouseLeave = function()
								isCloseHovered(false)
							end,
							Activated = props.onClose,

							create "UICorner" {
								CornerRadius = UDim.new(0, theme.radius.sm),
							},
						},
					}
					else nil,

				-- Content
				create "Frame" {
					LayoutOrder = 2,
					Size = if isFixedHeight
						then UDim2.new(1, 0, 1, if props.title then -44 else 0)
						else UDim2.new(1, 0, 0, 0),
					AutomaticSize = if isFixedHeight then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 20),
						PaddingRight = UDim.new(0, 20),
						PaddingTop = UDim.new(0, 20),
						PaddingBottom = UDim.new(0, 20),
					},

					create "Frame" {
						Size = if isFixedHeight then UDim2.fromScale(1, 1) else UDim2.new(1, 0, 0, 0),
						AutomaticSize = if isFixedHeight then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,

						create "UIListLayout" {
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 16),
						},

						-- Apply transparency to children if possible, or just let them fade with the container
						unpack(props.children),
					},
				},
			},
		},
	}
end

return Modal
