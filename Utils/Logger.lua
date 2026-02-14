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

--- Create a logger for a specific module
-- @param module_name string: Name of the module (e.g., "State", "HandSize", "Hooks")
-- @return function: A log(level, msg) function for that module
--   level: "error", "warning", "info", or "debug"
--   - error/warning: Always visible
--   - info/debug: Only visible when debug mode config is enabled
function M.create(module_name)
    return function(level, msg)
        -- Check if we should log this level
        if not should_log(level) then
            return
        end

        -- Format message
        local full_msg
        if module_name and module_name ~= "" then
            if level and level ~= "" then
                full_msg = M._prefix .. "[" .. module_name .. "][" .. tostring(level) .. "] " .. tostring(msg)
            else
                full_msg = M._prefix .. "[" .. module_name .. "] " .. tostring(msg)
            end
        else
            full_msg = M._prefix .. " " .. tostring(msg)
        end

        -- Protected print (prevents crash if another mod has buggy print hook)
        pcall(print, full_msg)
    end
end

--- Simple log function (no module name, used by main.lua/init)
-- @param level string: Log level ("error", "warning", "info", or "debug")
-- @param msg string: Log message
function M.log(level, msg)
    if not should_log(level) then
        return
    end

    local full_msg
    if level and level ~= "" then
        full_msg = M._prefix .. "[" .. tostring(level) .. "] " .. tostring(msg)
    else
        full_msg = M._prefix .. " " .. tostring(msg)
    end

    pcall(print, full_msg)
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
