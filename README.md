# CrimsonGift

**Crimson Heart's Gift** — When Crimson Heart disables a hand-size Joker, your run gains a permanent hand size increase. It is intentional, powerful, and built for endless runs.

## What This Mod Does

- Restores the classic Crimson Heart hand-size interaction as a **feature**
- Grants a **pending +N** when a hand-size Joker is disabled
- Applies the increase **after the hand resolves**
- **If that hand defeats the boss, the gift is lost**
- Keeps the hand-size display consistent (`9/9`, then `9/9+1`, then `10/10`)

## Why This Mod Exists

SMODS `1.0.0~BETA-1221a` and later fixed the vanilla Crimson Heart hand-size bug. This mod brings that behavior back as an intentional, balanced mechanic for endless runs.

## How It Plays (Example)

1. You have Juggler (+1 hand size) → hand size is `9/9`
2. Crimson Heart disables Juggler → display becomes `9/9+1`
3. You finish the hand → permanent hand size becomes `10/10`
4. If that same hand defeats the boss → the gift is **lost**

## Requirements

- **SMODS is required** (no vanilla support)
- **Minimum SMODS version:** `1.0.0~BETA-1221a`
- Lovely is required for the UI patch

## Installation

1. Copy the `CrimsonGift` folder into your Balatro `Mods` directory
2. Ensure **SMODS** + **Lovely** are installed
3. Launch Balatro

## Debug Tools

A **Debug: verbose logging** toggle is available in the SMODS mod settings. When enabled, it prints concise internal events like:

- Hand-size Joker disabled
- Pending increases and applied increases
- Base/permanent/total hand size values
- Gift lost due to boss defeat

By default, only warnings/errors are logged.

## Compatibility

- ✅ SMODS `1.0.0~BETA-1221a` and above
- ✅ Compatible with other hand-size mods (does not overwrite SMODS logic)
- ❌ Vanilla-only (SMODS is required)

## Strategy Tips

- **Endless Mode**: Crimson Heart becomes a real scaling tool
- **Juggler/Troubadour**: Each disable can grow your hand size over time
- **Stacking**: Multiple Crimson Heart appearances can stack permanent increases

---

If you want changes to UI, logging verbosity, or behavior timing, open an issue or tweak the mod config.
