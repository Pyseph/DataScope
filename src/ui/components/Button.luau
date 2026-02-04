--!strict
--[[
	Button Component
	Reusable button with variants, ripple effects, and focus states
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Tooltip = require(script.Parent.Tooltip)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local spring = Vide.spring
local effect = Vide.effect

export type ButtonVariant = "primary" | "secondary" | "danger" | "ghost"
export type ButtonSize = "small" | "medium" | "large"

export type ButtonProps = {
	text: string | () -> string,
	onClick: () -> (),
	variant: ButtonVariant?,
	size: ButtonSize?,
	disabled: (() -> boolean) | boolean?,
	icon: string?,
	fullWidth: boolean?,
	tooltip: string?,
}

-- Ripple effect manager
local function createRipple(parent: GuiObject, position: Vector2, color: Color3)
	local ripple = Instance.new("Frame")
	ripple.Name = "Ripple"
	ripple.AnchorPoint = Vector2.new(0.5, 0.5)
	ripple.Position = UDim2.fromOffset(position.X, position.Y)
	ripple.Size = UDim2.fromOffset(0, 0)
	ripple.BackgroundColor3 = color
	ripple.BackgroundTransparency = 0.7
	ripple.BorderSizePixel = 0
	ripple.ZIndex = 0
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ripple
	
	ripple.Parent = parent
	
	-- Calculate max size for ripple (diagonal of button)
	local maxSize = math.sqrt(parent.AbsoluteSize.X ^ 2 + parent.AbsoluteSize.Y ^ 2) * 2
	
	-- Animate ripple expansion
	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = game:GetService("TweenService"):Create(ripple, tweenInfo, {
		Size = UDim2.fromOffset(maxSize, maxSize),
		BackgroundTransparency = 1,
	})
	
	tween:Play()
	tween.Completed:Connect(function()
		ripple:Destroy()
	end)
end

local function Button(props: ButtonProps): TextButton
	local theme = Theme.get()
	local isHovered = source(false)
	local isPressed = source(false)
	local buttonRef = source(nil :: TextButton?)

	local variant = props.variant or "primary"
	local size = props.size or "medium"

	local disabled = if type(props.disabled) == "function" then props.disabled else function()
		return props.disabled == true
	end

	-- Target colors based on state
	local targetColors = derive(function()
		local c = theme.colors()
		local isDisabledVal = disabled()

		if isDisabledVal then
			return {
				background = c.backgroundTertiary,
				text = c.foregroundMuted,
				border = c.border,
				transparency = 0,
				ripple = c.foregroundMuted,
			}
		end

		local isPressedVal = isPressed()
		local isHoveredVal = isHovered()

		if variant == "primary" then
			local bg = c.accent
			if isPressedVal then
				bg = c.accentPressed
			elseif isHoveredVal then
				bg = c.accentHover
			end
			return {
				background = bg,
				text = Color3.new(1, 1, 1),
				border = bg,
				transparency = 0,
				ripple = Color3.new(1, 1, 1),
			}
		elseif variant == "secondary" then
			local bg = c.backgroundSecondary
			if isPressedVal then
				bg = c.backgroundTertiary
			elseif isHoveredVal then
				bg = c.backgroundTertiary
			end
			return {
				background = bg,
				text = c.foreground,
				border = c.border,
				transparency = 0,
				ripple = c.accent,
			}
		elseif variant == "danger" then
			local bg = c.error
			if isPressedVal then
				bg = Theme.darken(c.error, 0.2)
			elseif isHoveredVal then
				bg = Theme.lighten(c.error, 0.1)
			end
			return {
				background = bg,
				text = Color3.new(1, 1, 1),
				border = bg,
				transparency = 0,
				ripple = Color3.new(1, 1, 1),
			}
		else -- ghost
			local bg = c.background
			local transparency = 1
			if isPressedVal then
				bg = c.backgroundTertiary
				transparency = 0
			elseif isHoveredVal then
				bg = c.backgroundSecondary
				transparency = 0
			end
			return {
				background = bg,
				text = c.foreground,
				border = c.border,
				transparency = transparency,
				ripple = c.accent,
			}
		end
	end)

	-- Spring animations
	local bgColor = spring(function() return targetColors().background end, 0.15)
	local textColor = spring(function() return targetColors().text end, 0.15)
	local borderColor = spring(function() return targetColors().border end, 0.15)
	local bgTransparency = spring(function() return targetColors().transparency end, 0.15)
	
	local scale = spring(function()
		return if isPressed() then 0.96 else 1
	end, 0.1)

	local sizing = {
		small = { height = 28, paddingX = 10, fontSize = theme.fontSize.small, iconSize = 14 },
		medium = { height = 36, paddingX = 16, fontSize = theme.fontSize.normal, iconSize = 16 },
		large = { height = 44, paddingX = 24, fontSize = theme.fontSize.large, iconSize = 18 },
	}

	local sizeConfig = sizing[size]

	local button = create "TextButton" {
		Size = if props.fullWidth
			then UDim2.new(1, 0, 0, sizeConfig.height)
			else UDim2.new(0, 0, 0, sizeConfig.height),
		AutomaticSize = if props.fullWidth then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		BackgroundColor3 = bgColor,
		BackgroundTransparency = bgTransparency,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ClipsDescendants = true,

		Activated = function()
			if not disabled() then
				props.onClick()
			end
		end,

		MouseEnter = function()
			if not disabled() then
				isHovered(true)
			end
		end,

		MouseLeave = function()
			isHovered(false)
			isPressed(false)
		end,

		MouseButton1Down = function(rbx: TextButton, x: number, y: number)
			if not disabled() then
				isPressed(true)
				-- Trigger ripple effect
				local btn = buttonRef()
				if btn and x and y then
					local absPos = btn.AbsolutePosition
					if absPos then
						local relativeX = x - absPos.X
						local relativeY = y - absPos.Y
						createRipple(btn, Vector2.new(relativeX, relativeY), targetColors().ripple)
					end
				end
			end
		end,

		MouseButton1Up = function()
			isPressed(false)
		end,

		create "UICorner" {
			CornerRadius = UDim.new(0, theme.radius.md),
		},

		-- Main border
		create "UIStroke" {
			Color = borderColor,
			Thickness = 1,
			Transparency = function()
				return if variant == "ghost" and bgTransparency() > 0.5 then 1 else 0
			end,
		},
		
		create "UIScale" {
			Scale = scale,
		},

		create "UIPadding" {
			PaddingLeft = UDim.new(0, sizeConfig.paddingX),
			PaddingRight = UDim.new(0, sizeConfig.paddingX),
		},

		-- Content container
		create "Frame" {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,

			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
			},

			if props.icon
				then create "ImageLabel" {
					Size = UDim2.fromOffset(sizeConfig.iconSize, sizeConfig.iconSize),
					BackgroundTransparency = 1,
					Image = props.icon,
					ImageColor3 = textColor,
				}
				else nil,

			create "TextLabel" {
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text = props.text,
				TextColor3 = textColor,
				TextSize = sizeConfig.fontSize,
				FontFace = theme.fontMedium,
			},
		},
	}
	
	-- Store button reference for ripple positioning
	buttonRef(button)
	
	-- Add tooltip if specified
	if props.tooltip then
		Tooltip.addTooltip(button, props.tooltip, "bottom")
	end
	
	return button
end

return Button
