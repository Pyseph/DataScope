--!strict
--[[
	Breadcrumbs Component
	Path navigation for nested data structures
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local spring = Vide.spring
local indexes = Vide.indexes

export type BreadcrumbsProps = {
	path: () -> { string | number },
	onNavigate: (path: { string | number }) -> (),
	rootLabel: string?,
}

local function Breadcrumbs(props: BreadcrumbsProps): Frame
	local theme = Theme.get()
	local rootLabel = props.rootLabel or "root"
	
	-- Build crumb items from path
	local crumbs = derive(function(): { { label: string, path: { string | number } } }
		local currentPath = props.path()
		local items: { { label: string, path: { string | number } } } = {}
		
		-- Root crumb
		table.insert(items, {
			label = rootLabel,
			path = {},
		})
		
		-- Build path crumbs
		local accumulatedPath: { string | number } = {}
		for _, segment in currentPath do
			table.insert(accumulatedPath, segment)
			table.insert(items, {
				label = tostring(segment),
				path = table.clone(accumulatedPath),
			})
		end
		
		return items
	end)
	
	local BreadcrumbItem = function(crumb: () -> { label: string, path: { string | number } }, index: number, isLast: () -> boolean): Frame
		local isHovered = source(false)
		
		local textColor = derive(function()
			local c = theme.colors()
			if isLast() then
				return c.foreground
			elseif isHovered() then
				return c.accent
			else
				return c.foregroundMuted
			end
		end)
		
		return create "Frame" {
			LayoutOrder = index,
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			
			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
			},
			
			-- Separator (except for first item)
			if index > 1 then create "ImageLabel" {
				LayoutOrder = 1,
				Size = UDim2.fromOffset(12, 12),
				BackgroundTransparency = 1,
				Image = theme.icons.chevronRight,
				ImageColor3 = function()
					return theme.colors().foregroundMuted
				end,
				ImageTransparency = 0.5,
			} else nil,
			
			-- Crumb button
			create "TextButton" {
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				
				MouseEnter = function()
					isHovered(true)
				end,
				
				MouseLeave = function()
					isHovered(false)
				end,
				
				Activated = function()
					if not isLast() then
						props.onNavigate(crumb().path)
					end
				end,
				
				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 4),
				},
				
				-- Folder icon for root
				if index == 1 then create "ImageLabel" {
					LayoutOrder = 1,
					Size = UDim2.fromOffset(14, 14),
					BackgroundTransparency = 1,
					Image = theme.icons.folder,
					ImageColor3 = textColor,
				} else nil,
				
				-- Label
				create "TextLabel" {
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,
					Text = function()
						local c = crumb()
						local label = c.label
						-- Truncate long labels
						if #label > 20 then
							return string.sub(label, 1, 17) .. "..."
						end
						return label
					end,
					TextColor3 = textColor,
					TextSize = theme.fontSize.small,
					FontFace = function()
						return if isLast() then theme.fontMedium else theme.font
					end,
				},
			},
		}
	end
	
	return create "Frame" {
		Name = "Breadcrumbs",
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 24),
		BackgroundColor3 = function()
			return theme.colors().backgroundTertiary
		end,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		
		create "UICorner" {
			CornerRadius = UDim.new(0, theme.radius.sm),
		},
		
		create "UIPadding" {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		},
		
		create "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 0),
		},
		
		indexes(crumbs, function(crumb, index)
			local isLast = derive(function()
				return index == #crumbs()
			end)
			return BreadcrumbItem(crumb, index, isLast)
		end),
	}
end

-- Compact version that only shows the last few segments
local function BreadcrumbsCompact(props: BreadcrumbsProps): Frame
	local theme = Theme.get()
	
	local displayPath = derive(function(): string
		local path = props.path()
		local root = props.rootLabel or "root"
		if #path == 0 then
			return root
		end
		
		-- Show root + last 2 segments with ellipsis if needed
		local segments: { string } = { root }
		local startIdx = math.max(1, #path - 1)
		
		if startIdx > 1 then
			table.insert(segments, "...")
		end
		
		for i = startIdx, #path do
			local segment = tostring(path[i])
			if #segment > 15 then
				segment = string.sub(segment, 1, 12) .. "..."
			end
			table.insert(segments, segment)
		end
		
		return table.concat(segments, " / ")
	end)
	
	return create "Frame" {
		Name = "BreadcrumbsCompact",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 1,
		
		create "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		},
		
		create "ImageLabel" {
			Size = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1,
			Image = theme.icons.folder,
			ImageColor3 = function()
				return theme.colors().foregroundMuted
			end,
		},
		
		create "TextLabel" {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Text = displayPath,
			TextColor3 = function()
				return theme.colors().foregroundMuted
			end,
			TextSize = theme.fontSize.small,
			FontFace = theme.fontMono,
		},
	}
end

return {
	Breadcrumbs = Breadcrumbs,
	BreadcrumbsCompact = BreadcrumbsCompact,
}
