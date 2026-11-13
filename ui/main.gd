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

@onready var _day_label: Label = %DayLabel
@onready var _money_label: Label = %MoneyLabel
@onready var _rep_bar: ProgressBar = %RepBar
@onready var _rep_label: Label = %RepLabel
@onready var _contracts_box: VBoxContainer = %ContractsBox
@onready var _tabs: TabContainer = %Tabs
@onready var _facilities_box: VBoxContainer = %FacilitiesBox
@onready var _build_box: VBoxContainer = %BuildBox
@onready var _bom_box: VBoxContainer = %BomBox
@onready var _supply_box: VBoxContainer = %CatalogBox
@onready var _launch_box: VBoxContainer = %LaunchBox
@onready var _banner: PanelContainer = %Banner
@onready var _banner_label: Label = %BannerLabel
@onready var _game_over: Control = %GameOver
@onready var _game_over_summary: Label = %Summary
@onready var _log: RichTextLabel = %LogText


func _ready() -> void:
	%EndDayButton.pressed.connect(func() -> void: session.end_day())
	%FastForwardButton.pressed.connect(_on_fast_forward)
	%NewGameButton.pressed.connect(_new_game)
	var titles := [tr("Installations"), tr("Construction"), tr("Nomenclature"),
		tr("Fournisseurs"), tr("Contrats"), tr("Lancement")]
	for i in titles.size():
		_tabs.set_tab_title(i, titles[i])
	_new_game()


func _new_game() -> void:
	randomize()
	session = GameSession.new(DataLoader.load_default(), randi())
	session.changed.connect(_on_session_changed)
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
	_rebuild(_contracts_box, _build_contracts)
	_rebuild(_facilities_box, _build_facilities)
	_rebuild(_build_box, _build_construction)
	_rebuild(_bom_box, _build_bom)
	_rebuild(_supply_box, _build_supply)
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
		_label(row, tr("%s : %s cr · %d j · entretien %s cr/j · %d restant(s)") % [
			option["name"], _fmt(option["cost"]), option["days"], _fmt(option["upkeep"]), option["remaining"]])
		_button(row, tr("Construire"), func() -> void: _send(Command.build(option["type"])),
			option["remaining"] <= 0)

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


func _build_compare(card: VBoxContainer, cmp: Dictionary) -> void:
	_label(card, _component_name(cmp["component_id"]))
	var buy: Dictionary = cmp["buy"]
	if buy.is_empty():
		_label(card, tr("  Acheter : aucun fournisseur"), &"DimLabel")
	else:
		_label(card, tr("  Acheter : %s cr/u · %d j (%s)") % [
			_fmt(buy["unit_price"]), buy["lead_time_days"], buy["supplier_name"]])
	var make: Dictionary = cmp["make"]
	var cost := tr("matière %s cr") % _fmt(make["material_cost"]) if make["material_cost"] >= 0 else tr("matière indisponible")
	var duration := tr("%d j") % make["days"] if make["days"] > 0 else tr("à l'arrêt")
	if not make["ready"]:
		duration = tr("installation non construite")
	_label(card, tr("  Fabriquer : %s · %s") % [cost, duration])


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

	var catalog_card := _card(box)
	_label(catalog_card, tr("FOURNISSEURS"), &"HeadingLabel")
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	catalog_card.add_child(grid)
	for title in [tr("Fournisseur"), tr("Composant"), tr("Prix (cr) · délai"), tr("Quantité"), ""]:
		_grid_label(grid, title, &"DimLabel", title == tr("Fournisseur"))
	for supplier_id in data.suppliers:
		var supplier: Dictionary = data.suppliers[supplier_id]
		for entry in supplier["catalog"]:
			var component_id: String = entry["component_id"]
			var name_label := _grid_label(grid, supplier["name"], &"", true)
			name_label.tooltip_text = tr("%d %% de retards") % roundi(supplier["delay_chance"] * 100)
			name_label.mouse_filter = Control.MOUSE_FILTER_STOP
			_grid_label(grid, _component_name(component_id))
			_grid_label(grid, tr("%s/u · %d j") % [_fmt(entry["unit_price"]), entry["lead_time_days"]])
			var spin := _quantity_spin(grid, 1)
			var button := Button.new()
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(button)
			_bind_order(button, spin, null, supplier_id, component_id)


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
		show_cost := true) -> void:
	var refresh := func(_v := 0.0) -> void:
		var quote := SimQueries.order_quote(session.state, session.data, supplier_id, component_id, int(spin.value))
		button.text = tr("Commander (%s)") % _fmt(quote["total_cost"]) if show_cost else tr("Commander")
		button.disabled = not quote["affordable"]
		var tips: PackedStringArray = []
		if not quote["affordable"]:
			tips.append(tr("Trésorerie insuffisante : %s cr requis, %s cr disponibles.") % [
				_fmt(quote["total_cost"]), _fmt(session.state.money)])
		if not quote["fits"]:
			tips.append(tr("Entrepôt trop plein : la livraison attendra au portail."))
		tips.insert(0, tr("Coût : %s cr · %d places libres dans l'entrepôt") % [
			_fmt(quote["total_cost"]), quote["free_storage"]])
		if quote["fits"]:
			button.remove_theme_color_override("font_color")
		else:
			button.add_theme_color_override("font_color", Color(COLOR_WARN))
		button.tooltip_text = "\n".join(tips)
		if room == null:
			return
		room.text = tr("%d places libres") % quote["free_storage"]
		room.theme_type_variation = &"DimLabel" if quote["fits"] else &"DangerLabel"
	spin.value_changed.connect(refresh)
	button.pressed.connect(func() -> void: _send(Command.order(supplier_id, component_id, int(spin.value))))
	refresh.call()


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
	if plan["error"] != "":
		_label(card, tr(REJECT_REASONS.get(plan["error"], plan["error"])), &"WarnLabel")
	var go := _button(card, tr("Planifier le tir"), func() -> void:
		_send(Command.schedule_launch(_sel_launcher, _sel_pad, _sel_contract, _sel_day))
		_sel_day = -1
		_sel_pad = -1
		_sel_contract = -1, plan["error"] != "")
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


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
			_log_line(tr("Commande refusée : %s") % tr(REJECT_REASONS.get(e["reason"], e["reason"])), COLOR_WARN)
		"delivery_delayed":
			_log_line(tr("Commande #%d retardée de %d j par %s") % [
				e["order_id"], e["delay_days"], data.suppliers[e["supplier_id"]]["name"]], COLOR_WARN)
		"delivery_received":
			_log_line(tr("Commande #%d livrée : %d × %s") % [
				e["order_id"], e["quantity"], _component_name(e["component_id"])], COLOR_OK)
		"warehouse_full":
			_log_line(tr("Entrepôt plein : commande #%d en attente au portail") % e["order_id"], COLOR_WARN)
		"daily_costs":
			var extra := ""
			var launch_costs := int(e.get("scrub_costs", 0)) + int(e.get("refurb_costs", 0))
			if launch_costs > 0:
				extra = tr(" · tirs -%s cr") % _fmt(launch_costs)
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
		"facility_build_started":
			_log_line(tr("Construction : %s (-%s cr), prête au jour %d") % [
				_facility_name(e["facility_id"]), _fmt(e["cost"]), e["ready_day"]], COLOR_ACCENT)
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
