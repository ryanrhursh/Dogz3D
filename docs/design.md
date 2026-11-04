# Dogz 3D (working title): design

Source of truth for the game design. Supersedes the original single-dog idea document.

## Pitch

A cozy **life sim and town builder in a world of animals**. You start with a small
countryside plot and a house, and grow it into a town. Its citizens are animals (dogs
first, other species later, and a few human or other characters along the way) with real
lives: needs, personalities, friends, jobs, skill trees and quests of their own. You build
and supply the town, they live, work and make friends in it. Click any animal to step in
close: pet it, feed it by hand, play, train it.

Think of The Sims' lives and careers, a city builder's resource layer (Two Point,
Stardew's farm) and Dogz-style living pets. **Not a zoo**: nobody comes to look at the
animals; the animals are the town.

## Pillars

1. **Every dog is someone.** Each dog has its own brain, personality, likes, memories, skill
   tree and personal quests, and shows how it feels through tail, ears and posture before
   any UI does. You learn them by name.
2. **Build to care.** Buildings exist to meet the animals' needs and give them work. The
   economy is care made visible: happy, skilled animals do their jobs well and earn the
   town its income.
3. **Hands-on joy, never chores.** Close-up interactions are tactile, quick and rewarding,
   and every one grants bond and XP. Repetitive upkeep (filling bowls, cleaning) moves to
   buildings and staff as the town grows. The player's hand is for the fun parts.
4. **Learned, not scripted.** Tricks and habits come from reinforcement, so training feels
   earned.
5. **Cozy pressure.** Resources matter and choices have trade-offs, but failure is gentle.
   Dogs never die. Neglect makes dogs unhappy and less productive, and in the worst case a
   dog wanders off to a neighbour, and a quest brings it home.

## Loops

| Scale | Loop |
|---|---|
| Moment | Click a dog, then pet, play, treat or train it. It reacts in character and you get bond and XP right away. |
| Day | Needs use up resources (food, water, toys, beds, grooming). Animals go to their jobs and come home with wages; gardens grow food. Buildings store and convert resources. You spend coins on supplies and building. |
| Week | Animals level up and spend skill points, change jobs, quests and expeditions finish, competitions run, neighbours drop by, new animals arrive, and progress unlocks buildings and more land. |

## Resources

| Resource | Sources | Sinks |
|---|---|---|
| Coins | Animals' wages from jobs (scaled by performance: mood and job fit, later skills), town contracts, competition prizes, quest rewards, trade with neighbours | Supplies, buildings, upgrades, staff wages, land |
| Kibble | Bought from the supply depot (delivery delay) | Bowls (staff, a job or player refill) |
| Produce | Garden beds (farming): planted, grown over game days, harvested | Bowls (food), kitchen |
| Treats | Bought; later the kitchen (produce and ingredients become treats) | Hand-feeding and training rewards (bond, XP) |
| Ingredients | Garden beds, foraging expeditions, trade with neighbours | Kitchen |
| Water | Well/pump (capacity, not a cost) | Bowls, troughs |
| Toys | Bought or crafted; they wear out | Play yards, close-up play |
| Staff time | Hired caretakers (wages) | Chores: refills, cleaning, grooming |
| Space | Land expansions (coins + reputation) | Buildings, kennel capacity |
| Reputation | Happy animals, jobs done well, competitions, quests | Gates unlock tiers (buildings, land, new animals) |

Mess (droppings, muddy paws, chewed things) is the upkeep sink, handled by cleaning
(player early, staff later).

**Food sources.** Kibble is the baseline you buy. Farming grows produce in garden beds
(and an animal with the gardener job tends them). Later: the kitchen turns produce and
ingredients into treats and meals, foraging expeditions bring finds home, and neighbours
trade food for coins or favours.

## Jobs

Animals earn the town's money by working, like Sims careers.
- **Careers away from home:** at shift time the animal leaves through the gate, is away
  for the shift (its needs keep draining, it's "at work"), and comes home with its wage.
  Examples: courier, therapy visits, show performer.
- **Workplaces on the plot:** buildings where the job happens in view. The first is the
  garden (gardener: tends and harvests the beds); later the kitchen, a clinic, a shop.
- **Who picks:** animals apply for jobs that suit their personality, and the player
  approves, rejects or reassigns from the job board.
- **Pay:** base wage x performance. Performance comes from mood and job fit
  (personality), later from skills. A bad fit pays less and wears the mood down.
- Jobs are data (JobData Resources): new careers don't need code.

## Neighbours

A few named characters (human or other species) live nearby. They drop by now and then
to trade, ask favours, give quests and bring news. They are people with stories, not a
crowd: the town's citizens are its animals.

## Dogs

- **Brain (built):** five needs, seven traits, utility-AI behaviors and memory. A dog is
  autonomous; it uses whatever buildings and items the town gives it, via affordance tags.
- **Bond (built):** per-dog trust toward the player. It gates interactions and quest options
  and boosts XP.
- **Touch preferences (built):** per-dog liked and disliked petting zones, discovered by
  playing.
- **Levels and XP:** earned from activities (play, training, jobs, quests, competitions).
- **Skill trees:** each dog has the same four trees, and its personality sets how fast each
  one grows (its affinity).
  - Companion: therapy visits, calming other animals, better with neighbours.
  - Athlete: agility, fetch, races, competitions.
  - Smarts: tricks, puzzle toys, faster training, learning cues.
  - Scout: forage expeditions, digging up finds, tracking lost dogs.

  Some nodes change behavior (new actions) and some change the economy (for example
  "Courier: +10% courier wages"). Skill trees are data (Resources), so new
  trees and species don't need code changes.
- **Quests:**
  - Personal: generated from personality and memory, e.g. "make a friend", "get over fear of
    the vacuum", "learn to fetch". These give each dog a story.
  - Expeditions: send one dog or a team off-map for game hours. Their skills decide the
    rewards (ingredients, coins, finds, a new stray).
  - Town contracts: e.g. "Village fair: 3 dogs with Agility 2 by Saturday".
- **Land:** the plot starts small and grows: expansion parcels unlock as you and your
  animals level up and complete quests.
- **Traits drift with experience** (training builds trainability, scary events lower
  boldness, and so on).

## Interaction modes

| Mode | Camera | Mouse |
|---|---|---|
| Live | Orbit over the town | Click a dog to select it (info panel, camera follows it). Click it again to go close-up. |
| Close-up | Framed on one dog | Hand tool: pet zones, hand-feed, play ball and tug, train tricks, groom. Esc goes back. |
| Build | Top-down grid | Place, move and upgrade buildings; zone paths. |

## Scale

Start with 10–30 animals, each with a full brain. The architecture keeps a later jump to 100+
open: brains are plain data objects ticked by the scene, evaluation can be staggered and
budgeted, and off-screen dogs can drop to a cheaper "level of detail" simulation. Revisit
after the economy milestone.

## Species

Dogs first. Species and breeds are data (BreedData now, SpeciesData later), so cats and
others arrive as data plus a few species-specific behaviors.
