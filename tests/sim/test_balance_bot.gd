extends TestCase
## Garde-fous du bot d'équilibrage (issue #54). Il joue sur data/ : les assertions sont
## structurelles (aucune valeur d'équilibrage), pour qu'un rééquilibrage ne casse rien.

const SHORT_GAME_DAYS := 90
const SEED_A := 1
const SEED_B := 2


func _cheapest(data: GameData, component_id: String) -> int:
	var best := -1
	for supplier_id in data.suppliers:
		var entry := data.catalog_entry(supplier_id, component_id)
		if not entry.is_empty() and (best < 0 or int(entry["unit_price"]) < best):
			best = int(entry["unit_price"])
	return best


## La réserve vaut 2 kits L1 achetés, recalculée ici depuis data/.
func test_reserve_is_two_bought_kits() -> void:
	var data := DataLoader.load_default()
	var kit := 0
	var inputs: Dictionary = data.recipes[BalanceBot.LAUNCHER_RECIPE]["inputs"]
	for component_id in inputs:
		kit += int(inputs[component_id]) * _cheapest(data, component_id)
	var bot := BalanceBot.new(BalanceBot.INTEGRATE_STAGED, data, SEED_A)
	assert_eq(bot.reserve, BalanceBot.RESERVE_KITS * kit)


## En régime normal, aucune commande rejetée, quelle que soit la stratégie.
func test_no_rejected_commands_on_a_short_game() -> void:
	var data := DataLoader.load_default()
	for strategy in [BalanceBot.BUY_ALL, BalanceBot.WORKSHOP, BalanceBot.INTEGRATE_STAGED,
			BalanceBot.INTEGRATE_GREEDY, BalanceBot.ENGINES_ONLY]:
		var bot := BalanceBot.new(strategy, data, SEED_A)
		bot.play(SHORT_GAME_DAYS)
		assert_eq(bot.rejections, {}, "stratégie %s" % strategy)


## Même seed, même stratégie : même partie (le bot n'introduit aucun hasard).
func test_bot_is_deterministic() -> void:
	var data := DataLoader.load_default()
	var first := BalanceBot.new(BalanceBot.INTEGRATE_STAGED, data, SEED_B)
	first.play(SHORT_GAME_DAYS)
	var second := BalanceBot.new(BalanceBot.INTEGRATE_STAGED, data, SEED_B)
	second.play(SHORT_GAME_DAYS)
	assert_eq(first.state.money, second.state.money)
	assert_eq(first.built_day, second.built_day)


## Sans réserve, greedy construit au plus tôt l'atelier suivant ; staged attend la réserve.
func test_staged_waits_for_the_reserve_greedy_does_not() -> void:
	var data := DataLoader.load_default()
	var greedy := BalanceBot.new(BalanceBot.INTEGRATE_GREEDY, data, SEED_A)
	var staged := BalanceBot.new(BalanceBot.INTEGRATE_STAGED, data, SEED_A)
	greedy.play(SHORT_GAME_DAYS)
	staged.play(SHORT_GAME_DAYS)
	assert_true(greedy.built_day.has("tank_shop"))
	if staged.built_day.has("tank_shop"):
		assert_true(int(staged.built_day["tank_shop"]) >= int(greedy.built_day["tank_shop"]))
	assert_true(not staged.built_day.has("engine_shop") or staged.built_day.has("machine_shop"),
		"l'atelier moteurs exige l'atelier d'usinage")
