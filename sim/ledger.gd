extends Node
## The estate's resources. Autoloaded as Ledger.
##
## Accounts are StringNames with float balances: `coins`, `kibble` (stock in bowl fills,
## the unit WorldItem.fill uses: 1.0 is one full bowl), `treats` (pieces), later
## `reputation`. Every change goes through add/spend/pay with a reason, is tallied per
## game day (today, yesterday) and kept in a short history for the HUD. Brains never read
## the ledger: the owner runs the economy, the dogs live in the world.

signal changed(account: StringName, balance: float, delta: float, reason: StringName)
## Emitted after reset() and from_dict(), when every balance may have changed at once.
signal reloaded

const HISTORY_SIZE := 50
## Balances closer than this to the cost count as enough (float sums of fills).
const EPSILON := 0.000001

## account -> balance.
var accounts: Dictionary = {}
## account -> {reason -> net change} for the current game day, and the one before.
var today: Dictionary = {}
var yesterday: Dictionary = {}
## Newest last: {minute, account, delta, balance, reason}. Not saved.
var history: Array[Dictionary] = []


func _ready() -> void:
	SimClock.day_changed.connect(_on_day_changed)


func balance(account: StringName) -> float:
	return float(accounts.get(account, 0.0))


## Adds income (amount >= 0) to the account.
func add(account: StringName, amount: float, reason: StringName) -> void:
	if amount < 0.0:
		push_error("Ledger.add: negative amount %f for %s (use spend)" % [amount, account])
		return
	_apply(account, amount, reason)


## Takes amount (>= 0) from the account. Fails, changing nothing, if the balance is short.
func spend(account: StringName, amount: float, reason: StringName) -> bool:
	if amount < 0.0:
		push_error("Ledger.spend: negative amount %f for %s (use add)" % [amount, account])
		return false
	if balance(account) + EPSILON < amount:
		return false
	_apply(account, -amount, reason)
	return true


## Whether every account in costs (account -> amount) holds at least that much.
func can_afford(costs: Dictionary) -> bool:
	for account: StringName in costs:
		if balance(account) + EPSILON < float(costs[account]):
			return false
	return true


## Pays all of costs (account -> amount) or nothing.
func pay(costs: Dictionary, reason: StringName) -> bool:
	for account: StringName in costs:
		var amount := float(costs[account])
		if amount < 0.0:
			push_error("Ledger.pay: negative cost %f for %s" % [amount, account])
			return false
	if not can_afford(costs):
		return false
	for account: StringName in costs:
		_apply(account, -float(costs[account]), reason)
	return true


## Net change of the account by reason on `day` (&"today" or &"yesterday").
func tally(account: StringName, day: StringName = &"today") -> Dictionary:
	var days := today if day == &"today" else yesterday
	var by_reason: Dictionary = days.get(account, {})
	return by_reason.duplicate()


## Empties the ledger, then sets the given balances (account -> amount) without
## recording them as income.
func reset(start: Dictionary = {}) -> void:
	accounts.clear()
	today.clear()
	yesterday.clear()
	history.clear()
	for account: StringName in start:
		accounts[account] = float(start[account])
	reloaded.emit()


func to_dict() -> Dictionary:
	return {
		"accounts": _to_strings(accounts),
		"today": _days_to_strings(today),
		"yesterday": _days_to_strings(yesterday),
	}


func from_dict(data: Dictionary) -> void:
	accounts.clear()
	today.clear()
	yesterday.clear()
	history.clear()
	var saved_accounts: Dictionary = data.get("accounts", {})
	accounts = _to_names(saved_accounts)
	var saved_today: Dictionary = data.get("today", {})
	today = _days_to_names(saved_today)
	var saved_yesterday: Dictionary = data.get("yesterday", {})
	yesterday = _days_to_names(saved_yesterday)
	reloaded.emit()


func _apply(account: StringName, delta: float, reason: StringName) -> void:
	var new_balance := balance(account) + delta
	accounts[account] = new_balance
	var by_reason: Dictionary = today.get(account, {})
	by_reason[reason] = float(by_reason.get(reason, 0.0)) + delta
	today[account] = by_reason
	history.append({
		"minute": SimClock.total_minutes,
		"account": account,
		"delta": delta,
		"balance": new_balance,
		"reason": reason,
	})
	if history.size() > HISTORY_SIZE:
		history.pop_front()
	changed.emit(account, new_balance, delta, reason)


func _on_day_changed(_day: int) -> void:
	yesterday = today
	today = {}


static func _to_strings(values: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in values:
		out[String(key)] = float(values[key])
	return out


static func _to_names(values: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in values:
		out[StringName(str(key))] = float(values[key])
	return out


static func _days_to_strings(days: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for account in days:
		var by_reason: Dictionary = days[account]
		out[String(account)] = _to_strings(by_reason)
	return out


static func _days_to_names(days: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for account in days:
		var by_reason: Dictionary = days[account]
		out[StringName(str(account))] = _to_names(by_reason)
	return out
