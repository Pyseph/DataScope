--!strict
--[[
	DataStorePicker Component
	Text input with autocomplete suggestions powered by ListDataStoresAsync.
	Shows each DataStore's "Last active" time and respects the StandardList
	request budget so we never make a call that would throttle the plugin.
]]

local DataStoreService = game:GetService("DataStoreService")

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Operations = require(script.Parent.Parent.Parent.datastore.Operations)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local spring = Vide.spring
local indexes = Vide.indexes

type DataStoreListItem = Operations.DataStoreListItem

export type DataStorePickerProps = {
	value: () -> string,
	onChange: (value: string) -> (),
	onSubmit: ((value: string) -> ())?,
	placeholder: string?,
	label: (string | () -> string)?,
	validate: ((value: string) -> (boolean, string?))?,
	disabled: (() -> boolean)?,
}

local DEBOUNCE_SECONDS = 0.4
local CACHE_TTL_SECONDS = 30
local MIN_BUDGET_THRESHOLD = 1

-- Union of every DataStoreInfo we've ever seen this session, keyed by name.
-- Filtered case-insensitively on every keystroke so cached hits show instantly.
local allKnownStores: { [string]: DataStoreListItem } = {}
-- Prefix (lowercased) -> os.time() of last fetch, used to skip redundant API calls.
local prefixLastFetched: { [string]: number } = {}

local function computeMatches(query: string): { DataStoreListItem }
	local lower = string.lower(query)
	local results: { DataStoreListItem } = {}
	for _, item in allKnownStores do
		if lower == "" or string.find(string.lower(item.name), lower, 1, true) ~= nil then
			table.insert(results, item)
		end
	end
	table.sort(results, function(a, b)
		return (a.updatedTime or 0) > (b.updatedTime or 0)
	end)
	return results
end

local function formatRelativeTime(epochSeconds: number): string
	local now = os.time()
	local delta = now - epochSeconds
	if delta < 0 then
		return "just now"
	end
	if delta < 60 then
		return `{delta}s ago`
	end
	if delta < 3600 then
		return `{math.floor(delta / 60)}m ago`
	end
	if delta < 86400 then
		return `{math.floor(delta / 3600)}h ago`
	end
	if delta < 86400 * 30 then
		return `{math.floor(delta / 86400)}d ago`
	end
	if delta < 86400 * 365 then
		return `{math.floor(delta / (86400 * 30))}mo ago`
	end
	return `{math.floor(delta / (86400 * 365))}y ago`
end

-- ListDataStoresAsync returns DataStoreInfo.UpdatedTime in milliseconds
local function msToSeconds(ms: number?): number?
	if ms == nil then
		return nil
	end
	return math.floor(ms / 1000)
end

