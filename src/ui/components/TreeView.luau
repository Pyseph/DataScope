--!strict
--[[
	TreeView Component
	Hierarchical JSON data visualization with editing support
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Parent.Parent.core.Types)
local Functional = require(script.Parent.Parent.Parent.utils.Functional)
local LuaLiteral = require(script.Parent.Parent.Parent.utils.LuaLiteral)
local Store = require(script.Parent.Parent.Parent.core.Store)
local VirtualizedList = require(script.Parent.VirtualizedList)
local Button = require(script.Parent.Button)
local Tooltip = require(script.Parent.Tooltip)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local action = Vide.action
local effect = Vide.effect
local untrack = Vide.untrack
local show = Vide.show

type JSONValue = Types.JSONValue
type TreeNode = Types.TreeNode
type DiffFieldKind = Types.DiffFieldKind

export type TreeViewExpandRef = {
	expandPaths: ((paths: { { string | number } }) -> ())?,
	expandAll: ((data: JSONValue) -> ())?,
	collapseAll: (() -> ())?,
	setExpanded: ((paths: { [string]: boolean }) -> ())?,
	getExpanded: (() -> { [string]: boolean })?,
}

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
	expandRef: TreeViewExpandRef?,
	useAlternatingColors: (() -> boolean)?,
	onScrollPathChange: ((path: { string | number }) -> ())?,
	diffPathKinds: (() -> { [string]: DiffFieldKind })?,
	diffPathBeforeValues: (() -> { [string]: JSONValue })?,
	visiblePathFilter: (() -> { [string]: boolean })?,
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
local pathToKey = Functional.pathToKey

local function isPathInFilter(pathKey: string, filter: { [string]: boolean }): boolean
	if filter[pathKey] then
		return true
	end

	for filterPath in filter do
		if string.sub(filterPath, 1, #pathKey + 1) == pathKey .. "." then
			return true
		end
	end

	return false
end

local function getPathHighlightKind(path: { string | number }, highlights: { [string]: DiffFieldKind }): DiffFieldKind?
	local exact = highlights[pathToKey(path)]
	if exact then
		return exact :: DiffFieldKind
	end

	-- Fallback to nearest marked ancestor for branch-level highlights.
	for i = #path - 1, 1, -1 do
		local ancestor = {}
		for j = 1, i do
			table.insert(ancestor, path[j])
		end
		local ancestorKind = highlights[pathToKey(ancestor)]
		if ancestorKind then
			return ancestorKind :: DiffFieldKind
		end
	end

	return nil
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
	if not start or not finish then return text end
	
	local before = string.sub(text, 1, start - 1)
	local match = string.sub(text, start, finish)
	local after = string.sub(text, finish + 1)
	
	local colorHex = string.format("#%02x%02x%02x", color.R * 255, color.G * 255, color.B * 255)
	return `{before}<font color="{colorHex}"><b>{match}</b></font>{after}`
end

local function tintColor(base: Color3, tint: Color3, amount: number): Color3
	return Color3.new(
		base.R + (tint.R - base.R) * amount,
		base.G + (tint.G - base.G) * amount,
		base.B + (tint.B - base.B) * amount
	)
end

local function toHex(color: Color3): string
	return string.format("#%02x%02x%02x",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255))
end

-- Compute visual {line, col} from a character index in wrapped text
local function charToVisual(text: string, charIdx: number, charsPerLine: number): (number, number)
	local before = string.sub(text, 1, charIdx - 1)
	local lines = string.split(before, "\n")
	local visualLine = 0
	local col = 0

	for i, line in lines do
		if i < #lines then
			local wraps = if #line == 0 then 1 else math.ceil(#line / charsPerLine)
			visualLine += wraps
		else
			if #line == 0 then
				col = 0
			else
				local wraps = math.floor(#line / charsPerLine)
				visualLine += wraps
				col = #line - wraps * charsPerLine
			end
		end
	end

	return visualLine, col
end

local function openTableEditor(
	path: { string | number },
	currentValue: JSONValue,
	onValueChange: ((path: { string | number }, newValue: JSONValue) -> ())?
)
	if not onValueChange then return end

	-- Build path display string
	local pathStr = "root"
	for _, segment in path do
		if type(segment) == "number" then
			pathStr ..= `[{segment}]`
		else
			pathStr ..= `.{segment}`
		end
	end

	Store.openModal(function()
		local theme = Theme.get()
		local editorText = source(LuaLiteral.toLuaValuePretty(currentValue))
		local parseError = source(nil :: string?)

		-- Cursor and selection state
		local cursorX = source(0)
		local cursorY = source(0)
		local isFocused = source(false)
		local cursorVisible = source(true)
		local monoCharWidth = source(7.8)
		local monoLineHeight = source(theme.fontSize.normal + 2)
		local contentHeight = source(theme.fontSize.normal + 2)

		local selTopVisible = source(false)
		local selTopPos = source(UDim2.fromOffset(0, 0))
		local selTopSize = source(UDim2.fromOffset(0, 0))
		local selMidVisible = source(false)
		local selMidPos = source(UDim2.fromOffset(0, 0))
		local selMidSize = source(UDim2.fromOffset(0, 0))
		local selBotVisible = source(false)
		local selBotPos = source(UDim2.fromOffset(0, 0))
		local selBotSize = source(UDim2.fromOffset(0, 0))

		-- Measure monospace character width and line height
		task.spawn(function()
			local TextService = game:GetService("TextService")
			local ok, size = pcall(function()
				local p = Instance.new("GetTextBoundsParams")
				p.Text = "M"
				p.Font = theme.fontMono
				p.Size = theme.fontSize.normal
				p.Width = math.huge
				return TextService:GetTextBoundsAsync(p)
			end)
			if ok then
				monoCharWidth(size.X)
			end
			-- Measure actual line height by comparing 1-line vs 2-line bounds
			local ok2, oneLineH, twoLineH = pcall(function()
				local p1 = Instance.new("GetTextBoundsParams")
				p1.Text = "M"
				p1.Font = theme.fontMono
				p1.Size = theme.fontSize.normal
				p1.Width = math.huge
				local s1 = TextService:GetTextBoundsAsync(p1)
				local p2 = Instance.new("GetTextBoundsParams")
				p2.Text = "M\nM"
				p2.Font = theme.fontMono
				p2.Size = theme.fontSize.normal
				p2.Width = math.huge
				local s2 = TextService:GetTextBoundsAsync(p2)
				return s1.Y, s2.Y
			end)
			if ok2 then
				monoLineHeight(twoLineH - oneLineH)
			end
		end)

		-- Cursor blink loop
		task.spawn(function()
			while true do
				task.wait(0.53)
				if isFocused() then
					cursorVisible(not cursorVisible())
				end
			end
		end)

		local function getSyntaxColors(): LuaLiteral.SyntaxColors
			local c = theme.colors()
			return {
				keyword = toHex(c.accent),
				string = toHex(c.success),
				number = toHex(c.warning),
				boolean = toHex(c.accent),
				operator = toHex(c.foregroundSecondary),
				default = toHex(c.foreground),
			}
		end

		return create "Frame" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			create "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			},

			-- Path label
			create "TextLabel" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = pathStr,
				TextColor3 = function() return theme.colors().foregroundMuted end,
				TextSize = theme.fontSize.small,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = theme.fontMono,
			},

			-- Editor container (fills remaining space: total - path(18) - gap(8) - gap(8) - buttons(32))
			create "Frame" {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 1, -74),
				BackgroundColor3 = function() return theme.colors().backgroundTertiary end,
				BorderSizePixel = 0,
				ClipsDescendants = true,

				create "UICorner" { CornerRadius = UDim.new(0, theme.radius.md) },
				create "UIStroke" {
					Color = function()
						if parseError() then
							return theme.colors().error
						end
						return theme.colors().border
					end,
					Thickness = 1,
				},

				create "ScrollingFrame" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ScrollBarThickness = 4,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					CanvasSize = function()
						return UDim2.fromOffset(0, contentHeight() + 16)
					end,
					ScrollBarImageColor3 = function() return theme.colors().foregroundMuted end,
					BorderSizePixel = 0,

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
						PaddingTop = UDim.new(0, 8),
						PaddingBottom = UDim.new(0, 8),
					},

					-- Syntax-highlighted display (behind TextBox)
					create "TextLabel" {
						Name = "Highlight",
						Size = function()
							return UDim2.new(1, 0, 0, contentHeight())
						end,
						BackgroundTransparency = 1,
						RichText = true,
						Text = function()
							return LuaLiteral.highlightLuaLiteral(editorText(), getSyntaxColors())
						end,
						TextColor3 = function() return theme.colors().foreground end,
						TextSize = theme.fontSize.normal,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						FontFace = theme.fontMono,
						TextWrapped = true,
						ZIndex = 1,
					},

					-- Selection highlight frames (behind text, ZIndex 0)
					create "Frame" {
						Name = "SelectionTop",
						Position = selTopPos,
						Size = selTopSize,
						BackgroundColor3 = function() return theme.colors().accent end,
						BackgroundTransparency = 0.7,
						Visible = selTopVisible,
						ZIndex = 0,
						BorderSizePixel = 0,
					},
					create "Frame" {
						Name = "SelectionMid",
						Position = selMidPos,
						Size = selMidSize,
						BackgroundColor3 = function() return theme.colors().accent end,
						BackgroundTransparency = 0.7,
						Visible = selMidVisible,
						ZIndex = 0,
						BorderSizePixel = 0,
					},
					create "Frame" {
						Name = "SelectionBot",
						Position = selBotPos,
						Size = selBotSize,
						BackgroundColor3 = function() return theme.colors().accent end,
						BackgroundTransparency = 0.7,
						Visible = selBotVisible,
						ZIndex = 0,
						BorderSizePixel = 0,
					},

					-- Invisible TextBox for input (explicit size, no AutomaticSize)
					create "TextBox" {
						Name = "Editor",
						Size = function()
							return UDim2.new(1, 0, 0, contentHeight())
						end,
						BackgroundTransparency = 1,
						Text = editorText,
						TextColor3 = Color3.new(1, 1, 1),
						TextTransparency = 1,
						TextSize = theme.fontSize.normal,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						FontFace = theme.fontMono,
						ClearTextOnFocus = false,
						MultiLine = true,
						TextWrapped = true,
						ZIndex = 2,

						FocusLost = function()
							isFocused(false)
							selTopVisible(false)
							selMidVisible(false)
							selBotVisible(false)
						end,

						action(function(tb: TextBox)
							-- Compute content height from text
							local function measureContentHeight()
								local text = tb.Text
								local cw = monoCharWidth()
								local containerWidth = math.max(1, tb.AbsoluteSize.X)
								local charsPerLine = math.max(1, math.floor(containerWidth / cw))
								local lh = monoLineHeight()

								-- Count total visual lines
								local totalLines = 0
								local lines = string.split(text, "\n")
								for _, line in lines do
									local wraps = if #line == 0 then 1 else math.ceil(#line / charsPerLine)
									totalLines += wraps
								end

								contentHeight(math.max(lh, totalLines * lh))
							end

							local function updateCursorAndSelection()
								local lh = monoLineHeight()
								local cursorPos = tb.CursorPosition
								local selStart = tb.SelectionStart
								local text = tb.Text
								local cw = monoCharWidth()
								local containerWidth = math.max(1, tb.AbsoluteSize.X)
								local charsPerLine = math.max(1, math.floor(containerWidth / cw))

								-- Update cursor position
								if cursorPos >= 1 then
									local cLine, cCol = charToVisual(text, cursorPos, charsPerLine)
									cursorX(math.floor(cCol * cw))
									cursorY(cLine * lh)
								end

								-- Update selection
								if selStart >= 1 and cursorPos >= 1 and selStart ~= cursorPos then
									local fromIdx = math.min(selStart, cursorPos)
									local toIdx = math.max(selStart, cursorPos)

									local startLine, startCol = charToVisual(text, fromIdx, charsPerLine)
									local endLine, endCol = charToVisual(text, toIdx, charsPerLine)

									if startLine == endLine then
										selTopPos(UDim2.fromOffset(math.floor(startCol * cw), startLine * lh))
										selTopSize(UDim2.fromOffset(math.floor((endCol - startCol) * cw), lh))
										selTopVisible(true)
										selMidVisible(false)
										selBotVisible(false)
									else
										selTopPos(UDim2.fromOffset(math.floor(startCol * cw), startLine * lh))
										selTopSize(UDim2.fromOffset(math.floor(containerWidth - startCol * cw), lh))
										selTopVisible(true)

										local midLines = endLine - startLine - 1
										if midLines > 0 then
											selMidPos(UDim2.fromOffset(0, (startLine + 1) * lh))
											selMidSize(UDim2.fromOffset(math.floor(containerWidth), midLines * lh))
											selMidVisible(true)
										else
											selMidVisible(false)
										end

										if endCol > 0 then
											selBotPos(UDim2.fromOffset(0, endLine * lh))
											selBotSize(UDim2.fromOffset(math.floor(endCol * cw), lh))
											selBotVisible(true)
										else
											selBotVisible(false)
										end
									end
								else
									selTopVisible(false)
									selMidVisible(false)
									selBotVisible(false)
								end
							end

							tb:GetPropertyChangedSignal("CursorPosition"):Connect(function()
								cursorVisible(true)
								updateCursorAndSelection()
							end)

							tb:GetPropertyChangedSignal("SelectionStart"):Connect(function()
								cursorVisible(true)
								updateCursorAndSelection()
							end)

							tb:GetPropertyChangedSignal("Text"):Connect(function()
								editorText(tb.Text)
								local ok, _ = LuaLiteral.parseLuaValue(tb.Text)
								parseError(if ok then nil else "Invalid Lua table syntax")
								measureContentHeight()
								updateCursorAndSelection()
							end)

							tb.Focused:Connect(function()
								isFocused(true)
								cursorVisible(true)
								task.defer(function()
									measureContentHeight()
									updateCursorAndSelection()
								end)
							end)

							-- Initial measurement
							task.defer(function()
								measureContentHeight()
								tb:CaptureFocus()
							end)
						end),
					},

					-- Custom blinking cursor
					create "Frame" {
						Name = "Cursor",
						Position = function()
							return UDim2.fromOffset(cursorX(), cursorY())
						end,
						Size = function()
							return UDim2.fromOffset(1, monoLineHeight())
						end,
						BackgroundColor3 = function() return theme.colors().foreground end,
						Visible = function()
							return isFocused() and cursorVisible()
						end,
						ZIndex = 3,
						BorderSizePixel = 0,
					},
				},
			},

			-- Error message
			show(function() return parseError() ~= nil end, function()
				return create "TextLabel" {
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					Text = function() return parseError() or "" end,
					TextColor3 = function() return theme.colors().error end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.font,
				}
			end),

			-- Button row
			create "Frame" {
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				},

				Button({
					text = "Cancel",
					variant = "secondary",
					size = "medium",
					onClick = function()
						Store.closeModal()
					end,
				}),

				Button({
					text = "Save",
					variant = "primary",
					size = "medium",
					disabled = function() return parseError() ~= nil end,
					onClick = function()
						local text = editorText()
						local ok, parsed = LuaLiteral.parseLuaValue(text)
						if ok then
							onValueChange(path, parsed)
							Store.closeModal()
						end
					end,
				}),
			},
		}
	end, "Edit Table")
