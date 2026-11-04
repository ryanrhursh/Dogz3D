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
  Pressing on the food bowl or treat jar takes a piece (the item's `hand_piece`); the hand
  carries it 0.35 m over the floor and nearby dogs come for it. Letting go within 0.45 m
  of an awake dog's mouth calls `Dog.feed_from_hand(item)`; anywhere else drops it.
  Pressing on the ball (on the floor, or in a dog's mouth: the dog drops it) grabs it.
  While carrying, the hand keeps its last 0.1 s of points; letting go with the hand moving
  faster than 1.2 m/s (flat) throws with that velocity plus some lift, capped at 7 m/s
  (`throw_item`), a slower release drops it. Awake dogs within 10 m `notice(&"ball_thrown")`
  and `chase_toy` reacts at once.
  Code API: `stroke(dog, zone_id, strokes)`, `press_zone`, `drag_to`, `release`,
  `pick_from(item)`, `carry_to(point)`, `release_at(point)`, `throw_item(velocity)`,
  `hand_velocity()`, `add_hand_sample(point, at)`, static `throw_from_hand(v)`.

- `auto_hands.gd`: `AutoHands`, the simulated owner for `--autohands` soaks. Every 15
  game minutes (07:00 to 22:00) it feeds, strokes or throws for the dog that needs it most,
  through the code API above only, rotating which comes first. See `docs/m3_hands.md`
  step 5.

E still pets the selected dog the old way (`Dog.pet()`), kept for `--autopet` soaks.
