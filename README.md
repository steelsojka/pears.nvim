# pears.nvim
Auto pair plugin for neovim

This is still very much a work in progress... I would recommend not using it. At the time of writing this plugin is less than 48 hours old.

Features
--------

### Auto pairs

```lua
local cool = |

-- type {

local cool = {|}
```

### Multibyte auto pairs

```lua
local cool = |

-- type <!--

local cool = <!--|-->
```

### <CR> expansion

```lua
local cool = {|}

-- type <CR>

local cool = {
  |
}
```

### Remove empty pairs (inside)

```lua
local cool = {|}

-- type <BS>

local cool = |
```

### Remove empty pairs (outer)

```lua
local cool = {}|

-- type <BS>

local cool = |
```

### Remove empty multibyte pairs (inside)

```lua
local cool = <!--|-->

-- type <BS>

local cool = |
```

### Remove empty multibyte pairs (outer)

```lua
local cool = <!---->|

-- type <BS>

local cool = |
```

Install
-------

You can install this with your favorite package manager (packer.nvim shown).

```lua
use "steelsojka/pears.nvim"
```

Setup
-----

### Basic

```lua
require "pears".setup()
```


### Advanced

The setup function takes a configuration function as an argument that will get called with a configuration API.

```lua
require "pears".setup(function(conf)
  conf.pair("{", "}")
  conf.expand_on_enter(false)
end)
```

Configuration
-------------

The configuration interface is described as:

```typescript
interface PearsConfig {
  // Registers a pair to expand
  pair(opener: string, closer_or_config: string | PearsPairConfig | nil): void;
  // Enables an empty pair to be removed on backspace when the cursor is in the empty pair
  remove_pair_on_inner_backspace(enable: boolean): void;
  // Enables an empty pair to be removed on backspace when the cursor at the end of the empty pair
  remove_pair_on_outer_backspace(enable: boolean): void;
  // Overrides the on enter handler. Use to integrate other plugins to the <CR> key binding
  on_enter(handler: (pear_handler: () => void) => void): void;
  // Whether to bind <CR> to expand pairs
  expand_on_enter(enable: boolean): void;
}

interface PearsPairConfig {
  // Close characters
  close: string;
  // Whether the pair should expand or not. Use to add custom behavior to a pair
  should_expand?: (bufnr: number) => boolean;
  // A function to handle <CR> when the cursor is placed inside an empty pair
  // Default behavior is <CR><C-c>O
  handle_return?: (bufnr: number) => void;
}
```
