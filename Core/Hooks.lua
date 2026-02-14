--- CrimsonGift - Hooks.lua
--
-- Game hook installation and implementations.
-- Orchestrates all game event handling for Crimson Gift.

local M = {}

-- Load modules using SMODS.load_file
local Logger = (function()
    local chunk = SMODS.load_file("Utils/Logger.lua")
    return chunk and chunk() or nil
end)()
local Notification = (function()
    local chunk = SMODS.load_file("Utils/Notification.lua")
    return chunk and chunk() or nil
end)()
local State = (function()
    local chunk = SMODS.load_file("Core/State.lua")
    return chunk and chunk() or nil
end)()
local HandSize = (function()
    local chunk = SMODS.load_file("Core/HandSize.lua")
    return chunk and chunk() or nil
end)()

local log = Logger.create("Hooks")

-- Original function references (set during install)
local _Blind_drawn_to_hand = nil
local _Card_remove_from_deck = nil
local _CardArea_handle_card_limit = nil
local _Game_update = nil
local _Game_update_hand_played = nil
local _Game_start_run = nil

--- Check if SMODS is active
local function is_smods_active()
    return SMODS and CardArea and CardArea.handle_card_limit and SMODS.should_handle_limit
end

--- Load localization
local function load_localization()
    if CRIMSON_GIFT.localization_loaded then return end
    if not (SMODS and SMODS.handle_loc_file and CRIMSON_GIFT.mod and CRIMSON_GIFT.mod.path and CRIMSON_GIFT.mod.id) then
        return
    end
    
    SMODS.handle_loc_file(CRIMSON_GIFT.mod.path, CRIMSON_GIFT.mod.id)
    CRIMSON_GIFT.localization_loaded = true
    log("info", "Localization loaded")
end

--- Hook: Game:update - Update notification panel timer
local function hook_game_update()
    function Game:update(dt)
        Notification.update(dt)
        return _Game_update(self, dt)
    end
end

--- Hook: Game:update_hand_played - Handle boss defeat scenarios
local function hook_game_update_hand_played()
    function Game:update_hand_played(dt)
        local result = _Game_update_hand_played(self, dt)
        
        -- Check if boss defeated while we have preserved h_size
        local preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
        if preserved > 0 and G.GAME and G.GAME.blind and not CRIMSON_GIFT.boss_defeat_processed then
            local boss_defeated = false
            if G.GAME.blind.boss then
                boss_defeated = (G.GAME.chips - G.GAME.blind.chips) >= 0
            end
            
            if boss_defeated then
                CRIMSON_GIFT.boss_defeat_processed = true
                
                local max_excl = CRIMSON_GIFT.max_h_size_excluding_last or 0
                local gift_amount = math.max(preserved, max_excl)
                
                if gift_amount > 0 then
                    local current = CRIMSON_GIFT.permanent_hand_size_increase or 0
                    CRIMSON_GIFT.permanent_hand_size_increase = current + gift_amount
                    
                    log("debug", string.format(
                        "Boss defeated, applying gift: +%d (preserved=%d, max_excl=%d, permanent=%d -> %d)",
                        gift_amount, preserved, max_excl, current, current + gift_amount
                    ))
                    
                    -- Show keep_largest since we're keeping the max of preserved/max_excl
                    Notification.show("keep_largest", gift_amount)
                    HandSize.sync_base()
                    if G.hand then
                        HandSize.apply_gift(gift_amount)
                    end
                end
                
                State.reset_chain()
                HandSize.sync_display()
                State.save()
            end
        end
        
        return result
    end
end

--- Hook: Blind:drawn_to_hand - Detect Crimson Heart cycles
local function hook_blind_drawn_to_hand()
    function Blind:drawn_to_hand()
        -- Reset boss defeat flag for new blind
        CRIMSON_GIFT.boss_defeat_processed = false
        
        if self.name == 'Crimson Heart' and self.prepped then
            CRIMSON_GIFT.processing_crimson_heart = true
            
            -- Track max before resetting
            local old_preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
            if old_preserved > 0 then
                CRIMSON_GIFT.max_h_size_excluding_last = math.max(
                    CRIMSON_GIFT.max_h_size_excluding_last or 0,
                    old_preserved
                )
            end
            CRIMSON_GIFT.preserved_h_size_from_disabled = 0
        end
        
        local result = _Blind_drawn_to_hand(self)
        
        if self.name == 'Crimson Heart' then
            CRIMSON_GIFT.processing_crimson_heart = false
        end
        
        return result
    end
