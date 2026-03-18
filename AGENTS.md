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
# Enter development environment (requires nix-shell with neovim + plenary)
nix-shell

# Run all tests (from inside nix-shell)
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

## Development Environment

### Nix Shell

This project uses `shell.nix` to manage development dependencies. Key principles:

1. **Never pull external dependencies into the project folder** - Dependencies should come from:
   - The nix store (via nixpkgs) - preferred for CI/sandboxed environments
   - User's home directory (e.g., `~/.local/share/nvim/...`)
   - System-wide installations

2. **Using nixpkgs dependencies** - Reference packages via nixpkgs:
   ```nix
   { pkgs ? import <nixpkgs> {} }:

   pkgs.mkShell {
     buildInputs = with pkgs; [
       pkgs.vimPlugins.plenary-nvim  # stable reference via nixpkgs
       pkgs.stylua
     ];
   }
   ```

3. **Passing nix store paths to Neovim** - Use environment variables in `shell.nix`:
   ```nix
   PLENARY_PATH = pkgs.vimPlugins.plenary-nvim.outPath;
   ```

   Then reference in `scripts/tests/minimal.vim`:
   ```vim
   if exists("$PLENARY_PATH")
     let &rtp = $PLENARY_PATH . "," . &rtp
   endif
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

## Providers

### Available Providers

The plugin supports multiple LLM providers, configured via `setup()`:

| Provider | Description | Default Model |
|----------|-------------|---------------|
| `OpenCodeProvider` | OpenCode CLI | `opencode/claude-sonnet-4-5` |
| `ClaudeCodeProvider` | Claude Code CLI | `claude-sonnet-4-5` |
| `CursorAgentProvider` | Cursor Agent CLI | `sonnet-4.5` |
| `KiroProvider` | Kiro CLI | `claude-sonnet-4.5` |
| `GeminiCLIProvider` | Gemini CLI | `auto` |
| `OllamaProvider` | Ollama (local) | `qwen3.5:9b` |

### Adding a New Provider

Providers are defined in `lua/99/providers.lua`. Each provider must implement:

```lua
--- @class MyProvider : _99.Providers.BaseProvider
local MyProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param context _99.Prompt
--- @return string[]
function MyProvider._build_command(_, query, context)
  -- Return command as table (passed to vim.system)
end

--- @return string
function MyProvider._get_provider_name()
  return "MyProvider"
end

--- @return string
function MyProvider._get_default_model()
  return "default-model"
end

--- @param callback fun(models: string[]|nil, err: string|nil): nil
function MyProvider.fetch_models(callback)
  -- Optional: fetch available models from provider
end
```

### Output Filtering

The base provider's `_retrieve_response` method includes filtering for:

- **ANSI escape codes** - strips terminal control sequences
- **Code fences** - removes ``` markers
- **Import statements** - strips common imports (Rust, Python, JS, Go, Ruby, Java, C++)
- **Whitespace cleanup** - removes leading/trailing whitespace and collapses newlines

This filtering applies to all providers automatically.

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
