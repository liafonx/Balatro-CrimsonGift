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
| `main.lua` | Core logic: hooks, state tracking, h_size preservation, notifications, persistence | SMODS-only, loads `ui.lua` via `SMODS.load_file` |
| `ui.lua` | UI hooks to keep display limits synced | Keeps display values in sync with actual limits |
| `lovely.toml` | Patches `cardarea.lua` to use CrimsonGift display refs | Targets `crimson_gift_display_limit` + `crimson_gift_display_total_slots` |
| `CrimsonGift.json` | SMODS mod manifest | Declares SMODS dependency version constraint |
| `localization/en-us.lua` | English strings | SMODS `handle_loc_file` only |
| `localization/zh_CN.lua` | Simplified Chinese strings | SMODS `handle_loc_file` only |

### References/
All content in `References/` is for development reference only and is **not** part of the mod.

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

- **Single h_size joker disabled**: Gift is **lost**, show "lost" alert
- **Multiple h_size jokers disabled**: Keep largest excluding last, show "keep_largest" alert
  - The `max_h_size_excluding_last` tracks the maximum h_size from previous cycles
  - This value is added cumulatively to permanent hand size

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

All notifications use the unified `show_crimson_alert(type, value)` function with presets:

| Alert Type | Localization Key | When Shown |
|------------|------------------|------------|
| `arriving` | `crimson_gift_arriving` | First h_size joker disabled in chain |
| `keep_larger` | `crimson_gift_keep_larger` | Subsequent h_size jokers disabled |
| `applied` | `crimson_gift_applied` | Non-hand-size joker disabled (chain finalized) |
| `lost` | `crimson_gift_lost` | Boss defeated with single h_size disabled |
| `keep_largest` | `crimson_gift_keep_largest` | Boss defeated with multiple h_size disabled |

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
- `crimson_gift_arriving` - "Crimson's Gift is arriving, hand size +%d"
- `crimson_gift_applied` - "Crimson's Gift applied, hand size +%d"
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
- Single h_size disabled, boss defeated → gift lost
- Multiple h_size disabled, boss defeated → keep largest excluding last

---

## 10. Notes for Future Work

- If additional UI changes are needed, update `ui.lua` + `lovely.toml` together
- Alert presets are in `ALERT_PRESETS` table - easy to add new types
- All state resets should use `reset_chain_state()` helper
