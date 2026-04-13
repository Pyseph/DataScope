--!strict
--[[
	App Component
	Main application container using Vide
]]

local Vide = require(script.Parent.Parent.Packages.Vide)
local Theme = require(script.Parent.Theme)
local Store = require(script.Parent.Parent.core.Store)

local Toast = require(script.Parent.components.Toast)
local Modal = require(script.Parent.components.Modal)
local Tooltip = require(script.Parent.components.Tooltip)

local ConnectView = require(script.Parent.views.ConnectView)
local BrowseView = require(script.Parent.views.BrowseView)
local EditKeyView = require(script.Parent.views.EditKeyView)
local VersionsView = require(script.Parent.views.VersionsView)
local SettingsView = require(script.Parent.views.SettingsView)
local QueryView = require(script.Parent.views.QueryView)

local create = Vide.create
local switch = Vide.switch
local show = Vide.show

export type AppProps = {
	parent: Instance,
}

local function App(props: AppProps): Frame
	local theme = Theme.get()

	return create "Frame" {
		Name = "DataScope",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return theme.colors().background
		end,
		BorderSizePixel = 0,
		Parent = props.parent,

		-- Main content
		create "Frame" {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			-- Views are swapped based on current view
			switch(Store.currentView) {
				connect = ConnectView,
				browse = BrowseView,
				editKey = EditKeyView,
				versions = VersionsView,
				settings = SettingsView,
				query = QueryView,
			},
		},

		-- Toast container
		Toast.ToastContainer({
			toasts = Store.toasts,
			onDismiss = Store.dismissToast,
		}),

		-- Modal overlay (rendered via show so content is created/destroyed with modal)
		show(Store.isModalOpen, function()
			local contentFn = Store.modalContent()
			local children = if contentFn then { contentFn() } else {}
			return Modal({
				isOpen = function()
					return true
				end,
				onClose = Store.closeModal,
				title = Store.modalTitle(),
				size = "large",
				children = children,
			})
		end),
		
		-- Tooltip display (global, rendered on top)
		Tooltip.Display(),
	}
end

return App
