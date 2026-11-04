# Milestone 2 "Pack": plan and progress

Goal: 10–30 autonomous dogs share one home. The player selects a dog to follow and inspect
it. Dogs share bowls and beds without piling up, and they notice each other.

## Steps

- [x] 1. **Pack and selection.** Done; see "Step 1 outcome" below.
  - Pack: `dog/pack.gd`, a node in group `pack` that spawns dogs from `dog/body/dog.tscn`.
    Each dog gets a unique `dog_id` and a name from a list. Dog 0 keeps seed N and the old
    spawn point, so the seed-42 single-dog soak stays exact; dog i uses seed N + i*7919.
  - Selection:
    - LMB on a dog's body (layer 2) or Tab selects it; the camera follows the selected dog.
    - The debug overlay shows the selected dog; every dog keeps its status label.
    - Clicking the already-selected dog is reserved for close-up mode (M3).
  - Item sharing: WorldItem `max_users` plus `reserve(dog)` / `release(dog)`.
    `find_nearest_item` skips items other dogs have filled. Consume and sleep reserve on
    enter and release on exit. With no free bed, a dog sleeps where it stands.
  - Save/load spawns any saved dog that is missing and frees dogs that aren't in the save.
    `SaveManager.save_game(path)` and `load_game(path)` take an optional path for tests.
  - Debug: `--dogs=N` (default 1), the N key adopts a dog, autopet covers every dog, and the
    soak summary prints one line per dog plus the totals.
  - Tests: unique ids and seeds, reservation is exclusive, selection, save round-trip with
    3 dogs.
- [x] 2. **Dog to dog.** Done; see "Step 2 outcome" below.
  - Separation: a cheap separation steer, active only when another dog is within range.
  - Relationships: `DogMemory.relationships`, dog_id mapped to -1..1 affinity.
  - Behaviors: `greet`, `play_together`, bed sharing for dogs with high affinity.
  - Body API: `find_nearest_dog(max_dist, filter)`, `get_dog_info(id)` and friends.
- [x] 3. **Pack scale and UI.** Done; see "Step 3 outcome" below.
  - 30-dog soak with frame time recorded.
  - Brain evaluations staggered across frames.
  - `wait_turn`: a dog waits in line near a busy bowl instead of going without.
  - Player-facing dog card for the selected dog (I toggles), separate from F3.
  - The multi-dog soak is deterministic, and its exact baseline is checked by
    `tools/verify.sh`.

## Step 1 outcome (decisions to keep)

- `Pack` (`dog/pack.gd`) replaced the `Dog` node in main.tscn. It handles populate, adopt,
  remove_dog, select, select_next, get_dog and sync_to_ids, and emits selection_changed,
  dog_added and dog_removed. `Dog.retire()` takes a dog out of the sim before it's freed.
- Item sharing goes through the body API: `Dog.claim_item(item)` and `release_item(item)`
  wrap `WorldItem.reserve` and `release`, and `max_users` defaults to 1. A full item is
  invisible to `find_nearest_item`, so the dog simply picks another behavior (waiting in line
  is step 3).
- Clicking picks via a ray against layers world, dogs and touch, so walls block it.
  `main.pick_dog_at(screen_pos)`.
- Saves now use full-precision JSON floats. Before, traits lost precision on save; the
  pack save test caught it.
- `tools/verify.sh` gained a `pack` step (12 dogs, 48 h; errors and sane ranges only).
  Reference run: about 19 s; per dog roughly wander 34, idle 85, eat 10, drink 10, sleep 6.
  Lowest thirst across the pack is about 32–38, from the single water bowl.
- The one-dog seed-42 soak is still exact: idle 90, wander 24, drink 11, eat 9, sleep 5.

## Step 2 outcome (decisions to keep)

- Separation is a steer, not NavigationAgent3D avoidance: `Dog._separation_push()` sums
  pushes from dogs closer than 0.65 m and is added to the path direction only when it is
  non-zero, so a lone dog's movement is bit-identical. It switches off within 1 m of the
  destination so friends can reach the same bed. Dogs still don't collide physically.
  A static `Dog._all_dogs` list avoids a group query every physics tick.
- Body API for other dogs (brains only ever see ids and info dictionaries, never a Dog):
  `find_nearest_dog(max_dist, filter) -> id`, `get_dog_info(id) -> {id, name, position,
  distance, doing, sleeping, moving, mood, partner, affinity_to_me}`, `invite_dog(id, kind)`
  / `get_invite(kind)` / `clear_invite(kind)` (invitations expire after 4 game minutes),
  `notify_dog(id, kind)` (the other body passes it to its own brain via
  `DogBrain.on_social`), `set_social_partner(id)`, `find_shared_item(affordance,
  min_affinity)` and `claim_item(item, shared)`.
- Relationships: `DogMemory.relationships` (saved) maps dog_id to affinity -1..1; unknown
  dogs are 0 and `knows(id)` is false. `last_greeted` is not saved. `FRIEND_AFFINITY` 0.5.
  No decay toward 0 yet.
- `greet`: walk up to the nearest awake dog within 6 m that isn't eating, drinking or playing
  and wasn't greeted in the last 3 h; sniff 1–2.5 min. 60 min gap between greetings.
  Strangers score a bonus. Affinity +0.04..0.08 (sociability) for the greeter, +0.05 for
  the greeted dog. If the other dog's mood is below -0.3 it goes badly (both lose a little).
- Other dogs only top up affection to 60 (`SOCIAL_AFFECTION_CAP`), so they can't replace
  the player. Without the cap, greetings kept affection so high that autopet never fired.
