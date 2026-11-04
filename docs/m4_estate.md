# Milestone 4 "Estate, economy and jobs v0": plan and progress

The house room becomes the first building on a small countryside plot. The player builds
on the plot from data-driven building types, buys supplies, grows food in garden beds,
and the animals earn the town's money with jobs: careers away from home (they leave
through the gate for a shift and come back with a wage) and the garden, the first
workplace on the plot. This is the town layer of `docs/design.md` in its first, small
form: one plot (expansions come with levels and quests in M5/M6), a handful of
buildings, four resources that matter (coins, kibble, produce, treats), farming v0,
jobs v0 and save v4. Not a zoo: nobody visits to look at the animals.

Read this when working on M4. Tick steps off here and in DEVELOPMENT.md Status as they
land. The owner's answers are under "Decisions (owner)"; numbers marked *proposed* are
defaults the owner can still change (they're listed in `TODO.md`).

## Steps (`tools/verify.sh` after each, then commit)

- [x] 1. Ledger and save v4: `Ledger` autoload (accounts, add/spend, atomic costs, day
      tallies, recent history, signal), `SAVE_VERSION` 4 with a v3 -> v4 migration, F3
      overlay balances, `tests/test_ledger.gd`. Both baselines unchanged.
- [x] 2. Outdoor plot: 16 x 14 m with the house in its north-west corner, an open 1.5 m
      doorway in the house's low south wall, grass, a fence with a gate, one navmesh over
      house and plot, item bounds reworked, camera bounds widened. Moves both baselines
      once, on purpose (dogs wander outside).
- [ ] 3. Buildings core (no UI): `BuildingData` Resource, `Building` node, `BuildGrid`
      (cells, parcels, occupancy, can_place/place/remove, navmesh rebake), the first six
      `.tres` types, the room's bowl pair becomes a pre-placed feeding station (baselines
      must not move), save of placed buildings, tests.
- [ ] 4. Build mode: B toggles a top-down camera, grid overlay, palette, ghost preview
      (green/red), place (pays the cost), rotate, remove (full refund), Esc leaves. Code
      API for tests; screenshot check.
- [ ] 5. Supplies: new-game balances, kibble and treat stock in the ledger, refills draw
      from stock, a shop panel with deliveries after 2 game hours, "out of food" hint.
      `--autofeed` keeps its stock topped up so the soaks stay exact.
- [ ] 6. Farming v0: garden beds grow produce over game days (plant, tend, harvest by
      hand in Live mode), `produce` stock, refills use produce before kibble.
- [ ] 7. Jobs core: `JobData` Resources (three careers away and the gardener), the job
      board (animals apply by fit once a day, the owner approves, rejects or
      reassigns; J opens it), fit and performance, wages into the ledger, saved. No
      animal goes to work yet; baselines unchanged.
- [ ] 8. Shifts: `go_to_work` (walk out of the gate, away for the shift, back with the
      wage) and `work_garden` (tend and harvest beds during the shift). Both score 0
      without a job, so the baselines stay.
- [ ] 9. Economy HUD and soak: resources bar (top-right), day summary (K), `--autoowner`
      (approves applications, orders supplies, plants beds, builds from a fixed list),
      `tools/verify.sh estate` (12 dogs, 7 game days, not baseline-checked: coins never
      negative, wages paid, food never runs out). Tune the numbers from it.
- [ ] Windowed check on Windows (the plot, build mode feel, job board, HUD). Then M4 is
      done.

## What exists (before M4)

- One room, 10 x 8 m (`Home`, a NavigationRegion3D in `scenes/main.tscn`): floor, walls at
  x = +-5.1 and z = +-4.1 (north and west 1.4 m tall, south and east low so the camera sees
  in), couch, table, bookshelf, rug. `main.gd` bakes the navmesh at startup
  (`home.bake_navigation_mesh(false)`, synchronous; bake mask 1, agent radius 0.375,
  cell 0.125). A runtime rebake is therefore already the pattern.
