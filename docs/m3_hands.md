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
- [x] 2. Close-up mode (enter/exit, camera framing) + HandTool + petting: hover/highlight, strokes -> `Dog.touch()` -> `DogBrain.on_touched()`,
      stimulus + forced re-eval, `enjoy_pets` and `duck_away` behaviors, overlay HANDS section, tests.
- [x] 3. Hand feeding: kibble (from bowl) and treat (from new treat jar) pieces,
      `Dog.feed_from_hand()` -> `DogBrain.on_hand_fed()`, `come_for_food` behavior, tests.
- [x] 4. Ball: `items/ball.tscn`, item bounds, throw from hand, `chase_toy` behavior, tests,
      record new soak baseline (the idle ball will shift wander/idle counts).
- [x] 5. `--autohands` soak flag (simulated owner via HandTool API), README controls,
      `interaction/README.md`, DEVELOPMENT.md Status.
- [ ] Windowed check on Windows (by hand: feel of petting, feeding, throwing; see the
      known open questions below). Then M3 is done.

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

## What step 2 added

- Close-up: `main.gd` `click_dog()` (Live LMB: select, or close-up if already selected),
  `enter_closeup(dog)`, `exit_closeup()` (Esc), `closeup_dog`. Tab in close-up moves it to
  the next dog. `--closeup` starts in it (screenshots). `camera_rig.gd`
  `enter_closeup/exit_closeup/is_closeup/snap_view`: distance 1.9, pitch -32, zoom 0.9-3.5,
  panning locked, eased zoom/pitch; exit restores distance, pitch, look height and follow.
  The close-up dog's 3D label shrinks to emotes only (`Dog.set_closeup`).
- `HandTool` (`interaction/hand_tool.gd`, node `HandTool` in main.tscn, group `hand_tool`):
  states off/hover/petting(/carrying later), `hovered_zone`, `last_reaction`, `anchor`
  (group `player_hands`). `press_zone(zone, point)` pats, `drag_to(point, zone)` strokes,
  `release()`; mouse input goes through these. `stroke(dog, zone_id, strokes)` for code.
  `pick_from/release_at/throw_item` are stubs. Top-center hint label in close-up.
- `Dog.touch(zone, strokes = 1, hand_point = above the zone)` -> reaction; emotes, ears
  flatten for `EARS_FLAT_SECONDS` (0.8 real s). `Dog.point_away_from(from, min, max)`.
- `DogBrain.on_touched(zone, strokes, asleep, point)`, `stimuli` (kind -> dict, not saved),
  `get_stimulus(kind)`, `stimulus_age(kind)`, forced re-eval (`_force_eval`).
- Behaviors `enjoy_pets`, `duck_away` (registered last). Tests: `tests/test_petting.gd`.

## Decisions (step 2)

- **Touch numbers per stroke** (constants at the top of `dog_brain.gd`): liked: affection
  2 + 4 x pref, bond 0.05 + 0.15 x pref. Neutral: affection +1. Disliked: affection -1,
  bond -(0.1 + 0.2 x |pref|). Asleep + liked: affection +1, no bond. Asleep + neutral: as
  neutral. Asleep + disliked: as disliked, and duck_away (1.0) overrides sleep, which
  wakes it. No fun gain from strokes (E `pet()` still gives fun, unchanged).
- **A pat is sent on press** (immediate feedback); travel while held over a zone of the
  close-up dog adds strokes on the zone under the hand. Travel is measured on a plane
  through the press point facing the camera, so it doesn't depend on the dog's shape.
  Travel off the dog doesn't count.
- **Only the close-up dog responds** to the hand; other dogs' zones are ignored.
- **Stimuli count from when the brain reacts**: a new stimulus gets its time re-stamped
  on the forced re-evaluation. Without that, at 60x (a game minute per frame) a touch was
  already older than the 0.75 min window by the next tick.
- **Forced re-eval** skips min_duration and the per-frame eval budget; the planner's
  non-interruptible rule still applies. enjoy_pets (0.95) is above OVERRIDE_SCORE, so a
  liked touch also interrupts eat/drink/wait_turn; accepted (the dog turns to you).
