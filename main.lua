--- CrimsonGift - Crimson Heart's Gift
-- When a joker that increases hand size gets disabled by Crimson Heart,
-- the max hand size for that run is permanently increased by that amount.
--
-- This is an intentional feature (not a bug) that makes Crimson Heart
-- a strategic choice for endless mode runs.

-- ==================================================
-- GLOBAL STATE INITIALIZATION
-- ==================================================

CRIMSON_GIFT = CRIMSON_GIFT or {}

-- Early SMODS check
if not SMODS then
    CRIMSON_GIFT.disabled = true
    return
end

-- ==================================================
-- MOD METADATA & CONFIG
-- ==================================================

CRIMSON_GIFT.mod = SMODS.current_mod
CRIMSON_GIFT.localization_loaded = false

-- Initialize config with defaults
CRIMSON_GIFT.config = CRIMSON_GIFT.mod.config or {}
if CRIMSON_GIFT.config.debug_logs == nil then
    CRIMSON_GIFT.config.debug_logs = false
end
if CRIMSON_GIFT.config.notifications_enabled == nil then
    CRIMSON_GIFT.config.notifications_enabled = true
end
CRIMSON_GIFT.mod.config = CRIMSON_GIFT.config

-- Debug helpers
CRIMSON_GIFT.debug_last = CRIMSON_GIFT.debug_last or {}

-- State variables (will be initialized by State module)
CRIMSON_GIFT.permanent_hand_size_increase = 0
CRIMSON_GIFT.processing_crimson_heart = false
CRIMSON_GIFT.preserved_h_size_from_disabled = 0
CRIMSON_GIFT.max_h_size_excluding_last = 0
CRIMSON_GIFT.first_h_size_in_chain = true
CRIMSON_GIFT.apply_sequence = 0
CRIMSON_GIFT.using_smods = false
CRIMSON_GIFT.boss_defeat_processed = false

-- ==================================================
-- LOAD MODULES
-- ==================================================

-- Helper to load and return a module from file
local function load_module(path)
    local chunk, err = SMODS.load_file(path)
    if not chunk then
        error("Failed to load module " .. path .. ": " .. tostring(err))
    end
    return chunk()
end

-- Load all modules
local Logger = load_module("Utils/Logger.lua")
local Notification = load_module("Utils/Notification.lua")
local State = load_module("Core/State.lua")
local HandSize = load_module("Core/HandSize.lua")
local Hooks = load_module("Core/Hooks.lua")

-- ==================================================
-- LOCALIZATION
-- ==================================================

local function load_localization()
    if CRIMSON_GIFT.localization_loaded then return end
    if not (SMODS and SMODS.handle_loc_file and CRIMSON_GIFT.mod and CRIMSON_GIFT.mod.path and CRIMSON_GIFT.mod.id) then
        return
    end
    
    SMODS.handle_loc_file(CRIMSON_GIFT.mod.path, CRIMSON_GIFT.mod.id)
    CRIMSON_GIFT.localization_loaded = true
end

-- ==================================================
-- UI MODULE
-- ==================================================

local function load_ui_module()
    if not (SMODS and SMODS.load_file and CRIMSON_GIFT.mod) then
        Logger.log("warning", "Cannot load UI module: SMODS not available")
        return
    end
    
    local chunk, err = SMODS.load_file("ui.lua")
    if chunk then
        pcall(chunk)
        Logger.log("info", "UI module loaded")
    else
        Logger.log("error", "UI module load failed: " .. tostring(err))
    end
end

-- ==================================================
-- CONFIG TAB
-- ==================================================

local function setup_config_tab()
    if not (SMODS and SMODS.current_mod) then return end
    
    SMODS.current_mod.config_tab = function()
        load_localization()
        
        return {
            n = G.UIT.ROOT,
            config = { r = 0.1, minw = 8, align = "tm", padding = 0.2, colour = G.C.BLACK },
            nodes = {
                {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0.05 },
                    nodes = {
                        create_toggle({
                            label = (localize and localize("crimsongift_notifications_enabled")) or "Enable notifications",
                            ref_table = CRIMSON_GIFT.config,
                            ref_value = "notifications_enabled",
                        }),
                    },
                },
                {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0.05 },
                    nodes = {
                        create_toggle({
                            label = (localize and localize("crimsongift_debug_logs")) or "Debug: verbose logging",
                            ref_table = CRIMSON_GIFT.config,
                            ref_value = "debug_logs",
                        }),
                    },
                },
            },
        }
    end
end

-- ==================================================
-- INITIALIZATION
-- ==================================================

local function init_crimson_gift()
    -- Check required classes
    if not (Blind and Card and CardArea and Game) then
        Logger.log("error", "Required game classes not available")
        return false
    end
    
    -- Load localization
    load_localization()
    
    -- Initialize notification system (localize should be available now)
    Logger.log("debug", "Attempting to initialize notifications, localize available: " .. tostring(localize ~= nil))
    if localize then
        Notification.init(CRIMSON_GIFT.config, localize)
        Logger.log("debug", "Notification.init called")
    else
        Logger.log("warning", "localize function not available, notifications may not work")
    end
    
    -- Install game hooks
    local hooks_installed = Hooks.install()
    if not hooks_installed then
        Logger.log("error", "Failed to install game hooks")
        return false
    end
    
    -- Load UI module
    load_ui_module()
    
    -- Setup config tab
    setup_config_tab()
    
    Logger.log("info", "CrimsonGift initialized successfully")
    return true
end

-- ==================================================
-- RUN INITIALIZATION
-- ==================================================

-- Initialize immediately (all classes should be loaded by now)
init_crimson_gift()
