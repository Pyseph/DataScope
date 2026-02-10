--!strict
--[[
	Data Statistics Component
	Shows key count, size, and metadata for data
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Tooltip = require(script.Parent.Tooltip)

local create = Vide.create
local derive = Vide.derive
local action = Vide.action

export type DataStatsProps = {
	data: () -> any,
	keyInfo: () -> {
		CreatedTime: number?,
		UpdatedTime: number?,
		Version: string?,
	}?,
	rawSize: (() -> number?)?, -- Raw size before hook decompression (optional)
}

-- Calculate data statistics
local function calculateStats(data: any): { keyCount: number, size: number, depth: number, types: { [string]: number } }
	local stats = {
		keyCount = 0,
		size = 0,
		depth = 0,
		types = {} :: { [string]: number },
	}
	
	local function countType(typeName: string)
		stats.types[typeName] = (stats.types[typeName] or 0) + 1
	end
	
	local function traverse(value: any, currentDepth: number)
		stats.depth = math.max(stats.depth, currentDepth)
		
		local valueType = type(value)
		
		if valueType == "table" then
			-- Check if array or object
			local isArray = #value > 0 or next(value) == nil
			local hasStringKeys = false
			for k in value do
				if type(k) == "string" then
					hasStringKeys = true
					break
				end
			end
			
			if hasStringKeys then
				countType("object")
			else
				countType("array")
			end
			
			for k, v in value do
				stats.keyCount = stats.keyCount + 1
				-- Estimate string size for key
				if type(k) == "string" then
					stats.size = stats.size + #k
				end
				traverse(v, currentDepth + 1)
			end
		elseif valueType == "string" then
			countType("string")
			stats.size = stats.size + #value
		elseif valueType == "number" then
			countType("number")
			stats.size = stats.size + 8 -- Approximate number size
		elseif valueType == "boolean" then
			countType("boolean")
			stats.size = stats.size + 1
		elseif value == nil then
			countType("null")
			stats.size = stats.size + 4
		else
			countType("other")
		end
	end
	
	traverse(data, 0)
	return stats
end

-- Format file size
local function formatSize(bytes: number): string
	if bytes < 1024 then
		return `{bytes} B`
	elseif bytes < 1024 * 1024 then
		return string.format("%.1f KB", bytes / 1024)
	else
		return string.format("%.2f MB", bytes / (1024 * 1024))
	end
end

-- Format relative time
local function formatRelativeTime(timestamp: number): string
	local now = os.time() * 1000 -- Convert to milliseconds
	local diff = now - timestamp
	
	local seconds = diff / 1000
	local minutes = seconds / 60
	local hours = minutes / 60
	local days = hours / 24
	
	if seconds < 60 then
		return "just now"
	elseif minutes < 60 then
		local m = math.floor(minutes)
		return `{m} minute{m > 1 and "s" or ""} ago`
	elseif hours < 24 then
		local h = math.floor(hours)
		return `{h} hour{h > 1 and "s" or ""} ago`
	elseif days < 30 then
		local d = math.floor(days)
		return `{d} day{d > 1 and "s" or ""} ago`
	else
		local date = os.date("*t", math.floor(timestamp / 1000))
		return `{date.month}/{date.day}/{date.year}`
	end
end

-- DataStore key size limit: 4 MB
local MAX_KEY_SIZE = 4 * 1024 * 1024 -- 4 MB in bytes

local function DataStats(props: DataStatsProps): Frame
	local theme = Theme.get()
	
	local stats = derive(function()
		local data = props.data()
		if data == nil then
			return nil
		end
		return calculateStats(data)
	end)
	
	-- Calculate budget usage percentage
	local budgetPercent = derive(function(): number
		local size = 0
		-- Use raw size if provided (actual DataStore size)
		if props.rawSize then
			local raw = props.rawSize()
			if raw then
				size = raw
			end
		end
		-- Fallback to calculated size
		if size == 0 then
			local s = stats()
			if s then
				size = s.size
			end
		end
		return math.clamp((size / MAX_KEY_SIZE) * 100, 0, 100)
	end)
	
	-- Get color based on percentage (green -> yellow -> orange -> red)
	local function getBudgetColor(percent: number): Color3
		if percent < 50 then
			return theme.colors().success
		elseif percent < 75 then
			return theme.colors().warning
		elseif percent < 90 then
			return Color3.fromRGB(255, 140, 0) -- Orange
		else
			return theme.colors().error
		end
	end
	
	local StatItem = function(icon: string, label: string, value: () -> string): Frame
		return create "Frame" {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			
			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
			},
			
			create "ImageLabel" {
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				Image = icon,
				ImageColor3 = function()
					return theme.colors().foregroundMuted
				end,
			},
			
			create "TextLabel" {
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = label,
				TextColor3 = function()
					return theme.colors().foregroundMuted
				end,
				TextSize = theme.fontSize.xs,
				FontFace = theme.font,
			},
			
			create "TextLabel" {
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = value,
				TextColor3 = function()
					return theme.colors().foregroundSecondary
				end,
				TextSize = theme.fontSize.xs,
				FontFace = theme.fontMedium,
			},
		}
	end
	
	return create "Frame" {
		Name = "DataStats",
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = function()
			return theme.colors().backgroundTertiary
		end,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		
		create "UIPadding" {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		},
		
		create "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 20),
		},
		
		-- Key count
		StatItem(theme.icons.key, "Keys:", function()
			local s = stats()
			return if s then tostring(s.keyCount) else "0"
		end),
		
		-- Size estimate (prefer raw size if available)
		StatItem(theme.icons.database, "Size:", function()
			-- Use raw size if provided (actual DataStore size before decompression)
			if props.rawSize then
				local raw = props.rawSize()
				if raw then
					return formatSize(raw)
				end
			end
			-- Fallback to calculated size from decompressed data
			local s = stats()
			return if s then formatSize(s.size) else "0 B"
		end),
		
		-- Depth
		StatItem(theme.icons.folder, "Depth:", function()
			local s = stats()
			return if s then tostring(s.depth) else "0"
		end),
		
		-- Last modified
		StatItem(theme.icons.clock, "Modified:", function()
			local info = props.keyInfo()
			if info and info.UpdatedTime then
				return formatRelativeTime(info.UpdatedTime)
			end
			return "N/A"
		end),
		
		-- Budget usage bar
		create "Frame" {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			
			action(function(f)
				Tooltip.addTooltip(f, function()
					local size = 0
					if props.rawSize then
						local raw = props.rawSize()
						if raw then size = raw end
					else
						local s = stats()
						if s then size = s.size end
					end
					return `Data Size: {formatSize(size)} / 4.00 MB`
				end, "top")
			end),
			
			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
			},
			
			-- Label
			create "TextLabel" {
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = "Budget:",
				TextColor3 = function()
					return theme.colors().foregroundMuted
				end,
				TextSize = theme.fontSize.xs,
				FontFace = theme.font,
			},
			
			-- Progress bar container
			create "Frame" {
				Size = UDim2.fromOffset(60, 8),
				BackgroundColor3 = function()
					return theme.colors().backgroundSecondary
				end,
				BorderSizePixel = 0,
				
				create "UICorner" {
					CornerRadius = UDim.new(0, 4),
				},
				
				-- Progress fill
				create "Frame" {
					Size = function()
						return UDim2.new(budgetPercent() / 100, 0, 1, 0)
					end,
					BackgroundColor3 = function()
						return getBudgetColor(budgetPercent())
					end,
					BorderSizePixel = 0,
					
					create "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},
				},
			},
			
			-- Percentage text
			create "TextLabel" {
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = function()
					return string.format("%.1f%%", budgetPercent())
				end,
				TextColor3 = function()
					return getBudgetColor(budgetPercent())
				end,
				TextSize = theme.fontSize.xs,
				FontFace = theme.fontMedium,
			},
		},
	}