- `play_together`: needs a dog it already knows with affinity >= 0, energy >= 40 and a 60 min
  gap. The initiator invites and waits up to 5 min; the partner accepts through its own
  planner (accepting ignores the gap and needs energy >= 32). Chaser and fleer swap on a
  tag (0.8 m, 1 min cooldown). Runs, +3 fun/min, -0.35 energy/min, +0.008 affinity/min,
  6–12 min. The game ends for both when either stops.
- Bed sharing: `WorldItem.share_slots` (bed: 1) are extra slots usable only when every
  current user and the newcomer have mutual affinity >= 0.5. Sleep tries a free bed first,
  then a friend's bed, then the floor.
- Both social behaviors are registered last, score 0 with no dog near, and only use
  `brain.rng` in enter(). While running they return a fixed continue score, so they aren't
  dropped just because the partner no longer passes the "free to play" filter.
- The one-dog seed-42 soak is still exact. Reference 12-dog run (before step 3): greet ~265, play ~285,
  wander ~215, idle ~770; every dog knows all 11 others and has 1–4 friends after 48 h;
  about 4 shared-bed sleeps. Bond averages ~26 (was ~30) because dogs need petting a
  little less often. Lowest thirst ~30–34 from the single water bowl (step 3's wait_turn).
- Debug overlay shows the four strongest relationships; the soak summary prints
  knows/friends/best per dog.
- Save v3 adds relationships. `SaveManager.migrate(data)` upgrades older save
  dictionaries one version step at a time (v2 -> v3 adds empty relationships) and is tested
  directly and through a real v2 file.

## Step 3 outcome (decisions to keep)

- Determinism: the run-to-run drift came from `random_point_near`'s fallback,
  `NavigationServer3D.map_get_random_point`, which uses the engine's global RNG (seeded
  randomly at startup). `main.gd` now calls `seed(N)` for `--seed=N`. Found by diffing
  per-frame dog positions of two runs. `navigation/world/map_use_async_iterations=false` is
  also set so the navmesh sync can't land on a different frame; it alone did not fix it.
- Exact baselines (Godot 4.6.1 Linux headless, seed 42, 48 h), checked by `tools/verify.sh`
  (it fails with BASELINE CHANGED; update both there and here when a change is intended):
  - One dog: idle 85, wander 22, chase_toy 11, drink 10, eat 10, sleep 7 (since M3 Hands
    step 4, the ball; before it, unchanged since M1: idle 90, wander 24, drink 11, eat 9,
    sleep 5).
  - 12 dogs: idle 720, play_together 263, greet 243, wander 177, wait_turn 103, sleep 98,
    eat 59, drink 59, chase_toy 23. Lowest thirst 44, lowest hunger 48. (Before the ball:
    idle 656, play_together 266, greet 242, wander 174, wait_turn 106, sleep 97, eat 57,
    drink 48.)
- Frame time (wall clock, this 4-core cloud container; `Frame time:` line in every soak
  summary, not part of the baseline):

  | Dogs | 1x (60 physics ticks/s) | 60x soak (600 ticks/s) |
  |------|-------------------------|------------------------|
  | 1    | 0.4 ms                  | 2.6 ms                 |
  | 12   | 1.3 ms                  | 6.8 ms                 |
  | 30   | 2.7 ms (p95 3.9)        | 14.4 ms (p95 19.8)     |

  At 60x, the brains of 30 dogs cost about 3 ms per frame and physics about 5 ms. Before the
  optimizations below, the brains cost 6 ms, mostly in greet and play_together scoring.
- Cheaper social scans: `Dog.dogs_near(max_dist)` returns ids nearest first (native
  `bsearch` insert, no lambda sort), so behaviors rule dogs out from their own memory before
  calling `get_dog_info`. A scan that finds nobody isn't repeated for 5 game minutes
  (`SCAN_MINUTES`). Dogs are looked up by id through a static dictionary.
- Stagger: a routine re-evaluation needs a slot from a per-frame budget,
  `Dog.take_eval_slot()`. Budget = ceil(dogs × game minutes this frame / EVAL_INTERVAL) + 2,
  which covers the pack's average evaluation rate and spreads bursts over a few frames. A
  dog with no current behavior always chooses at once. One dog is never held back, so the
  baseline is unchanged. Determinism holds (tree order).
- `wait_turn`: one behavior covering hunger and thirst. It scores like eat/drink, but only
  when no bowl is free for the dog and one is busy. The dog joins the bowl's line
  (`WorldItem.enqueue`, FIFO, not saved), sits 1.1 m away (+0.5 m per place in line) facing
  it, and when its turn comes it runs the regular consume steps itself. A free slot goes to
  the front of the line (`is_free_for` checks the line), so nobody cuts in, and claiming
  takes the dog out of the line. Not interruptible except by an emergency; gives up after
  90 min. Body API: `find_busy_item`, `join_queue`, `leave_queue`.
- Bowl capacity: one water bowl can't serve 30 dogs (about 60 minutes of drinking per game
  hour). With one pair, thirst hit 0. `--bowls=N` (debug, max 4) adds bowl pairs along the
  north wall, and `verify.sh pack30` runs 30 dogs with 2 pairs: lowest thirst 34, hunger 41.
  How many bowls a pack needs belongs to the economy (M4: troughs, staff refills).
- Dog card (`ui/dog_panel.gd`, `DogPanel`, bottom-right, I toggles): name and breed,
  "Feeling great/happy/okay/low/miserable", what it's doing (and with whom), five need bars
  (Food, Water, Energy, Fun, Love), the three traits furthest from average as words, bond
  with a tier word, and best friend (affinity >= 0.5). Static helpers are unit-tested.
