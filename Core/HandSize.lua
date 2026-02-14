--- CrimsonGift - HandSize.lua
--
-- Hand size calculation and SMODS integration logic.
-- Handles limit tracking, card h_size extraction, and gift application.

local M = {}

-- Load Logger module
local Logger = (function()
    local chunk = SMODS.load_file("Utils/Logger.lua")
    return chunk and chunk() or nil
end)()
local log = Logger and Logger.create("HandSize") or function() end

--- Check if SMODS hand limit system is active
local function is_smods_active()
    return SMODS and CardArea and CardArea.handle_card_limit and SMODS.should_handle_limit
end

--- Get card's hand size contribution
-- @param card table: Card to check
-- @return number: Hand size value from card
function M.from_card(card)
    if not card or not card.ability then return 0 end
    local h_size = card.ability.h_size or 0
    if card.ability.extra and type(card.ability.extra) == "table" and card.ability.extra.h_size then
        h_size = h_size + card.ability.extra.h_size
    end
    return h_size
end

--- Get comprehensive hand limit summary
-- @return base, permanent, effective, total (all numbers)
function M.get_summary()
    if not (G and G.hand and G.hand.config) then return nil end
    
    local base = (G.hand.config.crimson_gift_original_base)
        or (G.GAME and G.GAME.starting_params and G.GAME.starting_params.hand_size)
        or 0
    local permanent = CRIMSON_GIFT.permanent_hand_size_increase or 0
    
    if G.hand.config.card_limits then
        local limits = G.hand.config.card_limits
        local total = limits.total_slots
            or (limits.extra_slots or 0) + (limits.base or 0) + (limits.mod or 0) + (limits.crimson_gift_mod or 0)
        local effective = total - (limits.extra_slots_used or 0)
        return base, permanent, effective, total
    end
    
    local limit = G.hand.config.card_limit or G.hand.config.real_card_limit or 0
    return base, permanent, limit, limit
end

--- Sync base tracking (ensure original base is stored)
function M.sync_base()
    if not (G and G.hand and G.GAME and G.GAME.starting_params) then return end
    if not G.hand.config.crimson_gift_original_base then
        G.hand.config.crimson_gift_original_base = G.GAME.starting_params.hand_size
        log("debug", "Base hand size tracking initialized: " .. G.GAME.starting_params.hand_size)
    end
end

--- Sync display limits (for UI)
function M.sync_display()
    if not (G and G.hand and G.hand.config) then return end
    
    if G.hand.config.card_limits then
        local limits = G.hand.config.card_limits
        local total_slots = limits.total_slots
            or (limits.extra_slots or 0) + (limits.base or 0) + (limits.mod or 0) + (limits.crimson_gift_mod or 0)
        local effective_limit = total_slots - (limits.extra_slots_used or 0)
        
        -- Display refs equal real values (no compensation needed)
        limits.crimson_gift_display_total_slots = total_slots
        G.hand.config.crimson_gift_display_limit = effective_limit
    else
        local limit = G.hand.config.card_limit or G.hand.config.real_card_limit or 0
        G.hand.config.crimson_gift_display_limit = limit
    end
end

--- Apply permanent gift increase (SMODS integration)
-- @param delta number: Amount to increase hand size by
function M.apply_gift(delta)
    if not (delta and delta ~= 0 and G and G.hand and G.E_MANAGER and Event) then
        log("warning", "Cannot apply gift: missing requirements")
        return
    end
    
    local hand = G.hand
    local limits = hand.config and hand.config.card_limits
    if not limits then
        log("warning", "SMODS card_limits missing; skipping permanent increase")
        return
    end
    
    local old_total = limits.total_slots or hand.config.card_limit or 0
    
    -- Update our dedicated mod field (don't touch config.card_limit directly in SMODS)
    limits.crimson_gift_mod = CRIMSON_GIFT.permanent_hand_size_increase or limits.crimson_gift_mod or 0
    
    CRIMSON_GIFT.apply_sequence = (CRIMSON_GIFT.apply_sequence or 0) + 1
    local apply_id = CRIMSON_GIFT.apply_sequence
    local seeded_old_slots = false
    local logged_reconcile = false
    
    local function reconcile_once(delay)
        G.E_MANAGER:add_event(Event({
            trigger = "after",
            delay = delay,
            func = function()
                if apply_id ~= CRIMSON_GIFT.apply_sequence then return true end
                if not (G and G.hand and G.hand.config and G.hand.config.card_limits) then return true end
                
                M.sync_base()
                
                local h = G.hand
                local l = h.config.card_limits
                
                -- Preserve pre-change slot count for SMODS auto-draw
                if not seeded_old_slots then
                    local prev_old_slots = l.old_slots or old_total
                    l.old_slots = math.min(prev_old_slots, old_total)
                    seeded_old_slots = true
                end
                
                if h.handle_card_limit then
                    h:handle_card_limit()
                end
                
                local effective_limit = (l.total_slots or (old_total + delta)) - (l.extra_slots_used or 0)
                
                if not logged_reconcile then
                    local base, permanent, effective, total = M.get_summary()
                    local cards_in_hand = (G.hand and G.hand.cards and #G.hand.cards) or 0
                    local card_count = (h.config and h.config.card_count) or 0
                    
                    log("debug", string.format(
                        "Applied gift +%d: base=%d, permanent=%d, limit=%d, total_slots=%d, hand_cards=%d, card_count=%d, old_slots=%d, extra_used=%d",
                        delta,
                        base or 0,
                        permanent or 0,
                        effective or 0,
                        total or 0,
                        cards_in_hand,
                        card_count,
                        l.old_slots or 0,
                        l.extra_slots_used or 0
                    ))
                    logged_reconcile = true
                end
                
                M.sync_display()
                
                -- Persist state (call via global to avoid circular dependency)
                if CRIMSON_GIFT and CRIMSON_GIFT._State_save then
                    CRIMSON_GIFT._State_save()
                end
                
                -- Mark slot history as caught up
                if l.total_slots then
                    l.old_slots = l.total_slots
                end
                return true
            end
        }))
    end
    
    -- Schedule reconciliation at two points for robustness
    reconcile_once(0.05)
    reconcile_once(0.20)
    
    log("info", string.format("Gift application scheduled: +%d hand size", delta))
end

-- Export sync_display to CRIMSON_GIFT for UI.lua compatibility
CRIMSON_GIFT.sync_display_limit = M.sync_display

return M
