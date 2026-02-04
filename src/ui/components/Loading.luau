--!strict
--[[
	Loading Components
	Animated loading spinners and skeleton placeholders
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local spring = Vide.spring
local effect = Vide.effect

-- Animated spinning loader
export type SpinnerProps = {
	size: number?,
	thickness: number?,
	color: Color3 | (() -> Color3)?,
}

local function Spinner(props: SpinnerProps): Frame
	local theme = Theme.get()
	local size = props.size or 24
	local thickness = props.thickness or 3
	
	local rotation = source(0)
	
	-- Continuous rotation animation
	effect(function()
		local connection: RBXScriptConnection
		local startTime = os.clock()
		
		connection = game:GetService("RunService").Heartbeat:Connect(function()
			local elapsed = os.clock() - startTime
			rotation(elapsed * 360) -- One full rotation per second
		end)
		
		return function()
			connection:Disconnect()
		end
	end)
	
	local getColor = if type(props.color) == "function" then props.color else function()
		return (props.color :: Color3?) or theme.colors().accent
	end
	
	return create "Frame" {
		Name = "Spinner",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		
		create "ImageLabel" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://100564892200095", -- Circular loading icon
			ImageColor3 = getColor,
			Rotation = rotation,
		},
	}
end

-- Skeleton loading placeholder with shimmer effect
export type SkeletonProps = {
	width: UDim?,
	height: UDim?,
	radius: number?,
	style: ("rectangle" | "circle" | "text")?,
}

local function Skeleton(props: SkeletonProps): Frame
	local theme = Theme.get()
	local style = props.style or "rectangle"
	local radius = props.radius or (if style == "circle" then 9999 else theme.radius.sm)
	
	local shimmerOffset = source(0)
	
	-- Shimmer animation
	effect(function()
		local connection: RBXScriptConnection
		local startTime = os.clock()
		
		connection = game:GetService("RunService").Heartbeat:Connect(function()
			local elapsed = os.clock() - startTime
			-- Loop every 1.5 seconds, -1 to 2 range
			shimmerOffset((elapsed % 1.5) / 1.5 * 3 - 1)
		end)
		
		return function()
			connection:Disconnect()
		end
	end)
	
	local width = props.width or UDim.new(1, 0)
	local height = props.height or UDim.new(0, 20)
	
	return create "Frame" {
		Name = "Skeleton",
		Size = UDim2.new(width, height),
		BackgroundColor3 = function()
			return theme.colors().backgroundTertiary
		end,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		
		create "UICorner" {
			CornerRadius = UDim.new(0, radius),
		},
		
		-- Shimmer gradient overlay
		create "Frame" {
			Name = "Shimmer",
			Size = UDim2.new(0.5, 0, 1, 0),
			Position = function()
				return UDim2.fromScale(shimmerOffset(), 0)
			end,
			BackgroundTransparency = 1,
			
			create "UIGradient" {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
				}),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.85),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 15,
			},
			
			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = function()
					return theme.colors().backgroundSecondary
				end,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
			},
		},
	}
end

-- Skeleton group for list items
export type SkeletonListProps = {
	count: number?,
	itemHeight: number?,
	gap: number?,
	showIcon: boolean?,
}

local function SkeletonList(props: SkeletonListProps): Frame
	local theme = Theme.get()
	local count = props.count or 5
	local itemHeight = props.itemHeight or 48
	local gap = props.gap or 8
	local showIcon = props.showIcon ~= false
	
	local children: { Instance } = {
		create "UIListLayout" {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap),
		},
	}
	
	for i = 1, count do
		table.insert(children, create "Frame" {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, itemHeight),
			BackgroundTransparency = 1,
			
			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
			},
			
			if showIcon then Skeleton({
				width = UDim.new(0, 32),
				height = UDim.new(0, 32),
				style = "circle",
			}) else nil,
			
			create "Frame" {
				Size = UDim2.new(1, if showIcon then -44 else 0, 1, 0),
				BackgroundTransparency = 1,
				
				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
				},
				
				Skeleton({
					width = UDim.new(0.6, 0),
					height = UDim.new(0, 14),
				}),
				
				Skeleton({
					width = UDim.new(0.4, 0),
					height = UDim.new(0, 10),
				}),
			},
		})
	end
	
	return create "Frame" {
		Name = "SkeletonList",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		children,
	}
end

-- Loading overlay for containers
export type LoadingOverlayProps = {
	visible: () -> boolean,
	text: string?,
}

local function LoadingOverlay(props: LoadingOverlayProps): Frame
	local theme = Theme.get()
	
	local opacity = spring(function()
		return if props.visible() then 1 else 0
	end, 0.2)
	
	return create "Frame" {
		Name = "LoadingOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return theme.colors().background
		end,
		BackgroundTransparency = function()
			return 1 - (opacity() * 0.8)
		end,
		Visible = function()
			return opacity() > 0.01
		end,
		ZIndex = 100,
		
		create "Frame" {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(120, 80),
			BackgroundTransparency = 1,
			
			create "UIListLayout" {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
			},
			
			Spinner({ size = 32 }),
			
			if props.text then create "TextLabel" {
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = props.text,
				TextColor3 = function()
					return theme.colors().foregroundSecondary
				end,
				TextTransparency = function()
					return 1 - opacity()
				end,
				TextSize = theme.fontSize.normal,
				FontFace = theme.font,
			} else nil,
		},
	}
end

return {
	Spinner = Spinner,
	Skeleton = Skeleton,
	SkeletonList = SkeletonList,
	LoadingOverlay = LoadingOverlay,
}
