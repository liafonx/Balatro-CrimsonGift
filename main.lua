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

-- Track h_size from the joker disabled THIS cycle by Crimson Heart
-- Reset at each cycle start since Crimson Heart alternates which joker it disables
CRIMSON_GIFT.preserved_h_size_from_disabled = 0

-- Track max h_size seen across previous cycles (for "keep largest" gift on boss defeat)
CRIMSON_GIFT.max_h_size_excluding_last = 0

-- Track whether we've seen the first h_size joker in the current chain
-- Used to show "arriving" for first, "keep_larger" for subsequent
CRIMSON_GIFT.first_h_size_in_chain = true

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

CRIMSON_GIFT.debug_last = CRIMSON_GIFT.debug_last or {}

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
end

-- Keep UI-only display limits in sync without mutating SMODS' real limit math.
local function sync_display_limit()
    if not (G and G.hand and G.hand.config) then return end

    -- In SMODS mode with h_size preservation, display equals actual limit
    -- (hand size never drops, so no compensation needed)
    if G.hand.config.card_limits then
        local limits = G.hand.config.card_limits
        local total_slots = limits.total_slots
            or (limits.extra_slots or 0) + (limits.base or 0) + (limits.mod or 0) + (limits.crimson_gift_mod or 0)
        local effective_limit = total_slots - (limits.extra_slots_used or 0)

        -- Display refs now equal real values (no compensation needed)
        limits.crimson_gift_display_total_slots = total_slots
        G.hand.config.crimson_gift_display_limit = effective_limit
    else
        local limit = G.hand.config.card_limit or G.hand.config.real_card_limit or 0
        G.hand.config.crimson_gift_display_limit = limit
    end
end

CRIMSON_GIFT.sync_display_limit = sync_display_limit

-- Reset chain state (used after chain finalized or boss defeated)
local function reset_chain_state()
    CRIMSON_GIFT.preserved_h_size_from_disabled = 0
    CRIMSON_GIFT.max_h_size_excluding_last = 0
    CRIMSON_GIFT.first_h_size_in_chain = true
end

-- Persist Crimson Gift state into the run save table (G.GAME).
local function sync_persistent_state()
    if not (G and G.GAME) then return end
    G.GAME.crimson_gift = G.GAME.crimson_gift or {}
    local saved = G.GAME.crimson_gift
    saved.permanent = CRIMSON_GIFT.permanent_hand_size_increase or 0
    saved.preserved_h_size = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
    saved.max_h_size_excluding_last = CRIMSON_GIFT.max_h_size_excluding_last or 0
    saved.first_h_size_in_chain = CRIMSON_GIFT.first_h_size_in_chain
    saved.original_base = (G.hand and G.hand.config and G.hand.config.crimson_gift_original_base) or saved.original_base
    saved.using_smods = CRIMSON_GIFT.using_smods or false
end

