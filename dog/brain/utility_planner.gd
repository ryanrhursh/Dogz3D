class_name UtilityPlanner
extends RefCounted
## Scores every behavior and picks one.
##
## Rules:
## - The current behavior gets a small inertia bonus.
## - A non-interruptible behavior only yields to an emergency (score >= OVERRIDE_SCORE).
## - An interruptible one stays as long as it is within NEAR_BEST_RATIO of the best.
## - Fresh picks are weighted-random among the top few near-best scores,
##   so the dog isn't a predictable state machine.

const INERTIA_BONUS := 0.08
const NEAR_BEST_RATIO := 0.85
const TOP_N := 3
const OVERRIDE_SCORE := 0.9

var behaviors: Array[DogBehavior] = []
## Behavior id -> score from the last evaluation (inertia included). Read by the debug overlay.
var last_scores: Dictionary = {}


func choose(dog: Dog, current: DogBehavior, cooldowns: Dictionary,
		rng: RandomNumberGenerator) -> DogBehavior:
	last_scores.clear()
	var ranked: Array = []
	for behavior in behaviors:
		var s := 0.0
		if not cooldowns.has(behavior.id):
			s = behavior.score(dog)
			if behavior == current:
				s += INERTIA_BONUS
		last_scores[behavior.id] = s
		ranked.append([behavior, s])
	if ranked.is_empty():
		return current
	ranked.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) > float(y[1]))

	var best: Array = ranked[0]
	var best_behavior: DogBehavior = best[0]
	var best_score: float = best[1]

	if current != null and not current.interruptible:
		if best_behavior != current and best_score >= OVERRIDE_SCORE:
			return best_behavior
		return current

	if best_score <= 0.0:
		return current

	var pool: Array = []
	var total := 0.0
	for i in mini(TOP_N, ranked.size()):
		var entry: Array = ranked[i]
		var s: float = entry[1]
		if s > 0.0 and s >= best_score * NEAR_BEST_RATIO:
			if entry[0] == current:
				return current
			pool.append(entry)
			total += s

	var roll := rng.randf() * total
	for entry in pool:
		roll -= float(entry[1])
		if roll <= 0.0:
			return entry[0]
	var last: Array = pool.back()
	return last[0]
