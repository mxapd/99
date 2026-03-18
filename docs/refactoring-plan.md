# 99 Plugin Refactoring Plan

## Overview

This document outlines a comprehensive refactoring plan for the 99 Neovim plugin. The goal is to improve code quality, maintainability, and extensibility while preserving existing functionality.

---

## Important Considerations (Pre-Refactor)

### Backward Compatibility
- **Critical**: All existing `require("99")` calls must continue to work
- **Solution**: Keep init.lua as re-export of api.lua for compatibility
- **Strategy**: Deprecate gradually, don't break existing configs

### Neovim Plugin Loading
- Neovim loads plugin/init.lua automatically
- Must ensure `lua/99/init.lua` exists and loads correctly
- New modules can be loaded on-demand via require

### Naming Conflicts
- `utils.lua` already exists - new filter module should be `utils/filter.lua` (subdirectory)
- `state.lua` already exists - use `state/init.lua` for new state module

---

## Phase 1: Module Organization

### 1.1 Split init.lua (Priority: HIGH)

**Current State:**
- 523 lines of mixed responsibilities
- Contains public API, internal logic, setup, keymaps, and helpers
- Acknowledged in TODO comment at line 1

**Proposed Structure:**

```
lua/99/
├── init.lua              # Minimal entry point, require all modules
├── api.lua               # Public API (search, vibe, visual, etc.)
├── config.lua            # Configuration management
├── consts.lua            # Constants (existing)
├── utils.lua             # Utilities (existing)
├── id.lua                # ID generation (existing)
├── time.lua              # Time utilities (existing)
├── geo.lua               # Geolocation (existing)
```

**New api.lua contents:**
```lua
-- Public API functions moved from init.lua
local _99 = {}

_99.search = function(opts) ... end
_99.vibe = function(opts) ... end
_99.visual = function(opts) ... end
_99.tutorial = function(opts) ... end
_99.stop_all_requests = function() ... end
_99.clear_previous_requests = function() ... end
_99.set_model = function(model) ... end
_99.get_model = function() ... end
_99.view_logs = function() ... end
_99.open = function() ... end
_99.info = function() ... end

return _99
```

**New config.lua contents:**
```lua
-- Configuration management
-- Handles setup(), defaults, validation
```

**Action Items:**
- [ ] Extract public API to `api.lua`
- [ ] Extract config handling to `config.lua`
- [ ] Keep init.lua as minimal bootstrapper + re-export for compatibility
- [ ] Update all require statements throughout codebase
- [ ] Update AGENTS.md with new module structure

**Backward Compatibility Strategy:**

```lua
-- lua/99/init.lua (post-refactor)
-- This file maintains backward compatibility

local api = require("99.api")
local config = require("99.config")

-- Re-export everything from api for backward compatibility
local _99 = setmetatable({}, { __index = api })

-- Keep setup here (calls config.setup)
_99.setup = config.setup

return _99
```

This way:
- Old code: `require("99").setup({...})` still works
- New code: `require("99.api").search({...})` also works

---

### 1.2 Consolidate Similar Modules

**State Directory:**
```
lua/99/state/
├── init.lua        # Main state module (NEW - wraps existing state.lua)
├── tracking.lua    # Request tracking (existing)
├── rules.lua       # Rules management (from extensions/agents)
```

**Module Dependencies (should be documented):**
```
api.lua
├── config.lua
├── ops (lazy loaded)
│   ├── make-prompt.lua
│   │   └── prompt.lua
│   ├── providers.lua
│   ├── state tracking
│   └── window
├── providers.lua
│   └── utils.filter
├── state.lua
└── window/

utils/
├── filter.lua (NEW)
└── ... existing utils
```

**Action Items:**
- [ ] Move `extensions/agents/` logic into `state/rules.lua` if small
- [ ] Or keep agents but document relationship to state
- [ ] Create module dependency graph
- [ ] Document load order (what requires what)

---

### 1.3 Refactor ops/ Directory

**Current Issues:**
- Mixed abstraction levels
- Some ops are user-facing (search, vibe)
- Some are internal (marks, clean-up, throbber)

**Proposed Structure:**

