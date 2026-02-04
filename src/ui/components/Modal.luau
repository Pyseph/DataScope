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
		large = UDim2.fromOffset(720, 0),
	}

	local modalSize = sizes[props.size or "medium"]
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

	return create "Frame" {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = transparency,
		Visible = visible,
		ZIndex = 1000,

		InputBegan = function(_rbx: Frame, input: InputObject)
			if closeOnBackdrop and input.UserInputType == Enum.UserInputType.MouseButton1 then
				props.onClose()
			end
		end,

		-- Modal content
		create "Frame" {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = modalSize,
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = function()
				return theme.colors().background
			end,
			BackgroundTransparency = contentTransparency,
			BorderSizePixel = 0,
			ZIndex = 1001,

			InputBegan = function(_rbx: Frame, input: InputObject)
				-- Prevent click through
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					-- Do nothing, stop propagation
				end
			end,
			
			create "UIScale" {
				Scale = scale,
			},

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
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
				},

				-- Header
				if props.title
					then create "Frame" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 56),
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
							BackgroundTransparency = 1,
							Image = theme.icons.close,
							ImageColor3 = function()
								return theme.colors().foregroundMuted
							end,
							ImageTransparency = contentTransparency,

							Activated = props.onClose,
						},
					}
					else nil,

				-- Content
				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 20),
						PaddingRight = UDim.new(0, 20),
						PaddingTop = UDim.new(0, 20),
						PaddingBottom = UDim.new(0, 20),
					},

					create "Frame" {
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
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
