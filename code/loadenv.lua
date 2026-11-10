-- loadenv.lua - minimal .env loader for LuatOS
-- Files flashed with LuaTools land in the read-only /luadb filesystem,
-- so /luadb/.env is checked before a plain relative .env.
-- Every KEY=VALUE found is exported as a global (_G.KEY) string.
--
-- Kept dependency-free on purpose: it must load before anything else.

local M = {}

local SEARCH = { "/luadb/.env", ".env" }

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_quotes(v)
    local first = v:sub(1, 1)
    if #v >= 2 and (first == '"' or first == "'") and v:sub(-1) == first then
        return v:sub(2, -2)
    end
    return v
end

-- Parse one file into globals. Returns key count, or nil when file is absent.
function M.parse_file(path)
    local fd = io.open(path, "r")
    if not fd then
        return nil
    end
    local count = 0
    while true do
        local line = fd:read("*l")
        if not line then
            break
        end
        line = trim(line)
        -- skip blanks and comments; "export KEY=value" also accepted
        if #line > 0 and line:sub(1, 1) ~= "#" then
            line = line:gsub("^export%s+", "")
            local key, value = line:match("^([%w_%.%-]+)%s*=%s*(.-)%s*$")
            if key and value then
                _G[key] = strip_quotes(value)
                count = count + 1
            end
        end
    end
    fd:close()
    return count
end

-- Load configuration. Path argument forces a single file (used by tests).
-- Returns: key count, path used (path is nil when nothing was found).
function M.load(path)
    local candidates = SEARCH
    if path then
        candidates = { path }
    end
    for _, candidate in ipairs(candidates) do
        local count = M.parse_file(candidate)
        if count then
            log.info("ENV", "loaded", count, "keys from", candidate)
            return count, candidate
        end
    end
    log.info("ENV", "no .env file found, using built-in defaults")
    return 0, nil
end

return M
