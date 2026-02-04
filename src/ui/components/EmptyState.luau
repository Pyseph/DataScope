--!strict
--[[
	Empty State Component
	Illustrated empty states for lists and views
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local spring = Vide.spring
local effect = Vide.effect

export type EmptyStateProps = {
	icon: string?,
	title: string,
	description: string?,
	actionText: string?,
	onAction: (() -> ())?,
	size: ("small" | "medium" | "large")?,
}

local function EmptyState(props: EmptyStateProps): Frame
	local theme = Theme.get()
	local size = props.size or "medium"
	local isHovered = source(false)
	
	-- Floating animation for the icon
	local floatOffset = source(0)
	effect(function()
		local connection: RBXScriptConnection
		local startTime = os.clock()
		
		connection = game:GetService("RunService").Heartbeat:Connect(function()
			local elapsed = os.clock() - startTime
			-- Gentle floating motion
			floatOffset(math.sin(elapsed * 1.5) * 4)
		end)
		
		return function()
			connection:Disconnect()
		end
	end)
	
	local iconFloat = spring(floatOffset, 0.3)
	
	local sizes = {
		small = { icon = 40, title = theme.fontSize.medium, desc = theme.fontSize.small, padding = 16 },
		medium = { icon = 64, title = theme.fontSize.large, desc = theme.fontSize.normal, padding = 24 },
		large = { icon = 96, title = theme.fontSize.xl, desc = theme.fontSize.medium, padding = 32 },
	}
	
	local config = sizes[size]
	
	-- Button hover animation
	local buttonScale = spring(function()
		return if isHovered() then 1.02 else 1
	end, 0.15)
	
	local buttonBg = spring(function()
		local c = theme.colors()
		if isHovered() then
			return c.accentHover
		end
		return c.accent
	end, 0.15)
	
	return create "Frame" {
		Name = "EmptyState",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		
		create "Frame" {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			
			create "UIListLayout" {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, config.padding / 2),
			},
			
			-- Illustrated icon area
			create "Frame" {
				Size = UDim2.fromOffset(config.icon * 1.5, config.icon * 1.5),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
				
				-- Background circle
				create "Frame" {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(config.icon * 1.3, config.icon * 1.3),
					BackgroundColor3 = function()
						return theme.colors().backgroundTertiary
					end,
					BackgroundTransparency = 0.5,
					
					create "UICorner" {
						CornerRadius = UDim.new(1, 0),
					},
				},
				
				-- Decorative ring
				create "Frame" {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(config.icon * 1.5, config.icon * 1.5),
					BackgroundTransparency = 1,
					
					create "UICorner" {
						CornerRadius = UDim.new(1, 0),
					},
					
					create "UIStroke" {
						Color = function()
							return theme.colors().accent
						end,
						Thickness = 2,
						Transparency = 0.7,
					},
				},
				
				-- Icon with float animation
				create "ImageLabel" {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = function()
						return UDim2.new(0.5, 0, 0.5, iconFloat())
					end,
					Size = UDim2.fromOffset(config.icon, config.icon),
					BackgroundTransparency = 1,
					Image = props.icon or theme.icons.emptyBox,
					ImageColor3 = function()
						return theme.colors().accent
					end,
					ImageTransparency = 0.2,
				},
			},
			
			-- Title
			create "TextLabel" {
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = props.title,
				TextColor3 = function()
					return theme.colors().foreground
				end,
				TextSize = config.title,
				FontFace = theme.fontDisplayMedium,
				TextWrapped = true,
				
				create "UISizeConstraint" {
					MaxSize = Vector2.new(300, math.huge),
				},
			},
			
			-- Description
			if props.description then create "TextLabel" {
				LayoutOrder = 3,
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = props.description,
				TextColor3 = function()
					return theme.colors().foregroundMuted
				end,
				TextSize = config.desc,
				FontFace = theme.fontLight,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				
				create "UISizeConstraint" {
					MaxSize = Vector2.new(280, math.huge),
				},
			} else nil,
			
			-- Action button
			if props.actionText and props.onAction then create "TextButton" {
				LayoutOrder = 4,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 36),
				BackgroundColor3 = buttonBg,
				Text = "",
				AutoButtonColor = false,
				
				MouseEnter = function()
					isHovered(true)
				end,
				
				MouseLeave = function()
					isHovered(false)
				end,
				
				Activated = props.onAction,
				
				create "UICorner" {
					CornerRadius = UDim.new(0, theme.radius.md),
				},
				
				create "UIScale" {
					Scale = buttonScale,
				},
				
				create "UIPadding" {
					PaddingLeft = UDim.new(0, 20),
					PaddingRight = UDim.new(0, 20),
				},
				
				create "TextLabel" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = props.actionText,
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = theme.fontSize.medium,
					FontFace = theme.fontMedium,
				},
			} else nil,
		},
	}
end

-- Preset empty states
local function NoKeys(onRefresh: (() -> ())?): Frame
	local theme = Theme.get()
	return EmptyState({
		icon = theme.icons.key,
		title = "No Keys Found",
		description = "This DataStore is empty or no keys match your filter.",
		actionText = if onRefresh then "Refresh" else nil,
		onAction = onRefresh,
	})
end

local function NoSearchResults(): Frame
	local theme = Theme.get()
	return EmptyState({
		icon = theme.icons.search,
		title = "No Results",
		description = "Try adjusting your search query or filters.",
		size = "small",
	})
end

local function NoHistory(): Frame
	local theme = Theme.get()
	return EmptyState({
		icon = theme.icons.history,
		title = "No History",
		description = "Your recent connections will appear here.",
		size = "small",
	})
end

local function NoData(): Frame
	local theme = Theme.get()
	return EmptyState({
		icon = theme.icons.emptyData,
		title = "No Data",
		description = "This key doesn't contain any data yet.",
		size = "medium",
	})
end

local function ConnectionError(onRetry: () -> ()): Frame
	local theme = Theme.get()
	return EmptyState({
		icon = theme.icons.error,
		title = "Connection Failed",
		description = "Unable to connect to the DataStore. Check your settings and try again.",
		actionText = "Retry",
		onAction = onRetry,
	})
end

return {
	EmptyState = EmptyState,
	NoKeys = NoKeys,
	NoSearchResults = NoSearchResults,
	NoHistory = NoHistory,
	NoData = NoData,
	ConnectionError = ConnectionError,
}
