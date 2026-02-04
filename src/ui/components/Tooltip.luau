--!strict
--[[
	Tooltip Component
	Hover tooltips with smooth animations
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local spring = Vide.spring
local effect = Vide.effect
local action = Vide.action

export type TooltipProps = {
	text: string | () -> string,
	position: ("top" | "bottom" | "left" | "right")?,
	delay: number?,
	maxWidth: number?,
}

-- Global tooltip state (singleton for performance)
local tooltipVisible = source(false)
local tooltipText = source("")
local tooltipPosition = source(Vector2.new(0, 0))
local tooltipAnchor = source("top" :: "top" | "bottom" | "left" | "right")
local containerSize = source(Vector2.new(0, 0))
local tooltipSize = source(Vector2.new(100, 30)) -- Estimated default
local showTimer: thread? = nil

local function showTooltip(text: string, position: Vector2, anchor: "top" | "bottom" | "left" | "right", delay: number)
	if showTimer then
		task.cancel(showTimer)
	end
	
	showTimer = task.delay(delay, function()
		tooltipText(text)
		tooltipPosition(position)
		tooltipAnchor(anchor)
		tooltipVisible(true)
		showTimer = nil
	end)
end

local function hideTooltip()
	if showTimer then
		task.cancel(showTimer)
		showTimer = nil
	end
	tooltipVisible(false)
end

-- Tooltip wrapper - wraps a child element and adds tooltip behavior
local function TooltipWrapper(props: TooltipProps, child: Instance): Instance
	local delay = props.delay or 0.5
	local position = props.position or "top"
	
	local getText = if type(props.text) == "function" then props.text else function()
		return props.text :: string
	end
	
	-- Connect hover events
	if child:IsA("GuiObject") then
		child.MouseEnter:Connect(function()
			local absolutePos = (child :: GuiObject).AbsolutePosition
			local absoluteSize = (child :: GuiObject).AbsoluteSize
			
			local tipPos: Vector2
			if position == "top" then
				tipPos = Vector2.new(absolutePos.X + absoluteSize.X / 2, absolutePos.Y)
			elseif position == "bottom" then
				tipPos = Vector2.new(absolutePos.X + absoluteSize.X / 2, absolutePos.Y + absoluteSize.Y)
			elseif position == "left" then
				tipPos = Vector2.new(absolutePos.X, absolutePos.Y + absoluteSize.Y / 2)
			else -- right
				tipPos = Vector2.new(absolutePos.X + absoluteSize.X, absolutePos.Y + absoluteSize.Y / 2)
			end
			
			showTooltip(getText(), tipPos, position, delay)
		end)
		
		child.MouseLeave:Connect(function()
			hideTooltip()
		end)
	end
	
	return child
end

-- The actual tooltip display element (should be added once at root level)
local function TooltipDisplay(): Frame
	local theme = Theme.get()
	
	local opacity = spring(function()
		return if tooltipVisible() then 1 else 0
	end, 0.15)
	
	local scale = spring(function()
		return if tooltipVisible() then 1 else 0.9
	end, 0.15)
	
	local anchorPoint = derive(function()
		local anchor = tooltipAnchor()
		if anchor == "top" then
			return Vector2.new(0.5, 1)
		elseif anchor == "bottom" then
			return Vector2.new(0.5, 0)
		elseif anchor == "left" then
			return Vector2.new(1, 0.5)
		else -- right
			return Vector2.new(0, 0.5)
		end
	end)
	
	local offset = derive(function()
		local anchor = tooltipAnchor()
		if anchor == "top" then
			return UDim2.fromOffset(0, -8)
		elseif anchor == "bottom" then
			return UDim2.fromOffset(0, 8)
		elseif anchor == "left" then
			return UDim2.fromOffset(-8, 0)
		else -- right
			return UDim2.fromOffset(8, 0)
		end
	end)
	
	-- Calculate clamped position
	local clampedPosition = derive(function()
		local pos = tooltipPosition()
		local off = offset()
		local anchor = tooltipAnchor()
		local container = containerSize()
		local tipSize = tooltipSize()
		
		-- Start with raw position + offset
		local x = pos.X + off.X.Offset
		local y = pos.Y + off.Y.Offset
		
		-- Adjust for anchor point
		if anchor == "top" or anchor == "bottom" then
			x = x - tipSize.X / 2
		elseif anchor == "left" then
			x = x - tipSize.X
		end
		-- "right" anchor: x stays as is
		
		if anchor == "left" or anchor == "right" then
			y = y - tipSize.Y / 2
		elseif anchor == "top" then
			y = y - tipSize.Y
		end
		-- "bottom" anchor: y stays as is
		
		-- Clamp to container bounds with padding
		local padding = 8
		x = math.max(padding, math.min(x, container.X - tipSize.X - padding))
		y = math.max(padding, math.min(y, container.Y - tipSize.Y - padding))
		
		return Vector2.new(x, y)
	end)
	
	return create "Frame" {
		Name = "TooltipContainer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10000,
		
		-- Track container size for clamping
		action(function(container: Frame)
			containerSize(container.AbsoluteSize)
			container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				containerSize(container.AbsoluteSize)
			end)
		end),
		
		create "Frame" {
			Name = "Tooltip",
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = function()
				return theme.colors().backgroundTertiary
			end,
			BackgroundTransparency = function()
				return 1 - opacity()
			end,
			Position = function()
				local pos = clampedPosition()
				return UDim2.fromOffset(pos.X, pos.Y)
			end,
			AnchorPoint = Vector2.new(0, 0), -- Use top-left since we calculated absolute position
			Visible = function()
				return opacity() > 0.01
			end,
			
			-- Track tooltip size for clamping calculations
			action(function(tooltip: Frame)
				tooltipSize(tooltip.AbsoluteSize)
				tooltip:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					tooltipSize(tooltip.AbsoluteSize)
				end)
			end),
			
			create "UIScale" {
				Scale = scale,
			},
			
			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.sm),
			},
			
			create "UIStroke" {
				Color = function()
					return theme.colors().border
				end,
				Transparency = function()
					return 1 - opacity()
				end,
				Thickness = 1,
			},
			
			create "UIPadding" {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
			},
			
			create "TextLabel" {
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = tooltipText,
				TextColor3 = function()
					return theme.colors().foreground
				end,
				TextTransparency = function()
					return 1 - opacity()
				end,
				TextSize = theme.fontSize.small,
				FontFace = theme.font,
				TextWrapped = true,
				
				create "UISizeConstraint" {
					MaxSize = Vector2.new(250, math.huge),
				},
			},
		},
	}
