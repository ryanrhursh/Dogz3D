class_name AutoHands
extends Node
## A simulated owner for soak runs (--autohands). It plays through the HandTool code API
## only, like a player in close-up would: it strokes lonely dogs (learning which zones
## each dog likes from its reactions), holds food out to hungry dogs and lets go once
## they've come over (a treat now and then), and throws the ball for bored dogs. One
## thing at a time, every ACTION_EVERY game minutes, and only while the owner is up. Each
## turn starts with the next kind of action in turn (feed, pet, throw) and falls through
## to the others if nobody needs it, so a big pack's loneliness doesn't crowd out the rest.
## Its own RNG, so a seeded run repeats exactly.
##
## Separate from --autopet (Dog.pet(), the E key), which stays as it was.

## Game minutes between the owner's actions.
const ACTION_EVERY := 15.0
## The owner is around from WAKE_HOUR to BED_HOUR.
const WAKE_HOUR := 7
const BED_HOUR := 22
## Needs below these get the owner's attention. Generous on purpose: the owner hand-feeds
## a peckish dog and plays with one that's a bit bored, not only one in need.
const HUNGRY_BELOW := 85.0
const LONELY_BELOW := 60.0
const BORED_BELOW := 90.0
const PLAY_MIN_ENERGY := 50.0
const STROKES := 3
## Zones tried in this order until the owner knows what a dog likes.
const ZONES := [&"back", &"head", &"ears", &"belly"]
const TREAT_CHANCE := 0.25
## Food is held out this far from the dog, at carry height.
const OFFER_DISTANCE := 1.2
## Game minutes the owner holds food out before walking the hand to the dog's mouth.
const OFFER_MINUTES := 6.0
const THROW_SPEED_MIN := 3.0
const THROW_SPEED_MAX := 5.0
const THROW_LIFT := 1.2
## The ball leaves the hand this far (flat metres) from the dog it's thrown for.
const THROW_FROM := 0.7

var hand: HandTool
var pack: Pack
var bowl: WorldItem
var jar: WorldItem
var ball: WorldItem
var rng := RandomNumberGenerator.new()

## Counts for the soak summary.
var strokes := 0
var kibble := 0
var treats := 0
var drops := 0
var throws := 0

var _next_action := 0.0
## Which kind of action goes first this turn (0 feed, 1 pet, 2 throw).
var _turn := 0
## While holding food out: the dog it's for, and game minutes left to wait.
var _feeding: Dog
var _offer_left := 0.0
## dog_id -> {zone: last reaction}.
var _learned: Dictionary = {}


func setup(p_hand: HandTool, p_pack: Pack, p_bowl: WorldItem, p_jar: WorldItem,
		p_ball: WorldItem, seed_value: int) -> void:
	hand = p_hand
	pack = p_pack
	bowl = p_bowl
	jar = p_jar
	ball = p_ball
	rng.seed = hash([seed_value, "autohands"])
	_next_action = SimClock.total_minutes + ACTION_EVERY


func _process(_delta: float) -> void:
	if SimClock.paused or hand == null:
		return
	if _feeding != null:
		_tick_feeding(SimClock.last_delta_minutes)
		return
	if SimClock.total_minutes < _next_action:
		return
	_next_action = SimClock.total_minutes + ACTION_EVERY
	var hour := SimClock.get_hour()
	if hour < WAKE_HOUR or hour >= BED_HOUR or hand.held_item != null:
		return
	for i in 3:
		var kind := (_turn + i) % 3
		var done := false
		match kind:
			0:
				done = _try_feed()
			1:
				done = _try_pet()
			_:
				done = _try_throw()
		if done:
			break
	_turn = (_turn + 1) % 3


## Summary line for the soak output.
func summary() -> String:
	return "Hands: strokes %d, kibble %d, treats %d (dropped %d), throws %d" % [
			strokes, kibble, treats, drops, throws]