- **duck_away** walks to `point_away_from(hand point)`: a fan of directions around
  "straight away", then `random_point_near`. If the hand is right above the dog it goes
  forward. A new disliked touch while ducking re-paths from the new spot. Gives up after
  2 game min.
- **enjoy_pets** faces the hand only when it's >= 0.3 m out (flat), else just sits; lies
  for the belly. Keeps 0.5 while running between 0.75 and 1 min after the last touch.
- Touch log lines merge: the same zone and reaction within 1 game min extends the stroke
  count instead of adding a decision-log line.

## What step 3 added

- `FoodPiece` (`items/food_piece.gd`, extends WorldItem): `hand_hunger`, `hand_affection`,
  `hand_fun`, `hand_bond`, `hand_fed_effects()`. Scenes `items/kibble.tscn` (food, fill
  0.1) and `items/treat.tscn` (food + treat, fill 0.05); both `movable`, `free_when_empty`.
- WorldItem: `hand_piece` (PackedScene) + `hand_piece_fill` (0.1): what the hand takes and
  how much fill it uses. Static `any_held_by_player()` (kept by attach_to/detach/remove).
  `find_offered_item` early-outs on it.
- Food bowl got `hand_piece = kibble` and a `Pick` Area3D on layer 4. New
  `items/treat_jar.tscn` (affordance `treat_jar`, 10 treats, `Pick` area) on the table at
  (1.95, 0.75, 0.75). F refills the bowl and the jar.
- HandTool: state `carrying`, `held_item`, `hovered_item`; `pick_from(item)` (piece from a
  bowl/jar, or a loose movable item), `carry_to(point)`, `release_at(point) -> Dog`
  (feeds the nearest awake dog whose mouth is within 0.45 m, else drops to the surface
  below). Carried food floats 0.35 m over the floor, or sits on a touch zone. Dogs within
  4 m `notice(&"food_offered")` on pick and every 1.5 m of hand travel.
- `Dog.feed_from_hand(item) -> bool` -> `DogBrain.on_hand_fed(effects, treat)`;
  `Dog.notice(stimulus, point)` -> `DogBrain.on_stimulus(kind, point)` (records and forces
  a re-eval). `can_reach(point, slack)` takes an optional slack. `get_dog_info` has `pose`.
- `come_for_food` (registered after duck_away). Eat now counts a piece that vanished after
  it ate some as done, not failed. Spawned pieces aren't saved. Tests: `tests/test_feeding.gd`.

## Decisions (step 3)

- **Numbers** as the design: kibble hunger +8, affection +4, bond 1.0; treat hunger +3,
  affection +8, fun +5, bond 1.5. Bond x lerp(0.7, 1.3, food_drive). Bowl food: no bond.
- **Pieces are data, not code**: the bowl/jar say what piece they give (`hand_piece`) and
  the piece carries its hand-fed numbers. Dropped, a piece is ordinary `food` whose fill is
  in bowl units, so eating it from the floor gives about what the bowl would (kibble 0.1
  fill = 1.25 min = 7.5 hunger).
- **Treat jar** is limited (10 treats, F refills) so treats can't be farmed endlessly.
- **Any awake dog** at the hand can be fed, not only the close-up dog (a crowd forms).
- **come_for_food score**: (0.3 + 0.6 x hunger urgency) x lerp(0.6, 1.3, food_drive)
  x lerp(0.85, 1.15, bond / 100), +0.15 for a treat, cap 0.85. Range 4 m (5 m once coming).
  Even a full dog comes over a little (0.3 base): it's curious about food in your hand.
- **Spots round the hand**: each dog waits 0.55 m out (its mouth is then under the hand)
  on a ring, from its own side, picking the reachable spot with the most clearance from
  the dogs already there. On arrival, if a dog within 0.4 m is sitting there already or
  has the smaller dog_id, it moves round the ring (up to 6 times). Without this a pack
  piled into one spot. Re-paths when the hand moves > 0.6 m; gives up after 10 min.
- **Close-up max zoom raised to 5 m** so the bowl and jar can be reached from close-up.
- **Labels in close-up**: the close-up dog's 3D label shows only emotes, other dogs' show
  only their name, both at 0.45x size (`Dog.set_label_mode`).
