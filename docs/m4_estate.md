# Milestone 4 "Estate and economy": plan and progress

The house room becomes the first building on a countryside plot. The player builds on the
plot from data-driven building types, buys supplies, and visitors come to meet the dogs and
pay for it. This is the town-builder layer from `docs/design.md` ("Build to care": the
economy is care made visible) in its first, small form: one plot, a handful of buildings,
three resources that matter (coins, kibble, treats), visitors v0 and save v4.

Read this when working on M4. Tick steps off here and in DEVELOPMENT.md Status as they land.
The questions under "Decisions for the owner" are open until the owner answers them; each
has a recommended default. Steps that depend on one say so and wait for it.

## Steps (`tools/verify.sh` after each, then commit)

- [ ] 1. Ledger and save v4: `Ledger` autoload (accounts, add/spend, atomic costs, day
      tallies, recent history, signal), `SAVE_VERSION` 4 with a v3 -> v4 migration, F3
      overlay ECONOMY line, `tests/test_ledger.gd`. Nothing earns or spends yet, so both
      soak baselines stay exact. Needs no open decision.
- [ ] 2. Outdoor plot: ground, fence, a doorway out of the house, navmesh over both, the
      camera bounds widened, item bounds extended. Moves both baselines once, on purpose
      (dogs wander outside). Needs Q2 (plot size and layout) and Q3 (doorway).
- [ ] 3. Buildings core (no UI): `BuildingData` Resource, `Building` node, `BuildGrid`
      (cells, occupancy, can_place/place/remove, navmesh rebake), the first `.tres` set,
      save of placed buildings, tests. Needs Q4 (first building set) and Q5 (bowls as
      buildings). Baselines stay (nothing placed in the soaks) unless Q5 moves the bowls.
- [ ] 4. Build mode: B toggles a top-down camera, grid overlay, palette, ghost
      preview (green/red), place (pays the cost), rotate, remove (refund), Esc leaves.
      Code API for tests; screenshot check. Needs Q1 (costs in coins) and Q6 (refund).
- [ ] 5. Supplies: kibble and treat stock in the ledger; F, `--autofeed` and the treat jar
      draw from stock; orders from the supply depot arrive after a delivery delay; "out of
      kibble" shows in the hint and the HUD. `--autofeed` keeps its stock topped up so the
      soaks stay exact. Needs Q1 (prices) and Q7 (delivery).
- [ ] 6. Visitors v0: visitors arrive at the gate in opening hours, walk to a few dogs,
      watch them, pay by how happy the dogs are, and leave. Dogs don't react to visitors in
      v0 (that keeps the baselines; reactions are a later step). `--visitors` soak flag.
      Needs Q1 (what a happy dog is worth) and Q8 (visitor numbers and hours).
- [ ] 7. Economy HUD and soak: resources bar (top-right), a day summary (income and
      expenses by reason), `--autoowner` (orders supplies, builds from a fixed list), and
      `tools/verify.sh estate` (12 dogs, 7 game days, not baseline-checked: coins never go
      negative, supplies get ordered, visitors pay). Tune the numbers from it.
- [ ] Windowed check on Windows (build mode feel, the plot, readability of the HUD). Then
      M4 is done.

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

## Design

**Resources ledger** (`sim/ledger.gd`, autoload `Ledger`, plain state like SimClock).
Accounts are StringNames with float balances: `coins`, `kibble` (in bowl fills, the unit
`WorldItem.fill` already uses: 1.0 is one full bowl, a handful is 0.1), `treats` (pieces),
later `reputation`. API: `balance(account)`, `add(account, amount, reason)`,
`spend(account, amount, reason) -> bool` (fails, changing nothing, if the balance is short),
`can_afford(costs: Dictionary)`, `pay(costs, reason) -> bool` (all or nothing),
`changed(account, balance, delta, reason)` signal. Day tallies per account and reason
(`today`, `yesterday`, rolled on `SimClock.day_changed`) feed the day summary; a short
history (last 50 entries: minute, account, delta, reason) feeds the HUD. `reset()` for
tests and `--fresh`. Nothing in the brain reads the ledger: dogs live in the world, the
owner runs the economy.

