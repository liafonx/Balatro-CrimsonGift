--- CrimsonGift - Notification.lua
--
-- Centralized notification/alert system for Crimson Gift mod.
-- Displays speed-independent notifications with styled text highlighting.

local M = {}

-- Load Logger module
local Logger = (function()
    local chunk = SMODS.load_file("Utils/Logger.lua")
    return chunk and chunk() or nil
end)()
-- Logger.create returns a function(level, msg), so fallback must match
local log = Logger and Logger.create("Notification") or function(level, msg) end

-- Module state
local panel = {
    element = nil,
    timer = 0,
    duration = 3.0,  -- Default duration in real-time seconds
    message = "",
    colour = {1, 0, 0, 0.5},
}

-- Configuration (will be set during init)
local config = nil
local localize_fn = nil

-- Notification styling
local STYLE = {
    -- Background color for notification panel (r, g, b, alpha)
    background = {0.2, 0.2, 0.2, 0.4},
    
    -- Text colors
    text_color = G.C.UI.TEXT_LIGHT,
    highlight_color = {0.751, 0.178, 0.182, 1},  -- Crimson red (HEX ac3232)
    number_color = {1.0, 0.604, 0.0, 1.0},       -- Orange (HEX ff9a00)
    
    -- Font scales
    text_scale = 0.6,
    highlight_scale = 0.7,
}

-- Alert preset defaults
local ALERT_DEFAULTS = {
    backdrop_colour = STYLE.background,
    sound = "other1",
    sound_volume = 0.4,
}

-- Alert presets for different notification types
-- IMPORTANT: hold/delay values are in SECONDS (real-time, not affected by game speed)
local ALERT_PRESETS = {
    arriving = {
        loc_key = "crimson_gift_arriving",
        delay = 1.0, hold = 2.5,
        sound_pitch = 0.76,
    },
    applied = {
        loc_key = "crimson_gift_applied",
        delay = 1.0, hold = 2.0,
        sound_pitch = 0.75,
    },
    lost = {
        loc_key = "crimson_gift_lost",
        delay = 0.6, hold = 2.0,
        sound = "cancel",
        sound_pitch = 0.8,
        sound_volume = 0.5,
    },
    keep_larger = {
        loc_key = "crimson_gift_keep_larger",
        delay = 0.6, hold = 2.0,
        sound_pitch = 0.6,
        sound_volume = 0.35,
    },
    keep_largest = {
        loc_key = "crimson_gift_keep_largest",
        delay = 0.6, hold = 2.0,
        sound_pitch = 0.6,
        sound_volume = 0.35,
    },
}

-- Merge preset with defaults
local function get_preset(alert_type)
    local preset = ALERT_PRESETS[alert_type]
    if not preset then return nil end
    
    return {
        loc_key = preset.loc_key,
        delay = preset.delay,
        hold = preset.hold,
        backdrop_colour = preset.backdrop_colour or ALERT_DEFAULTS.backdrop_colour,
        sound = preset.sound or ALERT_DEFAULTS.sound,
        sound_pitch = preset.sound_pitch,
        sound_volume = preset.sound_volume or ALERT_DEFAULTS.sound_volume,
    }
end

--- Helper to create a text node with appropriate styling
local function create_text_node(text, is_highlighted, is_number)
    return {
        n = G.UIT.T,
        config = {
            text = text,
            scale = is_number and STYLE.highlight_scale or STYLE.text_scale,
            colour = is_number and STYLE.number_color 
                     or (is_highlighted and STYLE.highlight_color or STYLE.text_color),
            shadow = true,
        },
    }
end

