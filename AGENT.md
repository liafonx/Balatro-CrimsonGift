# CrimsonGift - AI Development Guide

Guidance for AI agents working on this repo. Uses the Save Rewinder AGENT.md format as reference, but focused on CrimsonGift.

---

## 1. Big Picture

CrimsonGift restores and formalizes the Crimson Heart hand-size interaction: when a Joker with `hand_size` is disabled by Crimson Heart, the run gains a **permanent** hand size increase (after the next hand is completed). This is an intentional feature to support endless runs.

**Core objectives:**
- Track Crimson Heart disable cycles and detect hand-size Jokers
- Apply a pending +N increase after the hand completes
- **Do not apply** the pending increase if the boss is defeated on that same hand (gift lost)
- Keep the UI display consistent (`9/9+1` while pending, `10/10` after apply)
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
| `main.lua` | Core logic: hooks, state tracking, pending/permanent increases, notifications, persistence | SMODS-only, loads `ui.lua` via `SMODS.load_file` |
| `ui.lua` | UI hooks to keep display limits synced | Removes any old +N overlay and keeps display values in sync |
| `lovely.toml` | Patches `cardarea.lua` to use CrimsonGift display refs | Targets `crimson_gift_display_limit` + `crimson_gift_display_total_slots` |
| `CrimsonGift.json` | SMODS mod manifest | Declares SMODS dependency version constraint |
| `localization/en-us.lua` | English strings | SMODS `handle_loc_file` only |
| `localization/zh_CN.lua` | Simplified Chinese strings | SMODS `handle_loc_file` only |

### References/
All content in `References/` is for development reference only and is **not** part of the mod.

---

## 3. Core Behavior

### Crimson Heart Handling
- Detects Joker disables during Crimson Heart's disable cycle
- If a disabled Joker contributes `hand_size`, a **pending** increase is recorded
- Pending increase is applied **after** the hand resolves, **unless** the boss is defeated on that same hand
- When the boss is defeated on the same hand, the pending increase is **lost** and a notification is shown

### UI Display Rules
- Pending increases are reflected in the hand size display using patched display refs
- Display example before disable: `9/9`
- Display example after disable: `9/9+1` (displayed via patched ref values)
- Display example after play: `10/10`
- The old +N overlay label is **removed**

### Notifications
- Gift gained: `crimson_gift_arriving` (`"Crimson's Gift is arriving, hand size +%d"`)
- Gift lost: `crimson_gift_lost` (`"Crimson Heart defeated - gift lost"`)

---

## 4. Persistence & Save Rewinder Compatibility

State is stored in `G.GAME.crimson_gift` so rewinding restores correctly.

Stored fields:
- `permanent`: total permanent increase
- `pending`: pending increase for next hand
- `last_disabled_h_size`: last disabled Joker's hand size
- `original_base`: starting base hand size for the run
- `using_smods`: SMODS mode flag

**Important:** Do not write to `G.hand.config.card_limit` in SMODS mode. Instead, write to `G.hand.config.card_limits.crimson_gift_mod` and let SMODS reconcile.

---

## 5. Localization

- Use `SMODS.handle_loc_file(CRIMSON_GIFT.mod.path, CRIMSON_GIFT.mod.id)`
- Only the mod's localization files are used (no fallback dictionaries)
- Localization key (misc.dictionary): `crimson_gift_arriving`
- Localization key (misc.dictionary): `crimson_gift_lost`

---

## 6. Constraints / New Requirements

- SMODS-only implementation (no vanilla fallback paths)
- Keep core logic in `main.lua` and UI logic in `ui.lua`
- Use patched display refs in `lovely.toml` for hand size display
- Do not reintroduce +N overlay or per-frame UI widgets
- Maintain SMODS minimum version requirement (`>= 1.0.0~BETA-1221a`)

---

## 7. Notes for Future Work

- If additional UI changes are needed, update `ui.lua` + `lovely.toml` together.
- If you change the display format, also update tests/expectations in AGENT.md.
