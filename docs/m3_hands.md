# Milestone 3 "Hands" (close-up mode): plan and progress

This was milestone 2 before the pivot to a sanctuary town builder (see `docs/design.md`).
The design still holds, with one change: the hand only works in **close-up mode**. In Live
mode, LMB on a dog selects it (M2 Pack). Clicking the selected dog again enters close-up,
and Esc leaves it. The camera frames the dog, and the hand tool below takes over LMB.
Interactions must feel good: quick, juicy reactions, and every one grants bond (and XP
once M5 lands).

Read this when working on M3. Tick steps off here and in DEVELOPMENT.md Status as they land.

## Steps (`tools/verify.sh` after each, then commit)

- [x] 1. Plumbing: physics layers, WorldItem hold/detach, body API additions, DogTouchPrefs,
      TouchZones on the dog, save v2, headless test harness. Soak unchanged.
- [ ] 2. Close-up mode (enter/exit, camera framing) + HandTool + petting: hover/highlight, strokes -> `Dog.touch()` -> `DogBrain.on_touched()`,
      stimulus + forced re-eval, `enjoy_pets` and `duck_away` behaviors, overlay HANDS section, tests.
- [ ] 3. Hand feeding: kibble (from bowl) and treat (from new treat jar) pieces,
      `Dog.feed_from_hand()` -> `DogBrain.on_hand_fed()`, `come_for_food` behavior, tests.
- [ ] 4. Ball: `items/ball.tscn`, item bounds, throw from hand, `chase_toy` behavior, tests,
      record new soak baseline (the idle ball will shift wander/idle counts).
- [ ] 5. `--autohands` soak flag (simulated owner via HandTool API), README controls,
      `interaction/README.md`, DEVELOPMENT.md Status. Then do a windowed check on Windows.

## What already exists (step 1)

- Layers: 1 world, 2 dogs, 3 touch (`TouchZone.TOUCH_LAYER = 4`), 4 items (value 8), 5 item_bounds (16).
- `DogTouchPrefs` (`dog/brain/touch_prefs.gd`): `values` zone -> -1..1, `effective(zone, bond)`
  (bond < 30 lowers by up to 0.2), `reaction_for(pref)` -> likes (>= 0.25) / neutral / dislikes (<= -0.25).
  Rolled in `Dog.reroll_personality` from `roll_rng` after the personality. Lives at `brain.touch_prefs`.
- `TouchZone` (`interaction/touch_zone.gd`): Area3D, `zone_id`, `dog`, `set_highlight(on)`.
  Built by `Dog._build_touch_zones()` under BodyRoot; `dog.touch_zones[zone_id]`.
- `WorldItem`: `held`, `holder`, `attach_to(node)`, `detach(velocity)`, `is_held_by_player()`
  (holder in group `player_hands`), `remove()`, `get_root()`, `physics_body`, `movable`,
  `free_when_empty`, static `from_collider(collider)`.
- Dog body API added: `set_gait(&"walk"|&"run")`, `find_offered_item(aff)`, `can_reach(point)`,
  `pick_up(item)`, `drop_held(velocity)`, `get_mouth_position()`, `held_item`.
  `find_nearest_item` skips held items.
- Tests: `tests/test_runner.gd` (SUITES dict), `tests/test_suite.gd` (base: `check`, `check_near`,
  `frames`, `game_minutes`, `wait_until`), `tests/test_core.gd`. Add a suite per step
  (`test_petting.gd`, `test_feeding.gd`, `test_ball.gd`) and register it in SUITES.

## Design (approved)

**Controls.** RMB stays camera orbit. LMB on a zone: press = pat, drag = strokes (one per 0.15 m
of hand travel). LMB on food bowl = take a kibble handful (0.1 bowl fill); on treat jar = take a
treat; on the ball (floor or dog's mouth) = grab. Release food near the dog's head = hand-feed;
elsewhere = drop it on the floor (it's ordinary `food`, eat behavior finds it). Release the ball =
throw with recent hand velocity (slow release = drop). E stays as the old `pet()` fallback,
unchanged so `--autopet` soaks stay comparable.

**HandTool** (`interaction/hand_tool.gd`, Node3D in main.tscn, in group `player_hands` via an
anchor child the held item follows). Camera raycast with `collide_with_areas`, mask world|touch|items.
States: hover, petting, carrying. Cursor shape changes (pointing hand / drag), small 2D label
with the zone name, 3D hand marker. Code-facing API for tests and `--autohands`:
`stroke(dog, zone_id, strokes)`, `pick_from(item)`, `release_at(point)`, `throw_item(velocity)`.
Bowls and treat jar need a pickable collider on layer 4.

**Player -> dog entry points** (same pattern as `pet()`): `Dog.touch(zone, strokes)`,
`Dog.feed_from_hand(item)`, `Dog.notice(stimulus, source)`. Brain side: `on_touched`,
`on_hand_fed`, `on_stimulus` record timestamped stimuli (game minutes) and force the planner to
re-evaluate next tick (skip `min_duration`, but keep the emergency-override rule).

**Touch effects per stroke** (scale by `effective()` pref): liked -> affection and bond up, more
the more liked; neutral -> small affection; disliked -> small affection/bond loss and a duck.
Asleep + liked: stays asleep, small affection. Asleep + disliked: wakes and ducks.
Emotes: "<3" liked, "~" neutral, "!" disliked (ears flatten briefly).

**New behaviors** (all register in `DogBrain.setup()`; rows appear in overlay automatically):
- `enjoy_pets`: 0.95 while a liked/neutral touch is < 0.75 game min old and awake. Stop, face hand,
  sit (lie for belly). Succeeds after 1 game min without touch.
- `duck_away`: 1.0 right after a disliked touch (overrides eat/sleep), not interruptible.
  Walk to a nav point 0.8-1.4 m away from the hand.
- `come_for_food`: food held by hand within 4 m; score from hunger urgency, food_drive, bond;
  capped 0.85. Walk under the hand, sit, face it; re-path if it moves > 0.6 m. (M5 training lure.)
- `chase_toy`: base from toy_drive x fun urgency x energy gate; big bonus for a recent throw.
  States chase -> grab -> play/carry -> drop, plus a `RETURN` stub for M5 fetch. Runs
  (`set_gait(&"run")`), re-paths while the ball rolls, fails with cooldown if `!can_reach`.

**Hand feeding numbers (starting point).** Kibble handful: hunger +8, affection +4, bond +1.0.
Treat: hunger +3, affection +8, fun +5, bond +1.5. Scale bond by food_drive.
Hand-fed bond > bowl (bowl gives none).

**Ball.** `items/ball.tscn`: RigidBody3D root (layer 4, mask world|dogs|item_bounds) with a child
WorldItem (`toy`, `throwable`, `movable`, `physics_body` set). Invisible tall StaticBody3D walls on
layer 5 over the low south/east walls (not baked into navmesh). Respawn if y < -2.

**Overlay.** HANDS section: hand state, hovered zone, true prefs per zone (debug only), last
reaction. Update HELP_TEXT.

**Known open questions** (resolve during the milestone, don't block on them):
- Belly zone is hard to reach from the default camera; a `belly_up` pose may be needed.
- Dropped kibble and other spawned items are not saved (their scene paths don't exist on load).
