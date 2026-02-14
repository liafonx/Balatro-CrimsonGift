# CrimsonGift - AI Development Guide

Guidance for AI agents working on this repo. Uses the Save Rewinder AGENT.md format as reference, but focused on CrimsonGift.

---

## 1. Big Picture

CrimsonGift restores and formalizes the Crimson Heart hand-size interaction: when a Joker with `hand_size` is disabled by Crimson Heart, the run gains a **permanent** hand size increase. This is an intentional feature to support endless runs.

**Core objectives:**
- Track Crimson Heart disable cycles and detect hand-size Jokers
- Preserve hand size during disable (hand limit never actually drops)
- Apply permanent increase when a non-hand-size joker is disabled (chain finalized)
- Handle boss defeat scenarios (gift lost or keep largest excluding last)
- Keep the UI display consistent and stable
- Persist state in the run save so Save Rewinder restores correctly
- SMODS-only mod (no vanilla fallback)

**Requirements:**
- SMODS **must** be present
- Minimum SMODS version: `1.0.0~BETA-1221a`
- If SMODS is missing or below min version, the mod disables itself

---

## 2. File Structure & Relations

### Root Files

| File | Purpose | Notes |
|------|---------|-------|
| `main.lua` | Entry point & module coordination | Loads modules, initializes mod, coordinates components |
| `ui.lua` | UI hooks to keep display limits synced | Keeps display values in sync with actual limits |
| `lovely.toml` | Patches `cardarea.lua` to use CrimsonGift display refs | Desktop + Mobile iOS patterns (see below) |
| `CrimsonGift.json` | SMODS mod manifest | Declares SMODS dependency version constraint |

### Core Modules (`Core/`)

| File | Purpose | Notes |
|------|---------|-------|
| `State.lua` | State persistence and chain tracking | Handles save/restore, chain reset |
| `HandSize.lua` | Hand limit calculations and SMODS integration | Card h_size extraction, limit tracking, gift application |
| `Hooks.lua` | Game hook installation | Installs all game event hooks |

### Utility Modules (`Utils/`)

| File | Purpose | Notes |
|------|---------|-------|
| `Logger.lua` | Centralized logging | Module-specific loggers, debug mode support |
| `Notification.lua` | Alert and notification system | Speed-independent UI notifications with styling |

### Localization (`localization/`)

| File | Purpose | Notes |
|------|---------|-------|
| `en-us.lua` | English strings | SMODS `handle_loc_file` only |
| `zh_CN.lua` | Simplified Chinese strings | SMODS `handle_loc_file` only |

### lovely.toml Patches

The `lovely.toml` contains two patches for different platforms:

1. **Desktop**: Matches standard SMODS pattern
   ```lua
   {n=G.UIT.T, config={ref_table = self.config.card_limits, ref_value = 'total_slots', ...}}
   ```

2. **Mobile iOS**: Matches SMODS-aware conditional pattern with `lang` parameter
   ```lua
   {n=G.UIT.T, config={ref_table = SMODS and self.config.card_limits or self.config, ref_value = SMODS and 'total_slots' or 'card_limit', ..., lang = G.LANGUAGES['en-us'], ...}}
   ```

Both patches redirect to `crimson_gift_display_total_slots` for consistent UI display.

### References/
All content in `References/` is for development reference only and is **not** part of the mod.

### mod.config.json - Sync Configuration

Use directory patterns for subdirectories: `"localization/***"` (not individual files like `"localization/en-us.lua"`). Rsync needs parent directory included.

---

## 3. Core Behavior

### Hand Size Preservation Approach

The mod uses a **preservation approach** rather than tracking and compensating:
- When a hand-size joker is disabled, its `h_size` is captured
- The `preserved_h_size_from_disabled` value is added to SMODS' mod calculation
- This means the hand limit **never actually drops** during Crimson Heart cycles
- Result: stable UI, no flicker, no overfill issues

### Gift Application Flow

1. **First h_size joker disabled**: Show "arriving" alert, set `preserved`
2. **Subsequent h_size jokers disabled**: Show "keep_larger" alert with max value
3. **Non-hand-size joker disabled**: Chain finalized, gift applied immediately
4. **Boss defeated with preserved gift**: Special handling (see below)