--- Parse text and highlight key terms/numbers
local function parse_highlighted_text(text)
    local nodes = {}
    local remaining = text
    
    -- Patterns to highlight
    local highlight_patterns = {
        {pattern = "%+%d+", is_number = true},         -- +N numbers
        {pattern = "绯红之心", is_number = false},       -- Crimson Heart (Chinese)
        {pattern = "绯红恩赐", is_number = false},       -- Crimson Gift (Chinese)
        {pattern = "Crimson Heart", is_number = false},
        {pattern = "Crimson Gift", is_number = false},
    }
    
    while remaining and remaining ~= "" do
        local earliest_pos = nil
        local earliest_match = nil
        local earliest_pattern = nil
        
        -- Find earliest match
        for _, p in ipairs(highlight_patterns) do
            local start_pos, end_pos = remaining:find(p.pattern)
            if start_pos and (not earliest_pos or start_pos < earliest_pos) then
                earliest_pos = start_pos
                earliest_match = remaining:sub(start_pos, end_pos)
                earliest_pattern = p
            end
        end
        
        if earliest_match then
            -- Add text before match
            if earliest_pos > 1 then
                local before = remaining:sub(1, earliest_pos - 1)
                table.insert(nodes, create_text_node(before, false, false))
            end
            
            -- Add highlighted match (add padding for numbers)
            local display_text = earliest_pattern.is_number and (" " .. earliest_match .. " ") or earliest_match
            table.insert(nodes, create_text_node(display_text, true, earliest_pattern.is_number))
            
            -- Continue with remaining
            remaining = remaining:sub(earliest_pos + #earliest_match)
        else
            -- No more matches, add remaining text
            if remaining ~= "" then
                table.insert(nodes, create_text_node(remaining, false, false))
            end
            break
        end
    end
    
    return nodes
end

--- Create UI definition for notification panel
local function create_panel_definition()
    local msg = panel.message or ""
    local text_nodes = parse_highlighted_text(msg)
    
    return {
        n = G.UIT.ROOT,
        config = {
            align = "cm",
            padding = 0.1,
            r = 0.1,
            colour = panel.colour,
        },
        nodes = {
            {
                n = G.UIT.R,
                config = {
                    align = "cm",
                    padding = 0.05,
                },
                nodes = text_nodes,
            },
        },
    }
end

--- Show notification panel
local function show_panel(text, colour, duration)
    if not G or not G.ROOM_ATTACH then return end
    
    -- Remove old panel
    if panel.element then
        panel.element:remove()
        panel.element = nil
    end
    
    -- Set panel data
    panel.message = text
    panel.colour = colour or {1, 0, 0, 0.5}
    panel.timer = duration or panel.duration
    
    -- Create new panel
    panel.element = UIBox({
        definition = create_panel_definition(),
        config = {
            instance_type = "ALERT",
            align = "cm",
            major = G.ROOM_ATTACH,
            offset = {x = 0, y = -2.0},  -- Above chips, below blind
            can_collide = false,
        },
    })
end

--- Initialize notification system
-- @param mod_config table: Mod configuration (for notifications_enabled check)
-- @param localize_func function: Localization function
function M.init(mod_config, localize_func)
    config = mod_config
    localize_fn = localize_func
    log("info", "Notification system initialized")
end

--- Show an alert notification
-- @param alert_type string: Alert type key (arriving, applied, lost, keep_larger, keep_largest)
-- @param value number: Optional value for formatted messages
function M.show(alert_type, value)
    -- Read config directly from global to avoid stale reference issues
    local current_config = CRIMSON_GIFT and CRIMSON_GIFT.config
    local enabled = current_config and current_config.notifications_enabled
    
    log("debug", string.format("show() called: alert_type=%s, value=%s, config=%s, enabled=%s", 
        tostring(alert_type), tostring(value), tostring(current_config ~= nil), tostring(enabled)))
    
    -- Check if notifications enabled
    if not enabled then
        log("debug", "Notifications disabled, returning early")
        return
    end
    
    if not G or not G.E_MANAGER or not Event then return end
    
    local preset = get_preset(alert_type)
    if not preset then
        log("warning", "Unknown alert type: " .. tostring(alert_type))
        return
    end
    
    -- Build text from localization (use global localize function)
    local text
    if value then
        text = string.format(localize(preset.loc_key), value)
    else
        text = localize(preset.loc_key)
    end
    
    -- Queue notification with sound
    G.E_MANAGER:add_event(Event({
        trigger = "after",
        delay = preset.delay,
        func = function()
            show_panel(text, preset.backdrop_colour, preset.hold)
            
            -- Play sound after short delay
            G.E_MANAGER:add_event(Event({
                trigger = "after",
                delay = 0.06,
                blockable = false,
                blocking = false,
                func = function()
                    play_sound(preset.sound, preset.sound_pitch, preset.sound_volume)
                    return true
                end,
            }))
            return true
        end,
    }))
    
    log("debug", string.format("Alert queued [%s]: %s", alert_type, text))
end

--- Update notification panel timer (call from Game:update hook)
-- @param dt number: Delta time in real-time seconds
function M.update(dt)
    if panel.timer > 0 then
        panel.timer = panel.timer - dt
        
        if panel.timer <= 0 and panel.element then
            panel.element:remove()
            panel.element = nil
        end
    end
end

return M
