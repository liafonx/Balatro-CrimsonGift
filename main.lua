--- CrimsonGift - Crimson Heart's Gift
-- When a joker that increases hand size gets disabled by Crimson Heart,
-- the max hand size for that run is permanently increased by that amount.
--
-- This is an intentional feature (not a bug) that makes Crimson Heart
-- a strategic choice for endless mode runs.

CRIMSON_GIFT = CRIMSON_GIFT or {}

-- Track permanent hand size increases from Crimson Heart
-- This is added to the base hand size limit
CRIMSON_GIFT.permanent_hand_size_increase = 0

-- Track if we're currently processing a Crimson Heart disable cycle
CRIMSON_GIFT.processing_crimson_heart = false

-- Track the last disabled joker's hand_size status
-- Only grant permanent increase when a hand_size joker is disabled after a non-hand_size joker
CRIMSON_GIFT.last_disabled_h_size = 0

-- Track pending hand size increase (will be applied after next hand is played)
-- Only applied if boss is not defeated in that hand
CRIMSON_GIFT.pending_hand_size_increase = 0

-- Track which jokers have already been processed in the current disable cycle
-- Prevents multiple additions from the same disable event
CRIMSON_GIFT.processed_jokers_this_cycle = {}

-- Monotonic counter used to invalidate older deferred events
CRIMSON_GIFT.apply_sequence = 0

-- Whether SMODS hand limit handling is active for this run/session
CRIMSON_GIFT.using_smods = false

-- Require SMODS; no vanilla support.
if not SMODS then
    CRIMSON_GIFT.disabled = true
    return
end

CRIMSON_GIFT.mod = SMODS.current_mod
CRIMSON_GIFT.localization_loaded = false

CRIMSON_GIFT.config = CRIMSON_GIFT.mod.config or {}
if CRIMSON_GIFT.config.debug_logs == nil then
    CRIMSON_GIFT.config.debug_logs = false
end
CRIMSON_GIFT.mod.config = CRIMSON_GIFT.config

CRIMSON_GIFT.log_tags = {
    warn = true,
    error = true,
}

-- Logger function (similar to Save Rewinder)
local function log(tag, msg)
    if not CRIMSON_GIFT.log_tags[tostring(tag)] then return end
    local full_msg = "[CrimsonGift][" .. tostring(tag) .. "] " .. tostring(msg)
    pcall(print, full_msg)
end

local function log_debug(msg)
    if not (CRIMSON_GIFT.config and CRIMSON_GIFT.config.debug_logs) then return end
    local full_msg = "[CrimsonGift][debug] " .. tostring(msg)
    pcall(print, full_msg)
end

-- Store original functions (will be set during initialization)
local _Blind_drawn_to_hand = nil
local _Card_remove_from_deck = nil
local _Game_start_run = nil

-- Detect whether SMODS' hand limit system is active
local function is_smods_active()
    return SMODS and CardArea and CardArea.handle_card_limit and SMODS.should_handle_limit
end

local function load_crimson_gift_localization()
    if CRIMSON_GIFT.localization_loaded then return end
    if not (SMODS and SMODS.handle_loc_file and CRIMSON_GIFT.mod and CRIMSON_GIFT.mod.path and CRIMSON_GIFT.mod.id) then
        return
    end

    SMODS.handle_loc_file(CRIMSON_GIFT.mod.path, CRIMSON_GIFT.mod.id)
    CRIMSON_GIFT.localization_loaded = true
end

local function get_hand_limit_summary()
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

-- Safely extract the hand-size contribution from a joker card
local function get_card_hand_size(card)
    if not card or not card.ability then return 0 end
    local h_size = card.ability.h_size or 0
    if card.ability.extra and type(card.ability.extra) == "table" and card.ability.extra.h_size then
        h_size = h_size + card.ability.extra.h_size
    end
    return h_size
end

