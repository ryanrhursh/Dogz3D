class_name DogPanel
extends CanvasLayer
## Player-facing card for the selected dog: name, how it feels, what it's doing, its
## needs, its strongest traits, its bond with you and its best friend. Plain words, no
## numbers except the bond. The F3 debug overlay is the developer view. I toggles.

const REFRESH_SECONDS := 0.2
const NEED_ROWS := [
	[&"hunger", "Food"],
	[&"thirst", "Water"],
	[&"energy", "Energy"],
	[&"fun", "Fun"],
	[&"affection", "Love"],
]
## Trait -> [word when high, word when low].
const TRAIT_WORDS := {
	&"energy": ["Energetic", "Mellow"],
	&"sociability": ["Friendly", "Shy"],
	&"boldness": ["Bold", "Timid"],
	&"food_drive": ["Foodie", "Picky eater"],
	&"toy_drive": ["Toy-crazy", "Not into toys"],
	&"stubbornness": ["Stubborn", "Easygoing"],
	&"trainability": ["Eager to learn", "Free spirit"],
}
const TOP_TRAITS := 3
## [lowest bond for this word, word], highest first.
const BOND_WORDS := [
	[85.0, "Best buddies"],
	[60.0, "Close"],
	[35.0, "Friends"],
	[15.0, "Getting to know you"],
	[0.0, "Wary"],
]

var dog: Dog:
	set(value):
		dog = value
		_refresh = 0.0

var _panel: PanelContainer
var _name: Label
var _feeling: Label
var _doing: Label
var _need_bars: Dictionary = {}
var _traits: Label
var _bond: Label
var _friend: Label
var _refresh := 0.0


func _ready() -> void:
	layer = 9
	_build()


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_SECONDS
	refresh_view()


func toggle() -> void:
	_panel.visible = not _panel.visible


func is_shown() -> bool:
	return _panel.visible and dog != null and is_instance_valid(dog)


## Name, feeling, doing, traits, bond and friend lines as shown (for tests and tooltips).
func get_lines() -> PackedStringArray:
	return PackedStringArray([_name.text, _feeling.text, _doing.text, _traits.text,
			_bond.text, _friend.text])


func refresh_view() -> void:
	var has_dog := dog != null and is_instance_valid(dog)
	_panel.modulate.a = 1.0 if has_dog else 0.0
	if not has_dog:
		return
	var brain := dog.brain
	var breed_name := ""
	if dog.breed != null:
		breed_name = "  ·  " + dog.breed.breed_name
	_name.text = dog.dog_name + breed_name
	_feeling.text = "Feeling %s" % mood_word(brain.mood())
	_doing.text = doing_text(dog)
	for row: Array in NEED_ROWS:
		var bar: ProgressBar = _need_bars[row[0]][0]
		var fill: StyleBoxFlat = _need_bars[row[0]][1]
		var v := brain.needs.get_value(row[0]) / DogNeeds.MAX_VALUE
		bar.value = v
		fill.bg_color = Color.from_hsv(v * 0.33, 0.55, 0.85)
	_traits.text = ", ".join(top_traits(brain.personality, TOP_TRAITS))
	_bond.text = "Bond with you: %.0f  (%s)" % [brain.memory.bond, bond_word(brain.memory.bond)]
	_friend.text = friend_text(dog)


static func mood_word(mood: float) -> String:
	if mood >= 0.6:
		return "great"
	if mood >= 0.25:
		return "happy"
	if mood >= -0.1:
		return "okay"
	if mood >= -0.5:
		return "low"
	return "miserable"


static func bond_word(bond: float) -> String:
	for entry: Array in BOND_WORDS:
		if bond >= float(entry[0]):
			return entry[1]
	return BOND_WORDS.back()[1]


## The `count` traits furthest from average, as words ("Energetic", "Shy", ...).
static func top_traits(personality: DogPersonality, count: int) -> PackedStringArray:
	var ranked: Array = []
	for trait_name: StringName in DogPersonality.TRAITS:
		var v := personality.get_trait_value(trait_name)
		ranked.append([absf(v - 0.5), trait_name, v])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var words := PackedStringArray()
	for entry: Array in ranked.slice(0, count):
		var pair: Array = TRAIT_WORDS[entry[1]]
		words.append(pair[0] if float(entry[2]) >= 0.5 else pair[1])
	return words


static func doing_text(d: Dog) -> String:
	if d.sleeping:
		return "Sleeping"
	if d.brain.current == null:
		return "Thinking"
	var text := d.brain.current.label
	if d.social_partner_id != "":
		var info := d.get_dog_info(d.social_partner_id)
		if not info.is_empty():
			text += " with %s" % str(info["name"])
	return text


static func friend_text(d: Dog) -> String:
	var best_id := ""
	var best := DogMemory.FRIEND_AFFINITY
	for other_id: String in d.brain.memory.relationships:
		var a := d.brain.memory.get_affinity(other_id)
		if a >= best and d.get_dog_info(other_id).size() > 0:
			best = a
			best_id = other_id
	if best_id == "":
		if d.brain.memory.relationships.is_empty():
			return "Hasn't met the pack yet"
		return "No close friend yet"
	return "Best friend: %s" % str(d.get_dog_info(best_id)["name"])


func _build() -> void:
	var theme := Theme.new()
	theme.default_font_size = 14

	_panel = PanelContainer.new()
	_panel.theme = theme
	_panel.custom_minimum_size = Vector2(260, 0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.1, 0.09, 0.85)
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", bg)
	add_child(_panel)
	# Bottom-right corner, growing up and left with its content.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_right = -14.0
	_panel.offset_bottom = -14.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_name = _label(box, 20, Color(1.0, 0.93, 0.8))
	_feeling = _label(box, 14, Color(0.95, 0.9, 0.85))
	_doing = _label(box, 13, Color(0.8, 0.78, 0.75))

	for row: Array in NEED_ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var title := Label.new()
		title.text = row[1]
		title.custom_minimum_size = Vector2(60, 0)
		title.add_theme_font_size_override("font_size", 12)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(170, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.001
		var fill := StyleBoxFlat.new()
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		var track := StyleBoxFlat.new()
		track.bg_color = Color(1, 1, 1, 0.1)
		track.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", track)
		line.add_child(title)
		line.add_child(bar)
		box.add_child(line)
		_need_bars[row[0]] = [bar, fill]

	_traits = _label(box, 13, Color(0.85, 0.85, 0.95))
	_bond = _label(box, 13, Color(1.0, 0.8, 0.85))
	_friend = _label(box, 13, Color(0.8, 0.95, 0.85))


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
