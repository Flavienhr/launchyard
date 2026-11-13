extends TestCase
## Spec 005 acceptance criteria 1-3: GameSession.fast_forward() on fixture data.

const F := preload("res://tests/sim/fixtures.gd")


func _session() -> GameSession:
	return GameSession.new(F.data(), 1)


## Collects every event emitted by the session (what the journal would show).
func _record(session: GameSession) -> Array:
	var log: Array = []
	session.changed.connect(func(events: Array) -> void: log.append_array(events))
	return log


func test_nothing_pending_stops_after_the_cap() -> void:
	var session := _session()
	var log := _record(session)
	var days := session.fast_forward()
	assert_eq(days, GameSession.FAST_FORWARD_MAX_DAYS)
	assert_eq(session.state.day, GameSession.FAST_FORWARD_MAX_DAYS)
	assert_true(not log.is_empty())


func test_stops_on_the_delivery_day() -> void:
	var session := _session()
	var log := _record(session)
	session.submit(Command.order("acme", "steel", 1))
	log.clear()
	var days := session.fast_forward()
	assert_eq(days, F.LEAD_TIME)
	assert_true(F.types(log).has("delivery_received"))
	assert_eq(F.types(log).count("delivery_received"), 1)
	assert_eq(session.state.stock.get("steel", 0), 1)


func test_journal_has_the_upkeep_of_every_skipped_day() -> void:
	var session := _session()
	var log := _record(session)
	session.submit(Command.order("acme", "steel", 1))
	log.clear()
	var days := session.fast_forward()
	var costs := log.filter(func(e: Dictionary) -> bool: return e["type"] == "daily_costs")
	assert_eq(costs.size(), days)
	for e in costs:
		assert_eq(e["upkeep"], F.UPKEEP)


func test_stops_when_money_goes_negative() -> void:
	var session := _session()
	session.state.money = F.UPKEEP + 10  # positive today, negative after day 2
	var days := session.fast_forward()
	assert_eq(days, 2)
	assert_true(session.state.money < 0)
