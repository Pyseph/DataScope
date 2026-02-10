--!strict
--[[
	VirtualizedList Component
	Efficient rendering of large lists using Vide with pool-based recycling.
	
	Instead of creating/destroying row components as items scroll in/out of view,
	maintains a fixed pool of reusable row slots. When the visible range changes,
	slots are reassigned to new data indices — only property updates occur, no
	instance creation/destruction. This eliminates lag spikes during fast scrolling.
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local action = Vide.action
local untrack = Vide.untrack

export type VirtualizedListProps<T> = {
	items: () -> { T },
	itemHeight: number,
	renderItem: (item: () -> T?, absoluteIndex: () -> number) -> Frame,
	overscan: number?,
	scrollingFrameRef: ((ref: ScrollingFrame) -> ())?,
	scrollBarThickness: number?,
}

-- Larger buffer to prevent blank spaces during fast scrolling
local DEFAULT_OVERSCAN = 16
-- Maximum pool slots (covers 4K displays + overscan)
local MAX_POOL_SIZE = 80

local function VirtualizedList<T>(props: VirtualizedListProps<T>): ScrollingFrame
	local theme = Theme.get()
	local overscan = props.overscan or DEFAULT_OVERSCAN
	local itemHeight = props.itemHeight
	
	-- Track slot assignments: dataIndex -> slot
	type PoolSlot = {
		assignedIndex: typeof(source(0)),
	}
	
	local poolSlots: { PoolSlot } = {}
	local poolChildren: { Frame } = {}
	local indexToSlot: { [number]: PoolSlot } = {}
	
	-- Generation counter to cancel stale deferred reassignments
	local reassignGeneration = 0
	
	-- ═══════════════════════════════════════════════════════════════
	-- Pool slot reassignment (runs OUTSIDE reactive scopes via defer)
	-- ═══════════════════════════════════════════════════════════════
	
	local function reassignSlots()
		-- Read current state outside of any reactive scope (untracked)
		local items = untrack(props.items)
		local scrollFrame: ScrollingFrame? = nil
		
		-- We'll read viewport info from the ScrollingFrame directly
		-- to avoid depending on reactive sources during reassignment
		for _, child in poolChildren do
			local parent = child.Parent
			if parent and parent:IsA("ScrollingFrame") then
				scrollFrame = parent :: ScrollingFrame
				break
			end
		end
		
		local posY = 0
		local viewH = 0
		if scrollFrame then
			posY = scrollFrame.CanvasPosition.Y
			viewH = scrollFrame.AbsoluteWindowSize.Y
		end
		
		if viewH == 0 or itemHeight == 0 or #items == 0 then
			-- Hide all slots
			for _, slot in poolSlots do
				if slot.assignedIndex() ~= 0 then
					slot.assignedIndex(0)
				end
			end
			indexToSlot = {}
			return
		end
		
		local startIdx = math.max(1, math.floor(posY / itemHeight) - overscan + 1)
		local endIdx = math.min(#items, math.ceil((posY + viewH) / itemHeight) + overscan)
		
		-- Build set of needed indices
		local needed: { [number]: boolean } = {}
		for idx = startIdx, endIdx do
			needed[idx] = true
		end
		
		-- Separate currently-assigned slots into "keep" vs "free"
		local newIndexToSlot: { [number]: PoolSlot } = {}
		local freeSlots: { PoolSlot } = {}
		
		for idx, slot in indexToSlot do
			if needed[idx] then
				newIndexToSlot[idx] = slot
			else
				table.insert(freeSlots, slot)
			end
		end
		
		-- Also collect unassigned pool slots
		for _, slot in poolSlots do
			if slot.assignedIndex() == 0 then
				table.insert(freeSlots, slot)
			end
		end
		
		-- Assign free slots to indices that need them
		local freeIdx = 1
		for idx = startIdx, endIdx do
			if not newIndexToSlot[idx] then
				if freeIdx <= #freeSlots then
					local slot = freeSlots[freeIdx]
					slot.assignedIndex(idx)
					newIndexToSlot[idx] = slot
					freeIdx += 1
				end
			end
		end
		
		-- Hide leftover free slots
		while freeIdx <= #freeSlots do
			local slot = freeSlots[freeIdx]
			if slot.assignedIndex() ~= 0 then
				slot.assignedIndex(0)
			end
			freeIdx += 1
		end
		
		indexToSlot = newIndexToSlot
	end
	
	-- Schedule a deferred reassignment (coalesces multiple calls per frame)
	local function scheduleReassign()
		reassignGeneration += 1
		local gen = reassignGeneration
		task.defer(function()
			if gen ~= reassignGeneration then return end -- Stale, skip
			reassignSlots()
		end)
	end
	
	-- ═══════════════════════════════════════════════════════════════
	-- Pool creation (runs once)
	-- ═══════════════════════════════════════════════════════════════
	
	for i = 1, MAX_POOL_SIZE do
		local assignedIndex = source(0)
		
		-- Derive the item data from the assigned index
		local itemSource = derive(function(): T?
			local idx = assignedIndex()
			if idx < 1 then return nil end
			local items = props.items()
			if idx > #items then return nil end
			return items[idx]
		end)
		
		-- Create the rendered row component (once, reused forever)
		local renderedItem = props.renderItem(itemSource, assignedIndex)
		
		-- Wrapper frame with reactive position and visibility
		local container = create "Frame" {
			Name = `PoolSlot_{i}`,
			Size = UDim2.new(1, 0, 0, itemHeight),
			Position = function()
				local idx = assignedIndex()
				if idx < 1 then return UDim2.new() end
				return UDim2.fromOffset(0, (idx - 1) * itemHeight)
			end,
			Visible = function()
				return assignedIndex() > 0
			end,
			BackgroundTransparency = 1,
			
			renderedItem,
		}
		
		local slot: PoolSlot = {
			assignedIndex = assignedIndex,
		}
		
		poolSlots[i] = slot
		table.insert(poolChildren, container)
	end
	
	-- ═══════════════════════════════════════════════════════════════
	-- Total canvas size (reactive, for ScrollingFrame.CanvasSize)
	-- ═══════════════════════════════════════════════════════════════
	
	local canvasSize = derive(function()
		local totalHeight = #props.items() * itemHeight
		-- Also trigger reassignment when items change
		scheduleReassign()
		return UDim2.new(1, 0, 0, totalHeight)
	end)
	
	-- ═══════════════════════════════════════════════════════════════
	-- ScrollingFrame
	-- ═══════════════════════════════════════════════════════════════
	
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
			-- Expose ref if requested
			if props.scrollingFrameRef then
				props.scrollingFrameRef(instance)
			end
			
			-- Scroll handler: schedule reassignment on every scroll
			instance:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				scheduleReassign()
			end)
			
			-- Viewport resize: schedule reassignment
			instance:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
				scheduleReassign()
			end)
			
			-- Initial assignment (deferred to avoid reactive scope conflicts)
			scheduleReassign()
		end),
		
		-- All pool slot frames (hidden ones have Visible = false)
		table.unpack(poolChildren),
	}
end

return VirtualizedList
