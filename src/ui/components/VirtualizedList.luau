--!strict
--[[
	VirtualizedList Component
	Efficient rendering of large lists using Vide with isolated reactive scope
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local action = Vide.action
local root = Vide.root
local values = Vide.values

export type VirtualizedListProps<T> = {
	items: () -> { T },
	itemHeight: number,
	renderItem: (item: () -> T, absoluteIndex: number) -> Frame,
	overscan: number?,
	scrollingFrameRef: ((ref: ScrollingFrame) -> ())?,
	scrollBarThickness: number?,
}

-- Default buffer - renders extra items above/below viewport to handle fast scrolling
local DEFAULT_OVERSCAN = 8

local function VirtualizedList<T>(props: VirtualizedListProps<T>): ScrollingFrame
	local theme = Theme.get()
	local overscan = props.overscan or DEFAULT_OVERSCAN
	
	-- Must use root() to create reactive scope when called from within show/switch
	local canvasPosition, viewportSize, lastCanvasPosition, visibleRange, visibleItems, canvasSize
	
	root(function()
		canvasPosition = source(Vector2.zero)
		viewportSize = source(Vector2.zero)
		lastCanvasPosition = source(Vector2.zero)
		
		-- Calculate visible range with dynamic overscan based on scroll velocity
		visibleRange = derive(function()
			local pos = canvasPosition()
			local lastPos = lastCanvasPosition()
			local size = viewportSize()
			local itemHeight = props.itemHeight
			local items = props.items()
			
			if size.Y == 0 or itemHeight == 0 or #items == 0 then
				return { startIndex = 1, endIndex = 0 }
			end
			
			-- Calculate scroll velocity to add extra buffer when scrolling fast
			local scrollDelta = math.abs(pos.Y - lastPos.Y)
			local velocityBuffer = math.floor(scrollDelta / itemHeight)
			local dynamicOverscan = overscan + math.min(velocityBuffer, 10) -- Cap at 10 extra items
			
			local startIndex = math.max(1, math.floor(pos.Y / itemHeight) - dynamicOverscan + 1)
			local endIndex = math.min(
				#items,
				math.ceil((pos.Y + size.Y) / itemHeight) + dynamicOverscan
			)
			
			return { startIndex = startIndex, endIndex = endIndex }
		end)
		
		-- Calculate visible items as a simple array of indices
		visibleItems = derive(function()
			local range = visibleRange()
			local visible = {}
			for i = range.startIndex, range.endIndex do
				table.insert(visible, i)
			end
			return visible
		end)
		
		-- Calculate total canvas size
		canvasSize = derive(function()
			local totalHeight = #props.items() * props.itemHeight
			return UDim2.new(1, 0, 0, totalHeight)
		end)
	end)
	
	return create "ScrollingFrame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return theme.colors().background
		end,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = props.scrollBarThickness or 8,
		ScrollBarImageColor3 = function()
			return theme.colors().scrollbar
		end,
		CanvasSize = canvasSize,
		
		action(function(instance: ScrollingFrame)
			-- Call ref callback if provided
			if props.scrollingFrameRef then
				props.scrollingFrameRef(instance)
			end
			
			-- Initialize state with current values
			canvasPosition(instance.CanvasPosition)
			viewportSize(instance.AbsoluteWindowSize)
			
			-- Set up property listeners
			local posConnection = instance:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				lastCanvasPosition(canvasPosition()) -- Store previous position for velocity calc
				canvasPosition(instance.CanvasPosition)
			end)
			
			local sizeConnection = instance:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
				viewportSize(instance.AbsoluteWindowSize)
			end)
			
			return function()
				posConnection:Disconnect()
				sizeConnection:Disconnect()
			end
		end),
		
		-- Render visible items using values (keyed by index) for stable positioning
		-- Each item gets a stable component that never moves, only created/destroyed
		values(visibleItems, function(idx)
			-- Create a stable source for this item's data
			local itemSource = derive(function()
				return props.items()[idx]
			end)
			
			local renderedItem = props.renderItem(itemSource, idx)
			
			-- Fixed position based on index - never changes for this component
			return create "Frame" {
				Size = UDim2.new(1, 0, 0, props.itemHeight),
				Position = UDim2.new(0, 0, 0, (idx - 1) * props.itemHeight),
				BackgroundTransparency = 1,
				
				renderedItem,
			}
		end),
	}
end

return VirtualizedList
