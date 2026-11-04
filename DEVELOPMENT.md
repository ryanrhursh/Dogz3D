# Dogz 3D (working title)

Cozy 3D **dog sanctuary town builder** in Godot 4.6 (GDScript), PC first. You grow an estate
of 10–30 autonomous dogs (each with its own personality, needs, skills and quests), manage
resources and buildings, and click any dog to interact with it close-up.
Design: `docs/design.md`. Roadmap: `docs/roadmap.md`. Each milestone has a plan doc in
`docs/` with a step checklist and the decisions taken so far.

## Status

- M1 gray box: DONE (needs, utility AI, capsule dog, navmesh room, day/night, save/load,
  debug overlay).
- M2 Pack (many dogs, selection, shared items): DONE. See `docs/m2_pack.md`: pack and
  selection; dog to dog (separation, relationships, greet, play together, bed sharing);
  pack scale (30 dogs measured, staggered thinking, waiting in line at bowls, the dog card,
  deterministic pack soak).
- NEXT: the M3 windowed check on Windows; the owner decisions in `docs/m4_estate.md`
  ("Decisions for the owner", Q1-Q9), then M4 from step 1.
- M3 Hands (close-up mode): steps 1–5 of 5 done (plumbing and test harness; close-up
  mode, HandTool, petting with enjoy_pets and duck_away; hand feeding with kibble, the
  treat jar and come_for_food; the ball, item bounds, throwing and chase_toy; the
  `--autohands` simulated owner), plus the wrap-up (dogs skip food they can't reach; a
  ball out of reach comes back after 30 game minutes). Left: a windowed check on
  Windows. See `docs/m3_hands.md`.
- M4 Estate and economy: planned in `docs/m4_estate.md` (7 steps plus a windowed check).
- M5–M10 (growth/skill trees, quests, staff, art, content, scale-up): see the roadmap.

## Workflow

- Work in small steps from the current milestone's plan doc. Each step ends with
  `tools/verify.sh` passing, then a commit.
- When a step lands, tick it in the plan doc and update Status above.
- For any non-trivial choice, weigh the options, pick the most efficient one that keeps the
  design pillars (`docs/design.md`), and record it in the plan doc.
- Commit messages: imperative summary line, then a short body of what changed and why.

## Architecture rules

- The brain (`dog/brain/`) is plain RefCounted/Resource scripts with no node dependencies.
  Behaviors touch the world only through the Dog body API in `dog/body/dog.gd`
  (go_to, go_to_item, face_point, set_pose, set_gait, find_nearest_item, find_offered_item,
  random_point_near, can_reach, pick_up, drop_held, get_mouth_position, claim_item,
  release_item, find_shared_item, find_busy_item, join_queue, leave_queue,
  point_away_from, find_offered_item; for other dogs find_nearest_dog, dogs_near, get_dog_info, invite_dog,
  get_invite, notify_dog, set_social_partner). A behavior that claims an item, or joins its line, releases or
  leaves it in exit().
- Everything that simulates uses `SimClock.last_delta_minutes` (game minutes), never the
  raw engine delta. Movement uses real delta scaled by a capped time scale.
- The AI reads item affordance tags (`WorldItem.affordances`), never item names.
- New behavior: subclass `DogBehavior` and register it in `DogBrain.setup()`. Its row
  appears in the debug overlay automatically.
- Many dogs: never assume one dog (`$Dog`). Find dogs through the `dogs` group or the Pack
  (group `pack`). A brain never reads another dog's brain directly; dog-to-dog awareness
  goes through the body API.
- A social behavior must score 0, and not touch `brain.rng`, when no other dog is near, so
  the one-dog soak baseline stays exact. Likewise a hand behavior scores 0 (early-out on
  `brain.stimuli.is_empty()`) until the player's hand does something. The exception is
  `chase_toy`, which also plays with the ball lying in the room (so the baselines include
  it); keep its scoring cheap (early-outs before the item scan).
- Player input reaches a brain only through the Dog body (`touch`, later `feed_from_hand`,
  `notice`), which calls a `DogBrain.on_*` handler. Handlers record a stimulus and force
  a re-evaluation next tick (no min_duration, no eval budget).
- Content is data (BreedData, and later SkillTree, BuildingData, QuestData Resources), so
  new breeds, species, skills and buildings don't need code changes where possible.
- Save data is JSON via SaveManager. Bump `SAVE_VERSION` when the format changes.

## GDScript conventions (pitfalls hit before)

- Never write one-line match arms. Put the body on its own indented line.
- Explicitly type variables assigned from `Dictionary.get()` or other Variant sources.
- Avoid names that collide with Godot built-ins (e.g. `is_connected`, `trait`, `snapped`).
- Calling a custom method on a node typed as a built-in class (Node3D, CanvasLayer) is a
  compile error. Cast to the class_name or leave the variable untyped.
- Tabs for indentation.

## Verify every change

Linux: `tools/verify.sh` does all of it (import, tests, one-dog soak, 12-dog pack soak,
both soaks checked against their exact baselines) in about a minute, and prints VERIFY OK
or the offending lines. `tools/verify.sh pack30` adds a 30-dog soak and
`tools/verify.sh hands` a 12-dog soak with the `--autohands` simulated owner (neither is in
the default run or baseline-checked). `tools/godot.sh` downloads
and SHA-checks Godot 4.6.1 on first use, then runs it with your args. On Windows, point `GODOT` at
`Godot_v4.6.1-stable_win64_console.exe` and run the steps by hand.

1. Import, which also catches parse errors: `GODOT --headless --path . --import`
2. Tests: `GODOT --headless --fixed-fps 60 --path . -- --fresh --no-save --seed=42 --test=all`
   Prints PASS/FAIL lines and exits 1 on failure. Suites live in `tests/`.
3. Soak test, which runs 48 game hours in seconds and prints a summary:
   `GODOT --headless --fixed-fps 60 --path . -- --fresh --no-save --timescale=60 --quit-after-hours=48 --autofeed --autopet --seed=42 --log`
   Expect zero ERROR or WARNING lines. Baseline (seed 42): idle 83, wander 20,
   chase_toy 14, drink 10, eat 10, sleep 7 (exact on 4.6.1 Linux headless; the room's
   ball moved it in M3 Hands step 4, and its return from out of reach in the M3 wrap-up). Add `--dogs=12` for the pack
   soak, also exact (baseline in `tools/verify.sh` and `docs/m2_pack.md`). `--bowls=N`
   adds bowl pairs for big packs. The summary ends with a wall-clock `Frame time:` line.
4. Screenshot (needs a real renderer, not --headless):
   `GODOT --path . -- --fresh --no-save --screenshot=shot.png --screenshot-delay=4`
