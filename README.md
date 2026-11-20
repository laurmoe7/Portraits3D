# Portraits 3D: Forever Frames

Portraits3D is a World of Warcraft addon that replaces the flat portraits on the default unit frames with animated 3D models. Built for WoW Classic "Forever" (Interface 16001), which uses the modern-style unit frames.

## Features

- 3D portraits on the player, target, target of target, focus, pet and party frames, with the model's own idle animation.
- Portraits 3D's own rounded-square portrait frames in place of Blizzard's round ones. Each sits where Blizzard's ring is, at its size and shaded like it, so the name plate and bars run into it as they do into the ring; only the ring is removed from Blizzard's frame picture. Comes with its own level badge (Blizzard's level circle, with the level in Blizzard's difficulty colours on units you can attack) and a resting / combat glow, and the elite, rare and boss dragon borders are drawn on top (the Elite border mover in the options lines them up by hand).
- Camera per frame group (player, target + target of target + focus, party, pet), or one set of settings for every frame: zoom and turn, the model's left / right and up / down, and the model's size inside the frame. Right-click a slider to put it back to its default.
- Background: black, gradient, class-colour gradient or transparent, with gradient height and opacity.
- Animation: all idles, basic idle only, or none.
- Dead units appear as a see-through black-and-white ghost; offline players in black and white with a disconnect bolt. A player the game cannot build a model for (out of sight since a `/reload`) gets a grey gradient instead, plus the bolt if offline.
- In dungeons and raids the game lets no addon load a 3D model of a unit outside the group (its identity is secret there); those units get the game's own flat portrait inside the frame instead.
- Optional Zzz in rested areas, and options to hide the combat text and the crossed-swords combat icon on the player and pet frames.
- Combo points on your target's nameplate (on the top edge of its health bar, in Blizzard's own combo point art), and a slider to move the game's own combo points on the target frame.
- Your important buffs (Slice and Dice and the like) under the player frame, with the time left under each. The game hides buffs from addons in combat, so there a buff you cast yourself is timed from your cast (as long as it lasted when it was last seen, Slice and Dice by combo points); the real buffs are read again when combat ends.
- Per-frame on/off switches, options under Options > AddOns with a page each (General, Look, Camera, Combo points, Tracked buffs) and an optional minimap button (off by default; turn it on in the options or with `/p3d minimap`).
- `/p3d off` gives Blizzard's frames back exactly as they were, the hidden combat text and icon included.

## Install

Copy the `Portraits3D` folder to `World of Warcraft\_forever_\Interface\AddOns\` (so you have `AddOns\Portraits3D\Portraits3D.toc`) and restart the game or `/reload`.

## Use

| Command | Does |
| --- | --- |
| `/p3d` | opens the options (Options > AddOns > Portraits 3D) |
| `/p3d on` / `off` | turns the 3D portraits on / off |
| `/p3d minimap` | shows / hides the minimap button |
| `/p3d combo` | turns the combo points on the target's nameplate on / off; `scale <n>` and `move <x> <y>` size and move them, `modern \| classic` picks their art; `/p3d combo frame move <x> <y>` moves the game's own combo points on the target frame |
| `/p3d buffs` | lists the buffs tracked under the player frame (Slice and Dice, Adrenaline Rush, Blade Flurry, Evasion, Sprint, Cold Blood, Tiger's Fury, Dash); `on` / `off`, `add <name or spell ID>`, `remove <name or ID>`, `reset`, `size <n>`, `move <x> <y>` |

Each options page has a tooltip on every option, and the panel's own Defaults button resets the page that is open.

For troubleshooting (`/p3d dev` lists them all):

| Command | Does |
| --- | --- |
| `/p3d dev testparty` | shows the party frames with your model while solo |
| `/p3d dev vehicle` | opens a preview of the player and target vehicle frames with the custom frame (built from the addon's own frames; the game's are not touched) |
| `/p3d dev buffs` | shows whether the game lets the addon read your buffs right now, what the row shows and the buff lengths it remembers |
| `/p3d dev combo` | shows which of the game's frames holds the target frame's combo points, and where it sits before it is moved |
| `/p3d dev debug` | lists the portrait and ring the addon found in each unit frame, and what each frame shows (its state, what the last model load answered, whether the model or the flat portrait is shown) |
| `/p3d dev dump <unit>` | lists the named pieces inside a unit frame |
| `/p3d dev ring <unit>` | shows what the custom frame measured for that frame's ring |
| `/p3d dev shown <unit>` | lists Blizzard's pictures still drawn around the portrait |

## Notes

- Model frames cannot be masked to a shape, so the model sits in a square clipping frame and the addon draws its own border over it.
- The frames find Blizzard's ring from the part of the game's unit frame picture each frame shows; the ring positions were measured from that picture (see `RINGS` in `Portraits3D.lua`). Other UI addons that restyle the unit frames will not line up.
- `tools/make_blend_frame.py`, `tools/make_frame.py` and `tools/make_bolt.py` (need numpy) redraw the textures in `Textures/`. The game keeps a texture it has loaded until it restarts, so when one changes, save it under a new name.

## Changes

See `CHANGELOG.md`.

## License

MIT