end

-- Helper to add tooltip behavior to any GuiObject after creation
local function addTooltip(element: GuiObject, text: string, position: ("top" | "bottom" | "left" | "right")?, delay: number?)
	local pos = position or "bottom"
	local del = delay or 0.4
	
	element.MouseEnter:Connect(function()
		local absolutePos = element.AbsolutePosition
		local absoluteSize = element.AbsoluteSize
		
		local tipPos: Vector2
		if pos == "top" then
			tipPos = Vector2.new(absolutePos.X + absoluteSize.X / 2, absolutePos.Y)
		elseif pos == "bottom" then
			tipPos = Vector2.new(absolutePos.X + absoluteSize.X / 2, absolutePos.Y + absoluteSize.Y)
		elseif pos == "left" then
			tipPos = Vector2.new(absolutePos.X, absolutePos.Y + absoluteSize.Y / 2)
		else -- right
			tipPos = Vector2.new(absolutePos.X + absoluteSize.X, absolutePos.Y + absoluteSize.Y / 2)
		end
		
		showTooltip(text, tipPos, pos, del)
	end)
	
	element.MouseLeave:Connect(function()
		hideTooltip()
	end)
	
	return element
end

return {
	Wrapper = TooltipWrapper,
	Display = TooltipDisplay,
	show = showTooltip,
	hide = hideTooltip,
	addTooltip = addTooltip,
}
