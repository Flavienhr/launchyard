extends Control
## Main screen: displays the sim state and sends commands. No game rules here:
## every derived number comes from SimQueries / Simulation read-only queries.

const COLOR_DIM := "#7A8FA3"
const COLOR_OK := "#5BE49B"
const COLOR_WARN := "#FFB547"
const COLOR_DANGER := "#FF5C6C"
const COLOR_ACCENT := "#4FD1FF"

const REJECT_REASONS := {
	"insufficient_funds": "fonds insuffisants",
	"not_in_catalog": "hors catalogue",
	"invalid_quantity": "quantité invalide",
	"unknown_command": "commande inconnue",
	"not_buildable": "non constructible",
	"max_count_reached": "nombre maximum atteint",
	"missing_prerequisite": "installation prérequise manquante",
	"max_technicians": "maximum de techniciens atteint",
	"staff_assigned": "techniciens encore affectés",
	"unknown_facility": "installation inconnue",
	"facility_not_ready": "installation pas prête",
	"no_slots": "aucun poste de travail",
	"too_many_for_slots": "plus que de postes disponibles",
	"not_enough_staff": "pas assez de techniciens libres",
	"unknown_recipe": "recette inconnue",
	"wrong_facility": "recette incompatible avec l'installation",
	"queue_full": "file d'attente pleine",
	"job_started": "job déjà démarré",
	"unknown_job": "job inconnu",
	"not_an_offer": "ce n'est plus une offre",
	"too_many_contracts": "trop de contrats actifs",
	"orbit_unreachable": "orbite inaccessible depuis ce site",
	"payload_too_heavy": "charge trop lourde pour tout lanceur",
	"launcher_unavailable": "lanceur indisponible",
	"pad_unavailable": "pas de tir indisponible",
	"contract_unavailable": "contrat indisponible",
	"too_early": "trop tôt pour ce pas",
	"after_deadline": "après la date limite du contrat",
	"unknown_launch": "tir inconnu",
	"supplier_capacity": "capacité du fournisseur dépassée cette semaine",
	"contracts_not_offered": "ce fournisseur ne propose pas de contrat",
	"invalid_period": "période invalide",
	"invalid_duration": "nombre de livraisons invalide",
	"invalid_pricing": "mode de prix invalide",
	"duplicate_contract": "un contrat actif existe déjà pour ce produit",
	"too_many_supply_contracts": "trop de contrats d'approvisionnement actifs",
	"unknown_contract": "contrat inconnu",
	"already_skipped": "prochaine livraison déjà sautée",
	"notice_too_short": "préavis trop court pour sauter cette livraison",
}

const FAIL_REASONS := {
	"launch_failed": "échec du lanceur",
	"deadline_missed": "date limite manquée",
}

const BLOCK_REASONS := {
	"missing_inputs": "composants manquants",
	"hall_occupied": "hall occupé",
	"output_blocked": "entrepôt plein",
}

var session: GameSession

# Launch form selection (UI state only). -1 = not chosen yet, first valid option is used.
var _sel_launcher := -1
var _sel_pad := -1
var _sel_contract := -1
var _sel_day := -1
var _sel_insured := false

# Supply contract form (UI state only; the quote comes from SimQueries).
var _sf_entry := 0
var _sf_quantity := -1
var _sf_period_index := 0
var _sf_deliveries := -1
var _sf_indexed := false
var _sf_priority := false

const SCHEDULE_DAYS := 30

@onready var _day_label: Label = %DayLabel
@onready var _money_label: Label = %MoneyLabel
@onready var _rep_bar: ProgressBar = %RepBar
@onready var _rep_label: Label = %RepLabel
@onready var _contracts_box: VBoxContainer = %ContractsBox
@onready var _tabs: TabContainer = %Tabs
@onready var _map: MapView = %Carte
@onready var _facilities_box: VBoxContainer = %FacilitiesBox
@onready var _build_box: VBoxContainer = %BuildBox
@onready var _bom_box: VBoxContainer = %BomBox
@onready var _supply_box: VBoxContainer = %CatalogBox
@onready var _contract_supply_box: VBoxContainer = %SupplyBox
@onready var _launch_box: VBoxContainer = %LaunchBox
@onready var _banner: PanelContainer = %Banner
@onready var _banner_label: Label = %BannerLabel
@onready var _game_over: Control = %GameOver
@onready var _game_over_summary: Label = %Summary
@onready var _start_screen: Control = %StartScreen
@onready var _log: RichTextLabel = %LogText


func _ready() -> void:
	%EndDayButton.pressed.connect(func() -> void: session.end_day())
	%FastForwardButton.pressed.connect(_on_fast_forward)
	%NewGameButton.pressed.connect(_new_game)
	%SaveButton.pressed.connect(_on_save)
	%LoadButton.pressed.connect(_on_load)
	%ContinueButton.pressed.connect(_on_continue)
	%StartNewButton.pressed.connect(_new_game)
	_map.command_requested.connect(_send)
	var titles := [tr("Carte"), tr("Installations"), tr("Construction"), tr("Nomenclature"),
		tr("Fournisseurs"), tr("Appro."), tr("Contrats"), tr("Lancement")]
	for i in titles.size():
		_tabs.set_tab_title(i, titles[i])
	var autosave := SaveGame.read(SaveGame.AUTOSAVE_PATH)
	if autosave["ok"]:
		_new_game()  # a session must exist behind the start screen
		var saved: GameState = autosave["state"]
		%StartSummary.text = tr("Dernière partie : jour %d, trésorerie %s cr.") % [saved.day, _fmt(saved.money)]
		%ContinueButton.text = tr("CONTINUER (JOUR %d, %s CR)") % [saved.day, _fmt(saved.money)]
		_start_screen.visible = true
		return
	_new_game()
	if autosave["reason"] != "missing":
		_log_line(tr("Sauvegarde automatique ignorée (%s)") % _save_reason(autosave["reason"]), COLOR_WARN)


func _save_reason(reason: String) -> String:
	match reason:
		"missing": return tr("fichier absent")
		"version": return tr("version inconnue")
		"io": return tr("écriture impossible")
	return tr("fichier illisible")


func _attach(new_session: GameSession) -> void:
	session = new_session
	session.autosave_path = SaveGame.AUTOSAVE_PATH
	session.changed.connect(_on_session_changed)
	_map.bind(session)
	_sel_launcher = -1
	_sel_pad = -1
	_sel_contract = -1
	_sel_day = -1
	_log.clear()


func _on_save() -> void:
	var result := session.save_to(SaveGame.MANUAL_PATH)
	if result["ok"]:
		_log_line(tr("Partie sauvegardée (jour %d)") % session.state.day, COLOR_OK)
	else:
		_log_line(tr("Sauvegarde impossible (%s)") % _save_reason(result["reason"]), COLOR_DANGER)


func _on_load() -> void:
	_load_from(SaveGame.MANUAL_PATH)


func _on_continue() -> void:
	_load_from(SaveGame.AUTOSAVE_PATH)


func _load_from(path: String) -> void:
	var result := GameSession.load_from(path, session.data)
	if not result["ok"]:
		_start_screen.visible = false
		_log_line(tr("Chargement impossible : %s") % _save_reason(result["reason"]), COLOR_WARN)
		return
	_start_screen.visible = false
	_attach(result["session"])
	_log_line(tr("Partie chargée (jour %d)") % session.state.day, COLOR_DIM)
	_refresh()


func _new_game() -> void:
	_start_screen.visible = false
	randomize()
	_attach(GameSession.new(DataLoader.load_default(), randi()))
	_sel_launcher = -1
	_sel_pad = -1
	_sel_contract = -1
	_sel_day = -1
	_log.clear()
	_log_line(tr("Nouvelle partie (seed %d)") % session.state.game_seed, COLOR_DIM)
	_refresh()


func _on_fast_forward() -> void:
	var days := session.fast_forward()
	if days > 0:
		_log_line(tr("▸▸ Avance rapide : %d jour(s)") % days, COLOR_DIM)


func _on_session_changed(events: Array) -> void:
	for event in events:
		_log_event(event)
	_refresh()


func _refresh() -> void:
	var state := session.state
	_day_label.text = tr("JOUR %d") % state.day
	_money_label.text = "%s cr" % _fmt(state.money)
	_money_label.theme_type_variation = &"DangerLabel" if state.money < 0 else &"Label"
	_refresh_reputation()
	_map.refresh()
	_rebuild(_contracts_box, _build_contracts)
	_rebuild(_facilities_box, _build_facilities)
	_rebuild(_build_box, _build_construction)
	_rebuild(_bom_box, _build_bom)
	_rebuild(_supply_box, _build_supply)
	_rebuild(_contract_supply_box, _build_supply_contracts)
	_rebuild(_launch_box, _build_launch)
	_refresh_bankruptcy()


