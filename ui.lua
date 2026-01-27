--- CrimsonGift UI hooks (SMODS-only)

if not (CRIMSON_GIFT and CRIMSON_GIFT.sync_display_limit) then
    return
end

if CRIMSON_GIFT.ui_initialized then
    return
end
CRIMSON_GIFT.ui_initialized = true

if not CardArea then
    return
end

local _CardArea_draw = CardArea.draw
function CardArea:draw()
    local result = _CardArea_draw(self)

    -- Ensure non-hand areas have a sane display limit for the patched UI ref_value.
    if self ~= G.hand and self.config then
        if self.config.card_limits then
            if self.config.card_limits.total_slots == nil then
                self.config.card_limits.total_slots = self.config.card_limit or 0
            end
            self.config.card_limits.crimson_gift_display_total_slots = self.config.card_limits.total_slots
        end
        self.config.crimson_gift_display_limit = self.config.card_limit
    elseif self == G.hand then
        -- Keep hand display synced with pending increases.
        CRIMSON_GIFT.sync_display_limit()
    end

    -- Ensure any previous indicator is removed
    if self == G.hand and self.children and self.children.crimson_gift_indicator then
        self.children.crimson_gift_indicator = nil
    end

    return result
end

