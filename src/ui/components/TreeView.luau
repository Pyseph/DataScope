--!strict
--[[
	TreeView Component
	Hierarchical JSON data visualization with editing support using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Parent.Parent.core.Types)
local Functional = require(script.Parent.Parent.Parent.utils.Functional)
local VirtualizedList = require(script.Parent.VirtualizedList)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local indexes = Vide.indexes
local spring = Vide.spring
local action = Vide.action
local effect = Vide.effect
local untrack = Vide.untrack
local show = Vide.show

type JSONValue = Types.JSONValue
type TreeNode = Types.TreeNode

export type TreeViewProps = {
	data: () -> JSONValue,
	onValueChange: ((path: { string | number }, newValue: JSONValue) -> ())?,
	onKeyChange: ((path: { string | number }, oldKey: string | number, newKey: string | number) -> ())?,
	onDelete: ((path: { string | number }) -> ())?,
	onInsert: ((path: { string | number }, key: string | number, value: JSONValue) -> ())?,
	readOnly: (() -> boolean)?,
	searchQuery: (() -> string)?,
	searchResults: (() -> { { string | number } })?,
	currentSearchResult: (() -> { string | number }?)?,
	expandedPaths: (() -> { [string]: boolean })?,
	onToggleExpand: ((path: { string | number }) -> ())?,
	onExpandPaths: ((paths: { { string | number } }) -> ())?,
	useAlternatingColors: (() -> boolean)?,
	onScrollPathChange: ((path: { string | number }) -> ())?,
}

-- Helper to get value type for display
local function getValueType(value: JSONValue): string
	if value == nil then
		return "null"
	elseif typeof(value) == "buffer" then
		return "buffer"
	elseif type(value) == "table" then
		-- Check if array
		local isArray = true
		local count = 0
		for k, _ in value :: any do
			count += 1
			if type(k) ~= "number" then
				isArray = false
				break
			end
		end
		return if isArray then "array" else "object"
	else
		return type(value)
	end
end

-- Helper to count all keys in a table recursively
local function countAllKeys(value: any): number
	if type(value) ~= "table" then
		return 0
	end
	
	local count = 0
	for _, v in value :: any do
		count += 1 -- Count this key
		count += countAllKeys(v) -- Add nested keys
	end
	return count
end

-- Helper to format value for display
local function formatValue(value: JSONValue): string
	if value == nil then
		return "null"
	elseif type(value) == "string" then
		return `"{value}"`
	elseif type(value) == "boolean" then
		return tostring(value)
	elseif type(value) == "number" then
		return tostring(value)
	elseif typeof(value) == "buffer" then
		return `<buffer: {buffer.len(value)} bytes>`
	elseif type(value) == "table" then
		local valueType = getValueType(value)
		-- Count only direct children
		local count = 0
		for _ in value :: any do
			count += 1
		end
		if valueType == "array" then
			return `[{count} {if count == 1 then "item" else "items"}]`
		else
			return `\{{count} {if count == 1 then "key" else "keys"}\}`
		end
	end
	return tostring(value)
end

-- Path to string key for expanded state
local function pathToKey(path: { string | number }): string
	local parts = {}
	for _, p in path do
		table.insert(parts, tostring(p))
	end
	return table.concat(parts, ".")
end

-- Check if path matches search result
local function pathMatches(path: { string | number }, searchPath: { string | number }): boolean
	if #path ~= #searchPath then
		return false
	end
	for i, p in path do
		if p ~= searchPath[i] then
			return false
		end
	end
	return true
end

-- Check if path is ancestor of another path (kept for external use)
local function _isAncestorOf(ancestor: { string | number }, descendant: { string | number }): boolean
	if #ancestor >= #descendant then
		return false
	end
	for i, p in ancestor do
		if p ~= descendant[i] then
			return false
		end
	end
	return true
end

-- Helper to highlight matching text
local function highlightText(text: string, query: string, color: Color3): string
	if query == "" then return text end
	local lowerText = string.lower(text)
	local lowerQuery = string.lower(query)
	local start, finish = string.find(lowerText, lowerQuery, 1, true)
	if not start then return text end
	
	local before = string.sub(text, 1, start - 1)
	local match = string.sub(text, start, finish)
	local after = string.sub(text, finish + 1)
	
	local colorHex = string.format("#%02x%02x%02x", color.R * 255, color.G * 255, color.B * 255)
	return `{before}<font color="{colorHex}"><b>{match}</b></font>{after}`
end

local function TreeView(props: TreeViewProps): Frame
	local theme = Theme.get()

	-- Context Menu State (position stored as local X,Y relative to TreeView root)
	local contextMenu = source({ visible = false, x = 0, y = 0, node = nil } :: { visible: boolean, x: number, y: number, node: TreeNode? })
	
	local closeContextMenu = function()
		contextMenu({ visible = false, x = 0, y = 0, node = nil })
	end
	
	-- Track TreeView root frame position for coordinate conversion
	local treeViewAbsPos = source(Vector2.zero)

	-- Local state for expanded paths if not provided
	local localExpandedPaths = source({} :: { [string]: boolean })
	local expandedPaths = props.expandedPaths or function()
		return localExpandedPaths()
	end

	local toggleExpand = props.onToggleExpand or function(path: { string | number })
		local key = pathToKey(path)
		local current = localExpandedPaths()
		local newPaths = Functional.deepClone(current)
		newPaths[key] = not newPaths[key]
		localExpandedPaths(newPaths)
	end

	local readOnly = props.readOnly or function()
		return false
	end

	local searchQuery = props.searchQuery or function()
		return ""
	end

	local searchResults = props.searchResults or function()
		return {}
	end

	local currentSearchResult = props.currentSearchResult or function()
		return nil
	end

	local useAlternatingColors = props.useAlternatingColors or function()
		return false
	end

	-- Flatten tree for virtualized rendering (optimized)
	local flattenedNodes = derive(function(): { TreeNode }
		local data = props.data()
		if data == nil then
			return {}
		end

		local nodes: { TreeNode } = {}
		local expanded = expandedPaths()
		local results = searchResults()
		local query = string.lower(searchQuery())
		local hasQuery = query ~= ""
		
		-- Pre-compute search result path keys for faster lookup
		local searchPathKeys: { [string]: boolean } = {}
		local searchPathPrefixes: { string } = {}
		if hasQuery and #results > 0 then
			for _, result in results do
				local key = pathToKey(result)
				searchPathKeys[key] = true
				table.insert(searchPathPrefixes, key)
			end
		end

		-- Optimized flatten: reuse path array, only clone when storing
		local function flatten(value: JSONValue, path: { string | number }, pathKey: string, depth: number)
			if type(value) ~= "table" then
				return
			end

			local keys: { string | number } = {}
			for k in value :: any do
				table.insert(keys, k)
			end

			-- Sort keys: numbers first (sorted), then strings (alphabetical)
			table.sort(keys, function(a, b)
				if type(a) == "number" and type(b) == "number" then
					return a < b
				elseif type(a) == "number" then
					return true
				elseif type(b) == "number" then
					return false
				else
					return tostring(a) < tostring(b)
				end
			end)

			for _, key in keys do
				local childValue = (value :: any)[key]
				
				-- Build path key string efficiently
				local childPathKey = if pathKey == "" then tostring(key) else pathKey .. "." .. tostring(key)
				
				-- Only clone path when we need to store it in the node
				table.insert(path, key)
				local childPath = table.clone(path) -- table.clone is faster than deepClone for flat arrays

				local isExpanded = expanded[childPathKey] == true
				local valueType = getValueType(childValue)
				local isObject = valueType == "object"
				local isArray = valueType == "array"

				-- Check if matches search (optimized)
				local matchesSearch = false
				if hasQuery then
					local keyStr = string.lower(tostring(key))
					local valueStr = if type(childValue) ~= "table" then string.lower(tostring(childValue)) else ""
					matchesSearch = string.find(keyStr, query, 1, true) ~= nil
						or (valueStr ~= "" and string.find(valueStr, query, 1, true) ~= nil)

					-- Check search results using pre-computed keys
					if not matchesSearch then
						if searchPathKeys[childPathKey] then
							matchesSearch = true
						else
							-- Check if this is ancestor of any search result
							for _, prefix in searchPathPrefixes do
								if string.sub(prefix, 1, #childPathKey + 1) == childPathKey .. "." then
									matchesSearch = true
									break
								end
							end
						end
					end
				end

				-- Count all keys in the entire nested hierarchy
				local childCount = countAllKeys(childValue)

				local node: TreeNode = {
					key = key,
					value = childValue,
					path = childPath,
					depth = depth,
					isExpanded = isExpanded,
					isObject = isObject,
					isArray = isArray,
					childCount = childCount,
					matchesSearch = matchesSearch,
				}

				table.insert(nodes, node)

				-- Recursively add children if expanded
				if isExpanded and (isObject or isArray) then
					flatten(childValue, path, childPathKey, depth + 1)
				end
				
				-- Remove the key we added (reuse path array)
				table.remove(path)
			end
		end

		-- Handle root
		if type(data) == "table" then
			flatten(data, {}, "", 0)
		else
			-- Single value at root
			table.insert(nodes, {
				key = "(root)",
				value = data,
				path = {},
				depth = 0,
				isExpanded = false,
				isObject = false,
				isArray = false,
				childCount = 0,
				matchesSearch = query ~= ""
					and string.find(string.lower(tostring(data)), query, 1, true) ~= nil,
			})
		end

		return nodes
	end)

	-- Tree node row component (accepts reactive index for pool-based recycling)
	local TreeNodeRow = function(node: () -> TreeNode?, index: () -> number): Frame
		local isHovered = source(false)
		local isEditing = source(false)
		local editValue = source("")
		local keySectionWidth = source(36) -- tracks key section width for value positioning
		
		-- Reset transient UI state when the pool slot is reassigned to a different node.
		-- This prevents stale hover/editing state from carrying over after recycling.
		local lastNodePathKey = ""
		effect(function()
			local n = node()
			local newPathKey = if n then pathToKey(n.path) else ""
			if newPathKey ~= lastNodePathKey then
				if lastNodePathKey ~= "" then -- Don't reset on initial assignment
					isEditing(false)
					isHovered(false)
				end
				lastNodePathKey = newPathKey
			end
		end)

		-- Track if this node is the current search result (for styling)
		local isCurrentResult = derive(function()
			local n = node()
			if n == nil then return false end
			local currentResult = currentSearchResult()
			return currentResult ~= nil and pathMatches(n.path, currentResult)
		end)
		
		-- Base background color (for hover/alternating, animated with spring)
		local baseBackgroundColor = derive(function()
			local c = theme.colors()
			local n = node()
			
			-- Guard against nil node (can happen during cleanup)
			if n == nil then
				return c.background
			end

			if isHovered() then
				return c.backgroundTertiary
			end

			if useAlternatingColors() and index() % 2 == 0 then
				return c.backgroundSecondary
			end

			return c.background
		end)
		
		-- Final background color: search highlight is instant (no spring), hover uses spring
		local backgroundColor = derive(function()
			if isCurrentResult() then
				-- Search result highlight is instant, no animation
				local c = theme.colors()
				local h, s, v = c.accent:ToHSV()
				return Color3.fromHSV(h, s * 0.6, v * 0.35)
			end
			-- Removed spring animation to fix vide.timeout error
			return baseBackgroundColor()
		end)

		local valueColor = derive(function()
			local c = theme.colors()
			local n = node()
			if n == nil then
				return c.foregroundMuted
			end
			
			-- Dim empty objects/arrays
			if (n.isObject or n.isArray) and n.childCount == 0 then
				return c.foregroundMuted
			end

			local valueType = getValueType(n.value)

			if valueType == "string" then
				return Color3.fromRGB(152, 195, 121) -- Green
			elseif valueType == "number" then
				return Color3.fromRGB(209, 154, 102) -- Orange
			elseif valueType == "boolean" then
				return Color3.fromRGB(198, 120, 221) -- Purple
			elseif valueType == "null" then
				return c.foregroundMuted
			elseif valueType == "buffer" then
				return Color3.fromRGB(86, 182, 194) -- Cyan
			else
				return c.foregroundSecondary
			end
		end)

		local startEdit = function()
			if readOnly() then
				return
			end
			local n = node()
			if n == nil then
				return
			end
			if type(n.value) ~= "table" then
				editValue(tostring(n.value))
				isEditing(true)
			end
		end

		local finishEdit = function(newText: string)
			isEditing(false)
			if readOnly() or not props.onValueChange then
				return
			end

			local n = node()
			if n == nil then
				return
			end
			local newValue: JSONValue

			-- Parse the new value
			if newText == "null" or newText == "nil" then
				newValue = nil
			elseif newText == "true" then
				newValue = true
			elseif newText == "false" then
				newValue = false
			elseif tonumber(newText) then
				newValue = tonumber(newText)
			else
				-- String - remove quotes if present
				if string.sub(newText, 1, 1) == '"' and string.sub(newText, -1) == '"' then
					newValue = string.sub(newText, 2, -2)
				else
					newValue = newText
				end
			end

			props.onValueChange(n.path, newValue)
		end

		-- Shared right-click handler (opens context menu from any child element)
		local function handleRightClick(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				local n = node()
				if n then
					local absPos = treeViewAbsPos()
					contextMenu({
						visible = true,
						x = input.Position.X - absPos.X,
						y = input.Position.Y - absPos.Y,
						node = n
					})
				end
			end
		end
		
		-- Track double-click for expand/collapse or editing
		local lastClickTime = 0
		local DOUBLE_CLICK_THRESHOLD = 0.3
		
		local function handleDoubleClick()
			local currentTime = os.clock()
			if currentTime - lastClickTime < DOUBLE_CLICK_THRESHOLD then
				-- Double-click detected
				local n = node()
				if n then
					if (n.isObject or n.isArray) and n.childCount > 0 then
						-- Toggle expand for objects/arrays
						toggleExpand(n.path)
					elseif type(n.value) ~= "table" then
						-- Start editing for primitive values (string, number, boolean)
						startEdit()
					end
				end
				lastClickTime = 0 -- Reset to prevent triple-click
			else
				lastClickTime = currentTime
			end
		end
		
		return create "Frame" {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = backgroundColor,
			BorderSizePixel = 0,
			Visible = function()
				return node() ~= nil
			end,

			MouseEnter = function()
				isHovered(true)
			end,

			MouseLeave = function()
				isHovered(false)
			end,
			
			-- Double-click detection and Context Menu
			InputBegan = function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					handleDoubleClick()
				else
					handleRightClick(input)
				end
			end,
			
			-- Indent guide lines (positioned to counteract padding)
			create "Frame" {
				Name = "IndentGuides",
				Size = function()
					local n = node()
					local depth = if n then n.depth else 0
					return UDim2.new(0, 8 + depth * 20, 1, 0)
				end,
				Position = function()
					-- Offset left to counteract the padding
					local n = node()
					local depth = if n then n.depth else 0
					return UDim2.fromOffset(-(8 + depth * 20), 0)
				end,
				BackgroundTransparency = 1,
				ZIndex = 0,
				
				-- Generate vertical guide lines for each depth level
				Vide.indexes(function()
					local n = node()
					local depth = if n then n.depth else 0
					local guides = {}
					for i = 1, depth do
						table.insert(guides, i)
					end
					return guides
				end, function(depthLevel)
					return create "Frame" {
						Name = "GuideLine",
						Size = UDim2.new(0, 1, 1, 0),
						Position = function()
							-- Position at the center of each indent level (where the chevron would be)
							-- Base offset 8, then each level is 20px wide, center at +10
							return UDim2.fromOffset(8 + (depthLevel() - 1) * 20 + 7, 0)
						end,
						BackgroundColor3 = function()
							return theme.colors().foregroundMuted
						end,
						BackgroundTransparency = 0.3, -- Increased contrast (was 0.4)
						BorderSizePixel = 0,
					}
				end),
			},

			create "UIPadding" {
				PaddingLeft = function()
					local n = node()
					return UDim.new(0, 8 + (if n then n.depth else 0) * 20)
				end,
				PaddingRight = UDim.new(0, 8),
			},

		create "Frame" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			-- Key section (chevron + key + colon) with auto-width
			create "Frame" {
				Name = "KeySection",
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 4),
				},

				-- Expand/collapse button
				create "ImageButton" {
					LayoutOrder = 1,
					Size = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1,
					Image = function()
						local n = node()
						if n == nil then return "" end
						if n.isObject or n.isArray then
							return if n.isExpanded then theme.icons.chevronDown else theme.icons.chevronRight
						end
						return ""
					end,
					ImageColor3 = function()
						return theme.colors().foregroundSecondary
					end,
					Visible = function()
						local n = node()
						if n == nil then return false end
						return (n.isObject or n.isArray) and n.childCount > 0
					end,

					Activated = function()
						local n = node()
						if n == nil then return end
						toggleExpand(n.path)
					end,
					InputBegan = handleRightClick,
				},

				-- Spacer when no expand button
				create "Frame" {
					LayoutOrder = 1,
					Size = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1,
					Visible = function()
						local n = node()
						if n == nil then return true end
						return not ((n.isObject or n.isArray) and n.childCount > 0)
					end,
				},

				-- Key
				create "TextLabel" {
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.new(0, 0, 1, 0),
					BackgroundTransparency = 1,
					Text = function()
						local n = node()
						if n == nil then return "" end
						local text = tostring(n.key)
						if n.matchesSearch then
							return highlightText(text, searchQuery(), theme.colors().accent)
						end
						return text
					end,
					TextColor3 = function()
						local c = theme.colors()
						local n = node()
						if n == nil then return c.foreground end
						if isCurrentResult() then
							return c.foreground
						end
						if n.matchesSearch then
							return c.accent
						end
						if type(n.key) == "number" then
							return Color3.fromRGB(209, 154, 102)
						end
						return c.foreground
					end,
					TextSize = theme.fontSize.normal,
					FontFace = theme.fontMedium,
					RichText = true,
				},

				-- Colon separator
				create "TextLabel" {
					LayoutOrder = 3,
					Size = UDim2.fromOffset(8, 24),
					BackgroundTransparency = 1,
					Text = ":",
					TextColor3 = function()
						return theme.colors().foregroundMuted
					end,
					TextSize = theme.fontSize.normal,
					FontFace = theme.font,
				},

				-- Track key section width for value positioning
				action(function(keySection: Frame)
					keySectionWidth(keySection.AbsoluteSize.X)
					keySection:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
						keySectionWidth(keySection.AbsoluteSize.X)
					end)
				end),
			},

			-- Value display (when not editing) - positioned after key section
			show(function()
				return not isEditing()
			end, function()
				return create "TextButton" {
					Position = function()
						return UDim2.fromOffset(keySectionWidth() + 4, 0)
					end,
					Size = function()
						return UDim2.new(1, -(keySectionWidth() + 4 + 78), 1, 0)
					end,
					BackgroundTransparency = 1,
					Text = function()
						local n = node()
						if n == nil then return "" end
						return formatValue(n.value)
					end,
					TextColor3 = valueColor,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMono,
					TextTruncate = Enum.TextTruncate.AtEnd,
					AutoButtonColor = false,

					Activated = function()
						handleDoubleClick()
					end,
					InputBegan = handleRightClick,
				}
			end),

			-- Edit icon (pencil) - absolutely positioned before badge
			create "ImageButton" {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -62, 0.5, 0),
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				Image = theme.icons.pencil,
				ImageColor3 = function()
					return theme.colors().foregroundMuted
				end,
				Visible = function()
					local n = node()
					if n == nil then return false end
					return isHovered() and not isEditing() and type(n.value) ~= "table" and not readOnly()
				end,

				Activated = startEdit,
				InputBegan = handleRightClick,
			},

			-- Edit box (when editing) - positioned after key section
			show(isEditing, function()
				local editBoxRef: TextBox? = nil
				return create "TextBox" {
					Position = function()
						return UDim2.fromOffset(keySectionWidth() + 4, 0)
					end,
					Size = function()
						return UDim2.new(1, -(keySectionWidth() + 4 + 64), 1, 0)
					end,
					BackgroundColor3 = function()
						return theme.colors().backgroundTertiary
					end,
					BorderSizePixel = 0,
					Text = editValue,
					TextColor3 = valueColor,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMono,
					ClearTextOnFocus = false,

					action(function(textBox: TextBox)
						editBoxRef = textBox
						task.defer(function()
							textBox:CaptureFocus()
						end)
					end),

					FocusLost = function(enterPressed: boolean)
						if enterPressed and editBoxRef then
							finishEdit(editBoxRef.Text)
						else
							isEditing(false)
						end
					end,

					create "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
					},
				}
			end),

			-- Child count badge (positioned on the right)
			create "TextLabel" {
				Name = "ChildCountBadge",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 0, 18),
				BackgroundColor3 = function()
					return theme.colors().backgroundTertiary
				end,
				BackgroundTransparency = 0,
				Text = function()
					local n = node()
					if n == nil then return "" end
					return ` {n.childCount} `
				end,
				TextColor3 = function()
					return theme.colors().foregroundSecondary
				end,
				TextSize = theme.fontSize.small,
				FontFace = theme.font,
				Visible = function()
					local n = node()
					if n == nil then return false end
					return (n.isObject or n.isArray) and n.childCount > 0
				end,

				create "UICorner" {
					CornerRadius = UDim.new(0, 8),
				},
			},
		},
		}
	end

	local scrollingFrameRef: ScrollingFrame? = nil
	
	-- Auto-expand and scroll to current search result
	effect(function()
		local currentResult = currentSearchResult()
		if not currentResult then
			return
		end
		
		-- Expand all ancestor paths to reveal the result
		-- Use untrack to avoid creating a dependency on expandedPaths,
		-- which would cause a loop when we update it
		local currentExpanded = untrack(expandedPaths)
		local newExpanded = Functional.deepClone(currentExpanded)
		local needsUpdate = false
		
		-- Build all ancestor paths and expand them
		for i = 1, #currentResult do
			local ancestorPath = {}
			for j = 1, i do
				table.insert(ancestorPath, currentResult[j])
			end
			local pathKey = pathToKey(ancestorPath)
			
			-- Check if this path contains an object/array that should be expanded
			if not newExpanded[pathKey] then
				-- Verify this path actually needs expansion (has children)
				local value = Functional.getPath(props.data(), ancestorPath)
				if type(value) == "table" then
					local hasChildren = false
					for _ in value :: any do
						hasChildren = true
						break
					end
					if hasChildren then
						newExpanded[pathKey] = true
						needsUpdate = true
					end
				end
			end
		end
		
		-- Update expanded paths if needed
		if needsUpdate then
			if props.onExpandPaths then
				-- Use batch expand for external state (doesn't toggle, just ensures expanded)
				local pathsToExpand = {}
				for i = 1, #currentResult do
					local ancestorPath = {}
					for j = 1, i do
						table.insert(ancestorPath, currentResult[j])
					end
					local pathKey = pathToKey(ancestorPath)
					if newExpanded[pathKey] and not currentExpanded[pathKey] then
						-- Clone the path before inserting, otherwise all entries would reference the same table
						table.insert(pathsToExpand, table.clone(ancestorPath))
					end
				end
				
				-- Expand all paths in a single deferred callback
				if #pathsToExpand > 0 then
					task.defer(function()
						props.onExpandPaths(pathsToExpand)
					end)
				end
			elseif props.onToggleExpand then
				-- Fallback to toggle for backwards compatibility
				local pathsToExpand = {}
				for i = 1, #currentResult do
					local ancestorPath = {}
					for j = 1, i do
						table.insert(ancestorPath, currentResult[j])
					end
					local pathKey = pathToKey(ancestorPath)
					if newExpanded[pathKey] and not currentExpanded[pathKey] then
						table.insert(pathsToExpand, table.clone(ancestorPath))
					end
				end
				
				if #pathsToExpand > 0 then
					task.defer(function()
						for _, path in pathsToExpand do
							toggleExpand(path)
						end
					end)
				end
			else
				-- Using local state
				localExpandedPaths(newExpanded)
			end
			
			-- Wait a frame for the tree to rebuild before scrolling
			task.defer(function()
				if not scrollingFrameRef then
					return
				end
				
				-- Find the index of the current result in flattened nodes
				local nodes = flattenedNodes()
				local targetIndex = nil
				for i, node in nodes do
					if pathMatches(node.path, currentResult) then
						targetIndex = i
						break
					end
				end
				
				if targetIndex then
					-- Calculate the Y position of the target row (28 pixels per row)
					local rowHeight = 28
					local targetY = (targetIndex - 1) * rowHeight
					
					-- Scroll to show the target row in the middle of the viewport
					local viewportHeight = scrollingFrameRef.AbsoluteWindowSize.Y
					local scrollY = math.max(0, targetY - viewportHeight / 2)
					
					scrollingFrameRef.CanvasPosition = Vector2.new(0, scrollY)
				end
			end)
		else
			-- No expansion needed, scroll immediately
			if not scrollingFrameRef then
				return
			end
			
			-- Find the index of the current result in flattened nodes
			local nodes = flattenedNodes()
			local targetIndex = nil
			for i, node in nodes do
				if pathMatches(node.path, currentResult) then
					targetIndex = i
					break
				end
			end
			
			if targetIndex then
				-- Calculate the Y position of the target row (28 pixels per row)
				local rowHeight = 28
				local targetY = (targetIndex - 1) * rowHeight
				
				-- Scroll to show the target row in the middle of the viewport
				local viewportHeight = scrollingFrameRef.AbsoluteWindowSize.Y
				local scrollY = math.max(0, targetY - viewportHeight / 2)
				
				scrollingFrameRef.CanvasPosition = Vector2.new(0, scrollY)
			end
		end
	end)

	local list = VirtualizedList({
		items = flattenedNodes,
		itemHeight = 28,
		renderItem = TreeNodeRow,
		scrollBarThickness = 6,
		scrollingFrameRef = function(ref)
			scrollingFrameRef = ref
			
			-- Track scroll position for breadcrumbs
			if ref and props.onScrollPathChange then
				local lastPathKey = ""
				ref:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
					local pos = ref.CanvasPosition
					local topIndex = math.floor(pos.Y / 28) + 1
					local nodes = flattenedNodes()
					local topNode = nodes[topIndex]
					if topNode then
						local pathKey = table.concat(topNode.path :: any, ".")
						if pathKey ~= lastPathKey then
							lastPathKey = pathKey
							props.onScrollPathChange(topNode.path)
						end
					end
				end)
			end
		end,
	})
	
	return create "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		
		-- Track absolute position for coordinate conversion
		action(function(frame: Frame)
			treeViewAbsPos(frame.AbsolutePosition)
			frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				treeViewAbsPos(frame.AbsolutePosition)
			end)
		end),
		
		-- Click anywhere to close context menu (or right-click to re-open on new row)
		create "TextButton" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			Visible = function() return contextMenu().visible end,
			ZIndex = 100,
			
			-- Use InputBegan to handle both left-click (close) and right-click (re-open)
			InputBegan = function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					closeContextMenu()
				elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
					-- Right-click: find which row is under cursor and re-open menu there
					local absPos = treeViewAbsPos()
					local localX = input.Position.X - absPos.X
					local localY = input.Position.Y - absPos.Y
					
					if scrollingFrameRef then
						local scrollY = scrollingFrameRef.CanvasPosition.Y
						local rowIndex = math.floor((localY + scrollY) / 28) + 1
						local nodes = flattenedNodes()
						local targetNode = nodes[rowIndex]
						if targetNode then
							contextMenu({
								visible = true,
								x = localX,
								y = localY,
								node = targetNode,
							})
							return
						end
					end
					closeContextMenu()
				end
			end,
		},
		
		list,
		
		-- Context Menu
		show(function() return contextMenu().visible end, function()
			local state = contextMenu()
			local n = state.node
			if not n then return nil end
			
			-- Hover sources for menu items (avoids MouseEnter/MouseLeave self param issue)
			local copyHovered = source(false)
			local expandHovered = source(false)
			local deleteHovered = source(false)
			
			return create "Frame" {
				Position = UDim2.fromOffset(state.x, state.y),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundColor3 = function() return theme.colors().backgroundSecondary end,
				BorderSizePixel = 0,
				ZIndex = 101,
				
				create "UICorner" { CornerRadius = UDim.new(0, 6) },
				create "UIStroke" { 
					Color = function() return theme.colors().border end,
					Transparency = 0.5,
				},
				create "UIPadding" {
					PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
					PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
				},
				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 2),
				},
				
				-- Menu Items
				create "TextButton" {
					LayoutOrder = 1,
					Size = UDim2.new(0, 140, 0, 24),
					BackgroundColor3 = function() return theme.colors().backgroundTertiary end,
					BackgroundTransparency = function()
						return if copyHovered() then 0 else 1
					end,
					Text = "  Copy Path",
					TextColor3 = function() return theme.colors().foreground end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.font,
					ZIndex = 102,
					
					Activated = function()
						print(table.concat(n.path, "."))
						closeContextMenu()
					end,
					
					MouseEnter = function()
						copyHovered(true)
					end,
					MouseLeave = function()
						copyHovered(false)
					end,
					
					create "UICorner" { CornerRadius = UDim.new(0, 4) },
				},
				
				create "TextButton" {
					LayoutOrder = 2,
					Size = UDim2.new(0, 140, 0, 24),
					BackgroundColor3 = function() return theme.colors().backgroundTertiary end,
					BackgroundTransparency = function()
						return if expandHovered() then 0 else 1
					end,
					Text = "  Expand All",
					TextColor3 = function() return theme.colors().foreground end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.font,
					Visible = n.isObject or n.isArray,
					ZIndex = 102,
					
					Activated = function()
						if props.onToggleExpand then
							props.onToggleExpand(n.path)
						end
						closeContextMenu()
					end,
					
					MouseEnter = function()
						expandHovered(true)
					end,
					MouseLeave = function()
						expandHovered(false)
					end,
					
					create "UICorner" { CornerRadius = UDim.new(0, 4) },
				},
				
				create "TextButton" {
					LayoutOrder = 3,
					Size = UDim2.new(0, 140, 0, 24),
					BackgroundColor3 = function() return theme.colors().error end,
					BackgroundTransparency = function()
						return if deleteHovered() then 0.15 else 1
					end,
					Text = "  Delete Key",
					TextColor3 = function()
						if deleteHovered() then
							return Color3.new(1, 1, 1)
						end
						return theme.colors().error
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.font,
					ZIndex = 102,
					
					Activated = function()
						if props.onDelete then
							props.onDelete(n.path)
						end
						closeContextMenu()
					end,
					
					MouseEnter = function()
						deleteHovered(true)
					end,
					MouseLeave = function()
						deleteHovered(false)
					end,
					
					create "UICorner" { CornerRadius = UDim.new(0, 4) },
				},
			}
		end)
	}
end

return TreeView