- **pack30** (not baseline-checked) is chaotic with respect to physics scene contents:
  the new Area3D pick colliders shift its counts slightly. The 1- and 12-dog baselines are
  unchanged.

## What step 4 added

- `items/ball.tscn`: RigidBody3D root (layer 4 = value 8, mask world|dogs|item_bounds = 19,
  mass 0.06, bounce 0.55, friction 0.8, linear damp 0.4, angular damp 2, continuous CD,
  freeze mode kinematic, `can_sleep` off) with child `Item` = `Ball` (`items/ball.gd`,
  extends WorldItem: affordances `toy`, `throwable`, `movable`, approach radius 0.5,
  `physics_body` = root). Below y -2 it comes back at `respawn_point` (its start). One sits
  in main.tscn at (1.6, 0.06, 2.4), saved as `Items/Ball/Item`.
- Item bounds: `ItemBounds/South` and `ItemBounds/East` in main.tscn, 2.5 m tall, 0.4 m
  thick StaticBody3Ds on layer 5 (16) over the low south and east walls. Outside the
  navmesh region (and its bake mask is 1 anyway); dogs (mask 1) walk through them.
- HandTool: `pick_from` takes the ball from a dog's mouth too (`Dog.drop_held` first);
  hover highlights it there. While carrying it records hand points (`add_hand_sample`,
  `hand_velocity()` over the last 0.1 real s). Mouse release: `throw_from_hand(v)` (flat
  speed >= 1.2 m/s, vertical part capped at 2 m/s, lift 0.3 x flat speed) then
  `throw_item(v)`, else `release_at`. `throw_item(velocity) -> bool` caps at 7 m/s,
  detaches with that velocity and has awake dogs within 10 m `notice(&"ball_thrown")`.
  The hand ray excludes the carried ball. Physics items dropped from the hand fall from
  the hand instead of being placed on the floor. Food notices only fire for food.
- `WorldItem.detach` wakes the body (`sleeping = false`). `Dog.drop_held` pulls a dropped
  physics item back out of a wall the mouth pokes into. `Dog.find_nearest_item(aff,
  ignore_claims)`: a thrown ball is anyone's.
- `chase_toy` (`dog/brain/behaviors/chase_toy.gd`, registered last, label "Play ball").
  Overlay HANDS shows "saw a throw N min ago"; HELP_TEXT and the close-up hint (now two
  lines, clear of the overlay) mention the ball.
- Tests: `tests/test_ball.gd` (11). `TestSuite.before_each` parks the ball on the table
  (`park_ball()`, out of reach) so other suites run as before; `get_ball()` finds it.

## Decisions (step 4)

- **chase_toy score.** Lying about: (0.08 + 0.6 x fun urgency) x lerp(0.6, 1.3, toy_drive)
  x energy gate ((energy - 25) / 30, clamped), only with fun urgency >= 0.05, 60 game min
  after its last game, and if the ball is reachable (cached by ball position). A fresh
  throw (stimulus < 2 game min, re-stamped on reaction) adds 0.45 x lerp(0.8, 1.2,
  toy_drive) x gate and skips the fun, gap and reach checks. Cap 0.85 (never interrupts
  eat/sleep). 0.5 while running; stops below 20 energy. Early-outs (sleeping, gate,
  stimuli/fun/gap) come before the item scan.
- **One throw, one chase**: a dog remembers the throw it went after, so it doesn't
  re-chase the ball it just dropped while the throw is still fresh.
- **A ball lying about is one dog's game** (it claims the ball, `max_users` 1); **a thrown
  ball is a race** (no claim). Near the ball (1.4 m) a dog that sees another chaser nearer
  (tie: smaller dog_id) stops and watches (WATCH); when someone grabs it, the others end
  their game as done, not failed. This stops the pile-up at the ball.
