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
			BalanceBot.INTEGRATE_GREEDY, BalanceBot.ENGINES_ONLY, BalanceBot.CONTRACT_ENGINES,
			BalanceBot.CONTRACT_FULL_KIT, BalanceBot.CONTRACT_OVERCOMMIT, BalanceBot.OPPORTUNIST]:
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


## contract_engines signe un contrat fixe et prioritaire sur le composant le plus cher du kit.
func test_contract_engines_signs_a_priority_fixed_contract() -> void:
	var data := DataLoader.load_default()
	var bot := BalanceBot.new(BalanceBot.CONTRACT_ENGINES, data, SEED_A)
	bot.play(SHORT_GAME_DAYS)
	assert_true(bot.contracts_signed >= 1)
	var contract: Dictionary = bot.state.supply_contracts[0]
	assert_eq(contract["component_id"], bot._engine_component())
	assert_eq(contract["pricing"], BalanceBot.FIXED)
	assert_true(bool(contract["priority"]))


## Les stratégies sans contrat n'en signent jamais ; le seuil d'opportunist est un paramètre du bot.
func test_only_contract_strategies_sign_contracts() -> void:
	var data := DataLoader.load_default()
	var bot := BalanceBot.new(BalanceBot.BUY_ALL, data, SEED_A)
	bot.play(SHORT_GAME_DAYS)
	assert_eq(bot.contracts_signed, 0)
	assert_eq(BalanceBot.OPPORTUNIST_INDEX, 950)


# --- Politiques de placement (spec 008, issue #81) ---

const RICH := 10000000


## Bot de la politique donnée sur la carte de départ, riche, avec l'usinage prêt (prérequis de l'atelier moteurs).
func _placement_bot(policy: String) -> BalanceBot:
	var data := DataLoader.load_default()
	var bot := BalanceBot.new(BalanceBot.INTEGRATE_STAGED, data, SEED_A, policy)
	bot.state.money = RICH
	return bot


func _spatial_of_last(bot: BalanceBot) -> Dictionary:
	return SimQueries.facility_spatial(bot.state, bot.data, int(bot.state.facilities[-1]["id"]))


## careful ne met jamais un atelier en zone tant qu'une position sûre et desservie existe.
func test_careful_never_places_in_zone_when_a_safe_served_spot_exists() -> void:
	var bot := _placement_bot(BalanceBot.POLICY_CAREFUL)
	for type in ["tank_shop", "machine_shop"]:
		var best := bot._best_placement(bot.state, type)
		assert_true(not best.is_empty() and best["key"][0] == 0 and best["key"][1] == 0,
			"%s : une position sûre et desservie existe sur la carte de départ" % type)
		var events := bot._place_and_build(type)
		assert_eq(events[0]["type"], "facility_build_started", type)
		var spatial := _spatial_of_last(bot)
		assert_eq(spatial["in_safety_zone_of"], [], "%s hors zone" % type)
		assert_true(spatial["served"], "%s desservi" % type)
	assert_eq(bot.lots_bought, 0, "aucune parcelle achetée tant qu'une position sûre existe")
	assert_eq(bot.rejections, {})


## Avec la carte de départ, l'atelier moteurs n'a pas de position sûre et desservie : careful achète lot_west.
func test_careful_buys_lot_west_for_the_engine_shop() -> void:
	var bot := _placement_bot(BalanceBot.POLICY_CAREFUL)
	bot._place_and_build("machine_shop")
	bot.state.facilities[-1]["status"] = "ready"  # prérequis de l'atelier moteurs
	assert_true(not bot.state.owned_lots.has("lot_west"))
	var best := bot._best_placement(bot.state, "engine_shop")
	assert_true(best.is_empty() or best["key"][0] == 1 or best["key"][1] == 1,
		"pas de position sûre et desservie sans parcelle supplémentaire")
	var events := bot._place_and_build("engine_shop")
	assert_eq(events[0]["type"], "facility_build_started")
	assert_true(bot.state.owned_lots.has("lot_west"), "lot_west achetée")
	assert_eq(bot.lots_bought, 1)
	var spatial := _spatial_of_last(bot)
	assert_eq(spatial["in_safety_zone_of"], [])
	assert_true(spatial["served"])


## careful n'achète pas si la réserve manque : il prend le meilleur placement disponible.
func test_careful_keeps_the_best_spot_when_the_reserve_is_missing() -> void:
	var bot := _placement_bot(BalanceBot.POLICY_CAREFUL)
	bot._place_and_build("machine_shop")
	bot.state.facilities[-1]["status"] = "ready"
	var cost := int(bot.data.facilities["engine_shop"]["build_cost"])
	bot.state.money = cost  # ni le prix de la parcelle ni la réserve
	var events := bot._place_and_build("engine_shop")
	assert_eq(bot.lots_bought, 0)
	assert_eq(events[0]["type"], "facility_build_started")


## naive : premier emplacement libre (y puis x, rotation 0 puis 1), sans acheter si un emplacement existe.
func test_naive_takes_the_first_free_spot() -> void:
	var bot := _placement_bot(BalanceBot.POLICY_NAIVE)
	var first: Dictionary = bot._scan(bot.state, "tank_shop", true)[0]
	bot._place_and_build("tank_shop")
	var placed: Dictionary = bot.placements[0]
	assert_eq([placed["x"], placed["y"], placed["rotation"]], [first["x"], first["y"], first["rotation"]])
	assert_eq(bot.lots_bought, 0)


## Même seed, même politique : mêmes positions et mêmes achats de parcelles.
func test_placement_is_deterministic() -> void:
	var data := DataLoader.load_default()
	for policy in [BalanceBot.POLICY_NAIVE, BalanceBot.POLICY_CAREFUL]:
		var first := BalanceBot.new(BalanceBot.INTEGRATE_STAGED, data, SEED_B, policy)
		first.play(SHORT_GAME_DAYS)
		var second := BalanceBot.new(BalanceBot.INTEGRATE_STAGED, data, SEED_B, policy)
		second.play(SHORT_GAME_DAYS)
		assert_true(not first.placements.is_empty(), policy)
		assert_eq(first.placements, second.placements, policy)
		assert_eq(first.state.owned_lots, second.state.owned_lots, policy)
		assert_eq(first.rejections, {}, policy)