- Items under `Items`: food bowl (3.9, 0, -3.45) and water bowl (3.3, 0, -3.45), dog bed,
  treat jar on the table, the ball. `--bowls=N` adds bowl pairs along the north wall.
  `ItemBounds` (layer 5) keeps the ball in over the low walls.
- `WorldItem`: affordance tags, fill (bowl units), claims (`max_users`, `share_slots`),
  waiting lines, `refill()`, `to_dict/from_dict` (fill, position if movable). The AI reads
  affordances only, so a bowl inside a building works with no brain change.
- Owner actions today: F refills the food bowl and the treat jar, G the water bowl;
  `--autofeed` refills empty bowls and counts `Bowl refills` in the soak summary.
- `SaveManager` (autoload): JSON at `user://save.json`, `SAVE_VERSION` 3, `migrate(data)`
  steps old saves up one version at a time, items saved by node path (spawned pieces with
  `free_when_empty` are skipped), offline catch-up capped at 8 game hours.
- `SimClock` (autoload): `total_minutes`, `last_delta_minutes`, `hour_changed`,
  `day_changed`. At timescale 60 one process frame is one game minute.
- Data-driven content so far: `BreedData` (`dog/breeds/corgi.tres`).
- UI: F3 overlay top-left, dog card bottom-right, close-up hint top-center (two lines).
  Top-right is free; build mode can use bottom-center.
- Camera rig: Live (orbit, pan, follow) and close-up modes. No top-down mode yet.
- `DogBrain.mood()`: -1 (miserable) .. +1 (content), the lowest need weighs most.
  `memory.bond` 0..100 per dog.
- Keys in use: 1-4, Space, Esc, Tab, E, N, F, G, C, I, F3, F5, F8, F9. B, R, X, Delete,
  P and K are free.

## What step 1 added

- `Ledger` (`sim/ledger.gd`, autoload after SaveManager): `accounts` (StringName ->
  float), `balance(account)`, `add(account, amount, reason)`, `spend(...) -> bool`,
  `can_afford(costs)`, `pay(costs, reason) -> bool` (all or nothing), `tally(account,
  &"today"|&"yesterday")` (reason -> net change), `history` (last 50: minute, account,
  delta, balance, reason; not saved), `reset(start)`, `to_dict/from_dict`. Signals
  `changed(account, balance, delta, reason)` and `reloaded`. Day tallies roll on
  `SimClock.day_changed`. `EPSILON` (1e-6) so ten 0.1 handfuls buy a full bowl.
- Save v4: `SAVE_VERSION` 4, a `"ledger"` section, loaded after the items. `migrate` from
  v3 adds an empty ledger.
- F3 overlay: once the ledger has accounts, a second line under ITEMS shows each balance
  and today's net change.
- Tests: `tests/test_ledger.gd` (10).

## Decisions (step 1)

- **Floats with a reason on every change.** One account type for everything (coins are
  whole in practice, kibble is in bowl fills); reasons are StringNames so the day summary
  can group them. `add` and `spend` refuse negative amounts (push_error) so a sign slip
  can't hide as income.
- **No starting balances yet**: a fresh game and a migrated v3 save both start with no
  accounts. The new-game balances (step 5) go in through `reset(start)` (not
  income), never through the migration.
- **History isn't saved**: it's for the HUD's recent-changes list; the day tallies are
  saved, so the day summary survives a reload.
- **No ESTATE section in the overlay**: at 1600 x 900 the overlay already reaches the
  help line, so the balances share the ITEMS label and only show once accounts exist.
- Both baselines, pack30 and `hands` unchanged (nothing earns or spends yet).

## What step 2 added

- `scenes/main.tscn`, all under `Home` (the NavigationRegion3D, so one synchronous bake
  covers house and yard): `WallSouth` split into `WallSouthWest` (x -5.2..-2.35) and
  `WallSouthEast` (x -0.85..5.2), leaving the 1.5 m doorway at x -2.35..-0.85;
  `YardSouth` (x -5.2..10.8, z 4.0..9.8) and `YardEast` (x 5.0..10.8, z -4.2..4.0), grass
  boxes with their top at y 0 like the house floor; a 0.6 m fence (`FenceSouthWest`,
  `FenceSouthEast`, `FenceEast`, `FenceNorth`, `FenceWest`) and a closed `Gate` (x
  1.25..2.75 on the south fence, 0.7 m, darker), all on layer 1.
