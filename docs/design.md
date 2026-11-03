# Dogz 3D (working title): design

Source of truth for the game design. Supersedes the original single-dog idea document.

## Pitch

A cozy **dog sanctuary town builder**. You inherit a run-down countryside estate and grow it
into a famous sanctuary. You build and supply the town, and the dogs live their own lives in
it. Every dog is an individual with a personality, needs, skills, quests and a bond with you.
Click any dog to step in close: pet it, feed it by hand, play, train it.

Think of a city builder's resource layer (Two Point, Planet Zoo, Stardew's farm) around
Dogz-style living pets.

## Pillars

1. **Every dog is someone.** Each dog has its own brain, personality, likes, memories, skill
   tree and personal quests, and shows how it feels through tail, ears and posture before
   any UI does. You learn them by name.
2. **Build to care.** Buildings exist to meet dogs' needs. The economy is care made visible:
   happy, skilled dogs earn the town its income.
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
| Day | Needs use up resources (food, water, toys, beds, grooming). Buildings store and convert them. Visitors pay to meet happy dogs. You spend coins on supplies and building. |
| Week | Dogs level up and spend skill points, quests and expeditions finish, competitions run, new dogs arrive, and reputation tiers unlock buildings and land. |

## Resources

| Resource | Sources | Sinks |
|---|---|---|
| Coins | Visitors (scaled by dog happiness and attractions), competition prizes, quest rewards, shop goods | Supplies, buildings, upgrades, staff wages, land |
| Kibble | Bought from the supply depot (delivery delay) | Bowls (staff or player refill) |
| Treats | Kitchen: ingredients become treats | Hand-feeding and training rewards (bond, XP) |
| Ingredients | Garden plots, forager expeditions | Kitchen |
| Water | Well/pump (capacity, not a cost) | Bowls, troughs |
| Toys | Bought or crafted; they wear out | Play yards, close-up play |
| Staff time | Hired caretakers (wages) | Chores: refills, cleaning, grooming |
| Space | Land expansions (coins + reputation) | Buildings, kennel capacity |
| Reputation | Happy dogs, visitors, competitions, quests | Gates unlock tiers (buildings, land, new dogs) |

Mess (droppings, muddy paws, chewed things) is the upkeep sink, handled by cleaning
(player early, staff later).

## Dogs

- **Brain (built):** five needs, seven traits, utility-AI behaviors and memory. A dog is
  autonomous; it uses whatever buildings and items the town gives it, via affordance tags.
- **Bond (built):** per-dog trust toward the player. It gates interactions and quest options
  and boosts XP.
- **Touch preferences (built):** per-dog liked and disliked petting zones, discovered by
  playing.
- **Levels and XP:** earned from activities (play, training, quests, competitions, visitors).
- **Skill trees:** each dog has the same four trees, and its personality sets how fast each
  one grows (its affinity).
  - Companion: greeter and therapy-dog visits, visitor tips, calming other dogs.
  - Athlete: agility, fetch, races, competitions.
  - Smarts: tricks, puzzle toys, faster training, learning cues.
  - Scout: forage expeditions, digging up finds, tracking lost dogs.

  Some nodes change behavior (new actions) and some change the economy (for example
  "Greeter: +10% visitor coins while at the gate"). Skill trees are data (Resources), so new
  trees and species don't need code changes.
- **Quests:**
  - Personal: generated from personality and memory, e.g. "make a friend", "get over fear of
    the vacuum", "learn to fetch". These give each dog a story.
  - Expeditions: send one dog or a team off-map for game hours. Their skills decide the
    rewards (ingredients, coins, finds, a new stray).
  - Town contracts: e.g. "Village fair: 3 dogs with Agility 2 by Saturday".
- **Traits drift with experience** (training builds trainability, scary events lower
  boldness, and so on).

## Interaction modes

| Mode | Camera | Mouse |
|---|---|---|
| Live | Orbit over the town | Click a dog to select it (info panel, camera follows it). Click it again to go close-up. |
| Close-up | Framed on one dog | Hand tool: pet zones, hand-feed, play ball and tug, train tricks, groom. Esc goes back. |
| Build | Top-down grid | Place, move and upgrade buildings; zone paths. |

## Scale

Start with 10–30 dogs, each with a full brain. The architecture keeps a later jump to 100+
open: brains are plain data objects ticked by the scene, evaluation can be staggered and
budgeted, and off-screen dogs can drop to a cheaper "level of detail" simulation. Revisit
after the economy milestone.

## Species

Dogs first. Species and breeds are data (BreedData now, SpeciesData later), so cats and
others arrive as data plus a few species-specific behaviors.