### Boss Defeat Handling

- **Boss defeated with preserved gift**: Gift is **applied** (takes largest of all disabled)
  - Uses idempotency flag `boss_defeat_processed` to prevent re-triggering on save reloads
  - Applies `max(preserved, max_h_size_excluding_last)` to get the largest of all disabled h_sizes
  - Shows "applied" alert with the gift amount
  - The `max_h_size_excluding_last` tracks the maximum h_size from previous cycles

### State Variables

```lua
CRIMSON_GIFT.permanent_hand_size_increase  -- Actual permanent increase
CRIMSON_GIFT.preserved_h_size_from_disabled -- Current cycle's preserved h_size
CRIMSON_GIFT.max_h_size_excluding_last     -- Max h_size from previous cycles (for boss defeat)
CRIMSON_GIFT.first_h_size_in_chain         -- Flag: first h_size in current chain?
CRIMSON_GIFT.processing_crimson_heart      -- Flag: currently in Crimson Heart cycle?
CRIMSON_GIFT.apply_sequence                -- Monotonic counter for event invalidation
CRIMSON_GIFT.using_smods                   -- SMODS mode flag
```

### Helper Functions

- `reset_chain_state()` - Resets `preserved`, `max_h_size_excluding_last`, `first_h_size_in_chain`
- `show_crimson_alert(type, value)` - Unified alert function using `ALERT_PRESETS`

---

## 4. Notifications

### Notification System (Speed-Independent)

**Architecture:** Persistent UIBox panel (not `attention_text`)
- **Real-time duration:** Always visible for 3 seconds (not affected by game speed)
- **Compatible with:** HandySpeed, Speedmaster (works at 1x-999x speed)
- **Configurable:** Can be disabled via `config.notifications_enabled`

### Unified Styling

All colors/sizes centralized in `NOTIFICATION_STYLE`:
- `background`, `text_color` - panel styling
- `highlight_color` - Crimson Heart red for key terms ("Crimson Heart", "绯红之心", "Crimson Gift", "绯红恩赐")
- `number_color` - Orange (HEX ff9a00) for `+N` numbers
- `text_scale`, `highlight_scale` - font sizes

`parse_highlighted_text()` scans for patterns, applies appropriate colors/sizes per match type.

### Alert Types

All notifications use the unified `show_crimson_alert(type, value)` function with presets:

| Alert Type | Localization Key | When Shown | Duration |
|------------|------------------|------------|----------|
| `arriving` | `crimson_gift_arriving` | First h_size joker disabled in chain | 2.5s (real-time) |
| `keep_larger` | `crimson_gift_keep_larger` | Subsequent h_size jokers disabled | 2.0s (real-time) |
| `applied` | `crimson_gift_applied` | Non-hand-size joker disabled OR boss defeated | 2.0s (real-time) |

### Implementation Details

**Persistent Panel Components:**
```lua
CRIMSON_GIFT.notification_panel = {
    element = nil,     -- UIBox instance (instance_type="ALERT")
    timer = 0,         -- Real-time countdown (uses dt from Game:update)
    duration = 3.0,    -- Default 3 seconds (real-time)
    message = "",      -- Current notification text
    colour = {...},    -- Background color from ALERT_PRESETS
}
```

**Key Functions:**
- `parse_highlighted_text(text)` - Parses and highlights key terms/numbers
- `create_notification_panel_definition()` - Creates UIBox definition with highlighted text
- `show_notification_panel(text, colour, duration)` - Shows/updates panel
- `update_notification_panel(dt)` - Updates timer (hooked to `Game:update`)

**Why Not `attention_text`:**
- `attention_text` uses `hold` parameter in seconds, but gets scaled by game speed
- At high speeds (32x, 999x), notifications become invisible
- Persistent panel uses real delta time (dt), unaffected by `G.SETTINGS.GAMESPEED`

---

## 5. Persistence & Save Rewinder Compatibility

State is stored in `G.GAME.crimson_gift` so rewinding restores correctly.