```
lua/99/ops/
├── init.lua            # Require all ops, public interface
├── search.lua          # Search operation
├── vibe.lua            # Vibe operation  
├── visual.lua          # Visual operation
├── tutorial.lua        # Tutorial operation
├── helpers/
│   ├── make-prompt.lua    # Prompt building
│   ├── marks.lua          # Mark management
│   ├── clean-up.lua       # Cleanup operations
│   ├── throbber.lua       # Loading indicator
│   └── qfix-helpers.lua  # Quickfix utilities
```

**Action Items:**
- [ ] Move helper operations to `ops/helpers/`
- [ ] Keep user-facing ops at top level
- [ ] Create `ops/init.lua` that requires all operations
- [ ] Document which ops are user-facing vs internal

---

## Phase 2: Provider System Improvements

### 2.1 Standardize Provider Interface

**Current Issues:**
- Inconsistent command building (some use `sh -c`, some use table directly)
- No clear guidance on when to use which
- Missing type annotations on some providers (OllamaProvider - now fixed)

**Proposed Pattern:**

```lua
-- All providers should follow this pattern

--- @class MyProvider : _99.Providers.BaseProvider
local MyProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param context _99.Prompt
--- @return string[]
function MyProvider._build_command(_, query, context)
  -- Option 1: Direct table (for simple commands without shell features)
  return { "cli", "arg1", "arg2", query }
  
  -- Option 2: Use sh -c only when shell features needed:
  -- - Pipelines (|)
  -- - Redirection (>, >>, <)
  -- - Globbing (*, ?)
  -- - Command substitution ($())
  local cmd = "cli --flag " .. vim.fn.shellescape(query) .. " > output.txt"
  return { "sh", "-c", cmd }
end
```

**Decision Criteria for sh -c:**
| Use Direct Table | Use sh -c |
|-----------------|-----------|
| Simple CLI with args | Pipelines |
| No shell features | Redirection |
| Arguments are safe | Globbing |
| | Command substitution |

**Action Items:**
- [ ] Document provider interface in AGENTS.md
- [ ] Audit all providers for correct pattern
- [ ] Add comments explaining why sh -c is used where applicable

---

### 2.2 Provider Configuration

**Current Issues:**
- Default models hardcoded
- No way to configure provider-specific options
- Example: Ollama has no way to set host URL

**Proposed Enhancement:**

```lua
-- In config.lua or setup()

require("99").setup({
  provider = require("99.providers").OllamaProvider,
  model = "qwen3.5:9b",
  provider_config = {
    ollama = {
      host = "http://localhost:11434",
      extra_flags = {"--verbose"},
    },
  },
})
```

**Provider receives config:**
```lua
function OllamaProvider._build_command(_, query, context)
  local config = _99.get_provider_config("ollama") or {}
  local host = config.host or "http://localhost:11434"
  -- use host in command
end
```

**Action Items:**
- [ ] Add provider_config to setup options
- [ ] Add get_provider_config() API
- [ ] Update providers to accept config
- [ ] Document provider configuration

---

### 2.3 Consolidate Output Filtering

**Current Issues:**
- ANSI filtering exists in two places:
  1. `_retrieve_response()` - for temp file output
  2. `parse_opencode_status()` - for stdout streaming

**Proposed Solution:**

Create `utils/filter.lua`:
```lua
-- String filtering utilities

--- Strip ANSI escape codes from string
--- @param str string
--- @return string
function M.strip_ansi(str)
  -- Current implementation from _retrieve_response
end

--- Strip code fences from string
--- @param str string
--- @return string
function M.strip_code_fences(str)
  -- Current implementation
end

--- Strip import statements from code
--- @param lines string[]
--- @return string[]
function M.strip_imports(lines)
  -- Current implementation
end

--- Clean up whitespace
--- @param str string
--- @return string
function M.trim_whitespace(str)
  -- Current implementation
end

return M
```

**Action Items:**
- [ ] Create `lua/99/utils/filter.lua`
- [ ] Move all filtering functions to filter.lua
- [ ] Update `_retrieve_response` to use filter module
- [ ] Update `parse_opencode_status` to use filter module
- [ ] Add tests for filter functions

---

## Phase 3: State Management

### 3.1 Document State Flow

**Current Issues:**
- State is opaque
- Hard to understand how state flows

**Proposed Documentation:**

```lua
-- state/init.lua

-- State is a singleton accessed via:
--   local state = require("99.state")
--   state.get() -- returns current state
--   state.set(key, value) -- updates state
--   state.subscribe(callback) -- listen for changes
--
-- State contains:
--   - model: current LLM model
--   - provider: current provider instance
--   - rules: custom prompt rules
--   - tracking: in-flight requests
--   - config: user configuration
```