-- Restore Crimson Gift state from the run save table (G.GAME).
local function restore_persistent_state()
    if not (G and G.GAME and G.GAME.crimson_gift) then return end
    local saved = G.GAME.crimson_gift
    CRIMSON_GIFT.permanent_hand_size_increase = saved.permanent or 0
    CRIMSON_GIFT.preserved_h_size_from_disabled = saved.preserved_h_size or 0
    CRIMSON_GIFT.max_h_size_excluding_last = saved.max_h_size_excluding_last or 0
    CRIMSON_GIFT.first_h_size_in_chain = saved.first_h_size_in_chain ~= false
    CRIMSON_GIFT.using_smods = saved.using_smods or CRIMSON_GIFT.using_smods

    if G.hand and G.hand.config and saved.original_base then
        G.hand.config.crimson_gift_original_base = saved.original_base
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
                    local cards_in_hand = (G.hand and G.hand.cards and #G.hand.cards) or 0
                    local card_count = (h.config and h.config.card_count) or 0
                    log_debug(string.format(
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

                sync_display_limit()
                sync_persistent_state()

                -- In SMODS, rely on handle_card_limit auto-draw to avoid overfill.

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

-- Alert presets for different notification types
local ALERT_PRESETS = {
    arriving = {
        loc_key = "crimson_gift_arriving",
        delay = 1.0, scale = 0.7, hold = 18,
        backdrop_colour = {1, 0, 0, 0.5},
        sound = "other1", sound_pitch = 0.76, sound_volume = 0.4,
    },
    applied = {
        loc_key = "crimson_gift_applied",
        delay = 1.0, scale = 0.65, hold = 12,
        backdrop_colour = {0.9, 0.15, 0.15, 0.5},
        sound = "other1", sound_pitch = 0.75, sound_volume = 0.4,
    },
    lost = {
        loc_key = "crimson_gift_lost",
        delay = 0.6, scale = 0.7, hold = 10,
        backdrop_colour = {0.8, 0, 0, 0.35},
        sound = "cancel", sound_pitch = 0.8, sound_volume = 0.5,
    },
    keep_larger = {
        loc_key = "crimson_gift_keep_larger",
        delay = 0.6, scale = 0.65, hold = 12,
        backdrop_colour = {0.8, 0.2, 0.2, 0.4},
        sound = "other1", sound_pitch = 0.6, sound_volume = 0.35,
    },
    keep_largest = {
        loc_key = "crimson_gift_keep_largest",
        delay = 0.6, scale = 0.65, hold = 12,
        backdrop_colour = {0.8, 0.2, 0.2, 0.4},
        sound = "other1", sound_pitch = 0.6, sound_volume = 0.35,
    },
}

-- Unified alert function for all Crimson Gift notifications
-- @param alert_type: string key from ALERT_PRESETS (arriving, applied, lost, keep_larger, keep_largest)
-- @param value: optional number for formatted messages (e.g., hand size amount)
local function show_crimson_alert(alert_type, value)
    if not G or not G.E_MANAGER or not Event then return end

    local preset = ALERT_PRESETS[alert_type]
    if not preset then
        log("warn", "Unknown alert type: " .. tostring(alert_type))
        return
    end

    -- Build text from localization key, with optional value formatting
    local text
    if value then
        text = string.format(localize(preset.loc_key), value)
    else
        text = localize(preset.loc_key)
    end

    G.E_MANAGER:add_event(Event({
        trigger = "after",
        delay = preset.delay,
        func = function()
            attention_text({
                text = text,
                scale = preset.scale,
                hold = preset.hold,
                major = G.STAGE == G.STAGES.RUN and G.play or G.title_top,
                backdrop_colour = preset.backdrop_colour,
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
                    play_sound(preset.sound, preset.sound_pitch, preset.sound_volume)
                    return true
                end,
            }))
            return true
        end,
    }))
    log_debug(string.format("Alert queued [%s]: %s", alert_type, text))
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
    -- Check if boss was defeated while we have preserved h_size
    local _Game_update_hand_played = Game.update_hand_played
    function Game:update_hand_played(dt)
        local result = _Game_update_hand_played(self, dt)

        -- Check if we have preserved h_size and boss was defeated
        local preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
        if preserved > 0 and G.GAME and G.GAME.blind then
            local boss_defeated = false
            if G.GAME.blind.boss then
                boss_defeated = (G.GAME.chips - G.GAME.blind.chips) >= 0
            end

            if boss_defeated then
                local max_excluding_last = CRIMSON_GIFT.max_h_size_excluding_last or 0

                if max_excluding_last > 0 then
                    -- Multiple h_size jokers were disabled: keep largest excluding last (cumulative)
                    local current = CRIMSON_GIFT.permanent_hand_size_increase or 0
                    local new_value = current + max_excluding_last

                    CRIMSON_GIFT.permanent_hand_size_increase = new_value
                    log_debug(string.format(
                        "Boss defeated, keeping largest excluding last: +%d (max_excluding_last=%d, permanent=%d -> %d)",
                        max_excluding_last, max_excluding_last, current, new_value
                    ))
                    show_crimson_alert("keep_largest", max_excluding_last)

                    sync_base_tracking()
                    if G.hand then
                        schedule_smods_delta(max_excluding_last)
                    end
                else
                    -- Only one h_size joker was disabled: gift lost
                    log_debug(string.format(
                        "Boss defeated, gift lost (preserved=%d, no max_excluding_last)",
                        preserved
                    ))
                    show_crimson_alert("lost")
                end

                -- Reset state after boss defeat
                reset_chain_state()
                sync_display_limit()
                sync_persistent_state()
            end
        end

        return result
    end
    
    -- Hook Blind:drawn_to_hand to detect Crimson Heart cycles
    function Blind:drawn_to_hand()
        if self.name == 'Crimson Heart' and self.prepped then
            CRIMSON_GIFT.processing_crimson_heart = true
            -- Reset preserved at cycle start - it should only reflect THIS cycle's disabled jokers
            -- (Crimson Heart alternates which joker it disables, so we can't accumulate)
            -- But track max_h_size_excluding_last across cycles for the "keep largest" gift
            local old_preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
            if old_preserved > 0 then
                -- Update max excluding last before resetting
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
    
    -- Hook Card:remove_from_deck to preserve h_size from disabled hand-size jokers
    -- This prevents hand size from actually dropping during Crimson Heart cycles
    function Card:remove_from_deck(from_debuff)
        -- Capture h_size BEFORE the card is removed
        local h_size = 0
        if from_debuff and CRIMSON_GIFT.processing_crimson_heart and self.area == G.jokers then
            h_size = get_card_hand_size(self)
        end

        -- Let the normal removal happen (card is removed, animation plays)
        local result = _Card_remove_from_deck(self, from_debuff)

        -- Preserve h_size so it doesn't actually reduce the hand limit
        if from_debuff and CRIMSON_GIFT.processing_crimson_heart and self.area == G.jokers then
            if h_size > 0 then
                local card_name = (self.ability and self.ability.name) or "unknown"
                local current_preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0

                -- Within a single cycle, Crimson Heart only disables one joker at a time
                -- So just set preserved to this joker's h_size (it was reset at cycle start)
                -- If somehow multiple are disabled in same cycle, add them
                CRIMSON_GIFT.preserved_h_size_from_disabled = current_preserved + h_size

                -- Show different alerts based on whether this is the first h_size in the chain
                if CRIMSON_GIFT.first_h_size_in_chain then
                    log_debug(string.format(
                        "First h_size in chain: %s (h_size=%d, preserved=%d)",
                        card_name,
                        h_size,
                        CRIMSON_GIFT.preserved_h_size_from_disabled
                    ))
                    show_crimson_alert("arriving", h_size)
                    CRIMSON_GIFT.first_h_size_in_chain = false
                else
                    -- Show the max potential gift (current preserved or max from previous cycles)
                    local max_gift = math.max(
                        CRIMSON_GIFT.preserved_h_size_from_disabled or 0,
                        CRIMSON_GIFT.max_h_size_excluding_last or 0
                    )
                    log_debug(string.format(
                        "Keep larger: h_size=%d from %s (preserved=%d, max_excluding_last=%d, max_gift=%d)",
                        h_size,
                        card_name,
                        CRIMSON_GIFT.preserved_h_size_from_disabled,
                        CRIMSON_GIFT.max_h_size_excluding_last,
                        max_gift
                    ))
                    show_crimson_alert("keep_larger", max_gift)
                end

                sync_display_limit()
                sync_persistent_state()
            else
                -- Non-hand-size joker disabled: finalize and apply the gift immediately
                local card_name = (self.ability and self.ability.name) or "unknown"
                local preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0
                local max_excl = CRIMSON_GIFT.max_h_size_excluding_last or 0
                -- Gift is the max of current cycle's preserved and max from previous cycles
                local gift_amount = math.max(preserved, max_excl)

                if gift_amount > 0 then
                    -- Apply gift to permanent (cumulative - each chain adds to total)
                    local current = CRIMSON_GIFT.permanent_hand_size_increase or 0
                    local new_value = current + gift_amount

                    CRIMSON_GIFT.permanent_hand_size_increase = new_value

                    log_debug(string.format(
                        "Chain finalized by %s: applied +%d (gift=%d from preserved=%d/max_excl=%d, permanent=%d -> %d)",
                        card_name,
                        gift_amount,
                        gift_amount,
                        preserved,
                        max_excl,
                        current,
                        new_value
                    ))

                    show_crimson_alert("applied", gift_amount)

                    sync_base_tracking()
                    if G.hand then
                        schedule_smods_delta(gift_amount)
                    end

                    -- Reset chain state after gift applied
                    reset_chain_state()
                    sync_display_limit()
                    sync_persistent_state()
                else
                    log_debug(string.format(
                        "Non-hand-size Joker disabled: %s (no preservation to apply)",
                        card_name
                    ))
                end
            end
        end

        return result
    end
    
    -- For SMODS compatibility: Hook handle_card_limit to add permanent increase
    if CardArea.handle_card_limit then
        local _CardArea_handle_card_limit = CardArea.handle_card_limit
        function CardArea:handle_card_limit()
            if self == G.hand and CRIMSON_GIFT.using_smods and self.config.card_limits then
                sync_base_tracking()

                local limits = self.config.card_limits
                local gift = CRIMSON_GIFT.permanent_hand_size_increase or 0
                local preserved = CRIMSON_GIFT.preserved_h_size_from_disabled or 0

                limits.crimson_gift_mod = gift

                -- Temporarily add gift + preserved h_size into mod so SMODS includes both
                -- Gift: permanent increase being applied
                -- Preserved: h_size from disabled jokers (keeps hand size stable)
                local original_mod = limits.mod or 0
                limits.mod = original_mod + gift + preserved

                local result = _CardArea_handle_card_limit(self)

                -- Restore mod to avoid interfering with other mods' logic.
                limits.mod = original_mod

                sync_display_limit()
                sync_persistent_state()

                if CRIMSON_GIFT.config and CRIMSON_GIFT.config.debug_logs then
                    local total_slots = limits.total_slots or 0
                    local extra_slots = limits.extra_slots or 0
                    local base = limits.base or 0
                    local extra_used = limits.extra_slots_used or 0
                    local effective = total_slots - extra_used
                    local cards_in_hand = (self.cards and #self.cards) or 0
                    local card_count = self.config.card_count or 0
                    local old_slots = limits.old_slots or 0

                    -- Log only when slot math changes or when an anomaly begins.
                    local snapshot = string.format("%d|%d|%d", total_slots, old_slots, extra_used)
                    local prev_snapshot = CRIMSON_GIFT.debug_last.handle_limit_snapshot
                    local anomaly = cards_in_hand > effective
                    local was_anomaly = CRIMSON_GIFT.debug_last.handle_limit_anomaly

                    if snapshot ~= prev_snapshot or (anomaly and not was_anomaly) then
                        CRIMSON_GIFT.debug_last.handle_limit_snapshot = snapshot
                        CRIMSON_GIFT.debug_last.handle_limit_anomaly = anomaly or nil
                        log_debug(string.format(
                            "handle_card_limit: total=%d (base=%d + extra=%d + orig_mod=%d + gift=%d + preserved=%d), hand_cards=%d",
                            total_slots,
                            base,
                            extra_slots,
                            original_mod,
                            gift,
                            preserved,
                            cards_in_hand
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
    
    -- Initialize tracking on run start
    function Game:start_run(args)
        CRIMSON_GIFT.permanent_hand_size_increase = 0
        reset_chain_state()
        CRIMSON_GIFT.processing_crimson_heart = false
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
