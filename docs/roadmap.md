# Roadmap

Ordered to make the game fun early: many dogs, then the hands, then the economy, then depth.
Each milestone is split into small steps. `tools/verify.sh` must pass after every step.

| # | Milestone | Status | Plan |
|---|---|---|---|
| 1 | Gray box: needs, utility AI, one dog, room, day/night, save | DONE | README.md |
| 2 | **Pack**: many dogs, selection, shared items, dog-to-dog behaviors | DONE | `docs/m2_pack.md` |
| 3 | **Hands** (close-up mode): petting zones, hand-feeding, ball and chase | Steps 1–5 done; windowed check on Windows left | `docs/m3_hands.md` |
| 4 | **Estate, economy and jobs v0**: small outdoor plot, build mode, resources ledger, supplies, farming v0, jobs v0 (careers away from home, the garden workplace), save v4 | Step 1 of 9 done | `docs/m4_estate.md` |
| 5 | **Growth**: XP (from play, training and jobs), levels, data-driven skill trees that raise job performance, training (cue, reward window), plot expansions unlocked by level | Planned | |
| 6 | **Quests and neighbours**: personal quests, a few named neighbours (human or other species) who trade and give quests, expeditions (foraging food), town contracts, quest log, expansions unlocked by quests | Planned | |
| 7 | **Upkeep jobs**: caretaker and cleaner jobs, mess and cleaning, the kitchen (produce into treats and meals) | Planned | |
| 8 | **Art pass**: rigged Corgi from Blender, building models, UI skin | Planned | |
| 9 | **Content**: more breeds, competitions and events, reputation tiers, more buildings | Planned | |
| 10 | **Scale-up study**: 100+ animals (brain LOD, budgets), more species | Planned | |

Why this order:
- Pack comes first because every later system assumes many dogs. It's also the code the
  single-dog prototype had to give up (one `$Dog`, one overlay target, items without sharing).
- Hands comes next because it's partly built, and it proves the moment-to-moment fun before
  economy tuning.
- The economy needs both before its numbers mean anything (what a happy animal's work is
  worth, what bond buys).
- Jobs v0 lands with the economy because wages are the town's income; skills (M5) and
  quests (M6) then make the animals better at them and grow the land.
- Art waits until the systems settle, so models aren't redone.
