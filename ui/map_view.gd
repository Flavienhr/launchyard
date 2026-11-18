class_name MapView
extends VBoxContainer
## Map screen: canvas + status bar (hover, lot purchase, zoom) + build bar.
## Emits Commands through `command_requested`; holds no game rule.

signal command_requested(command: Command)

var session: GameSession
var _build_type := ""

@onready var _canvas: MapCanvas = %Canvas
@onready var _status: Label = %StatusLabel
@onready var _buy_button: Button = %BuyButton
@onready var _zoom_button: Button = %ZoomButton
@onready var _build_row: VBoxContainer = %BuildRow


func _ready() -> void:
	_canvas.placement_requested.connect(_on_placement)
	_canvas.lot_clicked.connect(func(_id: String) -> void: _update_status())
	_canvas.cancelled.connect(_cancel)
	_canvas.hover_text_changed.connect(_on_hover_text)
	_buy_button.pressed.connect(_on_buy)
	_buy_button.icon = load("res://assets/src/icon_lot.svg") if ResourceLoader.exists("res://assets/src/icon_lot.svg") else null
	_zoom_button.pressed.connect(func() -> void:
		_canvas.toggle_zoom()
		_update_status())


func bind(new_session: GameSession) -> void:
	session = new_session
	_canvas.session = new_session
	_build_type = ""
	_canvas.build_type = ""
	_canvas.selected_lot = ""
	refresh()


func refresh() -> void:
	if session == null:
		return
	_canvas.refresh()
	_rebuild_build_bar()
	_update_status()


func _cancel() -> void:
	_set_build_type("")
	_canvas.selected_lot = ""
	_canvas.refresh()
	_rebuild_build_bar()
	_update_status()


func _set_build_type(type: String) -> void:
	_build_type = type
	_canvas.set_build_type(type)


func _on_placement(type: String, x: int, y: int, rotation: int) -> void:
	command_requested.emit(Command.build(type, x, y, rotation))
	# The session emits `changed` synchronously: refresh() already ran. One build per selection.
	_cancel()


func _on_buy() -> void:
	var lot_id := _canvas.selected_lot
	if lot_id == "":
		return
	_canvas.selected_lot = ""
	command_requested.emit(Command.buy_lot(lot_id))
	_update_status()


func _on_hover_text(text: String) -> void:
	if text != "":
		_status.text = text
	else:
		_update_status()


func _update_status() -> void:
	var lot_id := _canvas.selected_lot
	_buy_button.visible = lot_id != ""
	_zoom_button.text = tr("ZOOM ×%d (Z)") % _canvas.zoom
	if lot_id != "":
		for lot in SimQueries.lot_list(session.state, session.data):
			if lot["id"] == lot_id:
				_buy_button.text = tr("Acheter la parcelle %s : %s cr") % [
					_canvas.lot_name(lot_id), MapCanvas._fmt(int(lot["price"]))]
		_status.text = tr("Échap : annuler")
	elif _build_type != "":
		_status.text = tr("Construction : %s · clic pour poser · R pivoter · Échap annuler") % \
			session.data.facilities[_build_type]["name"]
	else:
		_status.text = tr("Clic sur une parcelle à vendre pour l'acheter · molette ou flèches : défiler · Z : zoom")


func _rebuild_build_bar() -> void:
	for child in _build_row.get_children():
		_build_row.remove_child(child)
		child.queue_free()
	var still_available := false
	for option in SimQueries.build_options(session.state, session.data):
		var blocked := ""
		if option["remaining"] <= 0:
			blocked = tr("max atteint")
		elif not option["missing"].is_empty():
			var names: Array = option["requires"].filter(func(r): return not r["ready"]).map(func(r): return r["name"])
			blocked = tr("requiert %s") % ", ".join(names)
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 46)
		button.add_theme_font_size_override("font_size", 12)
		button.text = "%s\n%s" % [option["name"],
			blocked if blocked != "" else tr("%s cr · %d j") % [MapCanvas._fmt(option["cost"]), option["days"]]]
		button.tooltip_text = tr("%s : %s cr · %d j · entretien %s cr/j · %d restant(s)") % [
			option["name"], MapCanvas._fmt(option["cost"]), option["days"],
			MapCanvas._fmt(option["upkeep"]), option["remaining"]]
		if blocked != "":
			button.tooltip_text += "\n" + blocked
		button.disabled = blocked != ""
		var type: String = option["type"]
		button.button_pressed = type == _build_type and blocked == ""
		if button.button_pressed:
			still_available = true
		button.pressed.connect(func() -> void:
			_canvas.selected_lot = ""
			_set_build_type("" if _build_type == type else type)
			_rebuild_build_bar()
			_update_status())
		_build_row.add_child(button)
	if _build_type != "" and not still_available:
		_set_build_type("")
