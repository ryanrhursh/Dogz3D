extends CanvasLayer
## Live view into the selected dog's brain: clock, needs, behavior scores, personality
## and the decision log. F3 toggles. Tuning utility AI without this is guesswork.

const REFRESH_SECONDS := 0.1
const NEED_ORDER := [&"hunger", &"thirst", &"energy", &"fun", &"affection"]
const HELP_TEXT := "RMB drag orbit · wheel zoom · WASD pan · C follow dog    " \
		+ "LMB/Tab select dog · LMB selected dog close-up · Esc leave · N adopt · I dog card    " \
		+ "1-4 speed · Space pause\n" \
		+ "Close-up: LMB pat · drag stroke    " \
		+ "E pet · F refill food · G refill water    " \
		+ "F3 overlay · F5 save · F9 load · F8 re-roll dog"

@export var dog: Dog

var _panel: PanelContainer
var _clock: Label
var _header: Label
var _current: Label
var _need_rows: Dictionary = {}
var _score_box: VBoxContainer
var _score_rows: Dictionary = {}
var _items: Label
var _traits: Label
var _friends: Label
var _hands: Label
var _log: Label
var _help: Label
var _refresh := 0.0


func _ready() -> void:
	layer = 10
	_build()


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0 or not _panel.visible:
		return
	_refresh = REFRESH_SECONDS
	_refresh_view()


func toggle() -> void:
	_panel.visible = not _panel.visible
	_help.visible = _panel.visible


func _refresh_view() -> void:
	var status := ""
	if SimClock.paused:
		status = "   PAUSED"
	_clock.text = "%s    x%s%s" % [SimClock.format_time(), str(SimClock.time_scale), status]
	if dog == null or not is_instance_valid(dog):
		return
	var brain := dog.brain

	var breed_name := "?"
	if dog.breed != null:
		breed_name = dog.breed.breed_name
	var pack := get_tree().get_first_node_in_group("pack") as Pack
	var pack_text := ""
	if pack != null and pack.dogs.size() > 1:
		pack_text = "   [%d/%d]" % [pack.dogs.find(dog) + 1, pack.dogs.size()]
	_header.text = "%s (%s)   bond %.0f   mood %+.2f%s" % [dog.dog_name, breed_name,
			brain.memory.bond, brain.mood(), pack_text]

	var doing := "-"
	if brain.current != null:
		doing = brain.current.label
	var asleep := ""
	if dog.sleeping:
		asleep = "  [asleep]"
	_current.text = "Doing: %s  (%.0f min)%s" % [doing, brain.minutes_in_current, asleep]

	for need: StringName in NEED_ORDER:
		var row: Array = _need_rows[need]
		var v := brain.needs.get_value(need) / DogNeeds.MAX_VALUE
		(row[1] as ProgressBar).value = v
		(row[2] as Label).text = "%3.0f" % (v * 100.0)
		(row[3] as StyleBoxFlat).bg_color = Color.from_hsv(v * 0.33, 0.65, 0.85)

	for behavior in brain.planner.behaviors:
		if not _score_rows.has(behavior.id):
			_score_rows[behavior.id] = _bar_row(_score_box, String(behavior.label))
		var row: Array = _score_rows[behavior.id]
		var s: float = float(brain.planner.last_scores.get(behavior.id, 0.0))
		var chosen := brain.current == behavior
		var prefix := "  "
		if chosen:
			prefix = "> "
		(row[0] as Label).text = prefix + behavior.label
		(row[1] as ProgressBar).value = clampf(s, 0.0, 1.0)
		var value_text := "%.2f" % s
		if brain.cooldowns.has(behavior.id):
			value_text = "cd %.0f" % float(brain.cooldowns[behavior.id])
		(row[2] as Label).text = value_text
		var fill_color := Color(0.45, 0.5, 0.6)
		if chosen:
			fill_color = Color(0.35, 0.65, 1.0)
		(row[3] as StyleBoxFlat).bg_color = fill_color

	var item_lines := PackedStringArray()
	for node in get_tree().get_nodes_in_group("items"):
		var item := node as WorldItem
		if item != null and item.consumable:
			var busy := ""
			if item.user_count() > 0:
				busy = " (in use)"
			item_lines.append("%s %.0f%%%s" % [item.display_name, item.fill * 100.0, busy])
	_items.text = "   ".join(item_lines)

	var p := brain.personality
	_traits.text = "energy %.2f  social %.2f  bold %.2f  food %.2f\ntoy %.2f  stubborn %.2f  trainable %.2f" % [
			p.energy, p.sociability, p.boldness, p.food_drive,
			p.toy_drive, p.stubbornness, p.trainability]

	_friends.text = _relationship_text(brain.memory)
	_hands.text = _hands_text(dog)

	var lines := PackedStringArray()
	for i in range(brain.decision_log.size() - 1, -1, -1):
		lines.append(brain.decision_log[i])
		if lines.size() >= 8:
			break
	_log.text = "\n".join(lines)


