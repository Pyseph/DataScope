--!strict
--[[
	Toast Component
	Notification toasts with polished slide-in animations
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Parent.Parent.core.Types)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local indexes = Vide.indexes
local spring = Vide.spring
local effect = Vide.effect

type Toast = Types.Toast
type ToastType = Types.ToastType

export type ToastContainerProps = {
	toasts: () -> { Toast },
	onDismiss: (id: string) -> (),
}

local function ToastItem(toast: Toast, onDismiss: (id: string) -> (), index: number): Frame
	local theme = Theme.get()
	local isHovered = source(false)
	local isVisible = source(false)
	local progress = source(1) -- Progress bar for auto-dismiss
	
	-- Stagger the entry animation based on index
	effect(function()
		task.delay(index * 0.05, function()
			isVisible(true)
		end)
	end)
	
	-- Auto-dismiss progress (if duration is set)
	effect(function()
		if toast.duration and toast.duration > 0 then
			local startTime = os.clock()
			local duration = toast.duration / 1000 -- Convert to seconds
			
			local connection: RBXScriptConnection
			connection = game:GetService("RunService").Heartbeat:Connect(function()
				if isHovered() then
					-- Pause progress when hovered
					startTime = os.clock() - (1 - progress()) * duration
					return
				end
				
				local elapsed = os.clock() - startTime
				local remaining = 1 - (elapsed / duration)
				
				if remaining <= 0 then
					progress(0)
					connection:Disconnect()
					isVisible(false)
					task.delay(0.3, function()
						onDismiss(toast.id)
					end)
				else
					progress(remaining)
				end
			end)
			
			return function()
				connection:Disconnect()
			end
		end
		return nil
	end)

	local colors = derive(function()
		local c = theme.colors()
		local toastType = toast.type

		if toastType == "success" then
			return { bg = c.success, icon = theme.icons.success }
		elseif toastType == "error" then
			return { bg = c.error, icon = theme.icons.error }
		elseif toastType == "warning" then
			return { bg = c.warning, icon = theme.icons.warning }
		else
			return { bg = c.info, icon = theme.icons.info }
		end
	end)
	
	-- Smooth spring animations
	local opacity = spring(function()
		return if isVisible() then 1 else 0
	end, 0.25)
	
	local slideX = spring(function()
		return if isVisible() then 0 else 100
	end, 0.3)
	
	local scaleY = spring(function()
		return if isVisible() then 1 else 0.8
	end, 0.25)
	
	-- Hover lift effect
	local hoverLift = spring(function()
		return if isHovered() then -2 else 0
	end, 0.15)
	
	local shadowTransparency = spring(function()
		return if isHovered() then 0.7 else 0.9
	end, 0.15)

	return create "Frame" {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Position = function()
			return UDim2.new(0, slideX(), 0, hoverLift())
		end,
		
		create "UIScale" {
			Scale = function()
				return scaleY()
			end,
		},
		
		-- Shadow layer
		create "Frame" {
			Size = UDim2.new(1, 4, 1, 4),
			Position = UDim2.fromOffset(-2, 2),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = shadowTransparency,
			ZIndex = 0,
			
			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.md + 2),
			},
		},
		
		-- Main toast body
		create "Frame" {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = function()
				return theme.colors().backgroundSecondary
			end,
			BackgroundTransparency = function()
				return 1 - opacity()
			end,
			BorderSizePixel = 0,
			ZIndex = 1,
			ClipsDescendants = true,

			MouseEnter = function()
				isHovered(true)
			end,

			MouseLeave = function()
				isHovered(false)
			end,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.md),
			},

			create "UIStroke" {
				Color = function()
					return theme.colors().border
				end,
				Thickness = 1,
				Transparency = function()
					return 1 - opacity()
				end,
			},

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
			},

			create "Frame" {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					Padding = UDim.new(0, 12),
				},

				-- Color indicator with pulse animation
				create "Frame" {
					Size = UDim2.fromOffset(4, 20),
					BackgroundColor3 = function()
						return colors().bg
					end,
					BackgroundTransparency = function()
						return 1 - opacity()
					end,
					BorderSizePixel = 0,

					create "UICorner" {
						CornerRadius = UDim.new(0, 2),
					},
				},

				-- Icon with subtle bounce
				create "ImageLabel" {
					Size = UDim2.fromOffset(20, 20),
					BackgroundTransparency = 1,
					Image = function()
						return colors().icon
					end,
					ImageColor3 = function()
						return colors().bg
					end,
					ImageTransparency = function()
						return 1 - opacity()
					end,
				},

				-- Message
				create "TextLabel" {
					Size = UDim2.new(1, -80, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Text = toast.message,
					TextColor3 = function()
						return theme.colors().foreground
					end,
					TextTransparency = function()
						return 1 - opacity()
					end,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					FontFace = theme.font,
				},

				-- Close button
				create "ImageButton" {
					Size = UDim2.fromOffset(20, 20),
					BackgroundTransparency = 1,
					Image = theme.icons.close,
					ImageColor3 = function()
						local c = theme.colors()
						if isHovered() then
							return c.foreground
						end
						return c.foregroundMuted
					end,
					ImageTransparency = function()
						return 1 - opacity()
					end,

					Activated = function()
						isVisible(false)
						task.delay(0.3, function()
							onDismiss(toast.id)
						end)
					end,
				},
			},
			
			-- Progress bar (for auto-dismiss)
			if toast.duration and toast.duration > 0 then create "Frame" {
				Name = "ProgressBar",
				Size = function()
					return UDim2.new(progress(), 0, 0, 3)
				end,
				Position = UDim2.new(0, 0, 1, -3),
				BackgroundColor3 = function()
					return colors().bg
				end,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
			} else nil,
		},
	}
end

local function ToastContainer(props: ToastContainerProps): Frame
	return create "Frame" {
		Name = "ToastContainer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(360, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2000,

		create "UIListLayout" {
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 12),
		},

		indexes(props.toasts, function(toast, index)
			local item = ToastItem(toast(), props.onDismiss, index)
			item.LayoutOrder = index
			return item
		end),
	}
end

return {
	ToastContainer = ToastContainer,
	ToastItem = ToastItem,
}
