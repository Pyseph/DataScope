--!strict
--[[
	Theme System
	Reactive theme management using Vide
]]

local Vide = require(script.Parent.Parent.Packages.Vide)
local Types = require(script.Parent.Parent.core.Types)
local Functional = require(script.Parent.Parent.utils.Functional)

local source = Vide.source
local derive = Vide.derive
local root = Vide.root

type ThemePreset = Types.ThemePreset
type ThemeColors = Types.ThemeColors

export type Theme = {
	colors: () -> ThemeColors,
	preset: () -> ThemePreset,
	accent: () -> string,
	setPreset: (preset: ThemePreset) -> (),
	setAccent: (accent: string) -> (),
	-- Typography - Display/Headers (Gotham for bold headings)
	fontDisplay: Font,
	fontDisplayMedium: Font,
	fontDisplayBold: Font,
	-- Typography - Body text (clean sans-serif)
	font: Font,
	fontLight: Font,
	fontMedium: Font,
	fontBold: Font,
	-- Typography - Code/Data (monospace)
	fontMono: Font,
	fontMonoMedium: Font,
	fontMonoBold: Font,
	-- Font sizes with better hierarchy
	fontSize: {
		xs: number,      -- 10px - tiny labels
		small: number,   -- 11px - secondary info
		normal: number,  -- 13px - body text
		medium: number,  -- 14px - emphasized body
		large: number,   -- 16px - subheadings
		xl: number,      -- 20px - section titles
		xxl: number,     -- 24px - page titles
		display: number, -- 32px - hero text
	},
	-- Line heights
	lineHeight: {
		tight: number,   -- 1.2
		normal: number,  -- 1.5
		relaxed: number, -- 1.75
	},
	spacing: {
		xs: number,
		sm: number,
		md: number,
		lg: number,
		xl: number,
		xxl: number,
	},
	radius: {
		xs: number,
		sm: number,
		md: number,
		lg: number,
		xl: number,
		full: number,
	},
	icons: { [string]: string },
	-- Animation durations
	animation: {
		fast: number,
		normal: number,
		slow: number,
	},
}

-- Color utilities
local function hex(hexStr: string): Color3
	local r = tonumber(string.sub(hexStr, 2, 3), 16) or 0
	local g = tonumber(string.sub(hexStr, 4, 5), 16) or 0
	local b = tonumber(string.sub(hexStr, 6, 7), 16) or 0
	return Color3.fromRGB(r, g, b)
end

local function lighten(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.min(1, v + amount))
end

local function darken(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.max(0, v - amount))
end

-- Accent color definitions
local accentColors: { [string]: Color3 } = {
	blue = hex("#3B82F6"),
	purple = hex("#8B5CF6"),
	green = hex("#22C55E"),
	red = hex("#EF4444"),
	orange = hex("#F97316"),
	pink = hex("#EC4899"),
	cyan = hex("#06B6D4"),
	yellow = hex("#EAB308"),
}

-- Theme presets
local presets: { [ThemePreset]: (accentColor: Color3) -> ThemeColors } = {
	Studio = function(accent: Color3): ThemeColors
		return {
			background = hex("#2B2D31"), -- Slightly softer dark
			backgroundSecondary = hex("#313338"),
			backgroundTertiary = hex("#1E1F22"),
			foreground = hex("#F2F3F5"),
			foregroundSecondary = hex("#B5BAC1"),
			foregroundMuted = hex("#80848E"),
			accent = accent,
			accentHover = lighten(accent, 0.1),
			accentPressed = darken(accent, 0.1),
			border = hex("#1E1F22"), -- Darker border for depth
			borderHover = hex("#4E5058"),
			success = hex("#23A559"),
			error = hex("#DA373C"),
			warning = hex("#F0B232"),
			info = hex("#5865F2"),
			scrollbar = hex("#1A1B1E"),
			scrollbarHover = hex("#2B2D31"),
		}
	end,

	Dark = function(accent: Color3): ThemeColors
		return {
			background = hex("#111111"),
			backgroundSecondary = hex("#1A1A1A"),
			backgroundTertiary = hex("#222222"),
			foreground = hex("#EDEDED"),
			foregroundSecondary = hex("#A1A1A1"),
			foregroundMuted = hex("#666666"),
			accent = accent,
			accentHover = lighten(accent, 0.1),
			accentPressed = darken(accent, 0.1),
			border = hex("#333333"),
			borderHover = hex("#444444"),
			success = hex("#4ADE80"),
			error = hex("#EF4444"),
			warning = hex("#FBBF24"),
			info = hex("#60A5FA"),
			scrollbar = hex("#333333"),
			scrollbarHover = hex("#444444"),
		}
	end,

	Light = function(accent: Color3): ThemeColors
		return {
			background = hex("#FFFFFF"),
			backgroundSecondary = hex("#F3F4F6"),
			backgroundTertiary = hex("#E5E7EB"),
			foreground = hex("#1F2937"),
			foregroundSecondary = hex("#4B5563"),
			foregroundMuted = hex("#9CA3AF"),
			accent = accent,
			accentHover = darken(accent, 0.05),
			accentPressed = darken(accent, 0.1),
			border = hex("#E5E7EB"),
			borderHover = hex("#D1D5DB"),
			success = hex("#10B981"),
			error = hex("#EF4444"),
			warning = hex("#F59E0B"),
			info = hex("#3B82F6"),
			scrollbar = hex("#E5E7EB"),
			scrollbarHover = hex("#D1D5DB"),
		}
	end,
}