**Action Items:**
- [ ] Document state structure in state/init.lua
- [ ] Add state.get(), state.set(), state.subscribe() helpers
- [ ] Remove `__get_state()` pattern (use proper API)
- [ ] Update tests to use state API

---

### 3.2 Extract Tracking

**Current:**
`state/tracking.lua` handles:
- In-flight request tracking
- Completed request history
- Request cancellation

**Proposed:**
Keep as-is but make tracking accessible:
```lua
-- In state/tracking.lua

--- Get all in-flight requests
--- @return _99.Tracking.Request[]
Tracking.get_in_flight()

--- Stop all in-flight requests
Tracking.stop_all()

--- Get completed request count
--- @return number
Tracking.completed_count()
```

**Action Items:**
- [ ] Document tracking API
- [ ] Ensure all public methods have type annotations
- [ ] Add tests for tracking behavior

---

## Phase 4: Testing Improvements

### 4.1 Test Structure

**Current Issues:**
- Tests are implementation-focused
- Break easily when refactoring
- Hard to test user-visible behavior

**Proposed Approach:**

```lua
-- test/integration/ directory
lua/99/test/integration/
├── search_spec.lua     -- Tests search operation end-to-end
├── vibe_spec.lua       -- Tests vibe operation end-to-end
├── visual_spec.lua     -- Tests visual operation end-to-end
```

**Example Integration Test:**
```lua
-- Tests user-visible behavior, not implementation

describe("search operation", function()
  it("searches codebase and populates quickfix", function()
    -- Setup: create test files
    -- Execute: require("99.api").search({prompt = "find foo"})
    -- Verify: quickfix has expected entries
    -- Cleanup: remove test files
  end)
end)
```

**Action Items:**
- [ ] Create `test/integration/` directory
- [ ] Add integration tests for each user-facing op
- [ ] Keep unit tests for utilities (filter, etc.)
- [ ] Document testing patterns in AGENTS.md

---

### 4.2 Test Utilities

**Current:**
`test_utils.lua` has helper functions but:
- Mixed purposes
- Some are complex

**Proposed:**
```
lua/99/test/
├── helpers/
│   ├── buffer.lua     -- Buffer manipulation
│   ├── state.lua      -- State setup/teardown
│   ├── mocks.lua      -- Mock providers
│   └── files.lua      -- Test file creation
├── unit/              -- Unit tests (existing)
├── integration/       -- Integration tests (new)
└── test_utils.lua     -- Keep only generic helpers
```

**Action Items:**
- [ ] Refactor test_utils.lua into helpers/
- [ ] Create mock providers for testing
- [ ] Document test helper usage

---

## Phase 5: Documentation

### 5.1 Update AGENTS.md

**Required Updates:**

1. **Module Structure**
   ```
   lua/99/
   ├── api.lua         -- Public API
   ├── config.lua      -- Configuration
   ├── providers.lua   -- Provider interface
   ├── ops/           -- Operations
   ├── state/         -- State management
   ├── utils/         -- Utilities
   │   └── filter.lua -- Output filtering
   ```

2. **Provider Interface**
   - Document required methods
   - Document when to use sh -c vs direct table

3. **Testing**
   - Document integration vs unit test patterns
   - Document test helpers

**Action Items:**
- [ ] Rewrite module structure section
- [ ] Add provider development section
- [ ] Update testing conventions section

---

### 5.2 Code Comments

Add header comments to new modules:
```lua
--[[
  Module: filter
  Purpose: String filtering utilities for provider output
  Dependencies: None
  Public API:
    - filter.strip_ansi(str)
    - filter.strip_code_fences(str)
    - filter.strip_imports(lines)
    - filter.trim_whitespace(str)
--]]
```

**Action Items:**
- [ ] Add header comments to all new modules
- [ ] Add docstrings to all public functions

---

## Implementation Order

### Phase 1: Foundation (Week 1)
1. Create `api.lua` - extract public API from init.lua
2. Create `config.lua` - extract configuration
3. Reduce init.lua to bootstrapper
4. Run tests - ensure nothing breaks

### Phase 2: Core Improvements (Week 2)
1. Create `utils/filter.lua`
2. Consolidate filtering code
3. Test filtering still works

