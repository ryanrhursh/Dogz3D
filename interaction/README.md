# interaction/

Milestone 2, the player's hand. See `docs/milestone2.md` for the plan and progress.

- `touch_zone.gd`: `TouchZone` Area3D (head, ears, back, belly) on physics layer 3. The Dog
  builds four of them on its BodyRoot. The per-dog preferences live in
  `dog/brain/touch_prefs.gd`.
- Coming next: `hand_tool.gd` (camera-raycast hand cursor for petting, carrying food and
  throwing the ball).

Until the hand lands, press E in game to pet the dog (kept afterwards as a fallback).