Stored fields:
- `permanent`: total permanent increase
- `preserved_h_size`: current preserved h_size
- `max_h_size_excluding_last`: max from previous cycles
- `first_h_size_in_chain`: chain state flag
- `original_base`: starting base hand size for the run
- `using_smods`: SMODS mode flag

**Important:** Do not write to `G.hand.config.card_limit` in SMODS mode. Instead, write to `G.hand.config.card_limits.crimson_gift_mod` and let SMODS reconcile.

---

## 6. Localization

- Use `SMODS.handle_loc_file(CRIMSON_GIFT.mod.path, CRIMSON_GIFT.mod.id)`
- Only the mod's localization files are used (no fallback dictionaries)

Localization keys (misc.dictionary):
- `crimson_gift_arriving` - "Crimson Gift is arriving, hand size +%d"
- `crimson_gift_applied` - "Crimson Gift applied, hand size +%d"
- `crimson_gift_lost` - "Crimson Heart defeated, gift lost"
- `crimson_gift_keep_larger` - "Consecutive bonuses: keeping hand size +%d"
- `crimson_gift_keep_largest` - "Boss defeated: keeping hand size +%d"
- `crimsongift_debug_logs` - "Debug: verbose logging"

---

## 7. Key Hooks

| Hook | Purpose |
|------|---------|
| `Blind:drawn_to_hand` | Detect Crimson Heart cycles, track max_h_size across cycles |
| `Card:remove_from_deck` | Capture h_size before removal, preserve or finalize chain |
| `CardArea:handle_card_limit` | Add gift + preserved to SMODS mod calculation |
| `Game:update_hand_played` | Handle boss defeat scenarios |
| `Game:start_run` | Initialize/restore state |

---

## 8. Constraints / Requirements

- SMODS-only implementation (no vanilla fallback paths)
- Keep core logic in `main.lua` and UI logic in `ui.lua`
- Use patched display refs in `lovely.toml` for hand size display
- Maintain SMODS minimum version requirement (`>= 1.0.0~BETA-1221a`)
- Gift application is cumulative (each chain adds to permanent, not max)

---

## 9. Testing Scenarios

### Basic Flow
1. h_size joker disabled → hand limit stable (11/11, not 9/9)
2. Non-h_size joker disabled → gift applied immediately
3. Hand resolves → permanent increase visible

### Consecutive Disables
1. h_size=2 disabled → preserved=2, "arriving +2"
2. h_size=1 disabled → preserved=1, max_excl=2, "keep_larger +2"
3. h_size=0 disabled → gift +2 applied, "applied +2"

### Boss Defeat
- Boss defeated with preserved gift → gift applied (takes largest of all disabled)
- Uses idempotency flag to prevent re-triggering on save reloads

---

## 10. Common Mistakes & Pitfalls

### attention_text `hold` Parameter (CRITICAL)

**MISTAKE:** Assuming `hold` is in frames
**REALITY:** `hold` is in **SECONDS**

From game source (`UI_definitions.lua:888`):
```lua
args.hold = (args.hold or 0) + 0.1*(G.SPEEDFACTOR)
```

Examples from vanilla code:
- `hold = 1.4` → 1.4 seconds
- `hold = 0.3/G.SETTINGS.GAMESPEED` → 0.3 seconds at 1x speed

**Correct usage in CrimsonGift:**
```lua
hold = 2.0  -- 2 seconds at 1x speed
hold = 2.5  -- 2.5 seconds at 1x speed
```

**Historical error (2026-02-09):**
- Used `hold = 120` thinking it was frames
- Actually meant 120 SECONDS = 2 minutes!
- Notifications stayed visible way too long

**Speed compensation:**
- Multiply by `game_speed` to maintain real-time duration
- Example: `hold = 2.0 * 4 = 8.0` at 4x speed → still 2s real-time

---

## 11. Notes for Future Work

- UI changes: update `ui.lua` + `lovely.toml` together
- Alert presets: add new types to `ALERT_PRESETS` table
- State resets: use `reset_chain_state()` helper
- Notification styling: all colors/sizes in `NOTIFICATION_STYLE`; add patterns to `highlight_patterns` in `parse_highlighted_text()`
- Localization sync: use `localization/***` in `mod.config.json`
