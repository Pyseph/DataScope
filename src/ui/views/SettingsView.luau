--!strict
--[[
	Settings View
	Application settings using Vide
]]

local Vide = require(script.Parent.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Store = require(script.Parent.Parent.Parent.core.Store)

local Button = require(script.Parent.Parent.components.Button)
local Select = require(script.Parent.Parent.components.Select)
local TextInput = require(script.Parent.Parent.components.TextInput)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local indexes = Vide.indexes

local function SettingsView(): Frame
	local theme = Theme.get()
	local newTemplateLabel = source("")
	local newTemplateValue = source("Player_{userid}")

	-- Theme preset options
	local themeOptions = {
		{ value = "Studio", label = "Studio", description = "Matches Roblox Studio theme" },
		{ value = "Dark", label = "Dark", description = "Pure dark theme" },
		{ value = "Light", label = "Light", description = "Light theme" },
	}

	-- Accent color options
	local accentOptions = {
		{ value = "blue", label = "Blue" },
		{ value = "purple", label = "Purple" },
		{ value = "green", label = "Green" },
		{ value = "red", label = "Red" },
		{ value = "orange", label = "Orange" },
		{ value = "pink", label = "Pink" },
		{ value = "cyan", label = "Cyan" },
		{ value = "yellow", label = "Yellow" },
	}

	-- Highlight mode options
	local highlightOptions = {
		{ value = "Default", label = "Default", description = "DataScope colors" },
		{ value = "ScriptEditor", label = "Script Editor", description = "Match Studio script editor" },
	}

	-- View mode options
	local viewModeOptions = {
		{ value = "Tree", label = "Tree View", description = "Hierarchical tree structure" },
		{ value = "Code", label = "Code View", description = "JSON code editor" },
	}

	local keyTemplates = derive(function(): { any }
		return Store.settings().keyTemplates
	end)

	local addTemplate = function()
		local success, errorMessage = Store.addKeyTemplate(newTemplateLabel(), newTemplateValue())
		if success then
			newTemplateLabel("")
			newTemplateValue("Player_{userid}")
			Store.showToast("success", "Key template saved")
		else
			Store.showToast("warning", errorMessage or "Unable to save key template")
		end
	end

	-- Toggle setting component
	local ToggleSetting = function(props: {
		label: string,
		description: string?,
		value: () -> boolean,
		onChange: (boolean) -> (),
	}): Frame
		local isHovered = source(false)

		return create "Frame" {
			Size = UDim2.new(1, 0, 0, if props.description then 52 else 36),
			BackgroundColor3 = function()
				local c = theme.colors()
				if isHovered() then
					return c.backgroundSecondary
				end
				return c.background
			end,
			BackgroundTransparency = function()
				return if isHovered() then 0 else 1
			end,
			BorderSizePixel = 0,

			MouseEnter = function()
				isHovered(true)
			end,

			MouseLeave = function()
				isHovered(false)
			end,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.md),
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
				},

				-- Label and description
				create "Frame" {
					Size = UDim2.new(1, -60, 1, 0),
					BackgroundTransparency = 1,

					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					},

					create "TextLabel" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 18),
						BackgroundTransparency = 1,
						Text = props.label,
						TextColor3 = function()
							return theme.colors().foreground
						end,
						TextSize = theme.fontSize.normal,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.font,
					},

					if props.description
						then create "TextLabel" {
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 0, 16),
							BackgroundTransparency = 1,
							Text = props.description,
							TextColor3 = function()
								return theme.colors().foregroundMuted
							end,
							TextSize = theme.fontSize.small,
							TextXAlignment = Enum.TextXAlignment.Left,
							FontFace = theme.font,
						}
						else nil,
				},

				-- Toggle switch
				create "TextButton" {
					Size = UDim2.fromOffset(44, 24),
					BackgroundColor3 = function()
						local c = theme.colors()
						if props.value() then
							return c.accent
						end
						return c.backgroundTertiary
					end,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,

					Activated = function()
						props.onChange(not props.value())
					end,

					create "UICorner" {
						CornerRadius = UDim.new(0.5, 0),
					},

					-- Toggle knob
					create "Frame" {
						AnchorPoint = Vector2.new(0, 0.5),
						Position = function()
							if props.value() then
								return UDim2.new(1, -22, 0.5, 0)
							end
							return UDim2.new(0, 2, 0.5, 0)
						end,
						Size = UDim2.fromOffset(20, 20),
						BackgroundColor3 = Color3.new(1, 1, 1),
						BorderSizePixel = 0,

						create "UICorner" {
							CornerRadius = UDim.new(0.5, 0),
						},
					},
				},
			},
		}
	end

	local KeyTemplateRow = function(template: () -> any, index: number): Frame
		local isSelected = derive(function()
			local current = template()
			return current ~= nil and Store.getSelectedKeyTemplateId() == current.id
		end)

		return create "Frame" {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 138),
			BackgroundColor3 = function()
				local c = theme.colors()
				return if isSelected() then c.backgroundTertiary else c.backgroundSecondary
			end,
			BorderSizePixel = 0,
			ClipsDescendants = true,

			create "UICorner" {
				CornerRadius = UDim.new(0, theme.radius.md),
			},

			create "UIPadding" {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
			},

			create "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			},

			create "Frame" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 68),
				BackgroundTransparency = 1,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				},

				create "Frame" {
					LayoutOrder = 1,
					Size = UDim2.new(0.35, -4, 1, 0),
					BackgroundTransparency = 1,

					TextInput({
						value = function()
							local current = template()
							return if current then current.label else ""
						end,
						onChange = function(value)
							local current = template()
							if not current then
								return
							end

							local success, errorMessage = Store.updateKeyTemplate(current.id, value, current.template)
							if not success then
								Store.showToast("warning", errorMessage or "Unable to update key template")
							end
						end,
						label = "Name",
						placeholder = "Player",
					}),
				},

				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(0.65, -4, 1, 0),
					BackgroundTransparency = 1,

					TextInput({
						value = function()
							local current = template()
							return if current then current.template else ""
						end,
						onChange = function(value)
							local current = template()
							if not current then
								return
							end

							local success, errorMessage = Store.updateKeyTemplate(current.id, current.label, value)
							if not success then
								Store.showToast("warning", errorMessage or "Unable to update key template")
							end
						end,
						label = "Template",
						placeholder = "Player_{userid}",
						validate = function(value)
							local current = template()
							if not current then
								return true, nil
							end
							return Store.validateKeyTemplate(current.label, value)
						end,
					}),
				},
			},

			create "Frame" {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundTransparency = 1,
				ClipsDescendants = true,

				create "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				},

				create "Frame" {
					LayoutOrder = 1,
					Size = UDim2.new(1, -216, 1, 0),
					BackgroundTransparency = 1,

					create "UIFlexItem" {
						FlexMode = Enum.UIFlexMode.Fill,
					},
				},

				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(112, 32),
					BackgroundTransparency = 1,

					Button({
						text = function()
							return if isSelected() then "Selected" else "Use"
						end,
						onClick = function()
							local current = template()
							if current then
								local success, errorMessage = Store.selectKeyTemplateForCurrentStore(current.id)
								if not success then
									Store.showToast("warning", errorMessage or "Unable to select key template")
								end
							end
						end,
						variant = if isSelected() then "primary" else "secondary",
						size = "small",
						fullWidth = true,
					}),
				},

				create "Frame" {
					LayoutOrder = 3,
					Size = UDim2.fromOffset(96, 32),
					BackgroundTransparency = 1,

					Button({
						text = "Delete",
						onClick = function()
							local current = template()
							if current then
								local success, errorMessage = Store.removeKeyTemplate(current.id)
								if not success then
									Store.showToast("warning", errorMessage or "Unable to delete key template")
								end
							end
						end,
						variant = "danger",
						size = "small",
						fullWidth = true,
						disabled = function()
							return #Store.settings().keyTemplates <= 1
						end,
					}),
				},
			},
		}
	end

	-- Section header component
	local SectionHeader = function(title: string): TextLabel
		return create "TextLabel" {
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundTransparency = 1,
			Text = title,
			TextColor3 = function()
				return theme.colors().foregroundSecondary
			end,
			TextSize = theme.fontSize.small,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = theme.font,
		}
	end

	return create "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return theme.colors().background
		end,
		BorderSizePixel = 0,

		create "UIListLayout" {
			SortOrder = Enum.SortOrder.LayoutOrder,
		},

		-- Header
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
						Store.setView("browse")
					end,

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

				-- Title (fills available space)
				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(0, 100, 1, 0),
					BackgroundTransparency = 1,
					
					create "UIFlexItem" {
						FlexMode = Enum.UIFlexMode.Fill,
					},
					
					create "TextLabel" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "Settings",
						TextColor3 = function()
							return theme.colors().foreground
						end,
						TextSize = theme.fontSize.xl,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = theme.font,
					},
				},

				-- Reset button
				Button({
					text = "Reset",
					onClick = Store.resetSettings,
					variant = "ghost",
					size = "small",
				}),
			},
		},

		-- Settings content
		create "ScrollingFrame" {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 1, -56),
			BackgroundTransparency = 1,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = function()
				return theme.colors().scrollbar
			end,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BorderSizePixel = 0,

			create "UIPadding" {
				PaddingLeft = UDim.new(0.02, 16),
				PaddingRight = UDim.new(0.04, 24),
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
			},

			create "Frame" {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				},

				-- Appearance section
				create "Frame" {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					SectionHeader("APPEARANCE"),
				},

				-- Theme preset
				create "Frame" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					Select({
						value = function()
							return Store.settings().themePreset
						end,
						options = themeOptions,
						onChange = function(value)
							Store.updateSetting("themePreset", value)
							theme.setPreset(value)
						end,
						label = "Theme",
					}),
				},

				-- Accent color
				create "Frame" {
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					Select({
						value = function()
							return Store.settings().themeAccent
						end,
						options = accentOptions,
						onChange = function(value)
							Store.updateSetting("themeAccent", value)
							theme.setAccent(value)
						end,
						label = "Accent Color",
					}),
				},

				-- Alternating key colors
				create "Frame" {
					LayoutOrder = 4,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					ToggleSetting({
						label = "Alternating Key Colors",
						description = "Use alternating background colors for tree rows",
						value = function()
							return Store.settings().useAlternatingKeyColors
						end,
						onChange = function(value)
							Store.updateSetting("useAlternatingKeyColors", value)
						end,
					}),
				},

				-- Editor section
				create "Frame" {
					LayoutOrder = 10,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					SectionHeader("EDITOR"),
				},

				-- Default view mode
				create "Frame" {
					LayoutOrder = 11,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					Select({
						value = function()
							return Store.settings().viewerMode
						end,
						options = viewModeOptions,
						onChange = function(value)
							Store.updateSetting("viewerMode", value)
						end,
						label = "Default View Mode",
					}),
				},

				-- Highlight colors
				create "Frame" {
					LayoutOrder = 12,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					Select({
						value = function()
							return Store.settings().highlightColors
						end,
						options = highlightOptions,
						onChange = function(value)
							Store.updateSetting("highlightColors", value)
						end,
						label = "Syntax Highlighting",
					}),
				},

				-- Click to open
				create "Frame" {
					LayoutOrder = 13,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					ToggleSetting({
						label = "Click to Open",
						description = "Single click to open keys instead of double click",
						value = function()
							return Store.settings().clickToOpen
						end,
						onChange = function(value)
							Store.updateSetting("clickToOpen", value)
						end,
					}),
				},

				-- Behavior section
				create "Frame" {
					LayoutOrder = 20,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					SectionHeader("BEHAVIOR"),
				},

				-- Auto list keys
				create "Frame" {
					LayoutOrder = 21,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					ToggleSetting({
						label = "Automatically List Keys",
						description = "Auto-load keys when connecting to a DataStore",
						value = function()
							return Store.settings().automaticallyList
						end,
						onChange = function(value)
							Store.updateSetting("automaticallyList", value)
						end,
					}),
				},

				-- List deleted keys
				create "Frame" {
					LayoutOrder = 22,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					ToggleSetting({
						label = "Show Deleted Keys",
						description = "Include deleted keys in version history",
						value = function()
							return Store.settings().listDeletedKeys
						end,
						onChange = function(value)
							Store.updateSetting("listDeletedKeys", value)
						end,
					}),
				},

				-- Hide game name
				create "Frame" {
					LayoutOrder = 23,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					ToggleSetting({
						label = "Hide Game Name",
						description = "Don't show game name in the header",
						value = function()
							return Store.settings().hideGameName
						end,
						onChange = function(value)
							Store.updateSetting("hideGameName", value)
						end,
					}),
				},

				-- Key templates section
				create "Frame" {
					LayoutOrder = 30,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					SectionHeader("KEY TEMPLATES"),
				},

				create "Frame" {
					LayoutOrder = 31,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					},

					indexes(keyTemplates, function(template, index)
						return KeyTemplateRow(template, index)
					end),
				},

				create "Frame" {
					LayoutOrder = 32,
					Size = UDim2.new(1, 0, 0, 138),
					BackgroundColor3 = function()
						return theme.colors().backgroundSecondary
					end,
					BorderSizePixel = 0,

					create "UICorner" {
						CornerRadius = UDim.new(0, theme.radius.md),
					},

					create "UIPadding" {
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
						PaddingTop = UDim.new(0, 10),
						PaddingBottom = UDim.new(0, 10),
					},

					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					},

					create "Frame" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 68),
						BackgroundTransparency = 1,

						create "UIListLayout" {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 8),
						},

						create "Frame" {
							LayoutOrder = 1,
							Size = UDim2.new(0.35, -4, 1, 0),
							BackgroundTransparency = 1,

							TextInput({
								value = newTemplateLabel,
								onChange = function(value)
									newTemplateLabel(value)
								end,
								onSubmit = function(value)
									newTemplateLabel(value)
									addTemplate()
								end,
								label = "Name",
								placeholder = "Player",
							}),
						},

						create "Frame" {
							LayoutOrder = 2,
							Size = UDim2.new(0.65, -4, 1, 0),
							BackgroundTransparency = 1,

							TextInput({
								value = newTemplateValue,
								onChange = function(value)
									newTemplateValue(value)
								end,
								onSubmit = function(value)
									newTemplateValue(value)
									addTemplate()
								end,
								label = "Template",
								placeholder = "Player_{userid}",
								validate = function(value)
									return Store.validateKeyTemplate(newTemplateLabel(), value)
								end,
							}),
						},
					},

					create "Frame" {
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 0, 32),
						BackgroundTransparency = 1,

						create "UIListLayout" {
							FillDirection = Enum.FillDirection.Horizontal,
							HorizontalAlignment = Enum.HorizontalAlignment.Right,
							VerticalAlignment = Enum.VerticalAlignment.Center,
						},

						Button({
							text = "Add Template",
							onClick = addTemplate,
							variant = "primary",
							size = "small",
							disabled = function()
								return newTemplateLabel() == "" or newTemplateValue() == ""
							end,
						}),
					},
				},

				-- About section
				create "Frame" {
					LayoutOrder = 40,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,

					SectionHeader("ABOUT"),
				},

				create "TextLabel" {
					LayoutOrder = 41,
					Size = UDim2.new(1, 0, 0, 60),
					BackgroundTransparency = 1,
					Text = "DataScope\nA clean rewrite with Vide\n\nInspired by the original DataScope by pinehappi",
					TextColor3 = function()
						return theme.colors().foregroundMuted
					end,
					TextSize = theme.fontSize.normal,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					FontFace = theme.font,
				},
			},
		},
	}
end

return SettingsView
