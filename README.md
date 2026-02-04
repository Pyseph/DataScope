# DataScope

Originally a rewrite of the DataDelve plugin, now a separate & powerful DataStore editor plugin for Roblox Studio.

## Features

### Core Features (from original)
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
  - **Regex** - Search using Lua patterns

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
- **Clean Separation** - UI components, state management, and DataStore operations are clearly separated

## Installation

### Using Wally
```toml
[dependencies]
DataScope = "pyseph/datascope@1.0.0"
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
│       └── SettingsView.luau
├── utils/
│   ├── Functional.luau    # FP utilities (map, filter, reduce, etc.)
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
| Regex | Lua pattern matching | `^player%d+` finds keys starting with "player" + digits |

## Credits

- Original DataScope concept by [pinehappi](https://github.com/pinehappi/DataScope)
- Rewritten using [Vide](https://github.com/centau/vide) by centau

## License

GPL-3.0