-- Ensure base tracking fields exist and are up to date
local function sync_base_tracking()
    if not (G and G.hand and G.GAME and G.GAME.starting_params) then return end
    if not G.hand.config.crimson_gift_original_base then
        G.hand.config.crimson_gift_original_base = G.GAME.starting_params.hand_size
    end
    G.hand.config.crimson_gift_base_with_permanent =
        (G.hand.config.crimson_gift_original_base or G.GAME.starting_params.hand_size) +
        (CRIMSON_GIFT.permanent_hand_size_increase or 0)
end

-- Keep UI-only display limits in sync without mutating SMODS' real limit math.
local function sync_display_limit()
    if not (G and G.hand and G.hand.config) then return end

    local pending = CRIMSON_GIFT.pending_hand_size_increase or 0

    if G.hand.config.card_limits then
        local limits = G.hand.config.card_limits
        local total_slots = limits.total_slots
            or (limits.extra_slots or 0) + (limits.base or 0) + (limits.mod or 0) + (limits.crimson_gift_mod or 0)
        local effective_limit = total_slots - (limits.extra_slots_used or 0)

        -- SMODS UI ref value (patched in lovely.toml)
        limits.crimson_gift_display_total_slots = total_slots + pending

        -- Vanilla-style UI ref value (also patched)
        G.hand.config.crimson_gift_display_limit = effective_limit + pending
    else
        local limit = G.hand.config.card_limit or G.hand.config.real_card_limit or 0
        G.hand.config.crimson_gift_display_limit = limit + pending
    end
end

CRIMSON_GIFT.sync_display_limit = sync_display_limit

-- Persist Crimson Gift state into the run save table (G.GAME).
local function sync_persistent_state()
    if not (G and G.GAME) then return end
    G.GAME.crimson_gift = G.GAME.crimson_gift or {}
    local saved = G.GAME.crimson_gift
    saved.permanent = CRIMSON_GIFT.permanent_hand_size_increase or 0
    saved.pending = CRIMSON_GIFT.pending_hand_size_increase or 0
    saved.last_disabled_h_size = CRIMSON_GIFT.last_disabled_h_size or 0
    saved.original_base = (G.hand and G.hand.config and G.hand.config.crimson_gift_original_base) or saved.original_base
    saved.using_smods = CRIMSON_GIFT.using_smods or false
end

-- Restore Crimson Gift state from the run save table (G.GAME).
local function restore_persistent_state()
    if not (G and G.GAME and G.GAME.crimson_gift) then return end
    local saved = G.GAME.crimson_gift
    CRIMSON_GIFT.permanent_hand_size_increase = saved.permanent or 0
    CRIMSON_GIFT.pending_hand_size_increase = saved.pending or 0
    CRIMSON_GIFT.last_disabled_h_size = saved.last_disabled_h_size or 0
    CRIMSON_GIFT.using_smods = saved.using_smods or CRIMSON_GIFT.using_smods

    if G.hand and G.hand.config and saved.original_base then
        G.hand.config.crimson_gift_original_base = saved.original_base
    end
end

