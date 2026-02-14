--- CrimsonGift - State.lua
--
-- State management for Crimson Gift mod.
-- Handles persistence, chain tracking, and state synchronization.

local M = {}

-- Load Logger module
local Logger = (function()
    local chunk = SMODS.load_file("Utils/Logger.lua")
    return chunk and chunk() or nil
end)()
local log = Logger and Logger.create("State") or function() end

--- Initialize state for a new run
function M.init()
    -- These are stored in CRIMSON_GIFT global (volatile)
    CRIMSON_GIFT.permanent_hand_size_increase = 0
    CRIMSON_GIFT.preserved_h_size_from_disabled = 0
    CRIMSON_GIFT.max_h_size_excluding_last = 0
    CRIMSON_GIFT.first_h_size_in_chain = true
    CRIMSON_GIFT.processing_crimson_heart = false
    CRIMSON_GIFT.boss_defeat_processed = false
    CRIMSON_GIFT.apply_sequence = 0
    CRIMSON_GIFT.using_smods = false
    
    log("info", "State initialized")
end

--- Reset chain state (called after chain finalized or boss defeated)
function M.reset_chain()
    CRIMSON_GIFT.preserved_h_size_from_disabled = 0
    CRIMSON_GIFT.max_h_size_excluding_last = 0
    CRIMSON_GIFT.first_h_size_in_chain = true
    
    log("debug", "Chain state reset")
end

--- Persist state to G.GAME.crimson_gift (for save compatibility)
function M.save()
    if not (G and G.GAME) then
        log("warning", "Cannot save state: G or G.GAME not available")
        return
    end
    
    G.GAME.crimson_gift = G.GAME.crimson_gift or {}
    local saved = G.GAME.crimson_gift
    
    -- Cache previous values to detect changes
    local prev_permanent = saved.permanent or 0
    local prev_preserved = saved.preserved_h_size or 0
    
    saved.permanent = CRIMSON_GIFT.permanent_hand_size_increase or 0
    saved.preserved_h_size = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
    saved.max_h_size_excluding_last = CRIMSON_GIFT.max_h_size_excluding_last or 0
    saved.first_h_size_in_chain = CRIMSON_GIFT.first_h_size_in_chain
    saved.original_base = (G.hand and G.hand.config and G.hand.config.crimson_gift_original_base) or saved.original_base
    saved.using_smods = CRIMSON_GIFT.using_smods or false
    
    -- Only log when state actually changes
    if prev_permanent ~= saved.permanent or prev_preserved ~= saved.preserved_h_size then
        log("debug", string.format("State saved: permanent=%d, preserved=%d", 
            saved.permanent, saved.preserved_h_size))
    end
end

--- Restore state from G.GAME.crimson_gift (on load)
function M.restore()
    if not (G and G.GAME and G.GAME.crimson_gift) then
        log("info", "No saved state to restore")
        return
    end
    
    local saved = G.GAME.crimson_gift
    
    CRIMSON_GIFT.permanent_hand_size_increase = saved.permanent or 0
    CRIMSON_GIFT.preserved_h_size_from_disabled = saved.preserved_h_size or 0
    CRIMSON_GIFT.max_h_size_excluding_last = saved.max_h_size_excluding_last or 0
    CRIMSON_GIFT.first_h_size_in_chain = saved.first_h_size_in_chain ~= false
    CRIMSON_GIFT.using_smods = saved.using_smods or CRIMSON_GIFT.using_smods
    
    if G.hand and G.hand.config and saved.original_base then
        G.hand.config.crimson_gift_original_base = saved.original_base
    end
    
    log("info", string.format("State restored: permanent=%d, preserved=%d", 
        CRIMSON_GIFT.permanent_hand_size_increase, 
        CRIMSON_GIFT.preserved_h_size_from_disabled))
end

-- Export save function to global for cross-module access (avoids circular dependency)
CRIMSON_GIFT._State_save = M.save

return M
