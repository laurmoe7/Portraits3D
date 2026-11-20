# Changelog

## Unreleased

- Options moved into the game's Settings panel (Options > AddOns > Portraits 3D: Forever Frames), styled like funFX: a General page and sub-pages for Look, Camera, Combo points and Tracked buffs, with the panel's own sliders and drop-down boxes, a tooltip on every option and the panel's Defaults button resetting the open page. A game without the Settings panel gets the same pages in a window with tabs.
- Combo points on the target's nameplate, on the top edge of its health bar and drawn above the cast bar, in Blizzard's modern round points or the classic red gems, with size and position settings (`/p3d combo`).
- Sliders to move the game's own combo points on the target frame (`/p3d combo frame move <x> <y>`, `/p3d dev combo`).
- Tracked buffs under the player frame (Slice and Dice, Adrenaline Rush, Blade Flurry, Evasion, Sprint, Cold Blood, Tiger's Fury, Dash, or any you add), styled like Blizzard's aura buttons, wrapping to a new line like the target frame's auras, with a preview for placing them (`/p3d buffs`). The game hides buffs from addons in combat, so there your own casts start the timers, from the length each buff had when last seen (Slice and Dice by combo points spent); `/p3d dev buffs` shows what the addon can read.

## 0.2 (2026-11-07)

- Dungeons and raids: units outside the group (whose identity the game keeps secret from addons) cannot be loaded as a 3D model there. They now get the game's own flat portrait, square and filling the custom frame, greyed and faded like the model for dead and offline units, instead of an empty frame.
- The flat portrait sits under the model and is replaced by the model when one loads after all (a pet's load can answer "no" and still come a moment later).
- A frame showing the flat portrait only takes the new picture on a portrait update, which stops a reload loop that stuttered the game.
- Each new target loads its model once: the portrait update the game raises right after a target change no longer loads it a second time.
- `/p3d dev debug` shows each frame's state, what the last model load answered and whether the model or the flat portrait is shown.
- Secret values from newer clients are guarded (unit class, PvP state); the class-colour background skips a unit whose class is secret.

## 0.1 (2026-10-16)

- First release: animated 3D portraits on the player, target, target of target, focus, pet and party frames, with the custom rounded-square frames, level badge, resting / combat glow, elite / rare / boss borders, backgrounds, camera settings, ghost and offline looks, options window and minimap button.