-- Draw cards up to the given target limit without modifying the limit again
local function draw_missing_cards(target_limit)
    if not (G and G.hand and G.deck and target_limit) then return end
    if not draw_card then
        log("warn", "CrimsonGift: draw_card is unavailable; cannot fill to new hand limit")
        return
    end

    local current_cards = #G.hand.cards
    local limit = math.max(0, math.floor(target_limit))
    local to_draw = math.min(limit - current_cards, #G.deck.cards)

    if to_draw <= 0 then return end

    for i = 1, to_draw do
        if (#G.hand.cards + 1) <= limit and #G.deck.cards > 0 then
            draw_card(G.deck, G.hand, i * 100 / to_draw, nil, nil, nil, 0.07)
        end
    end

    if G.hand.sort and G.E_MANAGER and Event then
        G.E_MANAGER:add_event(Event({
            func = function()
                G.hand:sort()
                return true
            end
        }))
    end
end

-- Apply a permanent increase in SMODS by modifying card_limits and reconciling
local function schedule_smods_delta(delta)
    if not (delta and delta ~= 0 and G and G.hand and G.E_MANAGER and Event) then return end

    local hand = G.hand
    local limits = hand.config and hand.config.card_limits
    if not limits then
        log("warn", "CrimsonGift: SMODS card_limits missing; skipping permanent increase")
        return
    end

    local old_total = limits.total_slots or hand.config.card_limit or 0
    -- IMPORTANT: do not write to config.card_limit in SMODS, it mutates card_limits.mod.
    -- Instead, update our dedicated mod field and let handle_card_limit recompute totals.
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

                sync_base_tracking()

                local h = G.hand
                local l = h.config.card_limits

                -- Preserve the pre-change slot count so SMODS can draw the delta in SELECTING_HAND
                if not seeded_old_slots then
                    local prev_old_slots = l.old_slots or old_total
                    l.old_slots = math.min(prev_old_slots, old_total)
                    seeded_old_slots = true
                end

                if h.handle_card_limit then
                    h:handle_card_limit()
                end

                -- In SMODS, the effective limit is total_slots minus extra_slots_used.
                local effective_limit =
                    (l.total_slots or (old_total + delta)) - (l.extra_slots_used or 0)

                if not logged_reconcile then
                    local base, permanent, effective, total = get_hand_limit_summary()
                    log_debug(string.format(
                        "Applied gift +%d: base=%d, permanent=%d, limit=%d, total_slots=%d",
                        delta, base or 0, permanent or 0, effective or 0, total or 0
                    ))
                    logged_reconcile = true
                end

                sync_display_limit()
                sync_persistent_state()
                draw_missing_cards(effective_limit)

                -- Mark the slot history as caught up to avoid repeated auto-draws later in SELECTING_HAND.
                if l.total_slots then
                    l.old_slots = l.total_slots
                end
                return true
            end
        }))
    end

    reconcile_once(0.05)
    reconcile_once(0.20)
end

-- Show notification when Crimson's Gift is granted
-- Based on Brainstorm-Rerolled's saveManagerAlert() method
local function crimsonGiftAlert(h_size)
    if not G or not G.E_MANAGER or not Event then return end

    local text = string.format(localize("crimson_gift_arriving"), h_size)
    
    -- Use red color for Crimson Heart theme (with alpha for backdrop)
    -- Color format: {r, g, b, alpha}
    local backdrop_colour = {1, 0, 0, 0.5}  -- Red
    
    G.E_MANAGER:add_event(Event({
        trigger = "after",
        delay = 1.0,  -- Increased delay so notification appears after the disable animation
        func = function()
            attention_text({
                text = text,
                scale = 0.7,
                hold = 18,  -- Longer notification duration
                major = G.STAGE == G.STAGES.RUN and G.play or G.title_top,
                backdrop_colour = backdrop_colour,
                align = "cm",
                offset = {
                    x = 0,
                    y = -2.5,
                },
                silent = true,
            })
            G.E_MANAGER:add_event(Event({
                trigger = "after",
                delay = 0.06 * (G.SETTINGS and G.SETTINGS.GAMESPEED or 1),
                blockable = false,
                blocking = false,
                func = function()
                    play_sound("other1", 0.76, 0.4)
                    return true
                end,
            }))
            return true
        end,
    }))
end

-- Show notification when a pending gift is lost due to defeating the boss
local function crimsonGiftLostAlert()
    if not G or not G.E_MANAGER or not Event then return end
    local text = localize("crimson_gift_lost")
    local backdrop_colour = {0.8, 0, 0, 0.35}

    G.E_MANAGER:add_event(Event({
        trigger = "after",
        delay = 0.6,
        func = function()
            attention_text({
                text = text,
                scale = 0.7,
                hold = 10,
                major = G.STAGE == G.STAGES.RUN and G.play or G.title_top,
                backdrop_colour = backdrop_colour,
                align = "cm",
                offset = { x = 0, y = -2.5 },
                silent = true,
            })
            G.E_MANAGER:add_event(Event({
                trigger = "after",
                delay = 0.06 * (G.SETTINGS and G.SETTINGS.GAMESPEED or 1),
                blockable = false,
                blocking = false,
                func = function()
                    play_sound("cancel", 0.8, 0.5)
                    return true
                end,
            }))
            return true
        end,
    }))
end