### Phase 3: Provider System (Week 3)
1. Document provider interface
2. Add provider configuration
3. Audit providers for consistency

### Phase 4: Testing (Week 4)
1. Create integration test structure
2. Add integration tests for search
3. Refactor test utilities

### Phase 5: Polish (Week 5)
1. Update AGENTS.md
2. Add code comments
3. Full test suite pass

---

## Risk Mitigation

### Breaking Changes
- All public API remains unchanged
- Only internal structure changes
- Extensive test coverage during migration

### Testing Strategy
- Run full test suite after each sub-task
- Manual testing of key workflows
- Integration tests catch behavior changes

### Rollback Plan
- Keep old files during refactor
- Rename to .bak if needed
- Git branch for refactoring work

### Performance Considerations

**Module Loading:**
- Lazy load heavy modules (ops, extensions) to keep startup fast
- Don't require everything in init.lua - require on first use

**Memory:**
- Track request objects should be cleaned up after completion
- State should not grow unbounded

### Common Pitfalls to Avoid

1. **Circular requires**: Don't create circular dependencies between modules
2. **Loading order**: Don't assume modules are loaded in specific order
3. **Global state**: Minimize global state, use state module
4. **Blocking calls**: Don't block neovim main thread (use vim.system, vim.schedule)

---

## Success Criteria

1. ✅ init.lua reduced to <100 lines
2. ✅ All providers follow consistent pattern
3. ✅ Output filtering centralized
4. ✅ State management documented
5. ✅ Integration tests for user workflows
6. ✅ AGENTS.md reflects current structure

---

## Validation Checklist (Pre-Merge)

Before merging refactoring changes:

- [ ] All existing tests pass
- [ ] Manual testing: search operation works
- [ ] Manual testing: visual operation works  
- [ ] Manual testing: vibe operation works
- [ ] Manual testing: stop_all_requests works
- [ ] Manual testing: provider switching works
- [ ] Backward compatibility: require("99").setup() works
- [ ] Backward compatibility: keybindings work
- [ ] No new luacheck warnings
- [ ] No new stylua issues
- [ ] Plugin loads without errors on nvim startup

---

## Open Questions

1. **Configuration Storage**: Should config persist to disk? (Currently in-memory only)

2. **Provider Versioning**: How to handle provider API changes?

3. **Event System**: Should there be events for:
   - Request started
   - Request completed
   - Request failed
   - Config changed

4. **Plugin vs Library**: Is 99 meant as:
   - A plugin (user invokes commands)
   - A library (other plugins embed 99)
   
   This affects public API design.

---

## Appendix: Current Directory Structure (Post-Refactor)

```
lua/99/
├── init.lua              # Bootstrapper, requires all modules
├── api.lua               # Public API (search, vibe, visual, etc.)
├── config.lua            # Configuration management
├── providers.lua         # All providers
├── prompt.lua           # Prompt construction
├── state.lua            # State management
├── utils.lua            # General utilities
├── consts.lua           # Constants
├── id.lua               # ID generation
├── time.lua             # Time utilities
├── geo.lua              # Geolocation
│
├── ops/
│   ├── init.lua         # Require all operations
│   ├── search.lua       # Search operation
│   ├── vibe.lua         # Vibe operation
│   ├── visual.lua       # Visual operation
│   ├── tutorial.lua     # Tutorial operation
│   └── helpers/
│       ├── make-prompt.lua
│       ├── marks.lua
│       ├── clean-up.lua
│       ├── throbber.lua
│       └── qfix-helpers.lua
│
├── extensions/          # External integrations
│   ├── completions.lua
│   ├── pickers.lua
│   ├── files/
│   ├── agents/
│   ├── work/
│   └── native.lua
│
├── window/              # UI components
│   ├── init.lua
│   ├── status-window.lua
│   └── select-window.lua
│
├── state/               # State management
│   ├── init.lua
│   └── tracking.lua
│
├── logger/              # Logging system
│   ├── logger.lua
│   └── level.lua
│
├── utils/              # Utilities
│   ├── filter.lua      # Output filtering
│   └── ...
│
└── test/
    ├── helpers/        # Test utilities
    ├── unit/           # Unit tests
    └── integration/    # Integration tests
```

---

*Document Version: 1.0*
*Created: 2026-03-18*
