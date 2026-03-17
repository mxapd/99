# AGENTS.md - 99 Neovim Plugin

This document provides guidelines for agents working on the 99 codebase.

## Project Overview

99 is an AI-powered Neovim plugin that augments programmer productivity using LLMs. Built specifically for Neovim with plenary.nvim for testing.

## Key Constraints

* **Always use Neovim-provided functions** - Never use standard Lua libraries (`io`, `os`, `math`, `table`). Use `vim.fn`, `vim.api`, `vim.uv`, etc.
* **This is NOT a standard Lua project** - No package resolution or luarocks. All functionality comes from Neovim APIs.
* **Avoid generic AI aesthetics** - The codebase has a distinctive, practical style.

---

## Build, Lint, and Test Commands

### Testing

```bash
# Run all tests
make lua_test

# Run a single test file (using plenary's busted)
nvim --headless --noplugin -u scripts/tests/minimal.vim \
    -c "PlenaryBustedFile lua/99/test/your_spec.lua"

# Full PR-ready check (lint + test + format check)
make pr_ready
```

### Linting

```bash
make lua_lint
```

### Formatting

```bash
make lua_fmt          # Format all Lua files
make lua_fmt_check    # Check without modifying
```

### Cleanup

```bash
make lua_clean
```

---

## Code Style Guidelines

### Formatting

* **Column width**: 80 characters (enforced by stylua)
* **Indentation**: 2 spaces (no tabs)
* **Quotes**: Prefer double quotes (`"`)
* **Line endings**: Unix

### Imports

Use `require("module.path")`. Order alphabetically:

```lua
local Logger = require("99.logger.logger")
local Tracking = require("99.state.tracking")
local utils = require("99.utils")
```

### Naming Conventions

* **Files/Modules**: snake_case (`status-window.lua`)
* **Classes/Types**: PascalCase (in annotations)
* **Functions**: snake_case (`get_tmp_dir`)
* **Constants**: SCREAMING_SNAKE_CASE (`_99_STATE_FILE`)
* **Private functions**: prefix with `_` (`_internal_func`)
* **Module tables**: Return as `M`

### Type Annotations

Use LuaLS annotations:

```lua
--- @param path string
--- @param name string
--- @return string
function M.named_tmp_file(path, name)
  return string.format("%s/99-%s", path, name)
end
```

### Error Handling

Use `pcall` for operations that can fail. Return `nil` for graceful failure, `assert` for programming errors:

```lua
local ok, fh = pcall(io.open, path, "r")
if not ok or not fh then
  return nil
end
assert(type(t) == "table", "passed in non table into table")
```

### Module Structure

```lua
-- 1. Imports (alphabetical)
local utils = require("99.utils")

-- 2. Private constants
local _INTERNAL_FILE = "state"

-- 3. Type definitions (@class, @alias)
-- 4. Private functions (prefix with _)
-- 5. Public API (return as M)

local M = {}
M.__index = M
return M
```

### Comments

Use `---` for documentation (LuaLS compatible), `--` for inline. TODO comments should reference issues.

---

## Testing Conventions

Tests use plenary's busted framework. Place in `lua/99/test/`:

```lua
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local visual_fn = require("99.ops.over-range")

describe("<name of test group>", function()
    it("specific test condition", function()
        local p, buffer, range = setup(content, 2, 1, 2, 23)
        local state = _99.__get_state()
        local context = Prompt.visual(state)

        eq(0, state:active_request_count())
    end)
end)
```

Use `require("99.test.test_utils")` for buffer setup, test providers with controllable resolution, and synchronous scheduling (`next_frame()`).

---

## Configuration Files

| File | Purpose |
|------|---------|
| `.stylua.toml` | Code formatting rules |
| `.luacheckrc` | Linting configuration |
| `scripts/tests/minimal.vim` | Test environment setup |

### Luacheck Ignore Codes

* `111` - Setting undefined global (for `ok, _ = pcall`)
* `211` - Unused local variable
* `411` - Redefining local variable

---

## Useful Neovim APIs

Use Neovim's built-ins instead of Lua stdlib: `vim.fn.readfile()`/`vim.fn.writefile()` for file I/O, `vim.json.decode()`/`vim.json.encode()` for JSON, `vim.split()` for string splitting, `vim.fn.expand()` for path expansion, `vim.uv` for async/UV, and `vim.api.nvim_*` functions for API calls.
