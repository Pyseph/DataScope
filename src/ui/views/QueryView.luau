--!strict
--[[
	Query View
	Cross-key query interface with expression editor, key list input,
	and split-pane results with TreeView detail.
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Store = require(script.Parent.Parent.Parent.core.Store)
local Types = require(script.Parent.Parent.Parent.core.Types)
local QueryEngine = require(script.Parent.Parent.Parent.core.QueryEngine)
local Operations = require(script.Parent.Parent.Parent.datastore.Operations)
local Functional = require(script.Parent.Parent.Parent.utils.Functional)

local Button = require(script.Parent.Parent.components.Button)
local TreeView = require(script.Parent.Parent.components.TreeView)
local Tooltip = require(script.Parent.Parent.components.Tooltip)
local VirtualizedList = require(script.Parent.Parent.components.VirtualizedList)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local effect = Vide.effect
local show = Vide.show
local action = Vide.action
local spring = Vide.spring

local TextService = game:GetService("TextService")

type QueryResult = Types.QueryResult

-- Parse a duration string like "2h30m", "1d", "90s", or a plain number (seconds)
local function parseDuration(input: string): number?
	local trimmed = string.gsub(input, "%s+", "")
	-- Try plain number first
	local plain = tonumber(trimmed)
	if plain then
		return math.floor(plain)
	end
	-- Parse duration parts
	local total = 0
	local found = false
	local pos = 1
	local suffixes: { [string]: number } = { d = 86400, h = 3600, m = 60, s = 1 }
	while pos <= #trimmed do
		local numStart = pos
		while pos <= #trimmed and string.match(string.sub(trimmed, pos, pos), "%d") do
			pos += 1
		end
		if pos == numStart then
			return nil -- invalid
		end
		local n = tonumber(string.sub(trimmed, numStart, pos - 1)) or 0
		if pos <= #trimmed then
			local suffix = string.lower(string.sub(trimmed, pos, pos))
			local mult = suffixes[suffix]
			if mult then
				total += n * mult
				found = true
				pos += 1
			else
				return nil -- unknown suffix
			end
		else
			-- Trailing number with no suffix after duration parts
			if found then
				return nil
			end
			return math.floor(n)
		end
	end
	return if found then total else nil
end

-- Format seconds as a human-readable duration string
local function formatDuration(seconds: number): string
	if seconds <= 0 then
		return "0s"
	end
	local parts: { string } = {}
	local d = math.floor(seconds / 86400)
	seconds = seconds % 86400
	local h = math.floor(seconds / 3600)
	seconds = seconds % 3600
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	if d > 0 then
		table.insert(parts, d .. "d")
	end
	if h > 0 then
		table.insert(parts, h .. "h")
	end
	if m > 0 then
		table.insert(parts, m .. "m")
	end
	if s > 0 then
		table.insert(parts, s .. "s")
	end
	return table.concat(parts)
end

-- Helper: Color3 to hex string
local function toHex(color: Color3): string
	return string.format("#%02x%02x%02x", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

-- Helper: blend a color toward a muted gray (for placeholder/faded highlighting)
local function muteColor(color: Color3, amount: number): Color3
	local gray = Color3.fromRGB(128, 128, 128)
	return color:Lerp(gray, amount)
end

local function QueryView(): Frame
	local theme = Theme.get()

	-- Syntax color builders
	local function getSyntaxColors(): QueryEngine.SyntaxColors
		local c = theme.colors()
		return {
			keyword = toHex(c.accent),
			string = toHex(c.success),
			number = toHex(c.warning),
			boolean = toHex(c.accent),
			operator = toHex(c.foregroundSecondary),
			builtin = toHex(c.info),
			default = toHex(c.foreground),
		}
	end

	local function getMutedSyntaxColors(): QueryEngine.SyntaxColors
		local c = theme.colors()
		return {
			keyword = toHex(muteColor(c.accent, 0.55)),
			string = toHex(muteColor(c.success, 0.55)),
			number = toHex(muteColor(c.warning, 0.55)),
			boolean = toHex(muteColor(c.accent, 0.55)),
			operator = toHex(muteColor(c.foregroundSecondary, 0.55)),
			builtin = toHex(muteColor(c.info, 0.55)),
			default = toHex(c.foregroundMuted),
		}
	end

	-- Local state
	local expressionError = source(nil :: string?)
	local expandRef: TreeView.TreeViewExpandRef = {}
	local detailData = source(nil :: Types.JSONValue)
	local detailPaths = source({} :: { { string | number } })
	local viewWidth = source(600)

	-- Cursor and selection state for expression editor
	local exprCursorX = source(0)
	local exprCursorY = source(0)
	local exprFocused = source(false)
	local cursorBlink = source(true)
	local monoCharWidth = source(7.8)
	local exprLineHeight = theme.fontSize.normal + 2

	-- Selection highlight state (3 rectangles: top partial, middle full, bottom partial)
	local selTopVisible = source(false)
	local selTopPos = source(UDim2.fromOffset(0, 0))
	local selTopSize = source(UDim2.fromOffset(0, 0))
	local selMidVisible = source(false)
	local selMidPos = source(UDim2.fromOffset(0, 0))
	local selMidSize = source(UDim2.fromOffset(0, 0))
	local selBotVisible = source(false)
	local selBotPos = source(UDim2.fromOffset(0, 0))
	local selBotSize = source(UDim2.fromOffset(0, 0))

	-- Compute visual {line, col} from a character index in text
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

	-- Measure monospace character width
	task.spawn(function()
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
	end)

	-- Cursor blink loop
	task.spawn(function()
		while true do
			task.wait(0.53)
			if exprFocused() then
				cursorBlink(not cursorBlink())
			end
		end
	end)

	-- Derived state
	local matchedResults = derive(function(): { QueryResult }
		local results = Store.queryResults()
		local matched: { QueryResult } = {}
		for _, r in results do
			if r.matched then
				table.insert(matched, r)
			end
		end
		return matched
	end)

	local allResults = derive(function(): { QueryResult }
		return Store.queryResults()
	end)

	local progressPercent = derive(function(): number
		local total = Store.queryTotal()
		if total == 0 then return 0 end
		return Store.queryProgress() / total
	end)

	local resultSummary = derive(function(): string
		local results = Store.queryResults()
		local matched = 0
		local errors = 0
		for _, r in results do
			if r.matched then matched += 1 end
			if r.error then errors += 1 end
		end
		local total = #results
		if total == 0 then return "" end
		local parts = { `{matched}/{total} matched` }
		if errors > 0 then
			table.insert(parts, `{errors} errors`)
		end
		return table.concat(parts, ", ")
	end)

	local isNarrow = derive(function(): boolean
		return viewWidth() < 500
	end)

	-- Validate expression on change
	local validateExpression = function(text: string)
		if text == "" then
			expressionError(nil)
			return
		end
		local result = QueryEngine.validate(text)
		if result.success then
			expressionError(nil)
		else
			expressionError(result.error)
		end
	end

	-- Update detail panel when selection changes, auto-expanding ancestor paths
	effect(function()
		local result = Store.querySelectedResult()
		if result and result.keyData then
			detailData(Functional.deepClone(result.keyData.value))
			local paths = result.matchedPaths or {}
			detailPaths(paths)

			-- Auto-expand ancestor paths so matched fields are visible
			if expandRef.setExpanded then
				local newExpanded: { [string]: boolean } = {}
				for _, matchPath in paths do
					for i = 1, #matchPath do
						local ancestor = {}
						for j = 1, i do
							table.insert(ancestor, matchPath[j])
						end
						newExpanded[Functional.pathToKey(ancestor)] = true
					end
				end
				task.defer(function()
					(expandRef.setExpanded :: any)(newExpanded)
				end)
			end
		else
			detailData(nil)
			detailPaths({})
		end
	end)

	-- Budget polling
	local budgetText = source("")
	task.spawn(function()
		while true do
			local budget = Operations.getBudget(Enum.DataStoreRequestType.GetAsync)
			budgetText(`Budget: {budget}`)
			task.wait(2)
		end
	end)

	-- Result row component
	local function ResultRow(item: () -> QueryResult?, absoluteIndex: () -> number): Frame
		local isHovered = source(false)
		local isSelected = derive(function(): boolean
			local idx = Store.querySelectedIndex()
			return idx == absoluteIndex()
		end)

		local targetBg = derive(function()
			local c = theme.colors()
			if isSelected() then
				return c.backgroundTertiary
			elseif isHovered() then
				return c.backgroundSecondary
			elseif absoluteIndex() % 2 == 0 then
				return c.backgroundSecondary
			end
			return c.background
		end)
		local bgColor = spring(targetBg, 0.1)

		return create "TextButton" {
			LayoutOrder = absoluteIndex,
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = bgColor,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ClipsDescendants = false,

			Activated = function()
				local idx = absoluteIndex()
				Store.selectQueryResult(idx)
			end,

			MouseEnter = function()
				isHovered(true)
			end,

			MouseLeave = function()
				isHovered(false)
			end,

			-- Key name (positioned absolutely to avoid layout clipping)
			create "TextLabel" {
				LayoutOrder = 1,
				Position = UDim2.new(0, 12, 0, 8),
				Size = UDim2.new(1, -24, 0, 18),
				BackgroundTransparency = 1,
				Text = function()
					local r = item()
					return if r then r.keyName else ""
				end,
				TextColor3 = function()
					local r = item()
					local c = theme.colors()
					if r and r.error then
						return c.error
					end
					if r and r.matched then
						return c.foreground
					end
					return c.foregroundMuted
				end,
				TextSize = theme.fontSize.normal,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = theme.fontMono,
				TextTruncate = Enum.TextTruncate.AtEnd,
			},

			-- Summary / error
			create "TextLabel" {
				LayoutOrder = 2,
				Position = UDim2.new(0, 12, 0, 28),
				Size = UDim2.new(1, -24, 0, 16),
				BackgroundTransparency = 1,
				Text = function()
					local r = item()
					if not r then return "" end
					if r.error then
						return r.error
					end
					return r.summary
				end,
				TextColor3 = function()
					local r = item()
					local c = theme.colors()
					if r and r.error then
						return c.error
					end
					if r and r.matched then
						return c.success
					end
					return c.foregroundMuted
				end,
				TextSize = theme.fontSize.small,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = theme.font,
				TextTruncate = Enum.TextTruncate.AtEnd,
			},

			-- Selected indicator bar
			create "Frame" {
				Size = UDim2.new(0, 3, 1, -8),
				Position = UDim2.new(0, -8, 0, 4),
				BackgroundColor3 = function()
					return theme.colors().accent
				end,
				BackgroundTransparency = function()
					return if isSelected() then 0 else 1
				end,
				BorderSizePixel = 0,

				create "UICorner" {
					CornerRadius = UDim.new(0, 2),
				},
			},
		}
	end

	-- Dropdown portal for search bar dropdown (if needed)
	local dropdownPortalFrame = create "Frame" {
		Name = "DropdownPortal",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
	}

	return create "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return theme.colors().background
		end,
		BorderSizePixel = 0,

		action(function(frame: Frame)
			viewWidth(frame.AbsoluteSize.X)
			frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				viewWidth(frame.AbsoluteSize.X)
			end)
		end),

		dropdownPortalFrame,

		-- Content with vertical layout
		create "Frame" {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			create "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
			},

			-- ═══════════════════════════════════════════
			-- Header
			-- ═══════════════════════════════════════════
			create "Frame" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 56),
				BackgroundColor3 = function()
					return theme.colors().backgroundSecondary
				end,
				BorderSizePixel = 0,

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
						Padding = UDim.new(0, 12),
					},

					-- Back button
					create "ImageButton" {
						LayoutOrder = 1,
						Size = UDim2.fromOffset(32, 32),
						BackgroundColor3 = function()
							return theme.colors().backgroundTertiary
						end,
						Image = "",

						Activated = function()
							if Store.queryIsRunning() then
								Store.cancelQuery()
							end
							Store.setView("browse")
						end,

						action(function(btn)
							Tooltip.addTooltip(btn, "Back to keys", "bottom")
						end),

						create "UICorner" {
							CornerRadius = UDim.new(0, 6),
						},

						create "ImageLabel" {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromOffset(18, 18),
							BackgroundTransparency = 1,
							Image = theme.icons.back,
							ImageColor3 = function()
								return theme.colors().foreground
							end,
						},
					},

					-- Title area
					create "Frame" {
						LayoutOrder = 2,
						Size = UDim2.new(0, 100, 1, 0),
						BackgroundTransparency = 1,

						create "UIFlexItem" {
							FlexMode = Enum.UIFlexMode.Fill,
						},

						create "UIListLayout" {
							SortOrder = Enum.SortOrder.LayoutOrder,
							VerticalAlignment = Enum.VerticalAlignment.Center,
						},

						create "TextLabel" {
							LayoutOrder = 1,
							Size = UDim2.new(1, 0, 0, 20),
							BackgroundTransparency = 1,
							Text = "Query",
							TextColor3 = function()
								return theme.colors().foreground
							end,
							TextSize = theme.fontSize.large,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.fontBold,
						},

						create "TextLabel" {
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 0, 14),
							BackgroundTransparency = 1,
							Text = function()
								local conn = Store.connection()
								if conn then
									return conn.name .. (if conn.scope then ` ({conn.scope})` else "")
								end
								return ""
							end,
							TextColor3 = function()
								return theme.colors().foregroundMuted
							end,
							TextSize = theme.fontSize.small,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.font,
							TextTruncate = Enum.TextTruncate.AtEnd,
						},
					},

					-- Budget indicator pill
					create "Frame" {
						LayoutOrder = 3,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, 24),
						BackgroundColor3 = function()
							return theme.colors().backgroundTertiary
						end,
						BorderSizePixel = 0,

						create "UICorner" {
							CornerRadius = UDim.new(0, 6),
						},

						create "UIPadding" {
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						},

						create "TextLabel" {
							Size = UDim2.new(0, 0, 1, 0),
							AutomaticSize = Enum.AutomaticSize.X,
							BackgroundTransparency = 1,
							Text = budgetText,
							TextColor3 = function()
								return theme.colors().foregroundSecondary
							end,
							TextSize = theme.fontSize.small,
							FontFace = theme.fontMono,
						},
					},
				},
			},

			-- ═══════════════════════════════════════════
			-- Input Section
			-- ═══════════════════════════════════════════
			create "Frame" {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = function()
					return theme.colors().backgroundSecondary
				end,
				BorderSizePixel = 0,

				create "UIPadding" {
					PaddingLeft = UDim.new(0, 12),
					PaddingRight = UDim.new(0, 12),
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 12),
				},

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 6),
				},

				-- Expression label row with help button
				create "Frame" {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,

					create "TextLabel" {
						Size = UDim2.new(1, -24, 1, 0),
						BackgroundTransparency = 1,
						Text = "Expression",
						TextColor3 = function()
							return theme.colors().foreground
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.fontMedium,
					},

					-- Help button
					(function()
						local helpHovered = source(false)
						local btn = create "TextButton" {
							AnchorPoint = Vector2.new(1, 0),
							Position = UDim2.fromScale(1, 0),
							Size = UDim2.fromOffset(22, 20),
							BackgroundColor3 = function()
								local c = theme.colors()
								return if helpHovered() then c.borderHover else c.backgroundTertiary
							end,
							BorderSizePixel = 0,
							Text = "?",
							TextColor3 = function()
								local c = theme.colors()
								return if helpHovered() then c.foreground else c.foregroundSecondary
							end,
							TextSize = theme.fontSize.normal,
							FontFace = theme.fontBold,
							AutoButtonColor = false,

							MouseEnter = function()
								helpHovered(true)
							end,
							MouseLeave = function()
								helpHovered(false)
							end,

							Activated = function()
								Store.openModal(function()
									return create "Frame" {
										Size = UDim2.new(1, 0, 0, 0),
										AutomaticSize = Enum.AutomaticSize.Y,
										BackgroundTransparency = 1,

										create "UIListLayout" {
											SortOrder = Enum.SortOrder.LayoutOrder,
											Padding = UDim.new(0, 8),
										},

										create "TextLabel" {
											LayoutOrder = 1,
											Size = UDim2.new(1, 0, 0, 28),
											BackgroundTransparency = 1,
											Text = "Query Expression Syntax",
											TextColor3 = function()
												return theme.colors().foreground
											end,
											TextSize = theme.fontSize.xl,
											TextXAlignment = Enum.TextXAlignment.Left,
											FontFace = theme.fontBold,
										},

										create "TextLabel" {
											LayoutOrder = 2,
											Size = UDim2.new(1, 0, 0, 0),
											AutomaticSize = Enum.AutomaticSize.Y,
											BackgroundTransparency = 1,
											RichText = true,
											Text = function()
												local h = function(expr: string): string
													return QueryEngine.highlight(expr, getSyntaxColors())
												end
												local c = theme.colors()
												local headColor = toHex(c.foreground)
												local mutedColor = toHex(c.foregroundMuted)
												local head = function(title: string): string
													return `<font color="{headColor}"><b>{title}</b></font>`
												end
												return table.concat({
													head("Comparisons"),
													h('data.level > 10') .. "    " .. h('data.name == "admin"'),
													h("data.coins >= 100") .. "    " .. h("data.banned ~= true"),
													"",
													head("Logical operators"),
													h("data.level > 10 and data.coins > 50"),
													h("data.vip == true or data.level > 100"),
													h("not data.banned"),
													"",
													head("Length operator"),
													h("#data.inventory.items > 5"),
													h("#data.friends == 0"),
													"",
													head("String methods"),
													h('data.name:find("test")'),
													h('data.name:lower() == "admin"'),
													h('data.tag:match("^VIP")'),
													h(":upper()") .. "  " .. h(":len()") .. "  " .. h(":sub(1, 5)"),
													"",
													head("Existence checks"),
													h("data.oldField == nil"),
													h("data.badges.vip ~= nil"),
													"",
													head("Nested access"),
													h("data.stats.combat.level > 50"),
													h("data.inventory.items[1]"),
													"",
													head("Built-in functions"),
													h('type(data.value) == "string"'),
													h("math.abs(data.x) < 100"),
													"",
													head("Version queries"),
													`<font color="{mutedColor}">(enable Versions toggle first)</font>`,
													h('changed_since("level", 1h)'),
													`<font color="{mutedColor}">  true if level changed in last hour</font>`,
													h('had_value("status", "active", 2h)'),
													`<font color="{mutedColor}">  true if status was "active" in last 2h</font>`,
													h("version_count() > 5"),
													h('version_diff("coins").kind == "changed"'),
												"",
													head("Time durations"),
													h("30m") .. "  " .. h("1h") .. "  " .. h("2h30m") .. "  " .. h("1d") .. "  " .. h("1d12h") .. "  " .. h("90s"),
												}, "\n")
											end,
											TextColor3 = function()
												return theme.colors().foreground
											end,
											TextSize = theme.fontSize.normal,
											TextXAlignment = Enum.TextXAlignment.Left,
											FontFace = theme.fontMono,
											TextWrapped = true,
										},

										-- Close button
										Button({
											text = "Close",
											onClick = function()
												Store.closeModal()
											end,
											variant = "secondary",
											size = "small",
										}),
									}
								end)
							end,

							create "UICorner" {
								CornerRadius = UDim.new(0, 4),
							},
						}
						Tooltip.addTooltip(btn, "Query syntax help", "bottom")
						return btn
					end)(),
				},

				-- Expression editor
				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 72),
					BackgroundColor3 = function()
						return theme.colors().background
					end,
					BorderSizePixel = 0,
					ClipsDescendants = true,

					create "UICorner" {
						CornerRadius = UDim.new(0, 6),
					},

					create "UIStroke" {
						Color = function()
							local err = expressionError()
							if err then
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
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.fromScale(0, 0),
						ScrollBarImageColor3 = function()
							return theme.colors().scrollbar
						end,
						BorderSizePixel = 0,

						create "UIPadding" {
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
							PaddingTop = UDim.new(0, 6),
							PaddingBottom = UDim.new(0, 6),
						},

						-- Syntax-highlighted display layer (behind the TextBox)
						create "TextLabel" {
							Name = "ExpressionHighlight",
							Size = UDim2.new(1, 0, 1, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							RichText = true,
							Text = function()
								local expr = Store.queryExpression()
								if expr == "" then
									return QueryEngine.highlight(
										'data.level > 10 and #data.items > 5',
										getMutedSyntaxColors()
									)
								end
								return QueryEngine.highlight(expr, getSyntaxColors())
							end,
							TextColor3 = function()
								return theme.colors().foreground
							end,
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
							BackgroundColor3 = function()
								return theme.colors().accent
							end,
							BackgroundTransparency = 0.7,
							Visible = selTopVisible,
							ZIndex = 0,
							BorderSizePixel = 0,
						},
						create "Frame" {
							Name = "SelectionMid",
							Position = selMidPos,
							Size = selMidSize,
							BackgroundColor3 = function()
								return theme.colors().accent
							end,
							BackgroundTransparency = 0.7,
							Visible = selMidVisible,
							ZIndex = 0,
							BorderSizePixel = 0,
						},
						create "Frame" {
							Name = "SelectionBot",
							Position = selBotPos,
							Size = selBotSize,
							BackgroundColor3 = function()
								return theme.colors().accent
							end,
							BackgroundTransparency = 0.7,
							Visible = selBotVisible,
							ZIndex = 0,
							BorderSizePixel = 0,
						},

						-- Invisible TextBox for input (on top, captures input and cursor)
						create "TextBox" {
							Name = "ExpressionInput",
							Size = UDim2.new(1, 0, 1, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							Text = Store.queryExpression,
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

							FocusLost = function(_enterPressed: boolean, inputObj: InputObject?)
								local text = Store.queryExpression()
								validateExpression(text)
								exprFocused(false)
								selTopVisible(false)
								selMidVisible(false)
								selBotVisible(false)
							end,

							action(function(tb: TextBox)
								local lh = exprLineHeight

								local function updateCursorAndSelection()
									local cursorPos = tb.CursorPosition
									local selStart = tb.SelectionStart
									local text = tb.Text
									local cw = monoCharWidth()
									local containerWidth = math.max(1, tb.AbsoluteSize.X)
									local charsPerLine = math.max(1, math.floor(containerWidth / cw))

									-- Update cursor position
									if cursorPos >= 1 then
										local cLine, cCol = charToVisual(text, cursorPos, charsPerLine)
										exprCursorX(math.floor(cCol * cw))
										exprCursorY(cLine * lh)
									end

									-- Update selection
									if selStart >= 1 and cursorPos >= 1 and selStart ~= cursorPos then
										local fromIdx = math.min(selStart, cursorPos)
										local toIdx = math.max(selStart, cursorPos)

										local startLine, startCol = charToVisual(text, fromIdx, charsPerLine)
										local endLine, endCol = charToVisual(text, toIdx, charsPerLine)

										if startLine == endLine then
											-- Single line selection
											selTopPos(UDim2.fromOffset(math.floor(startCol * cw), startLine * lh))
											selTopSize(UDim2.fromOffset(math.floor((endCol - startCol) * cw), lh))
											selTopVisible(true)
											selMidVisible(false)
											selBotVisible(false)
										else
											-- Multi-line: top partial line
											selTopPos(UDim2.fromOffset(math.floor(startCol * cw), startLine * lh))
											selTopSize(UDim2.fromOffset(math.floor(containerWidth - startCol * cw), lh))
											selTopVisible(true)

											-- Middle full lines (if gap > 1 line)
											local midLines = endLine - startLine - 1
											if midLines > 0 then
												selMidPos(UDim2.fromOffset(0, (startLine + 1) * lh))
												selMidSize(UDim2.fromOffset(math.floor(containerWidth), midLines * lh))
												selMidVisible(true)
											else
												selMidVisible(false)
											end

											-- Bottom partial line
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
									cursorBlink(true)
									updateCursorAndSelection()
								end)

								tb:GetPropertyChangedSignal("SelectionStart"):Connect(function()
									cursorBlink(true)
									updateCursorAndSelection()
								end)

								tb:GetPropertyChangedSignal("Text"):Connect(function()
									Store.queryExpression(tb.Text)
									updateCursorAndSelection()
								end)

								tb.Focused:Connect(function()
									exprFocused(true)
									cursorBlink(true)
									task.defer(updateCursorAndSelection)
								end)
							end),
						},

						-- Custom cursor (blinking caret)
						create "Frame" {
							Name = "Cursor",
							Position = function()
								return UDim2.fromOffset(exprCursorX(), exprCursorY())
							end,
							Size = UDim2.fromOffset(1, exprLineHeight),
							BackgroundColor3 = function()
								return theme.colors().foreground
							end,
							Visible = function()
								return exprFocused() and cursorBlink()
							end,
							ZIndex = 3,
							BorderSizePixel = 0,
						},
					},
				},

				-- Expression error
				show(function()
					return expressionError() ~= nil
				end, function()
					return create "TextLabel" {
						LayoutOrder = 3,
						Size = UDim2.new(1, 0, 0, 14),
						BackgroundTransparency = 1,
						Text = function()
							return expressionError() or ""
						end,
						TextColor3 = function()
							return theme.colors().error
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.font,
					}
				end),

				-- Keys label
				create "TextLabel" {
					LayoutOrder = 5,
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					Text = "Keys (one per line or comma-separated)",
					TextColor3 = function()
						return theme.colors().foreground
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMedium,
				},

				-- Key list input
				create "Frame" {
					LayoutOrder = 6,
					Size = UDim2.new(1, 0, 0, 56),
					BackgroundColor3 = function()
						return theme.colors().background
					end,
					BorderSizePixel = 0,
					ClipsDescendants = true,

					create "UICorner" {
						CornerRadius = UDim.new(0, 6),
					},

					create "UIStroke" {
						Color = function()
							return theme.colors().border
						end,
						Thickness = 1,
					},

					create "ScrollingFrame" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						ScrollBarThickness = 4,
						ScrollingDirection = Enum.ScrollingDirection.Y,
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.fromScale(0, 0),
						ScrollBarImageColor3 = function()
							return theme.colors().scrollbar
						end,
						BorderSizePixel = 0,

						create "UIPadding" {
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
							PaddingTop = UDim.new(0, 6),
							PaddingBottom = UDim.new(0, 6),
						},

						create "TextBox" {
							Name = "KeyListInput",
							Size = UDim2.new(1, 0, 1, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							Text = Store.queryKeyListText,
							PlaceholderText = "Player_1234\nPlayer_5678\nPlayer_9012",
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
							ClearTextOnFocus = false,
							MultiLine = true,
							TextWrapped = true,

							action(function(tb: TextBox)
								tb:GetPropertyChangedSignal("Text"):Connect(function()
									Store.queryKeyListText(tb.Text)
								end)
							end),
						},
					},
				},

				-- Controls row
				create "Frame" {
					LayoutOrder = 7,
					Size = UDim2.new(1, 0, 0, 32),
					BackgroundTransparency = 1,

					create "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
					},

					-- Version mode toggle
					Button({
						text = function()
							return if Store.queryVersionMode() then "Versions: ON" else "Versions"
						end,
						onClick = function()
							Store.queryVersionMode(not Store.queryVersionMode())
						end,
						variant = function()
							return if Store.queryVersionMode() then "primary" else "secondary"
						end :: any,
						size = "small",
						tooltip = "Enable version history queries (changed_since, had_value)",
					}),

					-- Version time window (visible when version mode on)
					show(function()
						return Store.queryVersionMode()
					end, function()
						return create "Frame" {
							Size = UDim2.fromOffset(140, 28),
							BackgroundTransparency = 1,

							create "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 4),
							},

							create "TextLabel" {
								Size = UDim2.fromOffset(55, 28),
								BackgroundTransparency = 1,
								Text = "Window:",
								TextColor3 = function()
									return theme.colors().foregroundMuted
								end,
								TextSize = theme.fontSize.small,
								FontFace = theme.font,
							},

							create "Frame" {
								Size = UDim2.fromOffset(75, 24),
								BackgroundColor3 = function()
									return theme.colors().background
								end,
								BorderSizePixel = 0,

								create "UICorner" {
									CornerRadius = UDim.new(0, 4),
								},

								create "UIStroke" {
									Color = function()
										return theme.colors().border
									end,
									Thickness = 1,
								},

								create "TextBox" {
									Size = UDim2.fromScale(1, 1),
									BackgroundTransparency = 1,
									PlaceholderText = "1h",
									Text = function()
										return formatDuration(Store.queryVersionSeconds())
									end,
									PlaceholderColor3 = function()
										return theme.colors().foregroundMuted
									end,
									TextColor3 = function()
										return theme.colors().foreground
									end,
									TextSize = theme.fontSize.small,
									FontFace = theme.fontMono,
									ClearTextOnFocus = true,

									action(function(tb: TextBox)
										tb.FocusLost:Connect(function()
											local seconds = parseDuration(tb.Text)
											if seconds and seconds > 0 then
												Store.queryVersionSeconds(seconds)
											end
											-- Reset display to formatted value
											tb.Text = formatDuration(Store.queryVersionSeconds())
										end)
									end),
								},
							},
						}
					end),

					-- Spacer
					create "Frame" {
						Size = UDim2.new(0, 0, 1, 0),
						BackgroundTransparency = 1,

						create "UIFlexItem" {
							FlexMode = Enum.UIFlexMode.Fill,
						},
					},

					-- Result summary
					create "TextLabel" {
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.new(0, 0, 0, 20),
						BackgroundTransparency = 1,
						Text = resultSummary,
						TextColor3 = function()
							return theme.colors().foregroundSecondary
						end,
						TextSize = theme.fontSize.small,
						FontFace = theme.font,
					},

					-- Run / Cancel button
					Button({
						text = function()
							if Store.queryIsRunning() then
								return `Cancel ({Store.queryProgress()}/{Store.queryTotal()})`
							end
							return "Run Query"
						end,
						onClick = function()
							if Store.queryIsRunning() then
								Store.cancelQuery()
							else
								Store.startQuery()
							end
						end,
						variant = function()
							return if Store.queryIsRunning() then "danger" else "primary"
						end :: any,
						size = "small",
					}),
				},

				-- Query error display
				show(function()
					return Store.queryError() ~= nil
				end, function()
					return create "TextLabel" {
						LayoutOrder = 8,
						Size = UDim2.new(1, 0, 0, 16),
						BackgroundTransparency = 1,
						Text = function()
							return Store.queryError() or ""
						end,
						TextColor3 = function()
							return theme.colors().error
						end,
						TextSize = theme.fontSize.small,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.fontMedium,
					}
				end),
			},

			-- ═══════════════════════════════════════════
			-- Progress Bar
			-- ═══════════════════════════════════════════
			create "Frame" {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = function()
					return theme.colors().border
				end,
				BorderSizePixel = 0,
				Visible = Store.queryIsRunning,

				create "Frame" {
					Size = function()
						return UDim2.new(progressPercent(), 0, 1, 0)
					end,
					BackgroundColor3 = function()
						return theme.colors().accent
					end,
					BorderSizePixel = 0,
				},
			},

			-- ═══════════════════════════════════════════
			-- Results Section (split pane)
			-- ═══════════════════════════════════════════
			create "Frame" {
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,

				create "UIFlexItem" {
					FlexMode = Enum.UIFlexMode.Fill,
				},

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
				},

				-- Left pane: Results list
				create "Frame" {
					LayoutOrder = 1,
					Size = function()
						-- If narrow or no detail selected, take full width
						local hasSelection = Store.querySelectedIndex() > 0 and Store.querySelectedResult() ~= nil
						if isNarrow() or not hasSelection then
							return UDim2.fromScale(1, 1)
						end
						return UDim2.new(0.4, 0, 1, 0)
					end,
					BackgroundTransparency = 1,
					ClipsDescendants = true,

					-- Empty state
					show(function()
						return #allResults() == 0
					end, function()
						return create "Frame" {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,

							create "TextLabel" {
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.4),
								Size = UDim2.new(0.8, 0, 0, 40),
								BackgroundTransparency = 1,
								Text = "Enter keys and an expression, then click Run Query",
								TextColor3 = function()
									return theme.colors().foregroundMuted
								end,
								TextSize = theme.fontSize.normal,
								FontFace = theme.font,
								TextWrapped = true,
							},
						}
					end),

					-- Results list
					show(function()
						return #allResults() > 0
					end, function()
						return create "Frame" {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,

							VirtualizedList({
								items = allResults,
								itemHeight = 52,
								renderItem = ResultRow,
							}),
						}
					end),
				},

				-- Divider
				show(function()
					local hasSelection = Store.querySelectedIndex() > 0 and Store.querySelectedResult() ~= nil
					return hasSelection and not isNarrow()
				end, function()
					return create "Frame" {
						LayoutOrder = 2,
						Size = UDim2.new(0, 1, 1, 0),
						BackgroundColor3 = function()
							return theme.colors().border
						end,
						BorderSizePixel = 0,
					}
				end),

				-- Right pane: Detail panel
				show(function()
					local hasSelection = Store.querySelectedIndex() > 0 and Store.querySelectedResult() ~= nil
					return hasSelection and not isNarrow()
				end, function()
					return create "Frame" {
						LayoutOrder = 3,
						Size = UDim2.new(0.6, -1, 1, 0),
						BackgroundTransparency = 1,

						create "UIListLayout" {
							SortOrder = Enum.SortOrder.LayoutOrder,
						},

						-- Detail header
						create "Frame" {
							LayoutOrder = 1,
							Size = UDim2.new(1, 0, 0, 36),
							BackgroundColor3 = function()
								return theme.colors().backgroundSecondary
							end,
							BorderSizePixel = 0,

							create "UIPadding" {
								PaddingLeft = UDim.new(0, 12),
								PaddingRight = UDim.new(0, 8),
							},

							create "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 8),
							},

							create "TextLabel" {
								Size = UDim2.new(0, 0, 1, 0),
								AutomaticSize = Enum.AutomaticSize.X,
								BackgroundTransparency = 1,
								Text = function()
									local result = Store.querySelectedResult()
									return if result then result.keyName else ""
								end,
								TextColor3 = function()
									return theme.colors().foreground
								end,
								TextSize = theme.fontSize.normal,
								FontFace = theme.fontMonoMedium,
								TextTruncate = Enum.TextTruncate.AtEnd,
							},

							create "TextLabel" {
								Size = UDim2.new(0, 0, 1, 0),
								AutomaticSize = Enum.AutomaticSize.X,
								BackgroundTransparency = 1,
								Text = function()
									local result = Store.querySelectedResult()
									return if result then result.summary else ""
								end,
								TextColor3 = function()
									local result = Store.querySelectedResult()
									local c = theme.colors()
									if result and result.matched then
										return c.success
									end
									return c.foregroundMuted
								end,
								TextSize = theme.fontSize.small,
								FontFace = theme.font,
							},

							-- Spacer
							create "Frame" {
								Size = UDim2.new(0, 0, 1, 0),
								BackgroundTransparency = 1,

								create "UIFlexItem" {
									FlexMode = Enum.UIFlexMode.Fill,
								},
							},

							-- Open full view button
							Button({
								text = "Open",
								onClick = function()
									local result = Store.querySelectedResult()
									if result and result.keyData then
										Store.setCurrentKey(result.keyName, result.keyData, nil)
										Store.isReadOnly(false)
										Store.setView("editKey")
									end
								end,
								variant = "ghost",
								size = "small",
								tooltip = "Open in full editor (back returns to query)",
							}),
						},

						-- TreeView
						create "Frame" {
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 1, -36),
							BackgroundTransparency = 1,
							ClipsDescendants = true,

							show(function()
								return detailData() ~= nil
							end, function()
								return TreeView({
									data = detailData :: () -> Types.JSONValue,
									readOnly = function()
										return true
									end,
									searchResults = detailPaths,
									currentSearchResult = function()
										local paths = detailPaths()
										if #paths > 0 then
											return paths[1]
										end
										return nil
									end,
									expandRef = expandRef,
									useAlternatingColors = function()
										return Store.settings().useAlternatingKeyColors
									end,
								})
							end),
						},
					}
				end),
			},
		},
	}
end

return QueryView