end

--- Hook: Card:remove_from_deck - Preserve h_size from disabled jokers
local function hook_card_remove_from_deck()
    function Card:remove_from_deck(from_debuff)
        -- Capture h_size BEFORE card is removed
        local h_size = 0
        if from_debuff and CRIMSON_GIFT.processing_crimson_heart and self.area == G.jokers then
            h_size = HandSize.from_card(self)
        end
        
        local result = _Card_remove_from_deck(self, from_debuff)
        
        -- Preserve h_size to prevent hand limit drop
        if from_debuff and CRIMSON_GIFT.processing_crimson_heart and self.area == G.jokers then
            if h_size > 0 then
                -- Hand-size joker disabled: preserve the h_size
                local card_name = (self.ability and self.ability.name) or "unknown"
                local current_preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
                CRIMSON_GIFT.preserved_h_size_from_disabled = current_preserved + h_size
                
                if CRIMSON_GIFT.first_h_size_in_chain then
                    log("debug", string.format(
                        "First h_size in chain: %s (h_size=%d, preserved=%d)",
                        card_name, h_size, CRIMSON_GIFT.preserved_h_size_from_disabled
                    ))
                    Notification.show("arriving", h_size)
                    CRIMSON_GIFT.first_h_size_in_chain = false
                else
                    local max_gift = math.max(
                        CRIMSON_GIFT.preserved_h_size_from_disabled or 0,
                        CRIMSON_GIFT.max_h_size_excluding_last or 0
                    )
                    log("debug", string.format(
                        "Keep larger: h_size=%d from %s (preserved=%d, max_excl=%d, max_gift=%d)",
                        h_size, card_name, CRIMSON_GIFT.preserved_h_size_from_disabled,
                        CRIMSON_GIFT.max_h_size_excluding_last, max_gift
                    ))
                    Notification.show("keep_larger", max_gift)
                end
                
                HandSize.sync_display()
                State.save()
            else
                -- Non-hand-size joker disabled: finalize chain
                local card_name = (self.ability and self.ability.name) or "unknown"
                local preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
                local max_excl = CRIMSON_GIFT.max_h_size_excluding_last or 0
                local gift_amount = math.max(preserved, max_excl)
                
                if gift_amount > 0 then
                    local current = CRIMSON_GIFT.permanent_hand_size_increase or 0
                    CRIMSON_GIFT.permanent_hand_size_increase = current + gift_amount
                    
                    log("debug", string.format(
                        "Chain finalized by %s: applied +%d (gift=%d from preserved=%d/max_excl=%d, permanent=%d -> %d)",
                        card_name, gift_amount, gift_amount, preserved, max_excl, current, current + gift_amount
                    ))
                    
                    Notification.show("applied", gift_amount)
                    HandSize.sync_base()
                    if G.hand then
                        HandSize.apply_gift(gift_amount)
                    end
                    
                    State.reset_chain()
                    HandSize.sync_display()
                    State.save()
                else
                    log("debug", string.format("Non-hand-size joker disabled: %s (no preservation to apply)", card_name))
                end
            end
        end
        
        return result
    end
end

