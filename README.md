# Dogz 3D (working title)

A cozy dog sanctuary town builder (see `docs/design.md`, roadmap in `docs/roadmap.md`).
Current build: the gray box, a pack of capsule-shaped corgis with needs, personalities,
relationships and utility-AI brains, living in a one-room diorama with a day/night cycle.
Click a dog twice for close-up mode, where your hand pets, hand-feeds and throws a ball.
The town economy is next.

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
| Close-up: hold LMB on the food bowl / treat jar | Take kibble / a treat; let go at a dog's head to hand-feed it, anywhere else to drop it |
| Close-up: hold LMB on the ball (floor or a dog's mouth) | Grab it; flick the mouse and let go to throw (dogs chase it), let go slowly to drop it |
| I | Toggle the dog card (the selected dog's mood, needs, traits, bond, best friend) |
| N | Adopt another dog (debug) |
| E | Pet the selected dog (debug fallback, kept for the `--autopet` soak) |
| F / G | Refill food bowl and treat jar / water bowl |
| F3 | Toggle the debug overlay |
| F5 / F9 | Save / load |
| F8 | Re-roll the selected dog (new personality, needs reset) |

Time: 1 real second = 1 game minute at 1x, so a game day is 24 real minutes.
Change `SimClock.minutes_per_real_second` to tune it.

## Layout

```
sim/            SimClock, SaveManager and Ledger (autoloads), day_night.gd
dog/brain/      Plain scripts, no nodes: needs, personality, memory, planner, brain
dog/brain/behaviors/  wander, consume (eat + drink), sleep, idle, greet, play_together,
                wait_turn, enjoy_pets, duck_away, come_for_food, chase_toy
dog/body/       Dog CharacterBody3D: movement, poses, placeholder visual, body API
dog/pack.gd     Pack: spawns dogs (unique id, name, seed), selection, save sync
dog/breeds/     BreedData resources (corgi.tres)
items/          WorldItem + bowl, bed, treat jar and ball scenes, FoodPiece (kibble, treat);
                the AI reads affordance tags only
interaction/    Milestone 3: HandTool (close-up hand cursor), TouchZone, AutoHands (soak owner)
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

Reference result (seed 42, 48 h, attentive owner): idle 83, wander 20, chase_toy 14, drink 10,
eat 10, sleep 7; no need fell below 47 except affection (32). With no owner, hunger and thirst
hit 0 by day 2.

Swap `--autopet` for `--autohands` to have a simulated owner use the hand instead: it
strokes lonely dogs (learning their favorite spots), holds food out to hungry ones and throws
the ball for bored ones, and the summary adds a `Hands:` line. `tools/verify.sh hands` runs
it with 12 dogs.

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
