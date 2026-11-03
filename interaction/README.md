# interaction/

Milestone 3, the player's hand in close-up mode. See `docs/m3_hands.md` for the plan and progress.

- `touch_zone.gd`: `TouchZone` Area3D (head, ears, back, belly) on physics layer 3. The Dog
  builds four of them on its BodyRoot. The per-dog preferences live in
  `dog/brain/touch_prefs.gd`.
- `hand_tool.gd`: `HandTool`, the hand cursor (node `HandTool` in main.tscn). Off in Live
  mode; `main.gd` turns it on for the close-up dog. A camera raycast (world, touch, items)
  finds the zone under the cursor and highlights it. Press = pat, drag = strokes (one per
  0.15 m of hand travel), both through `Dog.touch(zone, strokes, hand_point)`. Its `Anchor`
  child is in group `player_hands`; held items follow it.
  Code API: `stroke(dog, zone_id, strokes)`, `press_zone`, `drag_to`, `release`, and
  `pick_from` / `release_at` / `throw_item` (food and ball, steps 3–4).

E still pets the selected dog the old way (`Dog.pet()`), kept for `--autopet` soaks.