func _refresh_bankruptcy() -> void:
	var status := SimQueries.bankruptcy_status(session.state, session.data)
	_banner.visible = status["warning"] and not status["game_over"]
	_banner_label.text = tr("FAILLITE IMMINENTE : trésorerie négative depuis %d jours, fin de partie dans %d jour(s).") % [
		status["days_in_debt"], status["days_left"]]
	_game_over.visible = status["game_over"]
	_game_over_summary.text = tr("Faillite : trésorerie négative pendant %d jours consécutifs. Dernier jour : %d, argent : %s cr.") % [
		status["days_in_debt"], session.state.day, _fmt(session.state.money)]


func _refresh_reputation() -> void:
	var rep := SimQueries.reputation_info(session.state, session.data)
	_rep_bar.min_value = rep["min"]
	_rep_bar.max_value = rep["max"]
	_rep_bar.value = rep["value"]
	_rep_label.text = "%d / %d" % [rep["value"], rep["max"]]


func _rebuild(box: VBoxContainer, builder: Callable) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	builder.call(box)


# --- Widget helpers ---------------------------------------------------------

func _card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


func _label(parent: Control, text: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		label.theme_type_variation = variation
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, on_press: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


func _send(command: Command) -> void:
	session.submit(command)


func _component_name(component_id: String) -> String:
	return session.data.components[component_id]["name"]


## The "type" field of facility events is overwritten by the event type
## (sim bug), so the name is looked up through the facility id.
func _facility_name(facility_id: int) -> String:
	for facility in session.state.facilities:
		if facility["id"] == facility_id:
			return session.data.facilities[facility["type"]]["name"]
	return "#%d" % facility_id


func _facility_type_names(types: Array) -> Array:
	var names: Array = []
	for type in types:
		names.append(session.data.facilities[type]["name"] if session.data.facilities.has(type) else String(type))
	return names


func _recipe_name(recipe_id: String) -> String:
	var output: Dictionary = session.data.recipes[recipe_id]["output"]
	if output.has("component_id"):
		return tr("Fabriquer : %s") % _component_name(output["component_id"])
	return tr("Assembler : %s") % String(output["launcher_model"]).to_upper()


# --- Installations tab ------------------------------------------------------

func _build_facilities(box: VBoxContainer) -> void:
	var state := session.state
	var data := session.data
	# Staff summary on top: assigning needs free technicians (hired in Construction).
	var staff: Dictionary = SimQueries.staff_info(state, data)
	var summary := _row(box)
	_label(summary, tr("Techniciens : %d embauchés · %d affectés · %d libres") % [
		staff["hired"], staff["assigned"], staff["free"]],
		&"WarnLabel" if staff["free"] <= 0 else &"DimLabel")
	for facility in state.facilities:
		var info := SimQueries.facility_info(data, facility, state.day)
		var card := _card(box)
		var head := _row(card)
		_label(head, "#%d  %s" % [info["id"], info["name"]], &"HeadingLabel")
		if info["status"] == "building":
			_label(head, tr("EN CONSTRUCTION"), &"WarnLabel")
			_label(card, tr("Prête au jour %d (dans %d j)") % [info["ready_day"], info["days_until_ready"]], &"DimLabel")
			continue
		_label(head, tr("PRÊTE"), &"OkLabel")
		if int(data.facilities[info["type"]].get("storage_capacity", 0)) > 0:
			_label(card, tr("Entrepôt : %d / %d unités (toutes installations)") % [
				Simulation.storage_used(state, data), Simulation.storage_capacity(state, data)], &"DimLabel")
		if info["slots"] > 0:
			_build_staff_row(card, info)
			_build_jobs(card, info)
		if data.facilities[info["type"]].has("launcher_capacity"):
			_build_hall(card, facility)


func _build_staff_row(card: VBoxContainer, info: Dictionary) -> void:
	var row := _row(card)
	_label(row, tr("Techniciens : %d / %d postes") % [info["assigned"], info["slots"]])
	var staff: Dictionary = SimQueries.staff_info(session.state, session.data)
	var free: int = staff["free"]
	_button(row, "−", func() -> void: _send(Command.assign_staff(info["id"], info["assigned"] - 1)),
		info["assigned"] <= 0)
	var plus := _button(row, "+", func() -> void: _send(Command.assign_staff(info["id"], info["assigned"] + 1)),
		info["assigned"] >= info["slots"] or free <= 0)
	if info["assigned"] >= info["slots"]:
		plus.tooltip_text = tr("Tous les postes sont pourvus.")
	elif free <= 0:
		# Playtest feedback: a greyed "+" with no explanation was a dead end.
		plus.tooltip_text = tr("Aucun technicien libre : embauchez-en, ou retirez-en d'une autre installation.")
		var can_hire: bool = staff["hired"] < staff["max"] and session.state.money >= staff["hire_cost"]
		_button(row, tr("Embaucher 1 (%s cr)") % _fmt(staff["hire_cost"]),
			func() -> void: _send(Command.hire(1)), not can_hire)


func _build_jobs(card: VBoxContainer, info: Dictionary) -> void:
	if info["jobs"].is_empty():
		_label(card, tr("File vide"), &"DimLabel")
	for i in info["jobs"].size():
		var job: Dictionary = info["jobs"][i]
		var row := _row(card)
		var text := "%d. %s" % [i + 1, _recipe_name(job["recipe_id"])]
		_label(row, text)
		if job["started"]:
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(110, 16)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.value = job["percent"]
			bar.show_percentage = true
			row.add_child(bar)
			if job["blocked"] != "":
				_label(row, tr("bloqué : %s") % tr(BLOCK_REASONS.get(job["blocked"], job["blocked"])), &"WarnLabel")
			elif job["idle"]:
				_label(row, tr("à l'arrêt (aucun technicien)"), &"WarnLabel")
			else:
				_label(row, tr("%d j restants") % job["days_left"], &"DimLabel")
		else:
			var status := tr("en attente")
			if job["blocked"] != "":
				status = tr("bloqué : %s") % tr(BLOCK_REASONS.get(job["blocked"], job["blocked"]))
			_label(row, status, &"WarnLabel" if job["blocked"] != "" else &"DimLabel")
			_button(row, tr("Annuler"), func() -> void: _send(Command.cancel_job(job["id"])))
	var add_row := _row(card)
	for recipe_id in info["recipes"]:
		_button(add_row, "+ " + _recipe_name(recipe_id),
			func() -> void: _send(Command.queue_job(info["id"], recipe_id, 1)))
	for recipe_id in info["recipes"]:
		var scrap := SimQueries.scrap_info(session.state, session.data, recipe_id)
		if not scrap["has_scrap"]:
			continue
		var out: Dictionary = session.data.recipes[recipe_id]["output"]
		var text := tr("Rebut %s : %d %% → %d %%") % [
			_component_name(out["component_id"]) if out.has("component_id") else recipe_id, roundi(scrap["start"] * 100), roundi(scrap["current"] * 100)]
		if scrap["attempts_to_floor"] > 0:
			text += tr(" (plancher %d %%, atteint dans %d pièce(s))") % [
				roundi(scrap["floor"] * 100), scrap["attempts_to_floor"]]
		else:
			text += tr(" (plancher atteint)")
		var lost := int(scrap["scrapped"])
		if lost > 0:
			text += tr(" · %d raté(s)") % lost
		_label(card, text, &"WarnLabel" if lost > 0 else &"DimLabel")


func _build_hall(card: VBoxContainer, facility: Dictionary) -> void:
	var occupancy := SimQueries.hall_occupancy(session.state, session.data, facility)
	_label(card, tr("Hall : %d / %d lanceur(s)") % [occupancy["used"], occupancy["capacity"]], &"DimLabel")
	for launcher in SimQueries.launchers_in(session.state, facility["id"]):
		_label(card, "▮ %s #%d" % [String(launcher["model"]).to_upper(), launcher["id"]], &"OkLabel")


# --- Construction & staff tab -----------------------------------------------

func _build_construction(box: VBoxContainer) -> void:
	var card := _card(box)
	_label(card, tr("CONSTRUIRE"), &"HeadingLabel")
	for option in SimQueries.build_options(session.state, session.data):
		var row := _row(card)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		_label(info, tr("%s : %s cr · %d j · entretien %s cr/j · %d restant(s)") % [
			option["name"], _fmt(option["cost"]), option["days"], _fmt(option["upkeep"]), option["remaining"]])
		var blocked_by: Array = []
		for req in option["requires"]:
			var state_text := tr("prêt") if req["ready"] else tr("manquant")
			blocked_by.append("%s (%s)" % [req["name"], state_text])
		if not blocked_by.is_empty():
			_label(info, tr("Nécessite : %s") % ", ".join(blocked_by),
				&"WarnLabel" if not option["missing"].is_empty() else &"DimLabel")
		var button := _button(row, tr("Construire"), func() -> void: _send(Command.build(option["type"])),
			option["remaining"] <= 0 or not option["missing"].is_empty())
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if option["remaining"] <= 0:
			button.tooltip_text = tr("Nombre maximum atteint.")
		elif not option["missing"].is_empty():
			button.tooltip_text = tr("Construisez d'abord : %s") % ", ".join(_facility_type_names(option["missing"]))

	var staff := SimQueries.staff_info(session.state, session.data)
	var staff_card := _card(box)
	_label(staff_card, tr("PERSONNEL"), &"HeadingLabel")
	_label(staff_card, tr("Techniciens : %d embauchés (max %d) · %d affectés · %d libres") % [
		staff["hired"], staff["max"], staff["assigned"], staff["free"]])
	_label(staff_card, tr("Salaires : %s cr/j"
		) % _fmt(staff["daily_salaries"]), &"DimLabel")
	var row := _row(staff_card)
	_button(row, tr("Embaucher (%s cr)") % _fmt(staff["hire_cost"]), func() -> void: _send(Command.hire(1)))
	_button(row, tr("Licencier (%s cr)") % _fmt(staff["fire_cost"]), func() -> void: _send(Command.fire(1)),
		staff["free"] <= 0)


# --- Bill of materials tab --------------------------------------------------

func _build_bom(box: VBoxContainer) -> void:
	var data := session.data
	for model_id in data.launchers:
		var recipe_id: String = data.launchers[model_id]["recipe_id"]
		var card := _card(box)
		_label(card, tr("NOMENCLATURE %s") % String(model_id).to_upper(), &"HeadingLabel")
		var rows := SimQueries.bill_of_materials(session.state, data, recipe_id)
		_build_bom_grid(card, rows)
		_label(card, tr("Comparateur acheter / fabriquer"), &"HeadingLabel")
		var any := false
		for entry in rows:
			var cmp := SimQueries.buy_vs_make(session.state, data, entry["component_id"])
			if cmp["make"].is_empty():
				continue
			any = true
			_build_compare(card, cmp)
		if not any:
			_label(card, tr("(aucun composant fabricable)"), &"DimLabel")


func _build_bom_grid(card: VBoxContainer, rows: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	for title in [tr("Composant"), tr("Requis"), tr("Stock"), tr("Commande"), tr("Manque"), ""]:
		_grid_label(grid, title, &"DimLabel", title == tr("Composant"))
	for entry in rows:
		var missing: int = entry["missing"]
		var marker := "● " if missing > 0 else "○ "
		_grid_label(grid, marker + _component_name(entry["component_id"]),
			&"DangerLabel" if missing > 0 else &"OkLabel", true)
		_grid_label(grid, str(entry["required"]))
		_grid_label(grid, str(entry["in_stock"]))
		_grid_label(grid, str(entry["on_order"]))
		_grid_label(grid, str(missing) if missing > 0 else "–", &"DangerLabel" if missing > 0 else &"DimLabel")
		var offers := SimQueries.supplier_offers(session.data, entry["component_id"])
		if offers.is_empty():
			_grid_label(grid, "")
			continue
		var offer: Dictionary = offers[0]
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		grid.add_child(cell)
		if missing > 0:
			var quick := _button(cell, tr("Le manque (%d)") % missing,
				func() -> void: _send(Command.order(offer["supplier_id"], entry["component_id"], missing)))
			quick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			quick.tooltip_text = tr("Commander exactement ce qui manque")
		_order_controls(cell, offer["supplier_id"], entry["component_id"], maxi(1, missing))


func _grid_label(grid: Container, text: String, variation := &"", expand := false) -> Label:
	var label := Label.new()
	label.text = text
	if variation != &"":
		label.theme_type_variation = variation
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	return label


## Label clipped to a fixed minimum width (long names must not widen the grid);
## the full text stays in the tooltip.
func _clipped_label(grid: Container, text: String, width: int) -> Label:
	var label := _grid_label(grid, text, &"", true)
	label.clip_text = true
	label.custom_minimum_size.x = width
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	return label


func _build_compare(card: VBoxContainer, cmp: Dictionary) -> void:
	var make: Dictionary = cmp["make"]
	var buy: Dictionary = cmp["buy"]
	_label(card, _component_name(cmp["component_id"]))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	card.add_child(grid)
	_grid_label(grid, tr("  Acheter"), &"DimLabel")
	if buy.is_empty():
		_grid_label(grid, tr("non achetable"), &"DimLabel", true)
	else:
		_grid_label(grid, tr("%s cr/u · %d j (%s)") % [
			_fmt(buy["unit_price"]), buy["lead_time_days"], buy["supplier_name"]], &"", true)
	_grid_label(grid, tr("  Fabriquer"), &"DimLabel")
	var effective: int = make["effective_cost"]
	var cost := tr("coût effectif %s cr/u (matière %s cr)") % [_fmt(effective), _fmt(make["material_cost"])] \
		if effective >= 0 else tr("matière indisponible")
	var variation := &""
	if effective >= 0 and not buy.is_empty():
		variation = &"OkLabel" if effective < int(buy["unit_price"]) else &"WarnLabel"
	_grid_label(grid, cost, variation, true)
	_grid_label(grid, tr("  Durée"), &"DimLabel")
	_grid_label(grid, tr("%d j par pièce") % make["days"] if make["days"] > 0 else tr("à l'arrêt"), &"", true)
	var scrapped: Array = []
	for step in make["steps"]:
		if step["scrap_rate"] > 0.0:
			scrapped.append("%s %d %%" % [_recipe_name(step["recipe_id"]), roundi(step["scrap_rate"] * 100)])
	if not scrapped.is_empty():
		_grid_label(grid, tr("  Rebut"), &"DimLabel")
		_grid_label(grid, ", ".join(scrapped), &"DimLabel", true)
	for missing in make["missing_facilities"]:
		_grid_label(grid, tr("  Manque"), &"DimLabel")
		var text: String = missing["name"]
		if not missing["requires_missing"].is_empty():
			text += tr(" (nécessite : %s)") % ", ".join(missing["requires_missing"])
		_grid_label(grid, text, &"DangerLabel", true)


# --- Suppliers & stock tab --------------------------------------------------

func _build_supply(box: VBoxContainer) -> void:
	var state := session.state
	var data := session.data
	var stock_card := _card(box)
	_label(stock_card, tr("STOCK"), &"HeadingLabel")
	_label(stock_card, tr("Occupation : %d / %d · %d places libres") % [
		Simulation.storage_used(state, data), Simulation.storage_capacity(state, data),
		Simulation.storage_capacity(state, data) - Simulation.storage_used(state, data)], &"DimLabel")
	var lines: PackedStringArray = []
	for component_id in state.stock:
		if state.stock[component_id] > 0:
			lines.append("%s : %d" % [_component_name(component_id), state.stock[component_id]])
	_label(stock_card, "\n".join(lines) if lines else tr("(vide)"))

	var transit_card := _card(box)
	_label(transit_card, tr("EN TRANSIT"), &"HeadingLabel")
	var pending: PackedStringArray = []
	for order in state.pending_orders:
		pending.append(tr("#%d · %d × %s · arrivée jour %d") % [
			order["id"], order["quantity"], _component_name(order["component_id"]), order["arrival_day"]])
	_label(transit_card, "\n".join(pending) if pending else tr("(aucune)"))

	_build_market_card(box)

	var catalog_card := _card(box)
	_label(catalog_card, tr("FOURNISSEURS (prix au comptant)"), &"HeadingLabel")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	catalog_card.add_child(grid)
	for title in [tr("Fournisseur"), tr("Composant"), tr("Prix · délai"), tr("Capacité"), tr("Quantité"), ""]:
		_grid_label(grid, title, &"DimLabel", title == tr("Fournisseur"))
	for supplier_id in data.suppliers:
		var supplier: Dictionary = data.suppliers[supplier_id]
		for entry in supplier["catalog"]:
			var component_id: String = entry["component_id"]
			var name_label := _clipped_label(grid, supplier["name"], 100)
			name_label.tooltip_text = tr("%s · %d %% de retards") % [supplier["name"], roundi(supplier["delay_chance"] * 100)]
			_clipped_label(grid, _component_name(component_id), 140)
			var spot := SimQueries.spot_price(state, data, supplier_id, component_id)
			var lead := SimQueries.spot_lead_days(state, data, supplier_id, component_id)
			var price_label := _grid_label(grid, tr("%s/u · %d j") % [_fmt(spot), lead],
				&"WarnLabel" if spot > int(entry["unit_price"]) else &"")
			price_label.tooltip_text = tr("Prix catalogue : %s cr/u · délai de base %d j") % [
				_fmt(entry["unit_price"]), entry["lead_time_days"]]
			price_label.mouse_filter = Control.MOUSE_FILTER_STOP
			var cap_label := _grid_label(grid, "", &"DimLabel")
			var spin := _quantity_spin(grid, 1)
			var button := Button.new()
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(button)
			_bind_order(button, spin, null, supplier_id, component_id, true, cap_label)


## One row per market component: index, change since the previous period, shortage.
func _build_market_card(box: VBoxContainer) -> void:
	var card := _card(box)
	_label(card, tr("MARCHÉ"), &"HeadingLabel")
	var snapshot := SimQueries.market_snapshot(session.state, session.data)
	if snapshot.is_empty():
		_label(card, tr("(marché inactif)"), &"DimLabel")
		return
	var next_day := SimQueries.market_next_update_day(session.state, session.data)
	_label(card, tr("Prochaine mise à jour au jour %d") % next_day, &"DimLabel")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	card.add_child(grid)
	for title in [tr("Composant"), tr("Indice"), tr("Variation"), tr("Pénurie")]:
		_grid_label(grid, title, &"DimLabel", title == tr("Composant"))
	var ids: Array = snapshot.keys()
	ids.sort()
	for id in ids:
		var row: Dictionary = snapshot[id]
		_clipped_label(grid, _component_name(id), 150)
		_grid_label(grid, "%.1f %%" % (row["index"] / 10.0))
		var change: int = row["change"]
		if change > 0:
			_grid_label(grid, "▲ +%.1f %%" % (change / 10.0), &"WarnLabel")
		elif change < 0:
			_grid_label(grid, "▼ %.1f %%" % (change / 10.0), &"OkLabel")
		else:
			_grid_label(grid, "= 0.0 %", &"DimLabel")
		if row["shortage"]:
			_grid_label(grid, tr("PÉNURIE → jour %d") % row["ends_day"], &"DangerLabel")
		else:
			_grid_label(grid, "—", &"DimLabel")


## SpinBox (min 1, step 1) with a fixed width so grid columns stay aligned.
func _quantity_spin(parent: Control, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 99
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size = Vector2(80, 0)
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(spin)
	return spin


## Free-quantity order (Nomenclature): SpinBox + "Commander"; the live cost
## and warehouse room are in the tooltip to keep the row compact.
func _order_controls(parent: Control, supplier_id: String, component_id: String, default_qty: int) -> void:
	var spin := _quantity_spin(parent, default_qty)
	var button := Button.new()
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(button)
	_bind_order(button, spin, null, supplier_id, component_id, false)


## Keeps the button label (total cost), its enabled state, tooltip and the
## warehouse-room label in sync with the spinner. All numbers come from SimQueries.
func _bind_order(button: Button, spin: SpinBox, room: Label, supplier_id: String, component_id: String,
		show_cost := true, cap_label: Label = null) -> void:
	var refresh := func(_v := 0.0) -> void:
		var quote := SimQueries.order_quote(session.state, session.data, supplier_id, component_id, int(spin.value))
		var capacity: int = quote["spot_capacity_remaining"]
		var over: bool = not quote["within_capacity"]
		button.text = tr("Commander (%s)") % _fmt(quote["total_cost"]) if show_cost else tr("Commander")
		if over:
			button.text = tr("Capacité dépassée")
		button.disabled = not quote["affordable"] or over
		var tips: PackedStringArray = []
		if over:
			tips.append(tr("Capacité du fournisseur dépassée : %d unité(s) restantes cette semaine, la capacité se renouvelle à la prochaine mise à jour du marché.") % capacity)
		if not quote["affordable"]:
			tips.append(tr("Trésorerie insuffisante : %s cr requis, %s cr disponibles.") % [
				_fmt(quote["total_cost"]), _fmt(session.state.money)])
		if not quote["fits"]:
			tips.append(tr("Entrepôt trop plein : la livraison attendra au portail."))
		tips.insert(0, tr("Coût : %s cr (%s cr/u au comptant) · %d places libres dans l'entrepôt") % [
			_fmt(quote["total_cost"]), _fmt(quote["unit_price"]), quote["free_storage"]])
		if quote["fits"] and not over:
			button.remove_theme_color_override("font_color")
		else:
			button.add_theme_color_override("font_color", Color(COLOR_WARN))
		button.tooltip_text = "\n".join(tips)
		if cap_label != null:
			cap_label.text = tr("illimitée") if capacity < 0 else tr("%d restantes") % capacity
			cap_label.theme_type_variation = &"DangerLabel" if over else &"DimLabel"
		if room == null:
			return
		room.text = tr("%d places libres") % quote["free_storage"]
		room.theme_type_variation = &"DimLabel" if quote["fits"] else &"DangerLabel"
	spin.value_changed.connect(refresh)
	button.pressed.connect(func() -> void: _send(Command.order(supplier_id, component_id, int(spin.value))))
	refresh.call()


# --- Supply contracts tab ---------------------------------------------------

func _build_supply_contracts(box: VBoxContainer) -> void:
	_build_contract_form(box)
	_build_supply_contract_list(box)
	_build_schedule_card(box)


## Catalog entries that accept supply contracts: [{supplier_id, component_id, label, terms}].
func _contract_entries() -> Array:
	var out: Array = []
	for supplier_id in session.data.suppliers:
		var supplier: Dictionary = session.data.suppliers[supplier_id]
		for entry in supplier["catalog"]:
			if entry.get("contract_terms", {}).is_empty():
				continue
			out.append({"supplier_id": supplier_id, "component_id": entry["component_id"],
				"label": "%s · %s" % [supplier["name"], _component_name(entry["component_id"])],
				"terms": entry["contract_terms"]})
	return out


func _form_row(card: VBoxContainer, title: String, control: Control) -> void:
	var row := _row(card)
	var title_label := _label(row, title, &"DimLabel")
	title_label.custom_minimum_size.x = 210
	title_label.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(control)


func _option_menu(items: Array, selected: int) -> OptionButton:
	var menu := OptionButton.new()
	menu.fit_to_longest_item = false
	menu.clip_text = true
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		menu.add_item(item)
	if not items.is_empty():
		menu.select(clampi(selected, 0, items.size() - 1))
	return menu


func _form_spin(min_value: int, max_value: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size = Vector2(90, 0)
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return spin


## "Nouveau contrat" form with a live quote. The widgets are updated in place
## (no rebuild), so the keyboard focus stays in the spin boxes.
func _build_contract_form(box: VBoxContainer) -> void:
	var data := session.data
	var card := _card(box)
	_label(card, tr("NOUVEAU CONTRAT D'APPROVISIONNEMENT"), &"HeadingLabel")
	var entries := _contract_entries()
	if entries.is_empty():
		_label(card, tr("(aucun fournisseur ne propose de contrat)"), &"DimLabel")
		return
	_sf_entry = clampi(_sf_entry, 0, entries.size() - 1)
	var params: Dictionary = data.supply_contracts
	var periods: Array = params["period_options_days"]
	_sf_period_index = clampi(_sf_period_index, 0, periods.size() - 1)
	_sf_deliveries = clampi(_sf_deliveries if _sf_deliveries > 0 else int(params["min_deliveries"]),
		int(params["min_deliveries"]), int(params["max_deliveries"]))

	var labels: Array = []
	for e in entries:
		labels.append(e["label"])
	var supplier_menu := _option_menu(labels, _sf_entry)
	_form_row(card, tr("Fournisseur · composant"), supplier_menu)
	var qty := _form_spin(1, 99, 1)
	_form_row(card, tr("Quantité par livraison"), qty)
	var period_names: Array = []
	for p in periods:
		period_names.append(tr("%d jours") % p)
	var period_menu := _option_menu(period_names, _sf_period_index)
	_form_row(card, tr("Période"), period_menu)
	var deliveries := _form_spin(int(params["min_deliveries"]), int(params["max_deliveries"]), _sf_deliveries)
	_form_row(card, tr("Nombre de livraisons"), deliveries)
	var pricing_menu := _option_menu([tr("Prix fixe (prime de fixation)"), tr("Prix indexé sur le marché")],
		1 if _sf_indexed else 0)
	_form_row(card, tr("Prix"), pricing_menu)
	var priority := CheckBox.new()
	priority.text = tr("Priorité en pénurie (prime)")
	priority.button_pressed = _sf_priority
	_form_row(card, tr("Priorité"), priority)

	var quote_grid := GridContainer.new()
	quote_grid.columns = 2
	quote_grid.add_theme_constant_override("h_separation", 16)
	quote_grid.add_theme_constant_override("v_separation", 4)
	card.add_child(quote_grid)
	var quote_titles := {"discount": tr("Remise de volume"), "unit_price": tr("Prix unitaire"),
		"invoice": tr("Facture par livraison"), "total": tr("Engagement total"),
		"fee": tr("Frais de résiliation (si résilié maintenant)"),
		"storage": tr("Place en entrepôt par livraison")}
	var quote_values: Dictionary = {}
	for key in quote_titles:
		_grid_label(quote_grid, quote_titles[key], &"DimLabel", true)
		quote_values[key] = _grid_label(quote_grid, "")
	var reason_label := _label(card, "", &"WarnLabel")
	var sign_row := _row(card)
	var sign_button := _button(sign_row, tr("Signer le contrat"), func() -> void: pass)
	sign_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var current_args := func() -> Dictionary:
		var entry: Dictionary = entries[_sf_entry]
		return {"supplier_id": entry["supplier_id"], "component_id": entry["component_id"],
			"quantity": int(qty.value), "period_days": int(periods[_sf_period_index]),
			"deliveries": int(deliveries.value), "pricing": "indexed" if _sf_indexed else "fixed",
			"priority": _sf_priority}
	var update := func() -> void:
		var args: Dictionary = current_args.call()
		var quote := SimQueries.supply_contract_quote(session.state, data, args)
		var unit_text := tr("%s cr/u") % _fmt(quote["unit_price"])
		if _sf_indexed:
			unit_text = tr("%s cr/u aujourd'hui (indexé)") % _fmt(quote["unit_price"])
		quote_values["discount"].text = "%d %%" % quote["discount_pct"]
		quote_values["unit_price"].text = unit_text
		quote_values["invoice"].text = tr("%s cr") % _fmt(quote["invoice"])
		quote_values["total"].text = tr("%s cr") % _fmt(quote["total_commitment"])
		quote_values["fee"].text = tr("%s cr") % _fmt(quote["termination_fee"])
		var free: int = SimQueries.order_quote(session.state, data, args["supplier_id"],
			args["component_id"], 1)["free_storage"]
		quote_values["storage"].text = tr("%d (libre : %d)") % [quote["storage_units"], free]
		quote_values["storage"].theme_type_variation = &"WarnLabel" if quote["storage_units"] > free else &"Label"
		sign_button.disabled = not quote["ok"]
		reason_label.visible = not quote["ok"]
		reason_label.text = tr(REJECT_REASONS.get(quote["reason"], quote["reason"]))
	var apply_entry := func() -> void:
		var terms: Dictionary = entries[_sf_entry]["terms"]
		qty.min_value = int(terms["min_quantity"])
		qty.max_value = int(terms["max_quantity"])
		if _sf_quantity < 0:
			_sf_quantity = int(terms["min_quantity"])
		qty.value = clampi(_sf_quantity, int(terms["min_quantity"]), int(terms["max_quantity"]))
	apply_entry.call()
	supplier_menu.item_selected.connect(func(i: int) -> void:
		_sf_entry = i
		apply_entry.call()
		update.call())
	qty.value_changed.connect(func(v: float) -> void:
		_sf_quantity = int(v)
		update.call())
	period_menu.item_selected.connect(func(i: int) -> void:
		_sf_period_index = i
		update.call())
	deliveries.value_changed.connect(func(v: float) -> void:
		_sf_deliveries = int(v)
		update.call())
	pricing_menu.item_selected.connect(func(i: int) -> void:
		_sf_indexed = i == 1
		update.call())
	priority.toggled.connect(func(on: bool) -> void:
		_sf_priority = on
		update.call())
	sign_button.pressed.connect(func() -> void:
		var a: Dictionary = current_args.call()
		_send(Command.sign_supply_contract(a["supplier_id"], a["component_id"], a["quantity"],
			a["period_days"], a["deliveries"], a["pricing"], a["priority"])))
	update.call()


func _build_supply_contract_list(box: VBoxContainer) -> void:
	var data := session.data
	var card := _card(box)
	_label(card, tr("CONTRATS D'APPROVISIONNEMENT ACTIFS"), &"HeadingLabel")
	var infos := SimQueries.supply_contract_infos(session.state, data)
	if infos.is_empty():
		_label(card, tr("(aucun contrat d'approvisionnement)"), &"DimLabel")
		return
	for info in infos:
		var supplier_name: String = data.suppliers[info["supplier_id"]]["name"]
		var price := tr("indexé · %s cr/u aujourd'hui") % _fmt(info["unit_price"]) \
			if info["pricing"] == "indexed" else tr("fixe · %s cr/u") % _fmt(info["unit_price"])
		var title := "#%d  %s · %d × %s" % [info["id"], supplier_name, info["quantity"],
			_component_name(info["component_id"])]
		if info["priority"]:
			title += tr("  ★ priorité")
		_label(card, title)
		_label(card, tr("Tous les %d j · prochaine livraison jour %d%s · %d livraison(s) restante(s) · %s") % [
			info["period_days"], info["next_delivery_day"],
			tr(" (sautée)") if info["skip_next"] else "", info["remaining"], price], &"DimLabel")
		var row := _row(card)
		var skip := _button(row, tr("Sauter la prochaine livraison (%s cr)") % _fmt(info["skip_cost"]),
			func() -> void: _send(Command.skip_supply_delivery(info["id"])), not info["can_skip"])
		skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		skip.tooltip_text = tr(REJECT_REASONS.get(info["skip_reason"], info["skip_reason"])) \
			if not info["can_skip"] else tr("Coût immédiat : %s cr (engagement ferme)") % _fmt(info["skip_cost"])
		var terminate := _button(row, tr("Résilier (%s cr)") % _fmt(info["termination_fee"]),
			func() -> void: _send(Command.terminate_supply_contract(info["id"])))
		terminate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		terminate.tooltip_text = tr("Frais de résiliation : %s cr") % _fmt(info["termination_fee"])
		if info["skip_reason"] != "":
			_label(card, tr("Saut impossible : %s") % tr(REJECT_REASONS.get(info["skip_reason"], info["skip_reason"])), &"WarnLabel")


func _build_schedule_card(box: VBoxContainer) -> void:
	var card := _card(box)
	_label(card, tr("ÉCHÉANCIER (%d prochains jours)") % SCHEDULE_DAYS, &"HeadingLabel")
	var rows := SimQueries.cash_projection(session.state, session.data, SCHEDULE_DAYS)
	_label(card, tr("Trésorerie projetée : coûts fixes connus (%s cr/j) et factures de contrats, hors recettes.") % _fmt(
		rows[0]["fixed_costs"]), &"DimLabel")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	card.add_child(grid)
	for title in [tr("Jour"), tr("Livraisons"), tr("Facture"), tr("Trésorerie")]:
		_grid_label(grid, title, &"DimLabel", title == tr("Livraisons"))
	for row in rows:
		_grid_label(grid, tr("J+%d · %d") % [row["day"] - session.state.day, row["day"]], &"DimLabel")
		var lines: PackedStringArray = []
		for e in row["entries"]:
			var what := "%d × %s" % [e["quantity"], _component_name(e["component_id"])]
			if e["kind"] == "transit":
				lines.append(tr("transit : %s") % what)
			else:
				lines.append(tr("contrat #%d : %s%s") % [e["contract_id"], what,
					tr(" (sautée)") if e["skipped"] else ""])
		var entries_label := _grid_label(grid, "\n".join(lines) if lines else "—",
			&"" if lines else &"DimLabel", true)
		entries_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entries_label.custom_minimum_size.x = 180
		_grid_label(grid, "-%s" % _fmt(row["invoices"]) if row["invoices"] > 0 else "", &"WarnLabel")
		_grid_label(grid, "%s cr" % _fmt(row["balance"]),
			&"DangerLabel" if row["balance"] < 0 else &"")


# --- Contracts tab ----------------------------------------------------------

func _build_contracts(box: VBoxContainer) -> void:
	var state := session.state
	var rep := SimQueries.reputation_info(state, session.data)
	var rep_card := _card(box)
	_label(rep_card, tr("RÉPUTATION : %d / %d") % [rep["value"], rep["max"]], &"HeadingLabel")
	if rep["next_unlock_at"] >= 0:
		_label(rep_card, tr("Prochain déblocage à %d : offres vers %s") % [
			rep["next_unlock_at"], String(rep["next_unlock_orbit"]).to_upper()], &"DimLabel")
	else:
		_label(rep_card, tr("Toutes les offres sont débloquées"), &"DimLabel")

	var offers_card := _card(box)
	_label(offers_card, tr("OFFRES"), &"HeadingLabel")
	var offers := SimQueries.contract_offers(state, session.data)
	if offers.is_empty():
		_label(offers_card, tr("(aucune offre)"), &"DimLabel")
	else:
		_build_offers_grid(offers_card, offers)

	var active_card := _card(box)
	_label(active_card, tr("CONTRATS ACTIFS"), &"HeadingLabel")
	var active := SimQueries.active_contracts(state, session.data)
	if active.is_empty():
		_label(active_card, tr("(aucun contrat actif)"), &"DimLabel")
	else:
		_build_active_grid(active_card, active)

	var history_card := _card(box)
	_label(history_card, tr("HISTORIQUE"), &"HeadingLabel")
	var history := SimQueries.contract_history(state)
	if history.is_empty():
		_label(history_card, tr("(vide)"), &"DimLabel")
	else:
		_build_history_grid(history_card, history)


func _build_offers_grid(card: VBoxContainer, offers: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	for title in [tr("Client"), tr("Orbite"), tr("Charge"), tr("Paiement"), tr("Avance"),
			tr("Pénalité"), tr("Limite"), tr("Expire"), ""]:
		_grid_label(grid, title, &"DimLabel", title == tr("Client"))
	for offer in offers:
		_grid_label(grid, "#%d  %s" % [offer["id"], offer["client"]], &"", true)
		_grid_label(grid, String(offer["orbit"]).to_upper(), &"AccentLabel")
		var mass := tr("%s kg") % _fmt(offer["payload_kg"])
		var mass_label := _grid_label(grid, ("▲ " if offer["near_capacity"] else "") + mass,
			&"WarnLabel" if offer["near_capacity"] else &"")
		if offer["near_capacity"]:
			mass_label.tooltip_text = tr("Proche de la capacité (%s kg)") % _fmt(offer["capacity_kg"])
			mass_label.mouse_filter = Control.MOUSE_FILTER_STOP
		_grid_label(grid, _fmt(offer["payment"]), &"OkLabel")
		_grid_label(grid, _fmt(offer["advance"]))
		_grid_label(grid, _fmt(offer["penalty"]), &"DimLabel")
		_grid_label(grid, tr("j%d (%d j)") % [offer["deadline_day"], offer["deadline_days_left"]])
		_grid_label(grid, tr("%d j") % offer["offer_days_left"],
			&"WarnLabel" if offer["offer_days_left"] <= 1 else &"DimLabel")
		var cell := _row(grid)
		var button := _button(cell, tr("Signer"), func() -> void: _send(Command.accept_contract(offer["id"])),
			not offer["can_accept"])
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not offer["can_accept"]:
			var why := tr(REJECT_REASONS.get(offer["reject_reason"], offer["reject_reason"]))
			button.tooltip_text = why
			var reason := _grid_label(cell, why, &"WarnLabel")
			reason.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _build_active_grid(card: VBoxContainer, active: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	for title in [tr("Contrat"), tr("Orbite"), tr("Charge"), tr("Paiement"), tr("Date limite"), tr("Tir")]:
		_grid_label(grid, title, &"DimLabel", title == tr("Contrat"))
	for c in active:
		var warn: bool = c["urgent"]
		_grid_label(grid, "#%d  %s" % [c["id"], c["client"]], &"", true)
		_grid_label(grid, String(c["orbit"]).to_upper(), &"AccentLabel")
		_grid_label(grid, tr("%s kg") % _fmt(c["payload_kg"]))
		_grid_label(grid, tr("%s cr") % _fmt(c["payment"]), &"OkLabel")
		var left: int = c["deadline_days_left"]
		_grid_label(grid, tr("jour %d (%d j)") % [c["deadline_day"], left],
			&"DangerLabel" if warn else &"")
		if c["launch_id"] >= 0:
			_grid_label(grid, tr("planifié jour %d") % c["launch_day"], &"OkLabel")
		else:
			_grid_label(grid, tr("▲ non planifié") if warn else tr("non planifié"),
				&"DangerLabel" if warn else &"DimLabel")


func _build_history_grid(card: VBoxContainer, history: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	card.add_child(grid)
	var labels := {"completed": tr("réussi"), "failed": tr("échoué"), "expired": tr("expirée")}
	var variations := {"completed": &"OkLabel", "failed": &"DangerLabel", "expired": &"DimLabel"}
	for c in history:
		_grid_label(grid, "#%d  %s" % [c["id"], c["client"]], &"", true)
		_grid_label(grid, String(c["orbit"]).to_upper(), &"AccentLabel")
		_grid_label(grid, tr("%s kg") % _fmt(c["payload_kg"]))
		_grid_label(grid, labels[c["status"]], variations[c["status"]])


# --- Launch tab ---------------------------------------------------------------

func _build_launch(box: VBoxContainer) -> void:
	_build_pads_card(box)
	_build_ready_card(box)
	_build_schedule_form(box)
	_build_scheduled_card(box)


func _build_pads_card(box: VBoxContainer) -> void:
	var card := _card(box)
	_label(card, tr("PAS DE TIR"), &"HeadingLabel")
	var pads := SimQueries.pad_infos(session.state, session.data)
	if pads.is_empty():
		_label(card, tr("(aucun pas de tir)"), &"DimLabel")
	for pad in pads:
		var row := _row(card)
		_label(row, "#%d  %s" % [pad["id"], pad["name"]])
		if pad["status"] == "building":
			_label(row, tr("EN CONSTRUCTION : prêt au jour %d") % pad["ready_day"], &"WarnLabel")
			continue
		match pad["pad_state"]:
			"free":
				_label(row, tr("LIBRE"), &"OkLabel")
			"occupied":
				var text := tr("OCCUPÉ : %s #%d") % [String(pad["launcher_model"]).to_upper(), pad["launcher_id"]]
				if pad["launch_id"] >= 0:
					text += tr(" · tir jour %d") % pad["launch_day"]
				else:
					text += tr(" · aucun tir planifié")
				_label(row, text, &"AccentLabel")
			"refurbishing":
				_label(row, tr("REMISE EN ÉTAT jusqu'au jour %d (dans %d j)") % [
					pad["refurb_until_day"], pad["refurb_until_day"] - session.state.day], &"WarnLabel")


func _build_ready_card(box: VBoxContainer) -> void:
	var card := _card(box)
	_label(card, tr("LANCEURS PRÊTS"), &"HeadingLabel")
	var ready := SimQueries.ready_launchers(session.state, session.data)
	if ready.is_empty():
		_label(card, tr("(aucun lanceur prêt : assemblez-en un dans le hall)"), &"DimLabel")
	for launcher in ready:
		var row := _row(card)
		_label(row, "▮ %s #%d" % [String(launcher["model"]).to_upper(), launcher["id"]], &"OkLabel")
		_label(row, tr("%s · fiabilité %d %%") % [launcher["location_name"], roundi(launcher["reliability"] * 100)], &"DimLabel")


func _build_schedule_form(box: VBoxContainer) -> void:
	var state := session.state
	var card := _card(box)
	_label(card, tr("PLANIFIER UN TIR"), &"HeadingLabel")
	var ready := SimQueries.ready_launchers(state, session.data)
	if ready.is_empty():
		_label(card, tr("(aucun lanceur prêt)"), &"DimLabel")
		return
	var launcher_ids: Array = ready.map(func(l: Dictionary) -> int: return l["id"])
	if _sel_launcher not in launcher_ids:
		_sel_launcher = launcher_ids[0]
		_sel_pad = -1
		_sel_contract = -1
		_sel_day = -1

	var launcher_row := _row(card)
	_label(launcher_row, tr("Lanceur"), &"DimLabel").custom_minimum_size.x = 110
	var launcher_menu := OptionButton.new()
	for launcher in ready:
		launcher_menu.add_item("%s #%d" % [String(launcher["model"]).to_upper(), launcher["id"]], launcher["id"])
	launcher_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launcher_menu.select(launcher_ids.find(_sel_launcher))
	launcher_menu.item_selected.connect(func(index: int) -> void:
		_sel_launcher = launcher_menu.get_item_id(index)
		_sel_pad = -1
		_sel_contract = -1
		_sel_day = -1
		_rebuild(_launch_box, _build_launch))
	launcher_row.add_child(launcher_menu)

	var pad_options := SimQueries.launch_pad_options(state, session.data, _sel_launcher)
	_sel_pad = _pick_option(pad_options, _sel_pad)
	_option_row(card, tr("Pas de tir"), pad_options, _sel_pad,
		func(o: Dictionary) -> String: return "#%d  %s" % [o["id"], o["name"]],
		func(id: int) -> void: _sel_pad = id)

	var contract_options := SimQueries.launch_contract_options(state, session.data, _sel_launcher)
	_sel_contract = _pick_option(contract_options, _sel_contract)
	_option_row(card, tr("Contrat"), contract_options, _sel_contract,
		func(o: Dictionary) -> String: return "#%d  %s · %s · %s kg" % [
			o["id"], o["client"], String(o["orbit"]).to_upper(), _fmt(o["payload_kg"])],
		func(id: int) -> void: _sel_contract = id)

	if _sel_pad < 0 or _sel_contract < 0:
		var why := tr("Aucun pas de tir utilisable.") if _sel_pad < 0 else tr("Aucun contrat actif compatible, sans tir.")
		_label(card, why, &"WarnLabel")
		return

	var min_day := SimQueries.min_launch_day(state, session.data, _sel_launcher, _sel_pad)
	if _sel_day < min_day:
		_sel_day = min_day
	var plan := SimQueries.launch_plan(state, session.data, _sel_launcher, _sel_pad, _sel_contract, _sel_day)
	var day_row := _row(card)
	_label(day_row, tr("Jour de tir"), &"DimLabel").custom_minimum_size.x = 110
	_button(day_row, "−", func() -> void: _shift_day(-1), _sel_day <= min_day)
	var day_label := _grid_label(day_row, tr("jour %d") % _sel_day)
	day_label.custom_minimum_size.x = 80
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(day_row, "+", func() -> void: _shift_day(1), plan["max_day"] >= 0 and _sel_day >= plan["max_day"])
	_label(day_row, tr("minimum : jour %d") % min_day, &"DimLabel")

	var risk_pct := roundi(plan["scrub_chance"] * 100)
	_label(card, tr("Saison : %s · risque de report météo ce jour-là : %d %%") % [plan["season_name"], risk_pct],
		&"WarnLabel" if risk_pct > 0 else &"OkLabel")
	_label(card, tr("Fiabilité actuelle du modèle : %d %%") % roundi(plan["reliability"] * 100))
	_label(card, tr("Marge avant la date limite : %d j (limite : jour %d)") % [plan["margin_days"], plan["max_day"]],
		&"DangerLabel" if plan["margin_days"] < 0 else &"DimLabel")
	_build_insurance_row(card, state)
	if plan["error"] != "":
		_label(card, tr(REJECT_REASONS.get(plan["error"], plan["error"])), &"WarnLabel")
	var go := _button(card, tr("Planifier le tir"), func() -> void:
		_send(Command.schedule_launch(_sel_launcher, _sel_pad, _sel_contract, _sel_day, _sel_insured))
		_sel_day = -1
		_sel_pad = -1
		_sel_contract = -1
		_sel_insured = false, plan["error"] != "")
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN



## Insurance (spec 003 decision 1): premium now, partial refund of a kit if the launch fails.
func _build_insurance_row(card: VBoxContainer, state: GameState) -> void:
	var contract := ContractRules.find(state, _sel_contract)
	var launcher := {}
	for l in state.launchers:
		if l["id"] == _sel_launcher:
			launcher = l
	if contract.is_empty() or launcher.is_empty() or not session.data.contracts.has("insurance_premium_pct"):
		return
	var premium := LaunchRules.insurance_premium(contract, session.data)
	var payout := LaunchRules.insurance_payout(session.data.launchers[launcher["model"]], session.data)
	var check := CheckBox.new()
	check.text = tr("Assurer ce tir : prime %s cr maintenant · %s cr remboursés si le tir échoue") % [
		_fmt(premium), _fmt(payout)]
	check.button_pressed = _sel_insured
	check.disabled = premium > state.money
	if check.disabled:
		check.tooltip_text = tr("Trésorerie insuffisante pour la prime.")
	check.toggled.connect(func(on: bool) -> void:
		_sel_insured = on
		_refresh())
	card.add_child(check)

## The current choice if it is an enabled option, else the first enabled option id. -1 if none.
func _pick_option(options: Array, current: int) -> int:
	for option in options:
		if option["id"] == current and option["ok"]:
			return current
	for option in options:
		if option["ok"]:
			return option["id"]
	return -1


func _option_row(card: VBoxContainer, title: String, options: Array, selected: int,
		describe: Callable, on_select: Callable) -> void:
	var row := _row(card)
	_label(row, title, &"DimLabel").custom_minimum_size.x = 110
	var menu := OptionButton.new()
	menu.fit_to_longest_item = false
	menu.clip_text = true
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in options.size():
		var option: Dictionary = options[i]
		var text: String = describe.call(option)
		if not option["ok"]:
			text += " (%s)" % tr(REJECT_REASONS.get(option["reason"], option["reason"]))
		menu.add_item(text, option["id"])
		menu.set_item_disabled(i, not option["ok"])
		if option["id"] == selected:
			menu.select(i)
	if options.is_empty():
		menu.add_item(tr("(aucun)"))
		menu.disabled = true
	menu.item_selected.connect(func(index: int) -> void:
		on_select.call(menu.get_item_id(index))
		_sel_day = -1
		_rebuild(_launch_box, _build_launch))
	row.add_child(menu)


func _shift_day(delta: int) -> void:
	_sel_day += delta
	_rebuild(_launch_box, _build_launch)


func _build_scheduled_card(box: VBoxContainer) -> void:
	var card := _card(box)
	_label(card, tr("TIRS PLANIFIÉS"), &"HeadingLabel")
	var launches := SimQueries.scheduled_launches(session.state, session.data)
	if launches.is_empty():
		_label(card, tr("(aucun tir planifié)"), &"DimLabel")
		return
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	for title in [tr("Lanceur"), tr("Contrat"), tr("Jour"), tr("Météo"), tr("Marge"), ""]:
		_grid_label(grid, title, &"DimLabel", title == tr("Contrat"))
	for launch in launches:
		_grid_label(grid, "%s #%d" % [String(launch["launcher_model"]).to_upper(), launch["launcher_id"]], &"OkLabel")
		_grid_label(grid, "#%d  %s" % [launch["contract_id"], launch["client"]], &"", true)
		_grid_label(grid, tr("jour %d") % launch["launch_day"])
		var risk_pct := roundi(launch["scrub_chance"] * 100)
		_grid_label(grid, "%s · %d %%" % [launch["season_name"], risk_pct], &"WarnLabel" if risk_pct > 0 else &"OkLabel")
		_grid_label(grid, tr("%d j") % launch["margin_days"], &"DangerLabel" if launch["margin_days"] < 0 else &"DimLabel")
		var cell := _row(grid)
		var earlier := _button(cell, "◂", func() -> void: _send(Command.reschedule_launch(launch["id"], launch["launch_day"] - 1)),
			launch["launch_day"] - 1 < session.state.day + 1)
		earlier.tooltip_text = tr("Avancer le tir d'un jour")
		var later := _button(cell, "▸", func() -> void: _send(Command.reschedule_launch(launch["id"], launch["launch_day"] + 1)),
			launch["launch_day"] + 1 > launch["deadline_day"])
		later.tooltip_text = tr("Reporter le tir d'un jour")
		_button(cell, tr("Annuler"), func() -> void: _send(Command.cancel_launch(launch["id"])))


# --- Journal ----------------------------------------------------------------

func _log_event(e: Dictionary) -> void:
	var data := session.data
	match e["type"]:
		"order_placed":
			_log_line(tr("Commande #%d passée : -%s cr, arrivée jour %d") % [
				e["order_id"], _fmt(e["cost"]), e["arrival_day"]], COLOR_ACCENT)
		"command_rejected":
			var why := tr(REJECT_REASONS.get(e["reason"], e["reason"]))
			if e["reason"] == "missing_prerequisite":
				why = tr("il faut d'abord construire : %s") % ", ".join(_facility_type_names(e.get("missing", [])))
			_log_line(tr("Commande refusée : %s") % why, COLOR_WARN)
		"delivery_delayed":
			_log_line(tr("Commande #%d retardée de %d j par %s") % [
				e["order_id"], e["delay_days"], data.suppliers[e["supplier_id"]]["name"]], COLOR_WARN)
		"delivery_received":
			var from_contract := tr(" (contrat #%d)") % e["contract_id"] if e.get("contract_id") != null else ""
			_log_line(tr("Commande #%d livrée : %d × %s%s") % [
				e["order_id"], e["quantity"], _component_name(e["component_id"]), from_contract], COLOR_OK)
		"market_updated":
			_log_line(tr("Marché mis à jour"), COLOR_DIM)
		"shortage_started":
			_log_line(tr("PÉNURIE : %s, jusqu'au jour %d") % [
				_component_name(e["component_id"]), e["ends_day"]], COLOR_DANGER)
		"shortage_ended":
			_log_line(tr("Fin de la pénurie : %s") % _component_name(e["component_id"]), COLOR_OK)
		"supply_contract_signed":
			var price := tr("prix indexé") if e["unit_price"] == null else tr("%s cr/u") % _fmt(e["unit_price"])
			_log_line(tr("Contrat d'appro #%d signé : %s chez %s (%s, remise %d %%)") % [
				e["contract_id"], _component_name(e["component_id"]),
				data.suppliers[e["supplier_id"]]["name"], price, e["discount_pct"]], COLOR_OK)
		"supply_delivery_dispatched":
			_log_line(tr("Contrat #%d : %d expédiés (commande #%d), facture -%s cr") % [
				e["contract_id"], e["quantity"], e["order_id"], _fmt(e["invoice"])], COLOR_ACCENT)
		"supply_delivery_reduced":
			_log_line(tr("Contrat #%d : livraison réduite par la pénurie, %d sur %d") % [
				e["contract_id"], e["quantity_shipped"], e["quantity_contracted"]], COLOR_WARN)
		"supply_delivery_skipped":
			_log_line(tr("Contrat #%d : livraison du jour %d sautée (-%s cr)") % [
				e["contract_id"], e["delivery_day"], _fmt(e["cost"])], COLOR_ACCENT)
		"supply_penalty_earned":
			_log_line(tr("Contrat #%d : pénalité de retard reçue +%s cr (%d j de retard)") % [
				e["contract_id"], _fmt(e["amount"]), e["days_late"]], COLOR_OK)
		"supply_contract_terminated":
			_log_line(tr("Contrat d'appro #%d résilié (-%s cr)") % [e["contract_id"], _fmt(e["fee"])], COLOR_DIM)
		"supply_contract_completed":
			_log_line(tr("Contrat d'appro #%d terminé") % e["contract_id"], COLOR_DIM)
		"warehouse_full":
			_log_line(tr("Entrepôt plein : commande #%d en attente au portail") % e["order_id"], COLOR_WARN)
		"daily_costs":
			var extra := ""
			var launch_costs := int(e.get("scrub_costs", 0)) + int(e.get("refurb_costs", 0))
			if launch_costs > 0:
				extra = tr(" · tirs -%s cr") % _fmt(launch_costs)
			if int(e.get("holding_fees", 0)) > 0:
				extra += tr(" · frais de garde -%s cr") % _fmt(e["holding_fees"])
			if int(e.get("supply_penalties", 0)) > 0:
				extra += tr(" · pénalités reçues +%s cr") % _fmt(e["supply_penalties"])
			_log_line(tr("── Fin du jour %d · entretien -%s cr · salaires -%s cr%s ──") % [
				e["day"], _fmt(e["upkeep"]), _fmt(e.get("salaries", 0)), extra], COLOR_DIM)
		"negative_balance":
			_log_line(tr("Trésorerie négative !"), COLOR_DANGER)
		"bankruptcy_warning":
			_log_line(tr("ALERTE FAILLITE : fin de partie dans %d jour(s) si la trésorerie reste négative") % e["days_left"], COLOR_DANGER)
		"game_over":
			_log_line(tr("FIN DE PARTIE : faillite"), COLOR_DANGER)
		"launch_scheduled":
			_log_line(tr("Tir #%d planifié au jour %d") % [e["launch_id"], e["launch_day"]], COLOR_ACCENT)
		"launch_rescheduled":
			_log_line(tr("Tir #%d reprogrammé au jour %d") % [e["launch_id"], e["launch_day"]], COLOR_ACCENT)
		"launch_cancelled":
			_log_line(tr("Tir #%d annulé (jour %d)") % [e["launch_id"], e["launch_day"]], COLOR_DIM)
		"pad_ready":
			_log_line(tr("Pas de tir #%d de nouveau disponible") % e["pad_id"], COLOR_OK)
		"launch_scrubbed":
			var season_names: Array = data.active_site()["season_names"]
			_log_line(tr("[REPORT] Tir #%d reporté au jour %d (météo : %s, report n°%d)") % [
				e["launch_id"], e["new_launch_day"], season_names[e["season"]], e["scrubs"]], COLOR_WARN)
		"launch_succeeded":
			_log_line(tr("[SUCCÈS] Tir #%d réussi ! Contrat #%d (fiabilité %d %%)") % [
				e["launch_id"], e["contract_id"], roundi(e["reliability"] * 100)], COLOR_OK)
		"launch_failed":
			_log_line(tr("[ÉCHEC] Tir #%d échoué : le lanceur est perdu. Contrat #%d (fiabilité %d %%)") % [
				e["launch_id"], e["contract_id"], roundi(e["reliability"] * 100)], COLOR_DANGER)
		"insurance_paid":
			_log_line(tr("Tir #%d assuré : prime -%s cr") % [e["launch_id"], _fmt(e["premium"])], COLOR_ACCENT)
		"insurance_payout":
			_log_line(tr("Assurance : +%s cr remboursés pour le tir #%d") % [_fmt(e["amount"]), e["launch_id"]], COLOR_OK)
		"facility_build_started":
			_log_line(tr("Construction : %s (-%s cr), prête au jour %d") % [
				_facility_name(e["facility_id"]), _fmt(e["cost"]), e["ready_day"]], COLOR_ACCENT)
		"lot_bought":
			_log_line(tr("Parcelle achetée : %s (-%s cr)") % [e["lot_id"], _fmt(e["cost"])], COLOR_ACCENT)
		"facility_built":
			_log_line(tr("Installation prête : %s") % _facility_name(e["facility_id"]), COLOR_OK)
		"staff_hired":
			_log_line(tr("Embauche : %d technicien(s), -%s cr") % [e["count"], _fmt(e["cost"])], COLOR_ACCENT)
		"staff_fired":
			_log_line(tr("Licenciement : %d technicien(s), -%s cr") % [e["count"], _fmt(e["cost"])], COLOR_ACCENT)
		"staff_assigned":
			_log_line(tr("Installation #%d : %d technicien(s) affecté(s)") % [e["facility_id"], e["count"]], COLOR_ACCENT)
		"job_queued":
			_log_line(tr("Job #%d en file : %s") % [e["job_id"], _recipe_name(e["recipe_id"])], COLOR_ACCENT)
		"job_cancelled":
			_log_line(tr("Job #%d annulé") % e["job_id"], COLOR_DIM)
		"job_started":
			_log_line(tr("Job #%d démarré (composants consommés)") % e["job_id"], COLOR_ACCENT)
		"job_blocked":
			var detail := ""
			if e["reason"] == "missing_inputs":
				var parts: PackedStringArray = []
				for component_id in e["missing"]:
					parts.append("%d × %s" % [e["missing"][component_id], _component_name(component_id)])
				detail = " (%s)" % ", ".join(parts)
			_log_line(tr("Job #%d bloqué : %s%s") % [
				e["job_id"], tr(BLOCK_REASONS.get(e["reason"], e["reason"])), detail], COLOR_WARN)
		"output_blocked":
			_log_line(tr("Job #%d : sortie bloquée, entrepôt plein") % e["job_id"], COLOR_WARN)
		"job_scrapped":
			_log_line(tr("Job #%d RATÉ : %s mis au rebut (taux %d %%), composants perdus") % [
				e["job_id"], _recipe_name(e["recipe_id"]), roundi(float(e["scrap_rate"]) * 100)], COLOR_DANGER)
		"job_completed":
			_log_line(tr("Job #%d terminé") % e["job_id"], COLOR_OK)
		"launcher_assembled":
			_log_line(tr("Lanceur %s #%d assemblé") % [String(e["model"]).to_upper(), e["launcher_id"]], COLOR_OK)
		"offer_generated":
			_log_line(tr("Nouvelle offre #%d : %s, %s kg, %s cr, limite jour %d") % [
				e["contract_id"], String(e["orbit"]).to_upper(), _fmt(e["payload_kg"]),
				_fmt(e["payment"]), e["deadline_day"]], COLOR_ACCENT)
		"offer_expired":
			_log_line(tr("Offre de contrat #%d expirée") % e["contract_id"], COLOR_DIM)
		"contract_accepted":
			_log_line(tr("Contrat #%d signé : avance +%s cr") % [e["contract_id"], _fmt(e["advance"])], COLOR_OK)
		"contract_completed":
			_log_line(tr("Contrat #%d réussi : solde +%s cr") % [e["contract_id"], _fmt(e["balance_paid"])], COLOR_OK)
		"contract_failed":
			_log_line(tr("Contrat #%d échoué (%s) : -%s cr") % [
				e["contract_id"], tr(FAIL_REASONS.get(e["reason"], e["reason"])), _fmt(e["amount_debited"])], COLOR_DANGER)
		"reputation_changed":
			_log_line(tr("Réputation %+d (%d)") % [e["delta"], e["reputation"]],
				COLOR_OK if e["delta"] >= 0 else COLOR_DANGER)
		_:
			_log_line(str(e), COLOR_DIM)


func _log_line(text: String, color: String) -> void:
	_log.append_text("[color=%s]%s[/color]\n" % [color, text])


## 1234567 -> "1 234 567"
static func _fmt(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += " "
		out += digits[i]
	return ("-" if value < 0 else "") + out
