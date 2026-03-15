<div align="center">
<img width="300" height="300" alt="image" src="https://github.com/user-attachments/assets/3add7618-1064-4ffb-8197-84813c0dbf31" />

<h1>DataScope</h1>

**[Install from Creator Store](https://create.roblox.com/store/asset/87717019449403/DataScope)**

<h3>A Modern DataStore Editor for Roblox Studio</h3>
<img width="800" height="706.6" alt="image" src="https://github.com/user-attachments/assets/90ee3656-5dec-43c6-887a-cdbda6c54d9d" />

</div>

## Features

### Core Features
- **Visual DataStore Management** - Browse and edit DataStores with a clean GUI
- **Multiple DataStore Types** - Support for Normal, Ordered, and Global DataStores
- **Key Browsing** - List, search, and filter keys with pagination
- **Full CRUD Operations** - Create, read, update, and delete keys
- **Version History** - Browse historical versions of keys
- **Undo/Redo** - 64-action undo/redo stack
- **Multiple View Modes** - Tree view and Code view for data editing
- **Connection History** - Quick access to recent DataStore connections with pinning
- **Theme Support** - Studio, Dark, and Light themes with accent colors
- **Settings Persistence** - Your preferences are saved between sessions

### New Features
- **🔍 Search Bar in Key Editor** - Search within your data with multiple modes:
  - **All** - Search both keys and values
  - **Content** - Match content directly (searches serialized form)
  - **Keys** - Search only key names
  - **Values** - Search only values
  - **Type** - Search by data type (string, number, boolean, array, object, null, buffer)
  - **`.*` Regex toggle** - Independent toggle that enables Lua pattern matching in any mode
  - **🕵️ Field History Scanner** - Track when a specific field in a player's data changed over time. Type a field path (e.g. `coins` or `inventory.sword`) into the search bar at the top of the version history panel, and it scans through every saved version to find exactly where that value changed — showing before and after for each change, with a button to open a full diff. Loads additional pages on demand via a "Scan more" button.

- **🪝 Hook System** - Compression/decompression hooks for DataStore values:
  - JSON String detection and decoding
  - Base64 buffer handling
  - Compressed data markers (LZ4/ZLIB)
  - MessagePack format detection
  - ProfileService data format
  - **Custom hooks** - Register your own compression/serialization hooks

### Architecture
- **Vide** - Reactive UI library for clean, declarative components
- **Functional Programming** - Pure functions, immutable state, composition

## Installation

### From Asset Store
https://create.roblox.com/store/asset/87717019449403/DataScope

### Using Wally
```toml
[dependencies]
DataScope = "pyseph/datascope@1.3.0"
```

### Manual Installation
1. Clone this repository
2. Run `wally install` to get dependencies
3. Use Rojo to sync or build the plugin

## Project Structure

```
src/
├── main.server.luau       # Plugin entry point
├── core/
│   ├── Types.luau         # Type definitions
│   └── Store.luau         # Reactive state management
├── datastore/
│   └── Operations.luau    # DataStore operations
├── hooks/
│   ├── HookManager.luau   # Hook registration and execution
│   └── BuiltInHooks.luau  # Default compression hooks
├── ui/
│   ├── App.luau           # Main app component
│   ├── Theme.luau         # Theme system
│   ├── components/        # Reusable UI components
│   │   ├── Button.luau
│   │   ├── TextInput.luau
│   │   ├── SearchBar.luau # Search with mode selection
│   │   ├── TreeView.luau  # Data visualization
│   │   ├── Tabs.luau
│   │   ├── Modal.luau
│   │   ├── Toast.luau
│   │   └── Select.luau
│   └── views/             # Application views
│       ├── ConnectView.luau
│       ├── BrowseView.luau
│       ├── EditKeyView.luau
│       ├── VersionsView.luau
│       └── SettingsView.luau
├── utils/
│   ├── Functional.luau    # FP utilities (map, filter, reduce, etc.)
│   ├── PatternMatcher.luau # Optimized search engine (~3-4x faster than native regex)
│   └── JSON.luau          # JSON utilities
└── settings/
    └── Settings.luau      # Settings persistence
```

## Custom Hooks

You can register custom compression/decompression hooks for your data formats:

```lua
local HookManager = require(path.to.HookManager)

HookManager.register({
    name = "MyCustomFormat",
    description = "Handle my custom data format",
    priority = 25, -- Higher priority runs first

    -- Called to check if this hook can handle the data
    canHandle = function(data, context)
        return type(data) == "string" and string.sub(data, 1, 4) == "MYF:"
    end,

    -- Transform data for display in editor
    decompress = function(data, context)
        -- Your decompression logic
        return decompressedData
    end,

    -- Transform data back for saving
    compress = function(data, context)
        -- Your compression logic
        return compressedData
    end,
})
```

## Search Modes

The search bar supports multiple modes for finding data:

| Mode | Description | Example |
|------|-------------|---------|
| All | Search keys and values | `player` matches key "playerName" and value "player1" |
| Content | Direct content matching | `gold` finds any occurrence in serialized data |
| Keys | Only search key names | `inventory` finds keys containing "inventory" |
| Values | Only search values | `100` finds values containing "100" |
| Type | Search by data type | `array` finds all arrays |

Enable the **`.*` toggle** to use Lua pattern matching in any of the above modes. For example, `^player%d+` in Keys mode finds keys starting with "player" followed by digits.

## Credits

- Original DataScope concept by [pinehappi](https://github.com/pinehappi/DataDelve)
- Rewritten using [Vide](https://github.com/centau/vide) by centau

## License

GPL-3.0
