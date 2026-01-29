# CrimsonGift

[中文说明](README_zh.md)

**Crimson's Gift** — When Crimson Heart disables a hand-size Joker, your run gains a permanent hand size increase. It is intentional, powerful, and built for endless runs.

## Why This Mod Exists

SMODS `1.0.0~BETA-1221a` and later fixed the vanilla Crimson Heart hand-size bug. This mod restores that behavior as an intentional, balanced mechanic.

## How It Works

- Disabling a hand-size Joker **preserves** the hand size (no drop)
- When a non-hand-size Joker is disabled, the gift is **applied immediately**
- Multiple hand-size Jokers disabled in sequence → keep the **largest** bonus
- **If the boss is defeated while gift is pending**, special rules apply (see below)

## Gift Application

| Scenario | Result |
|----------|--------|
| h_size Joker disabled → non-h_size Joker disabled | Gift applied immediately |
| Single h_size disabled → boss defeated by next play | Gift **lost** |
| Multiple h_size disabled → boss defeated by next play | Keep **largest** (excluding last) |

## Example

1. You have Troubadour (+2 hand size) → hand size is `10/10` (base 8 + Troubadour 2)
2. Crimson Heart disables Troubadour → display stays `10/10` (preserved)
3. Next cycle: Fortune Teller (no h_size) disabled → gift +2 applied
4. Hand size stays `12/12` (base 8 + Troubadour 2 + gift 2)
5. If you sell Troubadour later → hand size becomes `10/10` (base 8 + gift 2)

**Note:** The gift is a permanent bonus separate from the joker. The disabled joker still contributes its hand size until sold.

### Boss Defeat Scenarios

**Single disable:**
1. Troubadour (+2) disabled → pending +2
2. You defeat the boss on this hand → gift **lost**, stays `10/10`

**Multiple disables:**
1. Troubadour (+2) disabled → pending +2
2. Juggler (+1) disabled → pending +1, max_excluding_last = +2
3. You defeat the boss → keep +2, hand size becomes `12/12`

## Requirements & Compatibility

- **SMODS and Lovely required** (no vanilla support)
- **Minimum SMODS version:** `1.0.0~BETA-1221a`
- Compatible with other hand-size mods (does not overwrite SMODS logic)
- Compatible with Save Rewinder (state persists correctly)

## Installation

1. Download and extract the [latest release](https://github.com/Liafonx/Balatro-CrimsonGift/releases) — it contains a `CrimsonGift` folder
2. Copy the `CrimsonGift` folder into your Balatro `Mods` directory
3. Launch Balatro

## Languages

- English
- 简体中文 (Simplified Chinese)

## Notifications

| Event | Message |
|-------|---------|
| First h_size disabled | "Crimson's Gift is arriving, hand size +N" |
| Consecutive h_size disabled | "Consecutive bonuses: keeping hand size +N" |
| Gift applied | "Crimson's Gift applied, hand size +N" |
| Boss defeated (single) | "Crimson Heart defeated, gift lost" |
| Boss defeated (multiple) | "Boss defeated: keeping hand size +N" |

## Strategy Tips

In endless runs, we often use the combination of Baron, Mime, and red-seal Steel Kings to tackle the climb. That core scales best with larger hands, so hand size and Joker slots quickly become limiting factors. Negative Jokers are rare, so players often rely on Ectoplasm to add Negative to existing Jokers—but Ectoplasm also reduces hand size. Crimson Gift offsets that penalty, allowing you to take more Ectoplasm rolls without shrinking your hand size so much that you lose the game. Because viable endless seeds are rare and long runs can take hours, a single hand-size bottleneck can ruin a run; Crimson Gift slightly improves the odds without breaking balance.
