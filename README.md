# Dogz 3D (working title)

A cozy dog sanctuary town builder (see `docs/design.md`, roadmap in `docs/roadmap.md`).
Current build: the milestone 1 gray box, with a capsule-shaped corgi that has needs, a
personality and a utility-AI brain, living in a one-room diorama with a day/night cycle.
The pack (many dogs), the hand tool and the town economy are in progress.

Built and tested on **Godot 4.6.1** (Forward+). Open `project.godot` in the editor and press F5.

## Controls

| Input | Action |
| --- | --- |
| Right-drag / wheel / WASD | Orbit / zoom / pan camera |
| C | Re-follow the dog after panning |
| 1 2 3 4 | Time scale 1x, 4x, 16x, 60x |
| Space | Pause |
| LMB on a dog / Tab | Select a dog (camera follows it, card and overlay show it) |
| LMB on the selected dog | Close-up mode: the camera frames the dog and the hand takes over LMB |
| Esc | Leave close-up mode |
| Close-up: LMB press / drag on the dog | Pat / stroke (head, ears, back, belly; each dog has favorite spots) |
| I | Toggle the dog card (the selected dog's mood, needs, traits, bond, best friend) |
| N | Adopt another dog (debug) |
| E | Pet the selected dog (debug fallback, kept for the `--autopet` soak) |
| F / G | Refill food / water bowl |
| F3 | Toggle the debug overlay |
| F5 / F9 | Save / load |
| F8 | Re-roll the selected dog (new personality, needs reset) |

Time: 1 real second = 1 game minute at 1x, so a game day is 24 real minutes.
Change `SimClock.minutes_per_real_second` to tune it.

## Layout

```
sim/            SimClock (autoload), SaveManager (autoload), day_night.gd
dog/brain/      Plain scripts, no nodes: needs, personality, memory, planner, brain
dog/brain/behaviors/  wander, consume (eat + drink), sleep, idle, greet, play_together,
                wait_turn, enjoy_pets, duck_away
dog/body/       Dog CharacterBody3D: movement, poses, placeholder visual, body API
dog/pack.gd     Pack: spawns dogs (unique id, name, seed), selection, save sync
dog/breeds/     BreedData resources (corgi.tres)
items/          WorldItem + bowl and bed scenes; the AI reads affordance tags only
interaction/    Milestone 3: HandTool (close-up hand cursor) and TouchZone
tests/          Headless test runner and suites (--test=all)
tools/          godot.sh (fetch + run Godot 4.6.1 on Linux), verify.sh (import + tests + soak)
docs/           Milestone plans
ui/debug/       Debug overlay (needs, scores, personality, relationships, decision log)
ui/dog_panel.gd Player-facing dog card for the selected dog
scenes/         main.tscn (room), main.gd (keys, CLI args), camera_rig.gd
```

## How the brain works

- **Needs** (`needs.gd`): hunger, thirst, energy, fun, affection, each 0–100, decaying per game hour.
  Personality scales the decay rates (high energy = gets bored faster, etc.).
- **Behaviors** score 0–1 from needs, traits and time of day. Tuning constants sit at the top
  of each behavior file.
- **Planner** (`utility_planner.gd`): the current behavior gets +0.08 inertia. It keeps going while
  within 85% of the best score. Fresh picks are weighted-random among the top 3. Eat, drink and
  sleep can only be interrupted by an emergency score of 0.9 or more. A failed behavior is blocked
  for 10 game minutes.
- **Body API** (`dog.gd`): behaviors call `go_to`, `go_to_item`, `face_point`, `set_pose`,
  `find_nearest_item`, `random_point_near`. Milestone 4 swaps the placeholder visual for the rigged
  model without touching the brain.

## Headless soak test

Runs days of game time in seconds and prints a summary:

```
godot --headless --fixed-fps 60 --path . -- --fresh --no-save --timescale=60 --quit-after-hours=48 --autofeed --autopet --seed=42 --log
```

Reference result (seed 42, 48 h, attentive owner): idle 90, wander 24, drink 11, eat 9, sleep 5;
no need fell below 47 except affection (32). With no owner, hunger and thirst hit 0 by day 2.

All args are documented at the top of `scenes/main.gd`.

## Headless tests

```
godot --headless --fixed-fps 60 --path . -- --fresh --no-save --seed=42 --test=all
```

Suites live in `tests/` and run inside the real scene. On Linux, `tools/verify.sh` runs
import, tests and the soak in one go (`tools/godot.sh` fetches Godot 4.6.1 if needed).

## Known gaps (by design for this milestone)

- Affection only rises from you: petting in close-up (or E). Other dogs top it up a little.
- No behavior for an empty bowl. The dog just goes without; begging comes later.
- At 16x and above, walking is capped at 6x speed so it stays readable, so trips take more
  game time than they would at 1x. The soak test uncaps this automatically.
