class_name FoodPiece
extends WorldItem
## A bite of food the hand carries: kibble from the bowl, a treat from the jar.
## Hand-fed (Dog.feed_from_hand) it gives the hand_* amounts below. Dropped, it's ordinary
## food on the floor that the eat behavior finds; its fill is in bowl units (the bowl's
## eat rate applies), and it's freed once eaten.

@export var hand_hunger := 8.0
@export var hand_affection := 4.0
@export var hand_fun := 0.0
## Before the dog's food_drive scaling (DogBrain.on_hand_fed).
@export var hand_bond := 1.0


func hand_fed_effects() -> Dictionary:
	return {
		"hunger": hand_hunger,
		"affection": hand_affection,
		"fun": hand_fun,
		"bond": hand_bond,
	}