end

local function TreeView(props: TreeViewProps): Frame
	local theme = Theme.get()

	-- Context Menu State (position stored as local X,Y relative to TreeView root)
	local contextMenu = source({ visible = false, x = 0, y = 0, node = nil } :: { visible: boolean, x: number, y: number, node: TreeNode? })
	local closeContextMenu = function()
		contextMenu({ visible = false, x = 0, y = 0, node = nil })
	end

	local openContextMenu = function(x: number, y: number, node: TreeNode)
		Tooltip.hide()
		-- Close first so show() unmounts, then defer reopen so it remounts with fresh state
		closeContextMenu()
		task.defer(function()
			contextMenu({ visible = true, x = x, y = y, node = node })
		end)
	end


	-- Track TreeView root frame position for coordinate conversion
	local treeViewAbsPos = source(Vector2.zero)

	-- TreeView always owns its expand state internally
	local localExpandedPaths = source({} :: { [string]: boolean })
	local expandedPaths: () -> { [string]: boolean } = function()
		return localExpandedPaths()
	end

	local toggleExpand: ({ string | number }) -> () = function(path: { string | number })
		local key = pathToKey(path)
		local current = localExpandedPaths()
		local newPaths = Functional.deepClone(current)
		newPaths[key] = not newPaths[key]
		localExpandedPaths(newPaths)
	end

	-- Register imperative methods on expandRef so consumers can control expand state
	if props.expandRef then
		props.expandRef.expandPaths = function(paths: { { string | number } })
			local current = localExpandedPaths()
			local newPaths = Functional.deepClone(current)
			for _, path in paths do
				newPaths[pathToKey(path)] = true
			end
			localExpandedPaths(newPaths)
		end
		props.expandRef.expandAll = function(data: JSONValue)
			if type(data) ~= "table" then
				return
			end
			local paths: { [string]: boolean } = {}
			local function addPaths(value: any, pathStr: string)
				if type(value) ~= "table" then
					return
				end
				if pathStr ~= "" then
					paths[pathStr] = true
				end
				for k, v in value do
					local childPath = if pathStr == "" then tostring(k) else pathStr .. "." .. tostring(k)
					addPaths(v, childPath)
				end
			end
			addPaths(data, "")
			localExpandedPaths(paths)
		end
		props.expandRef.collapseAll = function()
			localExpandedPaths({})
		end
		props.expandRef.setExpanded = function(paths: { [string]: boolean })
			localExpandedPaths(paths)
		end
		props.expandRef.getExpanded = function()
			return localExpandedPaths()
		end
	end

	local readOnly: () -> boolean = props.readOnly or function()
		return false
	end

	local searchQuery: () -> string = props.searchQuery or function()
		return ""
	end

	local searchResults: () -> { { string | number } } = props.searchResults or function()
		return {}
	end

	local currentSearchResult: () -> { string | number }? = props.currentSearchResult or function()
		return nil
	end

	local useAlternatingColors: () -> boolean = props.useAlternatingColors or function()
		return false
	end

	local diffPathKinds: () -> { [string]: DiffFieldKind } = props.diffPathKinds or function()
		return {} :: { [string]: DiffFieldKind }
	end

	local diffPathBeforeValues: () -> { [string]: JSONValue } = props.diffPathBeforeValues or function()
		return {} :: { [string]: JSONValue }
	end

	local visiblePathFilter: () -> { [string]: boolean } = props.visiblePathFilter or function()
		return {} :: { [string]: boolean }
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
		local pathFilter = visiblePathFilter()
		local hasPathFilter = next(pathFilter) ~= nil
		
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
				if hasPathFilter and not isPathInFilter(childPathKey, pathFilter) then
					table.remove(path)
					continue
				end

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

		local nodeHighlightKind = derive(function(): DiffFieldKind?
			local n = node()
			if n == nil then
				return nil
			end
			return getPathHighlightKind(n.path, diffPathKinds())
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
			local c = theme.colors()
			local highlightKind = nodeHighlightKind()
			if highlightKind == "added" then
				return tintColor(baseBackgroundColor(), c.success, 0.2)
			elseif highlightKind == "removed" then
				return tintColor(baseBackgroundColor(), c.error, 0.2)
			elseif highlightKind == "changed" then
				return tintColor(baseBackgroundColor(), c.warning, 0.2)
			end

			if isCurrentResult() then
				-- Search result highlight is instant, no animation
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

			local highlightKind = nodeHighlightKind()
			if highlightKind == "added" then
				return c.success
			elseif highlightKind == "removed" then
				return c.error
			elseif highlightKind == "changed" then
				return c.warning
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
			if typeof(n.value) == "buffer" then
				return
			end
			if type(n.value) == "table" then
				openTableEditor(n.path, n.value, props.onValueChange)
				return
			end
			editValue(tostring(n.value))
			isEditing(true)
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
			elseif string.sub(newText, 1, 1) == "{" then
				local ok, parsed = LuaLiteral.parseLuaValue(newText)
				if ok then
					newValue = parsed
				else
					newValue = newText
				end
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
					openContextMenu(input.Position.X - absPos.X, input.Position.Y - absPos.Y, n)
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
					else
						-- Start editing for any value (primitives, empty tables)
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
					if contextMenu().visible then
						closeContextMenu()
					end
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
						local highlightKind = nodeHighlightKind()
						if highlightKind == "added" then
							return c.success
						elseif highlightKind == "removed" then
							return c.error
						elseif highlightKind == "changed" then
							return c.warning
						end
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
						local highlightKind = nodeHighlightKind()
						if highlightKind == "changed" then
							local beforeValues = diffPathBeforeValues()
							local beforeVal = beforeValues[pathToKey(n.path)]
							if beforeVal ~= nil then
								return formatValue(beforeVal) .. " → " .. formatValue(n.value)
							end
						end
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
					return isHovered() and not isEditing() and typeof(n.value) ~= "buffer" and not readOnly()
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
				Name = "DiffBadge",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -40, 0.5, 0),
				Size = UDim2.fromOffset(15, 15),
				BackgroundColor3 = function()
					local c = theme.colors()
					local kind = nodeHighlightKind()
					if kind == "added" then
						return c.success
					elseif kind == "removed" then
						return c.error
					elseif kind == "changed" then
						return c.warning
					end
					return c.backgroundTertiary
				end,
				BackgroundTransparency = 0.84,
				Text = function()
					local kind = nodeHighlightKind()
					if kind == "added" then
						return "+"
					elseif kind == "removed" then
						return "-"
					elseif kind == "changed" then
						return "~"
					end
					return ""
				end,
				TextColor3 = function()
					local c = theme.colors()
					local kind = nodeHighlightKind()
					if kind == "added" then
						return c.success
					elseif kind == "removed" then
						return c.error
					elseif kind == "changed" then
						return c.warning
					end
					return c.foregroundMuted
				end,
				TextSize = theme.fontSize.xs,
				FontFace = theme.fontMedium,
				Visible = function()
					return nodeHighlightKind() ~= nil
				end,

				create "UICorner" {
					CornerRadius = UDim.new(1, 0),
				},

				create "UIStroke" {
					Color = function()
						local c = theme.colors()
						local kind = nodeHighlightKind()
						if kind == "added" then
							return c.success
						elseif kind == "removed" then
							return c.error
						elseif kind == "changed" then
							return c.warning
						end
						return c.border
					end,
					Transparency = 0.35,
					Thickness = 1,
				},
			},

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
			localExpandedPaths(newExpanded)
		end

		-- Scroll to reveal the current search result.
		-- Defer if paths were expanded (wait for tree rebuild), otherwise scroll immediately.
		local function scrollToResult()
			if not scrollingFrameRef then
				return
			end

			local nodes = flattenedNodes()
			local targetIndex = nil
			for i, node in nodes do
				if pathMatches(node.path, currentResult) then
					targetIndex = i
					break
				end
			end

			if targetIndex then
				local rowHeight = 28
				local targetY = (targetIndex - 1) * rowHeight
				local viewportHeight = scrollingFrameRef.AbsoluteWindowSize.Y
				local scrollY = math.max(0, targetY - viewportHeight / 2)
				scrollingFrameRef.CanvasPosition = Vector2.new(0, scrollY)
			end
		end

		if needsUpdate then
			task.defer(scrollToResult)
		else
			scrollToResult()
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
	
	-- Build a synthetic root node representing the top-level data container
	local function makeRootNode(): TreeNode?
		local data = props.data()
		if type(data) ~= "table" then
			return nil
		end
		local isArray = true
		local count = 0
		for k, _ in data :: any do
			count += 1
			if type(k) ~= "number" then
				isArray = false
			end
		end
		return {
			key = "$root",
			value = data,
			path = {},
			depth = 0,
			isExpanded = true,
			isObject = not isArray,
			isArray = isArray,
			childCount = count,
			matchesSearch = false,
		}
	end

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

		-- Click handling for empty space
		InputBegan = function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				if contextMenu().visible then
					closeContextMenu()
				end
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				local absPos = treeViewAbsPos()
				local localX = input.Position.X - absPos.X
				local localY = input.Position.Y - absPos.Y

				-- Check if click is on a row
				if scrollingFrameRef then
					local scrollY = scrollingFrameRef.CanvasPosition.Y
					local rowIndex = math.floor((localY + scrollY) / 28) + 1
					local nodes = flattenedNodes()
					if nodes[rowIndex] then
						return -- Row handler will take care of it
					end
				end

				-- Empty space: open root context menu
				local rootNode = makeRootNode()
				if rootNode then
					openContextMenu(localX, localY, rootNode)
				end
			end
		end,

		
		list,
		
		-- Context Menu
		show(function() return contextMenu().visible end, function()
			local state = contextMenu()
			local n = state.node
			if not n then return nil end

			local isContainer = n.isObject or n.isArray
			local canInsert = isContainer and not readOnly() and props.onInsert ~= nil

			-- Hover sources for menu items (avoids MouseEnter/MouseLeave self param issue)
			local copyHovered = source(false)
			local expandHovered = source(false)
			local insertHovered = source(false)
			local insertKeyText = source("")
			local isInsertMode = source(false)
			local insertError = source("")
			local deleteHovered = source(false)

			-- Generate a unique key name for objects
			local function getNextKeyName(): string
				if n.isArray then
					return tostring(n.childCount + 1)
				end
				-- Object: find a unique "newKey" name
				local base = "newKey"
				local val = n.value :: any
				if val[base] == nil then
					return base
				end
				local i = 1
				while val[base .. "_" .. tostring(i)] ~= nil do
					i += 1
				end
				return base .. "_" .. tostring(i)
			end

			-- Handle insert submission
			local function submitInsert()
				if not props.onInsert then return end

				if n.isArray then
					-- Arrays: auto-append at next index
					props.onInsert(n.path, n.childCount + 1, "")
					-- Expand parent to show new entry
					local pathKey = pathToKey(n.path)
					local expanded = expandedPaths()
					if not expanded[pathKey] then
						toggleExpand(n.path)
					end
					closeContextMenu()
					return
				end

				-- Object: validate key name
				local keyName = insertKeyText()
				if keyName == "" then
					insertError("Key name cannot be empty")
					return
				end

				-- Check for duplicate key
				local val = n.value :: any
				if val[keyName] ~= nil then
					insertError("Key already exists")
					return
				end

				props.onInsert(n.path, keyName, "")
				-- Expand parent to show new entry
				local pathKey = pathToKey(n.path)
				local expanded = expandedPaths()
				if not expanded[pathKey] then
					toggleExpand(n.path)
				end
				closeContextMenu()
			end

			return create "Frame" {
				Position = UDim2.fromOffset(state.x, state.y),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundColor3 = function() return theme.colors().backgroundSecondary end,
				BorderSizePixel = 0,
				ZIndex = 101,
				Active = true,

				-- Right-click on the menu itself: close and reopen at new target
				InputBegan = function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseButton2 then
						local absPos = treeViewAbsPos()
						local localX = input.Position.X - absPos.X
						local localY = input.Position.Y - absPos.Y

						if scrollingFrameRef then
							local scrollY = scrollingFrameRef.CanvasPosition.Y
							local rowIndex = math.floor((localY + scrollY) / 28) + 1
							local nodes = flattenedNodes()
							local targetNode = nodes[rowIndex]
							if targetNode then
								openContextMenu(localX, localY, targetNode)
								return
							end
						end

						local rootNode = makeRootNode()
						if rootNode then
							openContextMenu(localX, localY, rootNode)
						else
							closeContextMenu()
						end
					end
				end,

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
					Size = UDim2.new(0, 180, 0, 24),
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
					Size = UDim2.new(0, 180, 0, 24),
					BackgroundColor3 = function() return theme.colors().backgroundTertiary end,
					BackgroundTransparency = function()
						return if expandHovered() then 0 else 1
					end,
					Text = "  Expand All",
					TextColor3 = function() return theme.colors().foreground end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.font,
					Visible = isContainer,
					ZIndex = 102,

					Activated = function()
						toggleExpand(n.path)
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

				-- Insert Key button
				create "TextButton" {
					LayoutOrder = 3,
					Size = UDim2.new(0, 180, 0, 24),
					BackgroundColor3 = function() return theme.colors().backgroundTertiary end,
					BackgroundTransparency = function()
						return if insertHovered() or isInsertMode() then 0 else 1
					end,
					Text = function()
						if n.isArray then
							return "  Insert Item"
						end
						return "  Insert Key"
					end,
					TextColor3 = function()
						local c = theme.colors()
						if isInsertMode() then
							return c.accent
						end
						return c.foreground
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.font,
					Visible = canInsert,
					ZIndex = 102,

					Activated = function()
						if n.isArray then
							-- Arrays: insert immediately at next index
							submitInsert()
						else
							-- Objects: show key name input
							insertKeyText(getNextKeyName())
							insertError("")
							isInsertMode(true)
						end
					end,

					MouseEnter = function()
						insertHovered(true)
					end,
					MouseLeave = function()
						insertHovered(false)
					end,

					create "UICorner" { CornerRadius = UDim.new(0, 4) },
				},

				-- Inline key name input (shown for objects after clicking Insert Key)
				show(isInsertMode, function()
					return create "Frame" {
						LayoutOrder = 4,
						Size = UDim2.new(0, 180, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						ZIndex = 102,

						create "UIListLayout" {
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 2),
						},

						-- Key name input
						create "Frame" {
							LayoutOrder = 1,
							Size = UDim2.new(1, 0, 0, 26),
							BackgroundColor3 = function() return theme.colors().background end,
							BorderSizePixel = 0,
							ZIndex = 102,

							create "UICorner" { CornerRadius = UDim.new(0, 4) },
							create "UIStroke" {
								Color = function()
									local c = theme.colors()
									if insertError() ~= "" then
										return c.error
									end
									return c.accent
								end,
								Thickness = 1,
							},
							create "UIPadding" {
								PaddingLeft = UDim.new(0, 6),
								PaddingRight = UDim.new(0, 6),
							},

							create "TextBox" {
								Size = UDim2.fromScale(1, 1),
								BackgroundTransparency = 1,
								Text = insertKeyText,
								PlaceholderText = "Key name...",
								TextColor3 = function() return theme.colors().foreground end,
								PlaceholderColor3 = function() return theme.colors().foregroundMuted end,
								TextSize = theme.fontSize.small,
								TextXAlignment = Enum.TextXAlignment.Left,
								FontFace = theme.fontMono,
								ClearTextOnFocus = false,
								ZIndex = 102,

								action(function(textBox: TextBox)
									task.defer(function()
										textBox:CaptureFocus()
									end)
									textBox:GetPropertyChangedSignal("Text"):Connect(function()
										insertKeyText(textBox.Text)
										insertError("")
									end)
								end),

								FocusLost = function(enterPressed: boolean)
									if enterPressed then
										submitInsert()
									end
								end,
							},
						},

						-- Error message
						show(function() return insertError() ~= "" end, function()
							return create "TextLabel" {
								LayoutOrder = 2,
								Size = UDim2.new(1, 0, 0, 14),
								BackgroundTransparency = 1,
								Text = insertError,
								TextColor3 = function() return theme.colors().error end,
								TextSize = theme.fontSize.small - 1,
								TextXAlignment = Enum.TextXAlignment.Left,
								FontFace = theme.font,
								ZIndex = 102,

								create "UIPadding" {
									PaddingLeft = UDim.new(0, 2),
								},
							}
						end),
					}
				end),

				-- Separator before delete
				show(function() return canInsert end, function()
					return create "Frame" {
						LayoutOrder = 5,
						Size = UDim2.fromOffset(176, 1),
						BackgroundColor3 = function() return theme.colors().border end,
						BackgroundTransparency = 0.5,
						BorderSizePixel = 0,
						ZIndex = 102,
					}
				end),

				create "TextButton" {
					LayoutOrder = 6,
					Size = UDim2.new(0, 180, 0, 24),
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
