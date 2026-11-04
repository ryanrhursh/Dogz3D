# Roadmap

Ordered to make the game fun early: many dogs, then the hands, then the economy, then depth.
Each milestone is split into small steps. `tools/verify.sh` must pass after every step.

| # | Milestone | Status | Plan |
|---|---|---|---|
| 1 | Gray box: needs, utility AI, one dog, room, day/night, save | DONE | README.md |
| 2 | **Pack**: many dogs, selection, shared items, dog-to-dog behaviors | DONE | `docs/m2_pack.md` |
| 3 | **Hands** (close-up mode): petting zones, hand-feeding, ball and chase | Steps 1–5 done; windowed check on Windows left | `docs/m3_hands.md` |
| 4 | **Estate and economy**: outdoor plot, build mode, resources ledger, supplies, visitors v0, save v4 | Planned; owner decisions open | `docs/m4_estate.md` |
| 5 | **Growth**: XP, levels, data-driven skill trees, training (cue, reward window) | Planned | |
| 6 | **Quests**: personal quests, expeditions, town contracts, quest log | Planned | |
| 7 | **Staff and upkeep**: caretakers with their own brains, mess and cleaning, wages | Planned | |
| 8 | **Art pass**: rigged Corgi from Blender, building models, UI skin | Planned | |
| 9 | **Content**: more breeds, competitions and events, reputation tiers, more buildings | Planned | |
| 10 | **Scale-up study**: 100+ dogs (brain LOD, budgets), more species | Planned | |

Why this order:
- Pack comes first because every later system assumes many dogs. It's also the code the
  single-dog prototype had to give up (one `$Dog`, one overlay target, items without sharing).
- Hands comes next because it's partly built, and it proves the moment-to-moment fun before
  economy tuning.
- The economy needs both before its numbers mean anything (what a happy dog is worth, what
  bond buys).
- Art waits until the systems settle, so models aren't redone.
