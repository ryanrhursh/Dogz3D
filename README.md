# Dogz 3D (working title) — Milestone 1: gray box

A capsule-shaped corgi with needs, a personality and a utility-AI brain, living in a one-room
diorama with a day/night cycle. No player hand yet; debug keys stand in for it.

Built and tested on **Godot 4.6.1** (Forward+). Open `project.godot` in the editor and press F5.

## Controls

| Input | Action |
| --- | --- |
| Right-drag / wheel / WASD | Orbit / zoom / pan camera |
| C | Re-follow the dog after panning |
| 1 2 3 4 | Time scale 1x, 4x, 16x, 60x |
| Space | Pause |
| E | Pet the dog (debug stand-in for milestone 2's hand tool) |
| F / G | Refill food / water bowl |
| F3 | Toggle the debug overlay |
| F5 / F9 | Save / load |
| F8 | New puppy (re-rolls personality, resets needs) |

Time: 1 real second = 1 game minute at 1x, so a game day is 24 real minutes.
Change `SimClock.minutes_per_real_second` to tune it.

## Layout

```
sim/            SimClock (autoload), SaveManager (autoload), day_night.gd
dog/brain/      Plain scripts, no nodes: needs, personality, memory, planner, brain
dog/brain/behaviors/  wander, consume (eat + drink), sleep, idle
dog/body/       Dog CharacterBody3D: movement, poses, placeholder visual, body API
dog/breeds/     BreedData resources (corgi.tres)
items/          WorldItem + bowl and bed scenes; the AI reads affordance tags only
interaction/    Milestone 2: hand cursor and touch zones
ui/debug/       Debug overlay (needs, scores, personality, decision log)
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

## Known gaps (by design for this milestone)

- Affection only rises when you press E. Nothing in the world satisfies it yet.
- No behavior for an empty bowl. The dog just goes without; begging comes later.
- At 16x and above, walking is capped at 6x speed so it stays readable, so trips take more
  game time than they would at 1x. The soak test uncaps this automatically.