- `ItemBounds`: `South`, `East`, `North`, `West`, 2.5 m tall, just outside the fence
  (the old ones over the house's low walls are gone). `Meadow`: a 60 x 60 m plane at
  y -0.03 round the plot, visual only (no collision; an escaped ball still falls and
  respawns).
- Pack spawn points, the bowls and `--bowls=N` pairs are unchanged (inside the house).
  No camera change was needed (Live panning has no bounds).
- Tests: `tests/test_plot.gd` (4: the yard is reachable and the walls and fence aren't,
  the path out goes through the doorway, the fence and gate hold, a dog walks out);
  `test_ball` checks the four bounds and that hard throws stay in the plot, reachable.

## Decisions (step 2)

- **Plot coordinates**: x -5.2..10.8, z -4.2..9.8, the house's tall north and west walls
  as the plot's edges; the yard (about 140 m2) is an L round the south and east sides.
- **Doorway west of the rug** (x -2.35..-0.85), clear of the bed, the table and the
  spawn rows; 0.75 m of navmesh after the 0.375 agent radius on each side.
- **The gate is closed** (solid, layer 1) until step 8 sends dogs to work through it.
- **Baselines moved once, on purpose** (navmesh change): one dog idle 69, wander 18,
  chase_toy 10, drink 10, eat 10, sleep 7 (the dog is outside about 12% of the time);
  12 dogs idle 592, play_together 240, greet 231, wander 175, wait_turn 95, sleep 98,
  eat 71, drink 49, chase_toy 21 (about 31% outside). Stable over repeated runs.
- The ball's 30-minute return fired once in pack30 (the ball came to rest on top of the
  low south wall next to the doorway), never in the other soaks. pack30 lowest thirst
  went from 34 to 24 and hunger from 45 to 38 (longer walks to the two bowl pairs for 30
  dogs); the 12-dog `hands` soak's lowest affection went from 17 to 6 (dogs spread over
  the yard; one simulated owner can't reach them all). Both are coverage soaks; feeding
  stations in the yard (step 3) should help.

## Decisions (owner)

Answered by the owner:
- **Vision**: a world of animals with real jobs, lives, friends and skill trees; not a
  zoo. Visitors are dropped. Income comes from the animals' jobs.
- **Jobs**: both careers away from home and workplaces on the plot from the start. Animals
  apply for jobs that suit them; the owner approves or reassigns.
- **Pay** (balanced): a 4-game-hour shift pays 15 coins x performance (0.5-1.5). Kibble 3
  coins per bowl fill in packs of 10 (30 coins); treats 10 for 15 coins. New game: 150
  coins, 10 bowl fills of kibble, a full treat jar (10).
- **Plot**: starts small, 16 x 14 m, and grows later with levels and quests.
- **Doorway**: an open 1.5 m gap in the house's south wall.
- **First buildings**: feeding station, dog bed, play yard, path tile, bench (plus the
  garden bed for farming).
- **Bowls become buildings**: the room's bowls become a pre-placed feeding station.
- **Refund**: always 100% when a building is removed.
- **Food**: more ways to get food than kibble and treats: farming in M4; kitchen,
  foraging and trade with neighbours later.

