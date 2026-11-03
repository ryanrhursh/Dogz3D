# Milestone 2 "Pack": plan and progress

Goal: 10–30 autonomous dogs share one home. The player selects a dog to follow and inspect
it. Dogs share bowls and beds without piling up, and they notice each other.

## Steps

- [ ] 1. **Pack and selection.**
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
- [ ] 2. **Dog to dog.**
  - Separation: NavigationAgent3D avoidance, or a cheap separation steer if avoidance shifts
    the single-dog baseline.
  - Relationships: `DogMemory.relationships`, dog_id mapped to -1..1 affinity.
  - Behaviors:
    - `greet` (sniff a nearby dog; sociability).
    - `play_together` (chase each other; fun, energy).
    - Bed sharing for dogs with high affinity.
  - All through new body API calls, `find_nearest_dog(filter)` and `get_dog_info(id)`.
    Brains must never touch other brains directly.
- [ ] 3. **Pack scale and UI.**
  - Soak with `--dogs=30` and record frame time.
  - Stagger brain evaluations across frames.
  - Bowl contention: a `wait_turn` behavior so a dog waits near a busy bowl instead of
    starving.
  - Player-facing info panel for the selected dog (name, mood, needs, top traits, bond),
    separate from the F3 debug overlay.