## Hand state and hovered zone, the dog's true touch prefs (effective at its bond, raw
## in brackets when the bond lowers them) and its last touch reaction.
func _hands_text(d: Dog) -> String:
	var hand := get_tree().get_first_node_in_group("hand_tool") as HandTool
	var lines := PackedStringArray()
	if hand != null:
		var zone_text := "-"
		if hand.hovered_zone != null and is_instance_valid(hand.hovered_zone):
			zone_text = String(hand.hovered_zone.zone_id)
		lines.append("hand %s   zone %s" % [hand.state, zone_text])
	var brain := d.brain
	var prefs := PackedStringArray()
	for zone: StringName in DogTouchPrefs.ZONES:
		var raw := brain.touch_prefs.get_raw(zone)
		var eff := brain.touch_prefs.effective(zone, brain.memory.bond)
		if absf(eff - raw) > 0.005:
			prefs.append("%s %+.2f (%+.2f)" % [zone, eff, raw])
		else:
			prefs.append("%s %+.2f" % [zone, eff])
	lines.append("  ".join(prefs))
	var touch := brain.get_stimulus(&"touch")
	if touch.is_empty():
		lines.append("last: -")
	else:
		lines.append("last: %s %s x%d, %.1f min ago" % [touch["zone"], touch["reaction"],
				int(touch["strokes"]), brain.stimulus_age(&"touch")])
	return "\n".join(lines)


## Strongest feelings first (either way), up to four, named via the pack.
func _relationship_text(memory: DogMemory) -> String:
	if memory.relationships.is_empty():
		return "(hasn't met anyone)"
	var ids: Array = memory.relationships.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return absf(memory.get_affinity(str(a))) > absf(memory.get_affinity(str(b))))
	var pack := get_tree().get_first_node_in_group("pack") as Pack
	var parts := PackedStringArray()
	for other_id in ids.slice(0, 4):
		var who := str(other_id)
		if pack != null and pack.get_dog(who) != null:
			who = pack.get_dog(who).dog_name
		parts.append("%s %+.2f" % [who, memory.get_affinity(str(other_id))])
	return "   ".join(parts)


func _build() -> void:
	var theme := Theme.new()
	theme.default_font_size = 13

	_panel = PanelContainer.new()
	_panel.theme = theme
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(380, 0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", bg)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_panel.add_child(box)

	_clock = _label(box, "", 15)
	_header = _label(box, "", 13)
	_current = _label(box, "", 13)

	_section(box, "NEEDS")
	for need: StringName in NEED_ORDER:
		_need_rows[need] = _bar_row(box, String(need).capitalize())

	_section(box, "BEHAVIOR SCORES")
	_score_box = VBoxContainer.new()
	_score_box.add_theme_constant_override("separation", 3)
	box.add_child(_score_box)

	_section(box, "ITEMS")
	_items = _label(box, "", 12)

	_section(box, "PERSONALITY")
	_traits = _label(box, "", 12)

	_section(box, "RELATIONSHIPS")
	_friends = _label(box, "", 12)

	_section(box, "HANDS")
	_hands = _label(box, "", 12)

	_section(box, "DECISIONS (newest first)")
	_log = _label(box, "", 12)
	_log.modulate = Color(0.85, 0.88, 0.92)

	_help = Label.new()
	_help.theme = theme
	_help.text = HELP_TEXT
	_help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.position = Vector2(12, -46)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_help)


func _label(parent: Control, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _section(parent: Control, title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	parent.add_child(spacer)
	var l := _label(parent, title, 11)
	l.modulate = Color(0.6, 0.7, 0.85)


## Returns [name Label, ProgressBar, value Label, fill StyleBoxFlat].
func _bar_row(parent: Control, title: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = title
	name_label.custom_minimum_size = Vector2(96, 0)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(190, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.001
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.GRAY
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.08)
	track.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", track)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(48, 0)
	row.add_child(name_label)
	row.add_child(bar)
	row.add_child(value_label)
	parent.add_child(row)
	return [name_label, bar, value_label, fill]
