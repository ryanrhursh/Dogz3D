extends TestSuite
## Milestone 4 Estate step 1: the resources ledger (accounts, add/spend/pay, day tallies,
## history, signal) and save v4 with its migration from v3.

const TEST_SAVE := "user://test_ledger_save.json"

var _events: Array = []


func before_each() -> void:
	await super.before_each()
	Ledger.reset()
	_events.clear()


func after_each() -> void:
	if Ledger.changed.is_connected(_on_changed):
		Ledger.changed.disconnect(_on_changed)
	Ledger.reset()
	SimClock.paused = false


func _on_changed(account: StringName, new_balance: float, delta: float, reason: StringName) -> void:
	_events.append([account, new_balance, delta, reason])


func test_starts_empty() -> void:
	check(Ledger.accounts.is_empty(), "a fresh ledger has no accounts")
	check(Ledger.balance(&"coins") == 0.0, "an unknown account reads 0")
	check(Ledger.can_afford({}), "nothing costs nothing")
	check(not Ledger.can_afford({&"coins": 1.0}), "can't afford a coin with none")


func test_add_and_spend() -> void:
	Ledger.changed.connect(_on_changed)
	Ledger.add(&"coins", 30.0, &"test_income")
	check(Ledger.balance(&"coins") == 30.0, "income adds")
	check(Ledger.spend(&"coins", 12.0, &"test_cost"), "spending what's there works")
	check(Ledger.balance(&"coins") == 18.0, "spending takes it off")
	check(not Ledger.spend(&"coins", 18.5, &"test_cost"), "spending more than there is fails")
	check(Ledger.balance(&"coins") == 18.0, "a failed spend changes nothing")
	check(Ledger.spend(&"coins", 18.0, &"test_cost"), "spending it all works")
	check(Ledger.balance(&"coins") == 0.0, "down to zero, never below")
	check(_events.size() == 3, "one signal per change, none for the failed spend (%d)" % _events.size())
	check(_events[0] == [&"coins", 30.0, 30.0, &"test_income"], "signal: account, balance, delta, reason")
	check(_events[1] == [&"coins", 18.0, -12.0, &"test_cost"], "a spend signals a negative delta")


func test_fill_sums_are_affordable() -> void:
	# Kibble stock is in bowl fills; ten handfuls of 0.1 must buy a full bowl.
	for i in 10:
		Ledger.add(&"kibble", 0.1, &"test_income")
	check(Ledger.can_afford({&"kibble": 1.0}), "0.1 x 10 counts as 1.0")
	check(Ledger.spend(&"kibble", 1.0, &"test_cost"), "and can be spent as 1.0")


func test_pay_all_or_nothing() -> void:
	Ledger.reset({&"coins": 50.0, &"kibble": 2.0})
	check(Ledger.balance(&"coins") == 50.0 and Ledger.balance(&"kibble") == 2.0,
			"reset sets starting balances")
	check(Ledger.tally(&"coins").is_empty(), "starting balances aren't income")
	check(not Ledger.pay({&"coins": 40.0, &"kibble": 3.0}, &"test_build"), "short of kibble: fails")
	check(Ledger.balance(&"coins") == 50.0 and Ledger.balance(&"kibble") == 2.0,
			"a failed payment takes nothing")
	check(Ledger.pay({&"coins": 40.0, &"kibble": 1.5}, &"test_build"), "affordable: pays")
	check(Ledger.balance(&"coins") == 10.0 and Ledger.balance(&"kibble") == 0.5, "both paid")
	check(Ledger.tally(&"coins") == {&"test_build": -40.0}, "tallied by reason")


func test_day_tallies_roll_over() -> void:
	SimClock.paused = true
	Ledger.add(&"coins", 5.0, &"visitor")
	Ledger.add(&"coins", 7.0, &"visitor")
	Ledger.spend(&"coins", 3.0, &"kibble")
	check(Ledger.tally(&"coins") == {&"visitor": 12.0, &"kibble": -3.0}, "today by reason")
	var to_midnight := SimClock.MINUTES_PER_DAY - SimClock.get_minute_of_day() + 1.0
	SimClock.advance(to_midnight)
	check(Ledger.tally(&"coins").is_empty(), "a new day starts an empty tally")
	check(Ledger.tally(&"coins", &"yesterday") == {&"visitor": 12.0, &"kibble": -3.0},
			"the old day is yesterday")
	check(Ledger.balance(&"coins") == 9.0, "balances carry over")


func test_history_is_capped() -> void:
	for i in Ledger.HISTORY_SIZE + 5:
		Ledger.add(&"treats", 1.0, &"test_income")
	check(Ledger.history.size() == Ledger.HISTORY_SIZE, "history keeps the last %d" % Ledger.HISTORY_SIZE)
	var last: Dictionary = Ledger.history[Ledger.history.size() - 1]
	check(float(last["balance"]) == float(Ledger.HISTORY_SIZE + 5), "newest last, with its balance")


func test_ledger_doesnt_touch_dogs() -> void:
	var state_before := dog.brain.rng.state
	Ledger.add(&"coins", 10.0, &"test_income")
	Ledger.spend(&"coins", 5.0, &"test_cost")
	check(dog.brain.rng.state == state_before, "the ledger never touches a dog's RNG")


func test_dict_roundtrip() -> void:
	Ledger.add(&"coins", 25.5, &"visitor")
	Ledger.add(&"kibble", 3.25, &"delivery")
	var data := Ledger.to_dict()
	var text := JSON.stringify(data, "\t", true, true)
	var parsed: Dictionary = JSON.parse_string(text)
	Ledger.reset()
	Ledger.from_dict(parsed)
	check(Ledger.balance(&"coins") == 25.5 and Ledger.balance(&"kibble") == 3.25,
			"balances survive JSON")
	check(Ledger.tally(&"kibble") == {&"delivery": 3.25}, "today's tally survives JSON")
	check(Ledger.spend(&"coins", 25.5, &"test_cost"), "loaded accounts work as before")


func test_migrate_v3_save() -> void:
	var v3 := {"version": 3, "dogs": [], "items": {}}
	var out := SaveManager.migrate(v3)
	check(SaveManager.SAVE_VERSION == 4, "the save format is v4")
	check(int(out["version"]) == 4, "v3 migrates to v4")
	var ledger: Dictionary = out.get("ledger", {})
	check(ledger.has("accounts") and (ledger["accounts"] as Dictionary).is_empty(),
			"an old estate gets an empty ledger")
	check(not v3.has("ledger"), "migrate doesn't modify its input")


func test_save_load_ledger() -> void:
	Ledger.add(&"coins", 42.0, &"visitor")
	check(SaveManager.save_game(TEST_SAVE), "saved")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	check(int(data["version"]) == 4, "written as v4")
	check(data.has("ledger"), "the save has a ledger section")
	Ledger.spend(&"coins", 40.0, &"test_cost")
	check(SaveManager.load_game(TEST_SAVE), "loaded")
	check(Ledger.balance(&"coins") == 42.0, "the balance is back to the saved one")

	# A v3 file on disk (no ledger) loads with an empty ledger.
	data["version"] = 3
	data.erase("ledger")
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	check(SaveManager.load_game(TEST_SAVE), "v3 save loaded")
	check(Ledger.accounts.is_empty(), "a v3 estate has no accounts yet")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
