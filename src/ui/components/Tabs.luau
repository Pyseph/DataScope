--!strict
--[[
	Tabs Component
	Tab navigation using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local indexes = Vide.indexes
local spring = Vide.spring

export type Tab = {
	id: string,
	label: string,
	icon: string?,
}

export type TabsProps = {
	tabs: { Tab },
	activeTab: () -> string,
	onTabChange: (tabId: string) -> (),
}

local function Tabs(props: TabsProps): Frame
	local theme = Theme.get()

	local TabItem = function(tab: Tab): TextButton
		local isHovered = source(false)

		local isActive = derive(function()
			return props.activeTab() == tab.id
		end)

		local targetBackgroundColor = derive(function()
			local c = theme.colors()
			if isActive() then
				return c.accent
			end
			if isHovered() then
				return c.backgroundTertiary
			end
			return c.backgroundSecondary
		end)

		local targetTextColor = derive(function()
			local c = theme.colors()
			if isActive() then
				return Color3.new(1, 1, 1)
			end
			return c.foreground
		end)
		
		local backgroundColor = spring(targetBackgroundColor, 0.15)
		local textColor = spring(targetTextColor, 0.15)

		return create "TextButton" {
			Size = UDim2.new(0, 0, 1, -4),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = backgroundColor,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,

			Activated = function()
				props.onTabChange(tab.id)
			end,

			MouseEnter = function()
				isHovered(true)
			end,

			MouseLeave = function()
				isHovered(false)
			end,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.sm),
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
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 6),
				},

				if tab.icon
					then create "ImageLabel" {
						LayoutOrder = 1,
						Size = UDim2.fromOffset(14, 14),
						BackgroundTransparency = 1,
						Image = tab.icon,
						ImageColor3 = textColor,
					}
					else nil,

				create "TextLabel" {
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,
					Text = tab.label,
					TextColor3 = textColor,
					TextSize = theme.fontSize.normal,
					FontFace = theme.fontMedium,
				},
			},
		}
	end

	return create "Frame" {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = function()
			return theme.colors().backgroundSecondary
		end,
		BorderSizePixel = 0,

		create "UICorner" {
			CornerRadius = UDim.new(0, theme.radius.md),
		},

		create "UIPadding" {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		},

		create "Frame" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 4),
			},

			indexes(function()
				return props.tabs
			end, function(tab, index)
				local tabItem = TabItem(tab())
				tabItem.LayoutOrder = index
				return tabItem
			end),
		},
	}
end

return Tabs