end

-- Compact version for toolbar
local function DataStatsCompact(props: DataStatsProps): Frame
	local theme = Theme.get()
	
	local stats = derive(function()
		local data = props.data()
		if data == nil then
			return nil
		end
		return calculateStats(data)
	end)
	
	return create "Frame" {
		Name = "DataStatsCompact",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundColor3 = function()
			return theme.colors().backgroundTertiary
		end,
		BorderSizePixel = 0,
		
		create "UICorner" {
			CornerRadius = UDim.new(0, theme.radius.sm),
		},
		
		create "UIPadding" {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		},
		
		create "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		},
		
		create "TextLabel" {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Text = function()
				local s = stats()
				if s then
					return `{s.keyCount} keys`
				end
				return "0 keys"
			end,
			TextColor3 = function()
				return theme.colors().foregroundMuted
			end,
			TextSize = theme.fontSize.xs,
			FontFace = theme.fontMono,
		},
		
		create "Frame" {
			Size = UDim2.fromOffset(1, 12),
			BackgroundColor3 = function()
				return theme.colors().border
			end,
			BorderSizePixel = 0,
		},
		
		create "TextLabel" {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Text = function()
				local s = stats()
				if s then
					return formatSize(s.size)
				end
				return "0 B"
			end,
			TextColor3 = function()
				return theme.colors().foregroundMuted
			end,
			TextSize = theme.fontSize.xs,
			FontFace = theme.fontMono,
		},
	}
end

return {
	DataStats = DataStats,
	DataStatsCompact = DataStatsCompact,
	calculateStats = calculateStats,
	formatSize = formatSize,
	formatRelativeTime = formatRelativeTime,
}