local function DataStorePicker(props: DataStorePickerProps): Frame
	local theme = Theme.get()

	local isFocused = source(false)
	local isHovered = source(false)
	local validationError = source(nil :: string?)
	local suggestions = source({} :: { DataStoreListItem })
	local isLoading = source(false)
	local fetchError = source(nil :: string?)
	local budgetHint = source(nil :: string?)
	local highlightedIndex = source(0)

	local disabled = props.disabled or function()
		return false
	end

	local textBoxRef: TextBox? = nil

	-- Ticks up every time we schedule a fetch so stale callbacks can bail out
	local fetchToken = 0

	local function runFetch(prefix: string)
		fetchToken += 1
		local myToken = fetchToken
		local cacheKey = string.lower(prefix)

		-- Skip the call entirely if we already fetched this prefix recently.
		local last = prefixLastFetched[cacheKey]
		if last and (os.time() - last) < CACHE_TTL_SECONDS then
			isLoading(false)
			fetchError(nil)
			budgetHint(nil)
			return
		end

		-- Budget gate — never call unless we have at least 1 StandardList request.
		-- Keep the current (possibly cached) suggestions visible either way.
		local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardList)
		if budget < MIN_BUDGET_THRESHOLD then
			isLoading(false)
			budgetHint("Listing budget exhausted — try again shortly")
			return
		end

		budgetHint(nil)
		isLoading(true)

		task.spawn(function()
			local result = Operations.listDataStores(prefix)
			if myToken ~= fetchToken then
				return -- Superseded by a newer fetch
			end

			isLoading(false)
			if result.success then
				for _, item in result.value.datastores do
					allKnownStores[item.name] = item
				end
				prefixLastFetched[cacheKey] = os.time()
				fetchError(nil)
				-- Re-filter against the input as it stands *now*, not the prefix we fetched.
				suggestions(computeMatches(props.value()))
			else
				fetchError(result.error)
			end
		end)
	end

	local function scheduleFetch(prefix: string)
		fetchToken += 1
		local myToken = fetchToken
		task.delay(DEBOUNCE_SECONDS, function()
			if myToken ~= fetchToken then
				return
			end
			runFetch(prefix)
		end)
	end

	local handleChange = function(text: string)
		if props.validate then
			local valid, err = props.validate(text)
			validationError(if valid then nil else err)
		end
		props.onChange(text)
		highlightedIndex(0)
		-- Instant local filter so cached hits appear with zero latency.
		suggestions(computeMatches(text))
		-- Kick off a background fetch to learn about stores we haven't seen yet.
		scheduleFetch(text)
	end

	local selectSuggestion = function(item: DataStoreListItem)
		if props.validate then
			local valid, err = props.validate(item.name)
			validationError(if valid then nil else err)
		end
		props.onChange(item.name)
		if textBoxRef then
			textBoxRef.Text = item.name
		end
		isFocused(false)
		if textBoxRef then
			textBoxRef:ReleaseFocus()
		end
	end

	local targetBorderColor = derive(function()
		local c = theme.colors()
		if validationError() then
			return c.error
		end
		if disabled() then
			return c.border
		end
		if isFocused() then
			return c.accent
		end
		if isHovered() then
			return c.borderHover
		end
		return c.border
	end)

	local borderColor = spring(targetBorderColor, 0.15)

	local dropdownVisible = derive(function()
		if not isFocused() then
			return false
		end
		return #suggestions() > 0 or isLoading() or fetchError() ~= nil or budgetHint() ~= nil
	end)

	local SuggestionItem = function(item: () -> DataStoreListItem, index: number): TextButton
		local itemHovered = source(false)

		local isCurrent = derive(function()
			return item().name == props.value() or highlightedIndex() == index
		end)

		local targetBackground = derive(function()
			local c = theme.colors()
			if isCurrent() then
				return c.accent
			end
			if itemHovered() then
				return c.backgroundTertiary
			end
			return c.backgroundSecondary
		end)

		local background = spring(targetBackground, 0.1)

		return create "TextButton" {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = background,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,

			Activated = function()
				selectSuggestion(item())
			end,

			MouseEnter = function()
				itemHovered(true)
				highlightedIndex(index)
			end,

			MouseLeave = function()
				itemHovered(false)
			end,

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
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					Padding = UDim.new(0, 8),
				},

				create "ImageLabel" {
					LayoutOrder = 1,
					Size = UDim2.fromOffset(14, 14),
					BackgroundTransparency = 1,
					Image = theme.icons.database,
					ImageColor3 = function()
						local c = theme.colors()
						if isCurrent() then
							return Color3.new(1, 1, 1)
						end
						return c.foregroundMuted
					end,
				},

				create "TextLabel" {
					LayoutOrder = 2,
					Size = UDim2.new(1, -150, 1, 0),
					BackgroundTransparency = 1,
					Text = function()
						return item().name
					end,
					TextColor3 = function()
						local c = theme.colors()
						if isCurrent() then
							return Color3.new(1, 1, 1)
						end
						return c.foreground
					end,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					FontFace = theme.fontMedium,
				},

				create "TextLabel" {
					LayoutOrder = 3,
					Size = UDim2.new(0, 130, 1, 0),
					BackgroundTransparency = 1,
					Text = function()
						local updated = msToSeconds(item().updatedTime)
						if updated then
							return `Last active {formatRelativeTime(updated)}`
						end
						return ""
					end,
					TextColor3 = function()
						local c = theme.colors()
						if isCurrent() then
							return Color3.fromRGB(220, 220, 220)
						end
						return c.foregroundMuted
					end,
					TextSize = theme.fontSize.small,
					TextXAlignment = Enum.TextXAlignment.Right,
					FontFace = theme.font,
				},
			},
		}
	end

	return create "Frame" {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = false,

		create "UIListLayout" {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		},

		-- Label
		if props.label
			then create "TextLabel" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = props.label,
				TextColor3 = function()
					return theme.colors().foreground
				end,
				TextSize = theme.fontSize.normal,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = theme.fontMedium,
			}
			else nil,

		-- Input container
		create "Frame" {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = function()
				local c = theme.colors()
				if disabled() then
					return c.backgroundTertiary
				end
				return c.backgroundSecondary
			end,
			BorderSizePixel = 0,
			ClipsDescendants = false,

			MouseEnter = function()
				if not disabled() then
					isHovered(true)
				end
			end,

			MouseLeave = function()
				isHovered(false)
			end,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.md),
			},

			create "UIStroke" {
				Color = borderColor,
				Thickness = 1,
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
					Padding = UDim.new(0, 8),
				},

				create "TextBox" {
					LayoutOrder = 1,
					Size = UDim2.new(1, -28, 1, 0),
					BackgroundTransparency = 1,
					Text = props.value,
					PlaceholderText = props.placeholder or "",
					TextColor3 = function()
						return theme.colors().foreground
					end,
					PlaceholderColor3 = function()
						return theme.colors().foregroundMuted
					end,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = theme.fontMono,
					TextEditable = function()
						return not disabled()
					end,
					ClearTextOnFocus = false,

					Vide.action(function(instance: TextBox)
						textBoxRef = instance
					end),

					Focused = function()
						isFocused(true)
						-- Show cached matches instantly; refresh in the background.
						suggestions(computeMatches(props.value()))
						scheduleFetch(props.value())
					end,

					FocusLost = function(enterPressed: boolean)
						-- Defer so a click on a suggestion can fire before we hide the dropdown
						task.delay(0.15, function()
							isFocused(false)
						end)
						if textBoxRef then
							local currentText = textBoxRef.Text
							handleChange(currentText)
							if enterPressed and props.onSubmit then
								props.onSubmit(currentText)
							end
						end
					end,

					Changed = function(property: string)
						if property == "Text" and textBoxRef then
							handleChange(textBoxRef.Text)
						end
					end,
				},

				-- Loading / status indicator
				create "ImageLabel" {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1,
					Image = function()
						if budgetHint() then
							return theme.icons.warning
						end
						if isLoading() then
							return theme.icons.loading
						end
						return theme.icons.chevronDown
					end,
					ImageColor3 = function()
						local c = theme.colors()
						if budgetHint() then
							return c.warning
						end
						return c.foregroundMuted
					end,
					Rotation = spring(function()
						return if isLoading() then 180 else 0
					end, 0.3),
				},
			},
		},

		-- Dropdown
		create "Frame" {
			LayoutOrder = 3,
			Size = UDim2.new(1, -4, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = function()
				return theme.colors().backgroundSecondary
			end,
			BorderSizePixel = 0,
			Visible = dropdownVisible,
			ZIndex = 50,
			Active = true,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.md),
			},

			create "UIStroke" {
				Color = function()
					return theme.colors().border
				end,
				Thickness = 1,
			},

			create "UIPadding" {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
			},

			-- Status rows (budget / error)
			create "TextLabel" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundTransparency = 1,
				Text = function()
					return budgetHint() or fetchError() or ""
				end,
				TextColor3 = function()
					local c = theme.colors()
					if budgetHint() then
						return c.warning
					end
					return c.error
				end,
				TextSize = theme.fontSize.small,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = theme.font,
				Visible = function()
					return budgetHint() ~= nil or fetchError() ~= nil
				end,

				create "UIPadding" {
					PaddingLeft = UDim.new(0, 12),
					PaddingRight = UDim.new(0, 12),
				},
			},

			-- Suggestion list
			create "ScrollingFrame" {
				LayoutOrder = 2,
				Size = function()
					local count = #suggestions()
					local height = math.min(count * 40, 240)
					return UDim2.new(1, 0, 0, height)
				end,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				ScrollBarImageColor3 = function()
					return theme.colors().scrollbar
				end,
				ZIndex = 50,
				Visible = function()
					return #suggestions() > 0
				end,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
				},

				create "UIPadding" {
					PaddingRight = UDim.new(0, 4),
				},

				indexes(suggestions, SuggestionItem),
			},

			-- Empty state (when focused and no results + not loading/error/budget)
			create "TextLabel" {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundTransparency = 1,
				Text = "No matching DataStores",
				TextColor3 = function()
					return theme.colors().foregroundMuted
				end,
				TextSize = theme.fontSize.small,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = theme.font,
				Visible = function()
					return #suggestions() == 0
						and not isLoading()
						and fetchError() == nil
						and budgetHint() == nil
				end,

				create "UIPadding" {
					PaddingLeft = UDim.new(0, 12),
					PaddingRight = UDim.new(0, 12),
				},
			},
		},

		-- Validation error
		create "TextLabel" {
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = function()
				return validationError() or ""
			end,
			TextColor3 = function()
				return theme.colors().error
			end,
			TextSize = theme.fontSize.small,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = theme.font,
			Visible = function()
				return validationError() ~= nil
			end,
		},
	}
end

return DataStorePicker