func _try_feed() -> bool:
	var target := _neediest(&"hunger", HUNGRY_BELOW)
	if target == null:
		return false
	var source := bowl
	if jar != null and jar.fill >= jar.hand_piece_fill and rng.randf() < TREAT_CHANCE:
		source = jar
	if not hand.pick_from(source):
		if source == bowl or not hand.pick_from(bowl):
			return false
	var toward := Vector3.ZERO - target.global_position
	toward.y = 0.0
	if toward.length() < 0.1:
		toward = Vector3.BACK
	var offer := target.global_position + toward.normalized() * OFFER_DISTANCE
	hand.carry_to(Vector3(offer.x, HandTool.CARRY_HEIGHT, offer.z))
	_feeding = target
	_offer_left = OFFER_MINUTES
	return true


## Holds the food out until the dog's mouth is at the hand, then lets go. If it doesn't
## come in time, the owner takes the food to it (or drops it if it fell asleep).
func _tick_feeding(minutes: float) -> void:
	_offer_left -= minutes
	var target := _feeding
	if hand.held_item == null:
		_feeding = null
		return
	var treat := hand.held_item.has_affordance(&"treat")
	if not is_instance_valid(target) or target.sleeping:
		_feeding = null
		hand.release_at(hand.hand_point)
		drops += 1
		return
	var at_hand := target.get_mouth_position().distance_to(hand.hand_point) <= HandTool.FEED_RADIUS
	if not at_hand and _offer_left > 0.0:
		return
	_feeding = null
	if hand.release_at(target.get_mouth_position()) != null:
		if treat:
			treats += 1
		else:
			kibble += 1
	else:
		drops += 1


func _try_pet() -> bool:
	var target := _neediest(&"affection", LONELY_BELOW)
	if target == null:
		return false
	var zone := _zone_for(target)
	var reaction := hand.stroke(target, zone, STROKES)
	var known: Dictionary = _learned.get(target.dog_id, {})
	known[zone] = reaction
	_learned[target.dog_id] = known
	strokes += STROKES
	return true


func _try_throw() -> bool:
	if ball == null or not is_instance_valid(ball) or ball.held:
		return false
	var target: Dog = null
	var lowest := BORED_BELOW
	for d in pack.dogs:
		var needs := d.brain.needs
		if d.sleeping or needs.get_value(&"energy") < PLAY_MIN_ENERGY:
			continue
		if needs.get_value(&"fun") < lowest:
			lowest = needs.get_value(&"fun")
			target = d
	if target == null or not hand.pick_from(ball):
		return false
	# From beside the dog, away from it.
	var angle := rng.randf() * TAU
	var away := Vector3(sin(angle), 0.0, cos(angle))
	hand.carry_to(target.global_position + away * THROW_FROM + Vector3(0.0, 0.5, 0.0))
	var velocity := away * rng.randf_range(THROW_SPEED_MIN, THROW_SPEED_MAX) \
			+ Vector3(0.0, THROW_LIFT, 0.0)
	if hand.throw_item(velocity):
		throws += 1
	return true


## The awake dog with the lowest `need` below `below`, or null.
func _neediest(need: StringName, below: float) -> Dog:
	var best: Dog = null
	var lowest := below
	for d in pack.dogs:
		if d.sleeping:
			continue
		var value := d.brain.needs.get_value(need)
		if value < lowest:
			lowest = value
			best = d
	return best


## A zone the dog liked last time, else one not tried yet, else one it didn't mind.
func _zone_for(target: Dog) -> StringName:
	var known: Dictionary = _learned.get(target.dog_id, {})
	for zone: StringName in ZONES:
		if known.get(zone) == &"likes":
			return zone
	for zone: StringName in ZONES:
		if not known.has(zone):
			return zone
	for zone: StringName in ZONES:
		if known.get(zone) != &"dislikes":
			return zone
	return ZONES[0]
