--!strict
--[[
	DataScope Types
	Core type definitions for the application using Vide reactivity
]]

local Vide = require(script.Parent.Parent.Packages.Vide)
type Source<T> = Vide.Source<T>

export type DataStoreType = "Normal" | "Ordered" | "Global"

export type ConnectionInfo = {
	datastoreType: DataStoreType,
	name: string,
	scope: string?,
	allScopes: boolean,
}

export type KeyInfo = {
	key: string,
	createdTime: number?,
	updatedTime: number?,
	version: string?,
}

export type OrderedKeyInfo = {
	key: string,
	value: number,
}

export type VersionInfo = {
	version: string,
	createdTime: number,
	isDeleted: boolean,
}

export type JSONValue = string | number | boolean | { [string]: JSONValue } | { JSONValue } | buffer | nil

export type KeyData = {
	value: JSONValue,
	keyInfo: DataStoreKeyInfo?,
	userIds: { number }?,
	metadata: { [string]: any }?,
}

export type HistoryRecord = {
	connectionInfo: ConnectionInfo,
	timestamp: number,
	pinned: boolean,
}

export type ViewMode = "Tree" | "Code"
export type BufferViewMode = "Hex" | "Deserializer"
export type ThemePreset = "Studio" | "Light" | "Dark"
export type HighlightMode = "Default" | "ScriptEditor"

export type Settings = {
	themePreset: ThemePreset,
	themeAccent: string,
	hideGameName: boolean,
	highlightColors: HighlightMode,
	useAlternatingKeyColors: boolean,
	listDeletedKeys: boolean,
	automaticallyList: boolean,
	clickToOpen: boolean,
	viewerMode: ViewMode,
	bufferViewerMode: BufferViewMode,
}

-- Hook types for compression/decompression
export type HookContext = {
	datastoreName: string,
	key: string,
	scope: string?,
}

export type DecompressHook = (data: buffer | string, context: HookContext) -> JSONValue
export type CompressHook = (data: JSONValue, context: HookContext) -> buffer | string

export type HookConfig = {
	name: string,
	description: string?,
	decompress: DecompressHook?,
	compress: CompressHook?,
	canHandle: ((data: any, context: HookContext) -> boolean)?,
	priority: number?,
}

-- Toast notification types
export type ToastType = "success" | "error" | "warning" | "info"

export type Toast = {
	id: string,
	type: ToastType,
	message: string,
	duration: number?,
}

-- Page types for pagination
export type Page<T> = {
	items: { T },
	hasNextPage: boolean,
	cursor: string?,
}

-- Theme colors
export type ThemeColors = {
	background: Color3,
	backgroundSecondary: Color3,
	backgroundTertiary: Color3,
	foreground: Color3,
	foregroundSecondary: Color3,
	foregroundMuted: Color3,
	accent: Color3,
	accentHover: Color3,
	accentPressed: Color3,
	border: Color3,
	borderHover: Color3,
	success: Color3,
	error: Color3,
	warning: Color3,
	info: Color3,
	scrollbar: Color3,
	scrollbarHover: Color3,
}

-- Tree node for visualization
export type TreeNode = {
	key: string | number,
	value: JSONValue,
	path: { string | number },
	depth: number,
	isExpanded: boolean,
	isObject: boolean,
	isArray: boolean,
	childCount: number,
	matchesSearch: boolean,
}

-- Undo/Redo action
export type UndoAction = {
	type: "set" | "delete" | "insert" | "reorder",
	path: { string | number },
	oldValue: JSONValue?,
	newValue: JSONValue?,
	oldKey: (string | number)?,
	newKey: (string | number)?,
}

return nil