**Save v4.** `SAVE_VERSION` 4. Step 1 adds `"ledger"` (accounts, today, yesterday); the
migration from v3 adds an empty ledger (the starting balances, once Q1 sets them, are
given by the new-game setup, not the migration, so old saves aren't handed money twice).
Later M4 steps add optional sections (`"buildings"`, `"orders"`) that default to empty
when missing, with no further version bump, so a save written after step 1 still loads
after step 7. Load order: clock, buildings (they create item nodes), dogs, items, ledger.
Visitors are not saved (on load, any visit in progress is gone).

**Outdoor plot.** The house stays as the starting building in one corner of a fenced
plot; a doorway (a gap in a house wall, no door to open in M4) lets dogs out. Ground:
grass-colored floor, fence on layer 1 (dogs and the ball stop at it), item bounds over low
fence parts. One NavigationRegion3D over house and plot, so behaviors keep using the same
navmesh calls. Camera: Live bounds widened to the plot. The plot is fixed in M4; buying
more land is later (design: land costs coins and reputation).

**Buildings** (data, not code). `BuildingData` (`buildings/building_data.gd`, Resource):
`id`, `display_name`, `scene` (PackedScene: the model plus any child WorldItems, which carry
the affordances), `footprint` (Vector2i cells), `cost` (Dictionary account -> amount),
`refund_ratio`, `indoor`/`outdoor` placement flags, `category` (care, play, path, service),
`description`, later `unlock` (reputation tier, M9). Types live in `buildings/*.tres`; a new
building is a scene plus a `.tres`, no code. `Building` (`buildings/building.gd`, Node3D)
knows its data, cell and rotation. `BuildGrid` (`world/build_grid.gd`): 1 m cells over the
plot (and the house floor for indoor types), occupancy map, blocked cells (house walls,
furniture, the doorway kept clear), `can_place(data, cell, rot)`, `place(...) -> Building`,
`remove(building)`. Placing or removing rebakes the navmesh once (synchronous, so seeded
runs stay deterministic) and releases claims on the removed building's items.

**Build mode.** B in Live mode. The camera rig gets a third mode, top-down over the plot
(eased like close-up, exit restores the Live view). Grid lines and blocked cells drawn on
the ground. Palette bottom-center: one button per BuildingData the player can afford
(price shown, greyed if short). Ghost of the selected type follows the cursor, snapped
to cells, green if `can_place` and affordable, red otherwise. LMB place (`Ledger.pay`),
R rotate 90 degrees, X or Delete on a building removes it (refund by Q6), Esc or B
leaves. RMB stays camera orbit. Dogs keep living while you build (time doesn't stop;
Space pauses as always). Code API for tests and `--autoowner`: `select_type(data)`,
`hover_cell(cell)`, `confirm() -> Building`, `remove_at(cell)`.

**Supplies.** Kibble and treats are stock in the ledger. Refilling a bowl (F, the bowl
station later, `--autofeed`) moves `1 - fill` kibble from stock into the bowl; with too
little stock it fills what there is and the hint says "Out of kibble". The treat jar draws
treats the same way. Water stays free (design: capacity, not a cost; a well or pump is a
later building). Orders: from the supply depot (a fixed service building by the gate),
buy a pack (Q1, Q7); it arrives after the delivery delay, as a crate at the depot that
adds to stock when it lands (or straight into stock in v0, Q7). Orders in flight are
saved. `--autofeed` gets free top-ups of exactly what it refills, so the default soaks
stay exact; `--autoowner` (step 7) orders and pays like a player.

**Visitors v0.** A visitor is a simple node (capsule, own walk on the navmesh, no physics
collision with dogs, not in the `dogs` group, no avoidance shared with dogs) with its own
tiny state machine, not a DogBrain: arrive at the gate -> walk to up to 3 dogs in turn
(nearest awake dog it hasn't met, within the plot) -> stand 2 m off and watch for a few
game minutes (emote) -> pay -> leave. Payment = entry fee + a tip per dog met, scaled by
that dog's happiness (Q1). Arrivals come from a seeded schedule
(`hash([seed, "visitors"])`), so seeded runs repeat. In v0 dogs don't notice visitors: no
stimulus, no behavior, no `brain.rng` use, so turning visitors on doesn't change any dog's
choices. Dogs greeting visitors (and the Companion skill tree's greeter bonus) come later,
through the body API (`Dog.notice(&"visitor", point)` -> a `greet_visitor` behavior that
scores 0 without a visitor near).

**HUD.** Resources bar top-right: coins, kibble (bowl fills), treats, and a small
"+12 visitor" float on income. The day summary (income and expenses by reason, from the
ledger's tallies) opens with K and shows at the first frame of a new day for a few seconds.
Both stay clear of the F3 overlay (top-left), the dog card (bottom-right) and the close-up
hint (top-center).

**Baseline rules for M4.** New systems must not move the 1- and 12-dog baselines unless
their trigger is present in the soak, and the soaks don't build, order or have visitors.
Two moves are expected and are recorded deliberately in their step's commit, in
`tools/verify.sh`, DEVELOPMENT.md, README.md and `docs/m2_pack.md`: step 2 (the plot
changes the navmesh, so `random_point_near` and wander paths change), and step 3 only if
Q5 moves the bowls. Run verify twice after each move to check it's stable. pack30 and
`hands` will shift with any physics or navmesh change (chaotic); check them for
ERROR/WARNING and sane needs only.

## Decisions for the owner

Each has a recommended default; say "defaults" to take them all.

- **Q1. Currency and numbers: what a happy dog is worth.** Recommended: one currency,
  coins (as `docs/design.md`). Visitor pays an entry fee of 5 coins plus, per dog met,
  a tip of `round(4 x h)` coins, where h = happiness 0..1 = (mood + 1) / 2, x 1.25 if the
  dog's bond >= 50 (a dog that trusts you shows off). So a content dog (mood +0.4) earns
  about 3 coins a visit, a miserable one 0-1. Kibble: 3 coins per bowl fill, sold in
  packs of 10 fills (30 coins). Treats: 10 for 15 coins. Start: 150 coins, 10 fills of
  kibble, a full treat jar. For scale: in the one-dog soak a dog eats about 3.5 bowl
  fills over 48 h (3 refills by `--autofeed`), about 5 coins a day; 12 dogs cost roughly
  60 coins a day in kibble. A visitor who meets 3 content dogs pays 5 + 3 x 3 = 14, so
  about 5 visitors a day break even and 7 (Q8) leave some 35 coins a day to build with.
  Tune in step 7 with the estate soak.
- **Q2. Plot size and layout.** Recommended: 30 x 24 m fenced plot, the house in the
  north-west corner, gate and supply depot on the south fence, about 450 m2 of open
  ground to build on. Big enough for 30 dogs and a few play yards, small enough that the
  navmesh rebake stays well under 100 ms.
- **Q3. Doorway.** Recommended: a 1.5 m gap in the south (low) wall of the house, west of
  the rug, always open. Alternative: a dog door building the player places (cuts the
  dogs off from the plot until built).
- **Q4. The first building set** (step 3; all `.tres` + scene). Recommended five:
  feeding station (food + water bowl pair, 1 x 2 cells, 40 coins), dog bed (1 x 1, 25),
  play yard (4 x 4 low fence with a ball, 80), path tile (1 x 1, 2; visitors prefer
  paths, a later attraction bonus), bench (1 x 1, 15; visitors rest, cosmetic in v0).
  Fixed, not buildable: house, gate, supply depot. Kitchen and garden (treats from
  ingredients) wait for M6, where ingredients come from expeditions.
- **Q5. Do bowls become buildings?** Recommended: yes. The room's bowl pair becomes a
  pre-placed feeding station at the same spot, so the dogs and the baselines don't
  notice; `--bowls=N` places more stations; the save migration maps the old
  `Items/FoodBowl` and `Items/WaterBowl` paths to the station's. The loose dog bed and
  treat jar stay items.
- **Q6. Remove refund.** Recommended: 50% of the cost back, 100% within 1 game minute of
  placing (an undo for misclicks).
- **Q7. Deliveries.** Recommended: an order arrives 2 game hours later as stock (no
  crate to carry in v0), one order in flight per resource type, placed from the depot
  or the HUD (K summary page) with a button.
- **Q8. Visitors.** Recommended: open 10:00-17:00, one visitor every 40-80 game minutes
  (about 7 a day), at most 3 on the plot at a time, each meets up to 3 dogs. No
  reputation gate in M4; track `reputation` in the ledger (+1 per visitor who met a
  happy dog) so M9 tiers have history to start from.
- **Q9. Is a dog's happiness only mood?** Recommended: yes for v0 (mood is already the
  care summary: every need feeds it). Skills that change earnings (greeter) come with M5.

## Known open questions (resolve during the milestone, don't block on them)

- Navmesh rebake cost on the bigger plot with many buildings; if it shows, bake per
  building region (one NavigationRegion3D each, linked) instead of one big region.
- Indoor building: whether the house floor is on the build grid in M4 or only the plot.
- Should dogs prefer indoors at night (sleep in the house)? Today they sleep at the bed
  item wherever it is; a second bed outdoors may split the pack.
- Mess (droppings, muddy paws) is the design's upkeep sink; it fits M7 (staff and
  cleaning) better than M4.
- Toys wearing out (design: a sink for toys) is left for later; the ball doesn't wear.
- Offline catch-up and the economy: visitors and deliveries while away. v0: deliveries
  complete, visitors don't come (no income while away, nothing lost either).