- **States**: CHASE (run, re-path when the ball has rolled 0.3 m from the aim) -> grab
  when the mouth is within 0.3 m flat of a ball that is down (y <= 0.45), or when stopped
  within 0.8 m -> PLAY (walk 1-3 legs of 1-3 m with it, max 8 min) -> DROP (toss 1 m/s
  forward, 0.6 up) -> done. RETURN is a stub for M5 fetch (`fetch` flag, goes to DROP).
  Fails with a 20 min cooldown if a resting ball can't be reached (not while it's still
  moving faster than 0.3 m/s), if stuck, or after 6 min of chasing. Fun +1.5/min, energy
  -0.3/min. The hand taking the ball ends the game as done.
- **Baselines moved once, on purpose**: the idle ball makes chase_toy score without hand
  input. One dog: idle 85, wander 22, chase_toy 11, drink 10, eat 10, sleep 7 (lowest
  fun went up from 47 to 59). 12 dogs: chase_toy 23 of about 1750 choices (one ball, one
  dog at a time). Stable over repeated runs.
- **Physics**: the ball never sleeps (`can_sleep` off): Godot's sleep timer kept running
  while it was frozen in the hand, so a slow drop hung in the air. One body, negligible cost.
- pack30 counts shifted again (chaotic, not baseline-checked); no errors, needs sane.

## What step 5 added

- `AutoHands` (`interaction/auto_hands.gd`), created by `main.gd` for `--autohands`: a
  simulated owner that only uses the HandTool code API. Every 15 game minutes between
  07:00 and 22:00 it does one thing, starting each turn with the next kind in rotation
  (feed, pet, throw) and falling through to the others when nobody needs it:
  - feed: the awake dog with the lowest hunger below 85; `pick_from` the bowl (a treat
    from the jar 25% of the time), `carry_to` 1.2 m from the dog toward the room's centre,
    then each frame lets go (`release_at`) once the dog's mouth is within 0.45 m of the
    hand, or after 6 game min takes it to the dog's mouth. A dog that fell asleep gets it
    dropped.
  - pet: the awake dog with the lowest affection below 60; `stroke(dog, zone, 3)`. It
    learns per dog: a zone it liked, else one not tried yet, else one it didn't mind.
  - throw: the awake dog with the lowest fun below 90 and energy >= 50; `pick_from` the
    loose ball, `carry_to` 0.7 m beside the dog, `throw_item` away from it at 3-5 m/s plus
    1.2 up.
  Own RNG (`hash([seed, "autohands"])`), so seeded runs repeat. The soak summary adds a
  `Hands:` line (strokes, kibble, treats, dropped, throws).
- `tools/verify.sh hands`: 12 dogs, `--autofeed --autohands`, 48 h; checks ERROR/WARNING
  and prints needs and the Hands line. Not in the default run and not baseline-checked.
- Tests: `tests/test_autohands.gd` (4).

## Decisions (step 5)

- **Separate from `--autopet`**: E, `Dog.pet()` and `--autopet` are unchanged, and the
  default verify runs use neither the hand nor AutoHands, so the baselines stay as step 4
  recorded them.
- **Generous thresholds** (hunger 85, affection 60, fun 90): with `--autofeed` the dogs
  are rarely really hungry or bored, and the point of the soak is to exercise every hand
  path for hours. With the stricter first try (45/45/60) the owner only ever petted.
- **Rotation**: in a 12-dog pack some dog is always lonely; without rotating which action
  goes first, petting crowded out feeding and throwing.
- Reference (seed 42, 48 h): one dog: strokes 9, kibble 10, treats 6, throws 4,
  come_for_food 15, chase_toy 19, bond 43 (30 with `--autopet`). 12 dogs: strokes 126,
  kibble 47, treats 16, throws 11, come_for_food 336 (a crowd comes each time), chase_toy
  92. One owner can't keep 12 dogs' affection up the way `--autopet` does (lowest 17,
  average 27); fine, it's a coverage soak, not a care model.

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
  Since step 3 SaveManager skips `free_when_empty` items, so saves stay clean.
- Food dropped on the table top is food a dog can't reach; eat walks there, gets stuck
  and fails with its cooldown. Drop only onto reachable floor, or let dogs skip
  unreachable food (`can_reach`), if it shows up in play.
- Close-up only frames one dog; reaching the bowl or jar means zooming out (wheel) or
  orbiting. A treat pouch or a hotkey may feel better; check in the windowed test.
