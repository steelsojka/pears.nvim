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
type CallableList<T> = ((value: T) => boolean | nil) | {
  include?: T[];
  exclude?: T[];
} | T[]

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

  // Pairs to include or exclude at a global level.
  // This will not be called if `setup_buf_pairs` is called with a CallableList
  // as it's first argument.
  // This will override filetype configuration for a pair.
  // If you need filetype specific pair logic then use a `setup_buf_pairs`
  pair_inclusion(pairs: CallableList<string>);
}

interface PearsPairConfig {
  // Close characters
  close: string;

  // Whether the pair should expand or not. Use to add custom behavior to a pair
  should_expand?: (bufnr: number) => boolean;

  // A function to handle <CR> when the cursor is placed inside an empty pair
  // Default behavior is <CR><C-c>O
  handle_return?: (bufnr: number) => void;

  // Includes and excludes for this specific pair by filetype.
  // This will be ignored if `setup_buf_pairs` is called with a pairs param.
  filetypes?: CallableList<string>;
}
```

Filetype configuration
----------------------

You can setup filetype specific configuration a couple different ways.

### By pair

You can configure a pair to only work on a set of filetypes.

```lua
require "pears".setup(function(conf)
  conf.pair("{", {filetypes = {"c", "javascript"}})
end)
```

This will only expand `{` on `c` and `javascript` files.
Look at the interface for `filetypes` to see all possible ways to determine the filetype to include/exclude.

### By buffer

You can specify which pairs to include/exclude by calling `setup_buf_pairs()` with a `CallableList<string>`.
This is useful when using filetype files. All these are valid.

```vim
lua require "pears".setup_buf_pairs {"{", "<"}

lua require "pears".setup_buf_pairs {include = {"{", "<"}}

lua require "pears".setup_buf_pairs {exclude = {"<!--"}}

lua require "pears".setup_buf_pairs(function(opener)
  return opener ~= "{"
end)
```

### Globally

You can add a hook to determine which pairs to use (this overwrites file type specifics unless `nil` is returned)

```lua
require "pears".setup(function(conf)
  conf.pair_inclusion(function(opener)
    return opener == "{"
  end)
end)
```

