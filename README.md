# pears.nvim
Auto pair plugin for neovim

This is still very much a work in progress... APIs may break at various times.

Features
--------

### Auto pairs

```lua
|
-- type {
{|}
```

### Multibyte auto pairs

```lua
|
-- type <!--
<!--|-->
```

### Return expansion

```lua
{|}
-- type <CR>
{
  |
}
```

### Remove empty pairs (inside)

```lua
{|}
-- type <BS>
|
```

### Remove empty pairs (outer)

```lua
{}|
-- type <BS>
|
```

### Remove empty multibyte pairs (inside)

```lua
<!--|-->
-- type <BS>
|
```

### Remove empty multibyte pairs (outer)

```lua
<!---->|
-- type <BS>
|
```

### Move past closed pairs

```lua
|
-- type {
{|}
-- type }
{}|
```

### Move past closed multibyte pairs

```lua
|
-- type <!--
<!--|-->
-- type -
<!---->|
```

### Speed

pears.nvim is lightning fast and doesn't slow down input at all!

### Treesitter language support

Detects language based off of the treesitter language at the cursor. This will fallback to `ft` if there is no treesitter parser.

* For rules that use treesitter (child_of_node), `nvim-treesitter` is required, but for basic injected language support it is not required.

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

  // A list of filetypes to never attach it to, basically not including this plugin at all.
  disabled_filetypes(filetypes: string[]): void;
}

interface PearsPairConfig {
  // Close characters
  close: string;

  // Whether the pair should expand or not. Use to add custom behavior to a pair
  should_expand?: (args: RuleArg) => boolean;

  // Whether the pair should perform <CR> behavior. Use to add custom behavior to a pair
  should_return?: (args: RuleArg) => boolean;

  // Whether when entering a closing pair char the cursor should move past the closing char or insert a new char
  should_move_right?: (args: RuleArg) => boolean;

  // A function to handle <CR> when the cursor is placed inside an empty pair
  // Default behavior is <CR><C-c>O
  handle_return?: (bufnr: number) => void;

  // Includes and excludes for this specific pair by filetype.
  // This will be ignored if `setup_buf_pairs` is called with a pairs param.
  filetypes?: CallableList<string>;
}

interface RuleArg {
  char: string | nil;
  context: Context | nil;
  leaf: PearsPairConfig;
  lang: string;
  cursor: [number, number];
  bufnr: number;
  input: Input;
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

Wildcard expansion
------------------

You can use pears to produce matching html tags or any matching content. Here is a sample configuration for matching html tags.

```lua
<div|

-- type > or any non valid character

<div>|</div>
```

For an example, take a look at the `tag_matching` preset.

* Only one wildcard may appear in a wildcard pair at a time.
* Carriage return behavior in wildcard pairs is still under development.

You can also enable this using the preset.

```lua
require "pears".setup(function(conf)
  conf.preset "tag_matching"
end)
```

You can bind the expansion to a certain key if you want to expand a wildcard before the terminating condition.

```vim
inoremap <silent> <C-l> lua require "pears".expand()
```

```lua
<div class="test|"
-- press <C-l>
<div class="test">|</div>
```

Rules
-----

pears uses several hooks to define how a specific pear should behave. These hooks can be set using rules, which in the end are just functions. A rule api is provided, and used internally, to make this enjoyable to write. Here is an example.

```lua
local R = require "pairs.rule"

require "pears".setup(function(conf)
  conf.pair("'", {
    close = "'",
    -- Don't expand a quote if it comes after an alpha character
    should_expand = R.not_(R.start_of_context "[a-zA-Z]")
  })
end)
```

We could also add a rule to only expand this within a treesitter "string" node.

```lua
local R = require "pairs.rule"

require "pears".setup(function(conf)
  conf.pair("'", {
    close = "'",
    should_expand = R.all_of(
      -- Don't expand a quote if it comes after an alpha character
      R.not_(R.start_of_context "[a-zA-Z]")
      -- Only expand when in a treesitter "string" node
      R.child_of_node "string"
    )
  })
end)
```

Completion Intergration
-----------------------

To work with completion framesworks you can use the `on_enter` option to add custom behavior on enter. Shown with `compe`.

```lua
require "pears".setup(function(conf)
  conf.on_enter(function(pears_handle)
    if vim.fn.pumvisible() == 1 and vim.fn.complete_info().selected ~= -1 then
      vim.fn["compe#confirm"]("<CR>")
    else
      pears_handle()
    end
  end)
end)
```