--- Hook: CardArea:handle_card_limit - SMODS integration
local function hook_cardarea_handle_card_limit()
    if not CardArea.handle_card_limit then
        log("warning", "CardArea.handle_card_limit not found, skipping hook")
        return
    end
    
    function CardArea:handle_card_limit()
        if self == G.hand and CRIMSON_GIFT.using_smods and self.config.card_limits then
            HandSize.sync_base()
            
            local limits = self.config.card_limits
            local gift = CRIMSON_GIFT.permanent_hand_size_increase or 0
            local preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
            
            limits.crimson_gift_mod = gift
            
            -- Temporarily add gift + preserved into mod for SMODS calculation
            local original_mod = limits.mod or 0
            limits.mod = original_mod + gift + preserved
            
            local result = _CardArea_handle_card_limit(self)
            
            -- Restore mod
            limits.mod = original_mod
            
            HandSize.sync_display()
            State.save()
            
            -- Debug logging
            if CRIMSON_GIFT.config and CRIMSON_GIFT.config.debug_logs then
                local total_slots = limits.total_slots or 0
                local extra_slots = limits.extra_slots or 0
                local base = limits.base or 0
                local extra_used = limits.extra_slots_used or 0
                local cards_in_hand = (self.cards and #self.cards) or 0
                
                local snapshot = string.format("%d|%d|%d", total_slots, limits.old_slots or 0, extra_used)
                local prev_snapshot = CRIMSON_GIFT.debug_last.handle_limit_snapshot
                local anomaly = cards_in_hand > (total_slots - extra_used)
                local was_anomaly = CRIMSON_GIFT.debug_last.handle_limit_anomaly
                
                if snapshot ~= prev_snapshot or (anomaly and not was_anomaly) then
                    CRIMSON_GIFT.debug_last.handle_limit_snapshot = snapshot
                    CRIMSON_GIFT.debug_last.handle_limit_anomaly = anomaly or nil
                    log("debug", string.format(
                        "handle_card_limit: total=%d (base=%d + extra=%d + orig_mod=%d + gift=%d + preserved=%d), hand_cards=%d",
                        total_slots, base, extra_slots, original_mod, gift, preserved, cards_in_hand
                    ))
                elseif (not anomaly) and was_anomaly then
                    CRIMSON_GIFT.debug_last.handle_limit_anomaly = nil
                end
            end
            
            return result
        end
        
        return _CardArea_handle_card_limit(self)
    end
end

--- Hook: Game:start_run - Initialize state on run start
local function hook_game_start_run()
    function Game:start_run(args)
        State.init()
        
        local ret = _Game_start_run(self, args)
        
        -- Detect SMODS
        CRIMSON_GIFT.using_smods = is_smods_active() and SMODS.should_handle_limit(G.hand)
        if not CRIMSON_GIFT.using_smods then
            log("warning", "start_run called but SMODS hand-limit handler is inactive; CrimsonGift will stay idle")
        end
        
        -- Load localization
        load_localization()
        
        -- Store original hand size base
        if G.hand and G.GAME and G.GAME.starting_params then
            G.hand.config.crimson_gift_original_base = G.GAME.starting_params.hand_size
            HandSize.sync_base()
            HandSize.sync_display()
        end
        
        -- Ensure SMODS structures exist
        if CRIMSON_GIFT.using_smods and G.hand and G.hand.config and G.hand.config.card_limits then
            G.hand.config.card_limits.crimson_gift_mod = 0
        end
        
        -- Restore persisted state
        State.restore()
        HandSize.sync_base()
        HandSize.sync_display()
        State.save()
        
        return ret
    end
end

--- Install all game hooks
function M.install()
    -- Check if already initialized
    if _Blind_drawn_to_hand then
        log("info", "Hooks already installed, skipping")
        return true
    end
    
    -- Check required classes
    if not (Blind and Card and CardArea and Game) then
        log("error", "Required classes not available")
        return false
    end
    
    -- Store original functions
    _Blind_drawn_to_hand = Blind.drawn_to_hand
    _Card_remove_from_deck = Card.remove_from_deck
    _CardArea_handle_card_limit = CardArea.handle_card_limit
    _Game_update = Game.update
    _Game_update_hand_played = Game.update_hand_played
    _Game_start_run = Game.start_run
    
    -- Install hooks
    hook_game_update()
    hook_game_update_hand_played()
    hook_blind_drawn_to_hand()
    hook_card_remove_from_deck()
    hook_cardarea_handle_card_limit()
    hook_game_start_run()
    
    log("info", "All game hooks installed successfully")
    return true
end

return M
