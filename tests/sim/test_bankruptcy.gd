extends TestCase
## Spec 004 (faillite), critères d'acceptation 1 à 4, plus la garde "règles vides".

const F := preload("res://tests/sim/fixtures.gd")
const GRACE := 10    # bankruptcy_grace_days (valeurs de test, pas celles de data/)
const WARNING := 7   # bankruptcy_warning_days


## Sans installation de départ : pas d'entretien ni de salaires, la trésorerie
## ne bouge que par le test lui-même.
func _data() -> GameData:
	var data := F.data()
	data.start = {"money": F.START_MONEY, "facilities": [], "site": F.SITE_ID}
	data.rules = {"bankruptcy_grace_days": GRACE, "bankruptcy_warning_days": WARNING}
	return data


## Joue `days` jours sans commande. Renvoie l'état final et la liste [numéro du jour, événement].
func _simulate(state: GameState, data: GameData, days: int) -> Dictionary:
	var events_at: Array = []
	for i in days:
		var result := Simulation.step(state, [], data)
		state = result.state
		for event in result.events:
			events_at.append([i + 1, event])
	return {"state": state, "events": events_at}


func _days_with(events_at: Array, type: String) -> Array:
	var days := []
	for pair in events_at:
		if pair[1]["type"] == type:
			days.append(pair[0])
	return days


func _first_event(events_at: Array, type: String) -> Dictionary:
	for pair in events_at:
		if pair[1]["type"] == type:
			return pair[1]
	return {}


func _reason(events: Array) -> String:
	for e in events:
		if e["type"] == "command_rejected":
			return e["reason"]
	return ""


# Critère 1 : négatif pendant 9 jours puis positif -> pas de faillite.
func test_nine_days_in_debt_then_positive_is_not_bankruptcy() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	state.money = -1
	var first := _simulate(state, data, GRACE - 1)
	state = first["state"]
	assert_eq(state.days_in_debt, GRACE - 1, "compteur après 9 jours négatifs")
	state.money = 1
	var second := _simulate(state, data, 1)
	state = second["state"]
	var all_events: Array = first["events"] + second["events"]
	assert_eq(_days_with(all_events, "game_over"), [], "aucun game_over")
	assert_true(not state.game_over, "game_over reste faux")
	assert_eq(state.days_in_debt, 0, "compteur remis à zéro")


# Critère 2 : négatif pendant 10 jours d'affilée -> game_over le 10e jour.
func test_ten_days_in_debt_is_game_over_on_tenth_day() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	state.money = -1
	var run := _simulate(state, data, GRACE)
	state = run["state"]
	assert_eq(_days_with(run["events"], "game_over"), [GRACE], "game_over émis le 10e jour")
	assert_eq(_first_event(run["events"], "game_over").get("reason"), "bankruptcy", "raison")
	assert_true(state.game_over, "state.game_over == true")
	assert_eq(state.days_in_debt, GRACE, "compteur == grâce")


# Critère 3 : bankruptcy_warning émis une seule fois, le 7e jour, avec les jours restants.
func test_warning_is_emitted_once_on_seventh_day() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	state.money = -1
	var run := _simulate(state, data, GRACE)
	assert_eq(_days_with(run["events"], "bankruptcy_warning"), [WARNING], "une seule fois, jour 7")
	assert_eq(_first_event(run["events"], "bankruptcy_warning").get("days_left"), GRACE - WARNING,
		"days_left")


# Critère 4 : après game_over, commandes rejetées et end_day ne fait rien.
func test_after_game_over_commands_are_rejected_and_day_is_frozen() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	state.money = -1
	state = _simulate(state, data, GRACE)["state"]
	var day := state.day

	var rejected := Simulation.apply_command(state, Command.hire(1), data)
	assert_eq(_reason(rejected), "game_over", "commande rejetée avec game_over")

	var step := Simulation.step(state, [Command.hire(1)], data)
	assert_eq(_reason(step.events), "game_over", "step rejette aussi la commande")
	assert_eq(step.state.day, day, "step ne fait pas avancer le jour")

	assert_eq(Simulation.end_day(state, data), [], "end_day renvoie []")
	assert_eq(state.day, day, "end_day n'avance pas le jour")


# Garde : règles absentes (fixtures existantes) -> la faillite ne s'applique pas.
func test_empty_rules_disable_bankruptcy() -> void:
	var data := _data()
	data.rules = {}
	var state := Simulation.new_game(data, 1)
	state.money = -1
	var run := _simulate(state, data, GRACE + 1)
	state = run["state"]
	assert_eq(_days_with(run["events"], "game_over"), [], "pas de game_over sans règles")
	assert_eq(_days_with(run["events"], "bankruptcy_warning"), [], "pas d'alerte sans règles")
	assert_true(not state.game_over, "game_over reste faux")
	assert_eq(state.days_in_debt, 0, "compteur inchangé")