*Proposed* (defaults the owner hasn't answered; change them in `TODO.md`):
- **Delivery**: shop orders arrive as stock 2 game hours later; one order in flight per
  resource.
- **Prices**: feeding station 40, dog bed 25, play yard 80, path tile 2, bench 15, garden
  bed 30 coins. Planting a bed costs 2 coins (seeds).
- **Garden**: a bed grows in 2 game days (1.5x faster on a day it's tended), yields 3
  bowl fills of produce. Produce is food for the bowls, used before kibble.
- **Careers**: courier (energy, boldness), therapy visits (sociability, calm = low
  energy), show performer (toy drive, trainability); shifts 09:00-13:00. Gardener
  (workplace; food drive, low stubbornness), shift 07:00-11:00. Up to 3 animals per job.
- **Performance** = lerp(0.5, 1.5, 0.5 x happiness + 0.5 x fit), happiness = (mood + 1)
  / 2, fit 0..1 from the job's trait weights. A fit below 0.35 drains fun faster at work.

## Design

**Resources ledger** (`sim/ledger.gd`, autoload `Ledger`, plain state like SimClock).
Accounts are StringNames with float balances: `coins`, `kibble` and `produce` (in bowl
fills, the unit `WorldItem.fill` already uses: 1.0 is one full bowl, a handful is 0.1),
`treats` (pieces), later `reputation`. Every change goes through `add`/`spend`/`pay` with
a reason; day tallies feed the day summary. Nothing in a brain reads the ledger.

**Save v4.** `SAVE_VERSION` 4 (step 1: `"ledger"`). Later M4 steps add optional sections
(`"buildings"`, `"orders"`, `"gardens"`, `"jobs"`) that default to empty when missing,
with no further bump, so a save written after step 1 still loads after step 9. Load
order: clock, buildings (they create item nodes), dogs, items, ledger, jobs. New-game
balances are set by the new-game setup through `Ledger.reset(start)`, never by the
migration, so an upgraded save isn't handed money.

**Outdoor plot.** 16 x 14 m: x from -5.2 to 10.8, z from -4.2 to 9.8, so the house's
north and west walls are the plot's edges and the yard (about 140 m2) wraps the house's
south and east sides. The doorway is a 1.5 m gap in the low south wall, always open.
Grass ground, a fence on layer 1 round the yard (dogs and the ball stop at it), item
bounds over the fence (the ball may fly over the low house walls: it lands in the yard).
A gate in the south fence (the way to work for careers). One NavigationRegion3D over house
and yard, still baked synchronously at startup. Camera Live bounds widened to the plot.
Land beyond the fence is meadow, visibly fenced off: `BuildGrid` knows parcels (the
starting one unlocked), so M5/M6 can unlock expansions without a rewrite.

**Buildings** (data, not code). `BuildingData` (`buildings/building_data.gd`, Resource):
`id`, `display_name`, `scene` (PackedScene: the model plus any child WorldItems, which
carry the affordances), `footprint` (Vector2i cells), `cost` (account -> amount),
`indoor`/`outdoor` flags, `category` (care, play, path, farm, rest), `description`, later
`unlock`. Types in `buildings/*.tres`; a new building is a scene plus a `.tres`.
`Building` (`buildings/building.gd`, Node3D) knows its data, cell and rotation.
`BuildGrid` (`world/build_grid.gd`): 1 m cells, parcels, occupancy, blocked cells (walls,
furniture, the doorway and gate kept clear), `can_place(data, cell, rot)`,
`place(...) -> Building`, `remove(building)` (full refund). Placing or removing rebakes the
navmesh once, synchronously (deterministic), and releases claims on removed items.
First six: feeding station (food + water bowl, 1 x 2), dog bed (1 x 1), play yard (4 x 4
low fence with a ball), path tile (1 x 1, cosmetic in v0), bench (1 x 1, cosmetic in
v0; a rest spot later), garden bed (2 x 1, farming). The room's bowls become a pre-placed
feeding station at their current spot; old saves' `Items/FoodBowl` and `Items/WaterBowl`
paths map to it.

**Build mode.** B in Live mode. The camera rig gets a top-down mode (eased like
close-up; exit restores the Live view). Grid lines and blocked cells on the ground.
Palette bottom-center: one button per type with its price, greyed if short. Ghost follows
the cursor snapped to cells, green if placeable and affordable, red otherwise. LMB place
(`Ledger.pay`), R rotate 90 degrees, X or Delete removes a building (full refund), Esc or
B leaves. RMB stays camera orbit. Time keeps running (Space pauses). Code API:
`select_type(data)`, `hover_cell(cell)`, `confirm() -> Building`, `remove_at(cell)`.

**Supplies.** Refilling a bowl (F, `--autofeed`, later a caretaker job) moves `1 - fill`
food from stock into it: produce first, then kibble; with too little it fills what there
is and the hint says "Out of food". The treat jar draws treats. Water stays free (a well
is a later building). The shop panel (in the K summary) buys packs; an order arrives as
stock after the delivery delay; orders in flight are saved. `--autofeed` gets free
top-ups of exactly what it refills, so the default soaks stay exact; `--autoowner` (step
9) buys like a player.

**Farming v0.** A garden bed (building) is empty, planted, growing or ripe. Planting costs
seeds (coins); it grows over game days, faster on a day someone tended it; ripe, it is
harvested into `produce` stock. In Live mode the player clicks a bed to plant, tend or
harvest it; the gardener job does the same during its shift. Beds are saved (state,
growth). Animals don't eat from beds directly in v0 (that would need a new behavior and
move the baselines); produce reaches them through the bowls.

**Jobs v0.** `JobData` (`jobs/job_data.gd`, Resource; `jobs/*.tres`): `id`,
`display_name`, `kind` (away or workplace), `shift_start_hour`, `shift_hours`,
`base_wage`, `trait_weights` (trait -> weight, the fit), `workplace_affordance` (for
workplace jobs), `max_workers`, `description`. `JobBoard` (`jobs/job_board.gd`, a node in
main.tscn, group `job_board`): once a game day each animal without a job applies for the
job it fits best (if the fit is at least 0.5 and the job has room); the owner approves,
rejects or reassigns on the board (J). Assignments are saved. Fit and performance are
computed by the board from the body's personality (`Dog.get_dog_info` style), never by a
brain reading another system. The brain learns its shift only through the body
(`Dog.get_job_shift()`), so a dog without a job scores 0 on the shift behaviors and never
touches `brain.rng`.
- **Careers away** (`go_to_work`): near shift start the dog walks to the gate (scores high,
  interrupted only by urgent needs >= 0.9), then the body goes away: hidden, collisions
  off, out of `dogs_near`/`find_nearest_dog`, claims released, its brain only drains
  needs (like `simulate_offline`) for the shift. At the end it reappears at the gate and
  the board pays the wage (`Ledger.add(&"coins", wage, &"wage")`).
- **Workplace** (`work_garden`): during the shift the gardener walks to beds that need
  planting, tending or harvesting and does it; paid the same way at the end.
- A missed shift (asleep, an urgent need) pays nothing; three in a row and the animal
  asks for another job on the board.

**HUD.** Resources bar top-right: coins, food stock (produce + kibble, bowl fills),
treats, a small "+15 wage" float on income. K opens the day summary (income and expenses
by reason) with the shop; J the job board. All clear of the F3 overlay (top-left), the dog
card (bottom-right) and the close-up hint (top-center).

**Baseline rules for M4.** New systems must not move the 1- and 12-dog baselines unless
their trigger is present in the soak, and the soaks don't build, order, plant or assign
jobs. Expected moves, recorded deliberately in their step's commit: step 2 (the plot
changes the navmesh, so `random_point_near` and wander paths change). Step 3 must not move
them (the feeding station keeps the bowls' spots and fills). Run verify twice after each
move. pack30 and `hands` shift with any physics or navmesh change; check them for
ERROR/WARNING and sane needs.

## Known open questions (resolve during the milestone, don't block on them)

- Navmesh rebake cost as buildings add up; if it shows, bake per building region instead
  of one big region.
- Indoor building: whether the house floor is on the build grid in M4 or only the yard.
- Friends and an animal at work: should friends miss it (greet it at the gate)? v0: it's
  simply not around.
- Offline catch-up: a shift that spans the time away completes and pays; beds grow.
- Should animals prefer indoors at night? Today they sleep at the bed item wherever it is.
- Mess and caretaker/cleaner jobs fit M7; the kitchen too (produce into treats).
- Other species: jobs and buildings are data keyed by affordances and traits, so cats and
  others can take jobs once SpeciesData exists.
