--- CrimsonGift - Logger.lua
--
-- Centralized logging utility. Provides a factory to create module-specific loggers.
--
-- Log Levels:
--   - "error": Critical failures, always shown
--   - "warning": Unusual situations, always shown  
--   - "info": Normal operational logs, only shown when debug mode is ENABLED
--   - "debug": Detailed technical logs, only shown when debug mode is ENABLED

local M = {}

M._prefix = "[CrimsonGift]"

-- Valid log levels
M._LEVELS = {
    error = true,
    warning = true,
    info = true,
    debug = true,
}

--- Check if a log level should be displayed based on current config
-- @param level string: The log level ("error", "warning", "info", "debug")
-- @return boolean: true if this level should be logged
local function should_log(level)
    if not level or not M._LEVELS[level] then
        -- Invalid level, log as error
        return true
    end
    
    -- error and warning always show
    if level == "error" or level == "warning" then
        return true
    end
    
    -- info and debug require debug mode to be enabled
    if CRIMSON_GIFT and CRIMSON_GIFT.config and CRIMSON_GIFT.config.debug_logs then
        return true
    end
    
    return false
end

--- Format a log message string
local function format_message(module_name, level, msg)
    local parts = {M._prefix}
    if module_name and module_name ~= "" then
        parts[#parts + 1] = "[" .. module_name .. "]"
    end
    if level and level ~= "" then
        parts[#parts + 1] = "[" .. tostring(level) .. "]"
    end
    parts[#parts + 1] = " " .. tostring(msg)
    return table.concat(parts)
end

--- Create a logger for a specific module
-- @param module_name string: Name of the module (e.g., "State", "HandSize", "Hooks")
-- @return function: A log(level, msg) function for that module
--   level: "error", "warning", "info", or "debug"
--   - error/warning: Always visible
--   - info/debug: Only visible when debug mode config is enabled
function M.create(module_name)
    return function(level, msg)
        if not should_log(level) then return end
        pcall(print, format_message(module_name, level, msg))
    end
end

--- Simple log function (no module name, used by main.lua/init)
-- @param level string: Log level ("error", "warning", "info", or "debug")
-- @param msg string: Log message
function M.log(level, msg)
    if not should_log(level) then return end
    pcall(print, format_message(nil, level, msg))
end

return M

--[[
USAGE:

1. In a module file (e.g., Core/State.lua):
   local Logger = require("Utils.Logger")
   local log = Logger.create("State")
   
   log("info", "Chain state reset")
   log("error", "Failed to persist state: " .. err)

2. In main.lua (without module name):
   local Logger = require("Utils.Logger")
   Logger.log("info", "CrimsonGift initialized")
   Logger.log("warning", "SMODS inactive")

3. Output format:
   [CrimsonGift][State][info] Chain state reset
   [CrimsonGift][error] Failed to persist state: ...
]]
