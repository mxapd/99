--- @class _99.Providers.Observer
--- @field on_stdout fun(line: string): nil
--- @field on_stderr fun(line: string): nil
--- @field on_complete fun(status: _99.Prompt.EndingState, res: string): nil
--- @field on_start fun(): nil

-- Debug flag: set to true to see all OpenCode thinking output
-- Set to false for clean filtered output (default)
local DEBUG_SHOW_ALL = false

--- @param fn fun(...: any): nil
--- @return fun(...: any): nil
local function once(fn)
  local called = false
  return function(...)
    if called then
      return
    end
    called = true
    fn(...)
  end
end

--- @class _99.Providers.BaseProvider
--- @field _build_command fun(self: _99.Providers.BaseProvider, query: string, context: _99.Prompt): string[]
--- @field _get_provider_name fun(self: _99.Providers.BaseProvider): string
--- @field _get_default_model fun(): string
local BaseProvider = {}

--- @param callback fun(models: string[]|nil, err: string|nil): nil
function BaseProvider.fetch_models(callback)
  callback(nil, "This provider does not support listing models")
end

--- @param context _99.Prompt
function BaseProvider:_retrieve_response(context)
  local logger = context.logger:set_area(self:_get_provider_name())
  local tmp = context.tmp_file
  local success, result = pcall(function()
    return vim.fn.readfile(tmp)
  end)

  if not success then
    logger:error(
      "retrieve_results: failed to read file",
      "tmp_name",
      tmp,
      "error",
      result
    )
    return false, ""
  end

  local str = table.concat(result, "\n")

  -- Filter out OpenCode diagnostic/status messages
  -- Keep lines that look like actual code (don't match status patterns)
  local lines = vim.split(str, "\n")
  local filtered = {}
  local skip_patterns = {
    "^Performing one time database migration",
    "^sqlite%-migration:",
    "^Database migration complete",
    "^> build",
    "^✗ write failed",
    "^Error:",
    "^→ Read",
    "^← Write",
    "^Done%.",
    "^✱ ",
    "^→ ",
    "^Done$",
    "^Wrote file successfully%.",
  }

  for _, line in ipairs(lines) do
    -- Skip empty lines
    if line == "" then
      goto continue
    end
    
    -- Skip lines matching status patterns
    for _, pattern in ipairs(skip_patterns) do
      if line:match(pattern) then
        goto continue
      end
    end
    
    -- Keep this line (looks like actual content/code)
    table.insert(filtered, line)
    
    ::continue::
  end

  str = table.concat(filtered, "\n")
  logger:debug("retrieve_results", "results", str)

  return true, str
end

--- @param query string
--- @param context _99.Prompt
--- @param observer _99.Providers.Observer
--- @param line string
--- @return string|nil
local function parse_opencode_status(line)
  -- Handle nil or empty
  if not line or line == "" then
    return nil
  end

  -- Strip ANSI escape codes more comprehensively
  -- Pattern matches: ESC [ <params> <letter>  and ESC [ ... m
  local clean = line
    :gsub("\x1b%[%d+;%d+;%d+;%d+;%d+m", "")  -- ESC [ 5 numbers m
    :gsub("\x1b%[%d+;%d+;%d+;%d+m", "")     -- ESC [ 4 numbers m
    :gsub("\x1b%[%d+;%d+;%d+m", "")          -- ESC [ 3 numbers m
    :gsub("\x1b%[%d+;%d+m", "")              -- ESC [ 2 numbers m
    :gsub("\x1b%[%d+m", "")                  -- ESC [ 1 number m
    :gsub("\x1b%[m", "")                     -- ESC [ m
    :gsub("\x1b%[?%d+l", "")                 -- ESC [ ? number l (reset)
    :gsub("\x1b%(B", "")                     -- ESC ( B (set default font)
    :gsub("\x1b%[K", "")                     -- ESC [ K (clear line)
    :gsub("\x1b%[?7l", "")                   -- ESC [ ? 7 l (disable wrap)
    :gsub("\x1b%[?7h", "")                   -- ESC [ ? 7 h (enable wrap)
    :gsub("[\x1b\x07]", "")                  -- ESC or BEL
    :gsub("%s+$", "")                        -- trailing whitespace

  -- Strip any remaining non-printable/non-ASCII characters
  -- Keep only printable ASCII, unicode letters, numbers, and common punctuation
  clean = clean:gsub("[^%w%s%p]", "")
  clean = clean:gsub("%s+$", ""):gsub("^%s+", "")  -- trim

  -- DEBUG: If enabled, show all output (for testing what OpenCode sends)
  if DEBUG_SHOW_ALL then
    if clean == "" or clean == nil then
      return nil
    end
    return clean
  end

  -- Skip empty lines
  if clean == "" then
    return nil
  end

  -- Skip known noise patterns
  if clean:match("^Performing one time database migration") then
    return nil
  end
  if clean:match("^sqlite%-migration:") then
    return nil
  end
  if clean:match("^Database migration complete") then
    return nil
  end
  if clean:match("^> build") then
    return nil
  end

  -- Translate key patterns to clean messages
  if clean:match("^→ Read") then
    local file = clean:match("→ Read (.+)")
    if file then
      return "Reading: " .. file
    end
    return "Reading file..."
  end

  if clean:match("^← Write") then
    return "Writing result..."
  end

  if clean:match("^✗ write failed") then
    return "Error: write failed"
  end

  if clean:match("^Error:") then
    -- Filter out errors that don't affect the result
    -- e.g., "Error: You must read file first..." - this doesn't matter, operation succeeds
    if clean:match("You must read") then
      return nil  -- Skip this error entirely
    end
    return clean  -- Show other errors that might matter
  end

  if clean:match("^Grep") or clean:match("^Glob") then
    return "Searching..."
  end

  if clean:match("^✱ ") then
    -- Progress indicator, skip
    return nil
  end

  if clean:match("^→ ") then
    -- Tool execution that's not Read/Write, skip
    return nil
  end

  if clean:match("^Done%.?$") then
    return "Done!"
  end

  -- Filter thinking content - show lines that look like actual analysis/context
  -- Include lines that:
  -- 1. Are longer than 30 characters (meaningful content)
  -- 2. Contain letters and spaces (natural language, not just symbols)
  -- 3. Don't match noise patterns
  local has_letters = clean:match("%a")
  local has_spaces = clean:match("%s")
  local too_short = #clean < 30

  if has_letters and has_spaces and not too_short then
    -- This looks like meaningful thinking/context - show it
    -- Truncate if too long
    if #clean > 80 then
      return clean:sub(1, 77) .. "..."
    end
    return clean
  end

  -- Otherwise skip it (likely noise or short symbols)
  return nil
end

function BaseProvider:make_request(query, context, observer)
  observer.on_start()

  local logger = context.logger:set_area(self:_get_provider_name())
  logger:debug("make_request", "tmp_file", context.tmp_file)

  local once_complete = once(
    --- @param status "success" | "failed" | "cancelled"
    ---@param text string
    function(status, text)
      observer.on_complete(status, text)
    end
  )

  local command = self:_build_command(query, context)
  logger:debug("make_request", "command", command)

  local proc = vim.system(
    command,
    {
      text = true,
      stdout = vim.schedule_wrap(function(err, data)
        -- Parse and filter the stdout line for clean status
        local clean_status = parse_opencode_status(data)
        if clean_status then
          -- Pass clean status to the observer instead of raw data
          observer.on_stdout(clean_status)
        end
        if context:is_cancelled() then
          once_complete("cancelled", "")
          return
        end
        if err and err ~= "" then
          logger:debug("stdout#error", "err", err)
        end
      end),
      stderr = vim.schedule_wrap(function(err, data)
        logger:debug("stderr", "data", data)
        if context:is_cancelled() then
          once_complete("cancelled", "")
          return
        end
        if err and err ~= "" then
          logger:debug("stderr#error", "err", err)
        end
        if not err then
          observer.on_stderr(data)
        end
      end),
    },
    vim.schedule_wrap(function(obj)
      if context:is_cancelled() then
        once_complete("cancelled", "")
        logger:debug("on_complete: request has been cancelled")
        return
      end
      if obj.code ~= 0 then
        local str =
          string.format("process exit code: %d\n%s", obj.code, vim.inspect(obj))
        once_complete("failed", str)
        logger:fatal(
          self:_get_provider_name() .. " make_query failed",
          "obj from results",
          obj
        )
      else
        vim.schedule(function()
          local ok, res = self:_retrieve_response(context)
          if ok then
            once_complete("success", res)
          else
            once_complete(
              "failed",
              "unable to retrieve response from temp file"
            )
          end
        end)
      end
    end)
  )

  context:_set_process(proc)
end

--- @class OpenCodeProvider : _99.Providers.BaseProvider
local OpenCodeProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param context _99.Prompt
--- @return string[]
function OpenCodeProvider._build_command(_, query, context)
  local tmp_dir = vim.fn.fnamemodify(context.tmp_file, ":h")
  -- Don't use sed - we'll parse stdout in Lua for clean status messages
  local cmd = "opencode run --agent build --dir " 
    .. vim.fn.shellescape(tmp_dir) 
    .. " -m " .. vim.fn.shellescape(context.model) .. " " 
    .. vim.fn.shellescape(query)
    .. " 2>&1"
  return { "sh", "-c", cmd }
end

--- @return string
function OpenCodeProvider._get_provider_name()
  return "OpenCodeProvider"
end

--- @return string
function OpenCodeProvider._get_default_model()
  return "opencode/claude-sonnet-4-5"
end

function OpenCodeProvider.fetch_models(callback)
  vim.system({ "opencode", "models" }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        callback(nil, "Failed to fetch models from opencode")
        return
      end
      local models = vim.split(obj.stdout, "\n", { trimempty = true })
      callback(models, nil)
    end)
  end)
end

--- @class ClaudeCodeProvider : _99.Providers.BaseProvider
local ClaudeCodeProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param context _99.Prompt
--- @return string[]
function ClaudeCodeProvider._build_command(_, query, context)
  return {
    "claude",
    "--dangerously-skip-permissions",
    "--model",
    context.model,
    "--print",
    query,
  }
end

--- @return string
function ClaudeCodeProvider._get_provider_name()
  return "ClaudeCodeProvider"
end

--- @return string
function ClaudeCodeProvider._get_default_model()
  return "claude-sonnet-4-5"
end

-- TODO: the claude CLI has no way to list available models.
-- We could use the Anthropic API (https://docs.anthropic.com/en/api/models)
-- but that requires the user to have an ANTHROPIC_API_KEY set which isn't ideal.
-- Until Anthropic adds a CLI command for this, we have to hardcode the list here.
-- See https://github.com/anthropics/claude-code/issues/12612
function ClaudeCodeProvider.fetch_models(callback)
  callback({
    "claude-opus-4-6",
    "claude-sonnet-4-5",
    "claude-haiku-4-5",
    "claude-opus-4-5",
    "claude-opus-4-1",
    "claude-sonnet-4-0",
    "claude-opus-4-0",
    "claude-3-7-sonnet-latest",
  }, nil)
end

--- @class CursorAgentProvider : _99.Providers.BaseProvider
local CursorAgentProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param context _99.Prompt
--- @return string[]
function CursorAgentProvider._build_command(_, query, context)
  return { "cursor-agent", "--model", context.model, "--print", query }
end

--- @return string
function CursorAgentProvider._get_provider_name()
  return "CursorAgentProvider"
end

--- @return string
function CursorAgentProvider._get_default_model()
  return "sonnet-4.5"
end

function CursorAgentProvider.fetch_models(callback)
  vim.system({ "cursor-agent", "models" }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        callback(nil, "Failed to fetch models from cursor-agent")
        return
      end
      local models = {}
      for _, line in ipairs(vim.split(obj.stdout, "\n", { trimempty = true })) do
        -- `cursor-agent models` outputs lines like "model-id - description",
        -- so we grab everything before the first " - " separator
        local id = line:match("^(%S+)%s+%-")
        if id then
          table.insert(models, id)
        end
      end
      callback(models, nil)
    end)
  end)
end

--- @class KiroProvider : _99.Providers.BaseProvider
local KiroProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param context _99.Prompt
--- @return string[]
function KiroProvider._build_command(_, query, context)
  return {
    "kiro-cli",
    "chat",
    "--no-interactive",
    "--model",
    context.model,
    "--trust-all-tools",
    query,
  }
end

--- @return string
function KiroProvider._get_provider_name()
  return "KiroProvider"
end

--- @return string
function KiroProvider._get_default_model()
  return "claude-sonnet-4.5"
end

--- @class GeminiCLIProvider : _99.Providers.BaseProvider
local GeminiCLIProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param context _99.Prompt
--- @return string[]
function GeminiCLIProvider._build_command(_, query, context)
  return {
    "gemini",
    "--approval-mode",
    -- Allow writing to temp files by default. See:
    -- https://geminicli.com/docs/core/policy-engine/#default-policies
    "auto_edit",
    "--model",
    context.model,
    "--prompt",
    query,
  }
end

--- @return string
function GeminiCLIProvider._get_provider_name()
  return "GeminiCLIProvider"
end

--- @return string
function GeminiCLIProvider._get_default_model()
  -- Default to auto-routing between pro and flash. See:
  -- https://geminicli.com/docs/cli/model/
  return "auto"
end

return {
  BaseProvider = BaseProvider,
  OpenCodeProvider = OpenCodeProvider,
  ClaudeCodeProvider = ClaudeCodeProvider,
  CursorAgentProvider = CursorAgentProvider,
  KiroProvider = KiroProvider,
  GeminiCLIProvider = GeminiCLIProvider,
}
