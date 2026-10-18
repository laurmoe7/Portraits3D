# Portraits 3D: Forever Frames

Portraits3D is a World of Warcraft addon that replaces the flat portraits on the default unit frames with animated 3D models. Built for WoW Classic "Forever" (Interface 16001), which uses the modern-style unit frames.

## Features

- 3D portraits on the player, target, target of target, focus, pet and party frames, with the model's own idle animation.
- **Rounded square frame** option: swaps the round ring for a rounded-square gold border drawn to match the default frames, hides the round Blizzard ring behind it, and draws its own level badge and resting / combat glow. Elite, rare and boss dragon borders are redrawn on top of it.
- Size, position and camera per frame group (player, target + target of target + focus, party, pet), or one set of settings for every frame: frame size, frame position, camera zoom and turn, and the model's left / right and up / down.
- Background: black, gradient, class-colour gradient or transparent, with gradient height and opacity.
- Animation: all idles, basic idle only, or none.
- Grey portraits when the unit is dead, optional Zzz in rested areas, optional combat text on the player and pet frames.
- Per-frame on/off switches, a movable options window and an optional minimap button (off by default; turn it on in the options or with `/p3d minimap`).

## Install

Copy the `Portraits3D` folder to `World of Warcraft\_classic_beta_\Interface\AddOns\` (so you have `AddOns\Portraits3D\Portraits3D.toc`) and restart the game or `/reload`.

## Use

| Command | Does |
| --- | --- |
| `/p3d` | opens the options window |
| `/p3d on` / `off` | turns the 3D portraits on / off |
| `/p3d minimap` | shows / hides the minimap button |
| `/p3d blend` | switches the rounded square between the original and the blended look |

The options are also under Options > AddOns. For troubleshooting, `/p3d dev testparty` shows the party frames while solo, and `/p3d dev dump <unit>` and `/p3d dev debug` list what the addon found in each unit frame.

## Notes

- Model frames cannot be masked to a circle, so the addon hides the corners behind the unit frame's ring art (round look) or draws its own border over the model (rounded square look).
- The rounded square look hides part of Blizzard's frame picture with a mask. The positions were measured on the default frames at default UI scale; other UI addons that restyle the unit frames may need different values.
- `tools/make_frame.py` (needs numpy) redraws the textures in `Textures/`.

## License

MIT