-- Icon asset IDs
local icons: { [string]: string } = {
	-- Navigation
	back = "rbxassetid://105966752505258",
	home = "rbxassetid://111374510322423",
	settings = "rbxassetid://93353783008647",
	refresh = "rbxassetid://139245246276657",

	-- Actions
	add = "rbxassetid://135490093943126",
	delete = "rbxassetid://138220264677639",
	edit = "rbxassetid://100903139005278",
	save = "rbxassetid://109455831996952",
	copy = "rbxassetid://81075541402651",
	undo = "rbxassetid://113056367955035",
	redo = "rbxassetid://111087159721510",

	-- Tree view
	expand = "rbxassetid://137104530823716",
	collapse = "rbxassetid://115143183151918",
	folder = "rbxassetid://86923203802423",

	-- Data types
	string = "rbxassetid://6034818375",
	number = "rbxassetid://6034818374",
	boolean = "rbxassetid://6034818370",
	table = "rbxassetid://6034818376",
	array = "rbxassetid://6034818369",
	null = "rbxassetid://6034818373",
	buffer = "rbxassetid://6034509988",

	-- Status
	success = "rbxassetid://125615038950962",
	error = "rbxassetid://70868305602519",
	warning = "rbxassetid://137889581471909",
	info = "rbxassetid://87415384298647",
	loading = "rbxassetid://100564892200095",

	-- Search
	search = "rbxassetid://75996689572798",
	close = "rbxassetid://88866007749127",
	clear = "rbxassetid://105098103454193",
	history = "rbxassetid://113056367955035",

	-- Misc
	pin = "rbxassetid://109455831996952",
	chevronDown = "rbxassetid://114165873930451",
	chevronRight = "rbxassetid://132086991456473",
	chevronUp = "rbxassetid://90018096993427",
	check = "rbxassetid://125615038950962",
	more = "rbxassetid://135490093943126",
	database = "rbxassetid://86923203802423",
	key = "rbxassetid://6034818375",
	clock = "rbxassetid://100564892200095",
	chart = "rbxassetid://87415384298647",
	
	-- Empty states (using simple geometric shapes)
	emptyBox = "rbxassetid://86923203802423",
	emptySearch = "rbxassetid://75996689572798",
	emptyData = "rbxassetid://6034818376",
}

-- Create theme
local function createTheme(): Theme
	local currentPreset = source("Studio" :: ThemePreset)
	local currentAccent = source("blue")

	local colors: () -> ThemeColors
	root(function()
		colors = derive(function(): ThemeColors
			local preset = currentPreset()
			local accentName = currentAccent()
			local accentColor = accentColors[accentName] or accentColors.blue
			local presetFn = presets[preset]
			return presetFn(accentColor)
		end)
	end)

	return {
		colors = colors,
		preset = currentPreset,
		accent = currentAccent,

		setPreset = function(preset: ThemePreset)
			currentPreset(preset)
		end,

		setAccent = function(accent: string)
			if accentColors[accent] then
				currentAccent(accent)
			end
		end,

		-- Display/Header fonts (Gotham-style for bold impact)
		fontDisplay = Font.fromEnum(Enum.Font.GothamBold),
		fontDisplayMedium = Font.fromEnum(Enum.Font.GothamMedium),
		fontDisplayBold = Font.fromEnum(Enum.Font.GothamBlack),
		
		-- Body fonts (clean, readable)
		font = Font.fromEnum(Enum.Font.Gotham),
		fontLight = Font.fromEnum(Enum.Font.Gotham),
		fontMedium = Font.fromEnum(Enum.Font.GothamMedium),
		fontBold = Font.fromEnum(Enum.Font.GothamBold),
		
		-- Monospace fonts (for code/data)
		fontMono = Font.fromEnum(Enum.Font.Code),
		fontMonoMedium = Font.fromEnum(Enum.Font.Code),
		fontMonoBold = Font.fromEnum(Enum.Font.Code),

		-- Improved font size hierarchy
		fontSize = {
			xs = 10,       -- Tiny labels, badges
			small = 11,    -- Secondary info, timestamps
			normal = 13,   -- Body text
			medium = 14,   -- Emphasized body, buttons
			large = 16,    -- Subheadings
			xl = 20,       -- Section titles
			xxl = 24,      -- Page titles
			display = 32,  -- Hero/display text
		},
		
		-- Line heights for text
		lineHeight = {
			tight = 1.2,
			normal = 1.5,
			relaxed = 1.75,
		},

		spacing = {
			xs = 4,
			sm = 8,
			md = 12,
			lg = 16,
			xl = 24,
			xxl = 32,
		},

		radius = {
			xs = 4,
			sm = 6,
			md = 8,
			lg = 12,
			xl = 16,
			full = 9999,
		},

		icons = icons,
		
		-- Animation timing
		animation = {
			fast = 0.1,
			normal = 0.2,
			slow = 0.4,
		},
	}
end

-- Singleton theme instance
local theme: Theme? = nil

local function getTheme(): Theme
	if not theme then
		theme = createTheme()
	end
	return theme :: Theme
end

-- Export theme getter and utilities
return {
	get = getTheme,
	hex = hex,
	lighten = lighten,
	darken = darken,
	accentColors = accentColors,
	presets = Functional.keys(presets),
	accents = Functional.keys(accentColors),
}