-- Initialize hooks after classes are loaded
local function init_crimson_gift()
    -- Check if all required classes are available
    if not Blind or not Card or not CardArea or not Game then
        return false
    end
    
    -- Only initialize once
    if _Blind_drawn_to_hand then
        return true
    end
    
    -- Store original functions
    _Blind_drawn_to_hand = Blind.drawn_to_hand
    _Card_remove_from_deck = Card.remove_from_deck
    _Game_start_run = Game.start_run

    -- Load UI hooks
    if SMODS and SMODS.load_file and CRIMSON_GIFT.mod then
        local chunk, err = SMODS.load_file("ui.lua")
        if chunk then
            pcall(chunk)
        else
            log("error", "CrimsonGift: UI load failed: " .. tostring(err))
        end
    end

    if SMODS and SMODS.current_mod then
        SMODS.current_mod.config_tab = function()
            load_crimson_gift_localization()

            return {
                n = G.UIT.ROOT,
                config = { r = 0.1, minw = 8, align = "tm", padding = 0.2, colour = G.C.BLACK },
                nodes = {
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
    
    -- Hook Game:update_hand_played to detect when a hand is completed
    -- Apply pending increases only if boss is not defeated
    local _Game_update_hand_played = Game.update_hand_played
    function Game:update_hand_played(dt)
        local result = _Game_update_hand_played(self, dt)
        
        -- Check if hand just completed and we have pending increases
        -- Only apply if boss is not defeated
        if CRIMSON_GIFT.pending_hand_size_increase > 0 and G.GAME and G.GAME.blind then
            local boss_defeated = false
            if G.GAME.blind.boss then
                boss_defeated = (G.GAME.chips - G.GAME.blind.chips) >= 0
            end
            local pending_to_apply = CRIMSON_GIFT.pending_hand_size_increase
            
            -- Clear pending immediately so older deferred events cannot re-apply it
            CRIMSON_GIFT.pending_hand_size_increase = 0
            sync_display_limit()
            if G.hand and G.hand.children then
                G.hand.children.crimson_gift_indicator = nil
            end
            sync_persistent_state()
            
            -- Only apply if boss was NOT defeated
            if not boss_defeated then
                if not CRIMSON_GIFT.using_smods then
                    log("warn", "CrimsonGift: SMODS hand-limit handler inactive after start_run; skipping permanent increase")
                    return result
                end

                CRIMSON_GIFT.permanent_hand_size_increase = CRIMSON_GIFT.permanent_hand_size_increase + pending_to_apply
                sync_base_tracking()
                sync_persistent_state()

                if G.hand then
                    schedule_smods_delta(pending_to_apply)
                end
            else
                log_debug(string.format(
                    "Gift lost: boss defeated, pending=%d",
                    pending_to_apply
                ))
                crimsonGiftLostAlert()
            end
        end
        
        return result
    end
    
    -- Hook Blind:drawn_to_hand to detect Crimson Heart cycles
    function Blind:drawn_to_hand()
        if self.name == 'Crimson Heart' and self.prepped then
            CRIMSON_GIFT.processing_crimson_heart = true
            -- Reset tracking at the start of each Crimson Heart cycle
            CRIMSON_GIFT.last_disabled_h_size = 0
            CRIMSON_GIFT.processed_jokers_this_cycle = {}  -- Reset processed jokers table
        end
        
        local result = _Blind_drawn_to_hand(self)
        
        if self.name == 'Crimson Heart' then
            CRIMSON_GIFT.processing_crimson_heart = false
            -- Clear processed jokers after cycle completes
            CRIMSON_GIFT.processed_jokers_this_cycle = {}
        end
        
        return result
    end
    
    -- Hook Card:remove_from_deck to detect when hand_size jokers are disabled by Crimson Heart
    function Card:remove_from_deck(from_debuff)
        -- Let the normal decrease happen first
        local result = _Card_remove_from_deck(self, from_debuff)
        
        -- Then grant permanent increase if this is a Crimson Heart disable cycle
        -- Original bug behavior: only grant increase when a hand_size joker is disabled
        -- AFTER a non-hand_size joker was disabled (not consecutively)
        if from_debuff and CRIMSON_GIFT.processing_crimson_heart and self.area == G.jokers then
            -- Use the card object itself as a per-cycle dedupe key.
            -- This is robust against re-sorting or position changes mid-cycle.
            local card_key = self
            local card_name = (self.ability and self.ability.name) or "unknown"

            if not CRIMSON_GIFT.processed_jokers_this_cycle[card_key] then
                CRIMSON_GIFT.processed_jokers_this_cycle[card_key] = true

                local h_size = get_card_hand_size(self)

                -- Only grant pending increase if:
                -- 1. This joker has hand_size > 0
                -- 2. Last disabled joker had hand_size == 0 (non-hand_size joker) OR this is the first joker disabled
                if h_size > 0 and CRIMSON_GIFT.last_disabled_h_size == 0 then
                    CRIMSON_GIFT.pending_hand_size_increase = CRIMSON_GIFT.pending_hand_size_increase + h_size

                    log_debug(string.format(
                        "Hand-size Joker disabled: %s (h_size=%d), pending=%d",
                        card_name, h_size, CRIMSON_GIFT.pending_hand_size_increase
                    ))

                    crimsonGiftAlert(h_size)
                end

                -- Update last disabled joker's hand_size status
                CRIMSON_GIFT.last_disabled_h_size = h_size
                sync_display_limit()
                sync_persistent_state()
            end
        end
        
        return result
    end
    
    -- For SMODS compatibility: Hook handle_card_limit to add permanent increase
    if CardArea.handle_card_limit then
        local _CardArea_handle_card_limit = CardArea.handle_card_limit
        function CardArea:handle_card_limit()
            local result = _CardArea_handle_card_limit(self)
            
            if self == G.hand and CRIMSON_GIFT.using_smods and self.config.card_limits then
                sync_base_tracking()

                local limits = self.config.card_limits
                limits.crimson_gift_mod = CRIMSON_GIFT.permanent_hand_size_increase or 0

                -- Recalculate total_slots to include Crimson Gift's permanent increase
                limits.total_slots =
                    (limits.extra_slots or 0) +
                    (limits.base or 0) +
                    (limits.mod or 0) +
                    (limits.crimson_gift_mod or 0)

                sync_display_limit()
                sync_persistent_state()
            end
            
            return result
        end
    end
    
    -- Initialize tracking on run start
    function Game:start_run(args)
        CRIMSON_GIFT.permanent_hand_size_increase = 0
        CRIMSON_GIFT.processing_crimson_heart = false
        CRIMSON_GIFT.last_disabled_h_size = 0
        CRIMSON_GIFT.pending_hand_size_increase = 0
        CRIMSON_GIFT.processed_jokers_this_cycle = {}
        CRIMSON_GIFT.apply_sequence = 0

        local ret = _Game_start_run(self, args)

        -- Detect SMODS after the run has been initialized
        CRIMSON_GIFT.using_smods = is_smods_active() and SMODS.should_handle_limit(G.hand)
        if not CRIMSON_GIFT.using_smods then
            log("warn", "CrimsonGift: start_run called (new run or loaded save) but SMODS hand-limit handler is inactive; CrimsonGift will stay idle")
        end

        -- Load localization once per session after G is initialized
        load_crimson_gift_localization()

        -- Store original hand size base for this run and sync derived values
        if G.hand and G.GAME and G.GAME.starting_params then
            G.hand.config.crimson_gift_original_base = G.GAME.starting_params.hand_size
            sync_base_tracking()
            sync_display_limit()

        end

        -- Ensure SMODS structures exist for our mod field, if applicable
        if CRIMSON_GIFT.using_smods and G.hand and G.hand.config and G.hand.config.card_limits then
            G.hand.config.card_limits.crimson_gift_mod = 0
        end

        -- Restore persisted state (e.g., Save Rewinder / continue run)
        restore_persistent_state()
        sync_base_tracking()
        sync_display_limit()
        sync_persistent_state()

        return ret
    end
    
    return true
end

-- Initialize hooks immediately
-- Since this mod is appended to main.lua, all classes should be loaded by now
init_crimson_gift()
