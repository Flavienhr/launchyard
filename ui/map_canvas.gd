class_name MapCanvas
extends Control
## Top-down view of the site grid (spec 008, UI). Draws the sim state and the
## `placement_check` of the ghost; sends nothing itself except signals. The only
## computations here are presentation: pixels <-> grid cells.

signal placement_requested(facility_type: String, x: int, y: int, rotation: int)
signal lot_clicked(lot_id: String)
signal cancelled
signal facility_clicked(facility_id: int)
signal hover_text_changed(text: String)

const COLOR_BG := Color("#0B1119")
const COLOR_PANEL := Color("#101A26")
const COLOR_LINE := Color("#1E3A52")
const COLOR_TEXT := Color("#D6E2EE")
const COLOR_DIM := Color("#7A8FA3")
const COLOR_ACCENT := Color("#4FD1FF")
const COLOR_OK := Color("#5BE49B")
const COLOR_WARN := Color("#FFB547")
const COLOR_DANGER := Color("#FF5C6C")

const ASSET_DIR := "res://assets/src/"
const MIN_CELL := 8
const MAX_ZOOM := 2
const FONT_SIZE := 12
const PAN_STEP_CELLS := 3
const GHOST_ALPHA := 0.65
const FILL_ALPHA := 0.28

const REASONS := {
	"out_of_bounds": "hors des parcelles possédées",
	"overlap": "emplacement occupé",
}

var session: GameSession
var build_type := ""
var rotation_index := 0
var selected_lot := ""
var selected_facility := 0
## Instance being moved (0 = plain construction of `build_type`).
var move_id := 0
var zoom := 1:
	set(value):
		zoom = clampi(value, 1, MAX_ZOOM)
		queue_redraw()

var _pan := Vector2.ZERO
var _dragging := false
var _hover := Vector2i(-1, -1)
var _lots: Array = []
var _facilities: Array = []
var _check: Dictionary = {}
var _zones: Dictionary = {"safety": [], "service": []}
var _rollouts: Array = []
var _textures: Dictionary = {}


func _ready() -> void:
	clip_contents = true
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(queue_redraw)


## Re-reads the sim state (call after every `changed`).
func refresh() -> void:
	if session == null:
		return
	_lots = SimQueries.lot_list(session.state, session.data)
	_facilities = SimQueries.map_facilities(session.state, session.data)
	_zones = SimQueries.map_zones(session.state, session.data)
	if selected_facility != 0 and _facility_by_id(selected_facility).is_empty():
		selected_facility = 0
	if selected_lot != "" and _lot_by_id(selected_lot).get("owned", true):
		selected_lot = ""
	_update_check()
	queue_redraw()


func set_build_type(type: String) -> void:
	build_type = type
	_update_check()
	queue_redraw()


func rotate_ghost() -> void:
	rotation_index = 1 - rotation_index
	_update_check()
	queue_redraw()


func toggle_zoom() -> void:
	zoom = 1 if zoom >= MAX_ZOOM else zoom + 1


# --- Geometry (presentation only) ---------------------------------------------

func _map_size() -> Vector2i:
	var site_map := session.data.site_map()
	return Vector2i(int(site_map.get("width", 0)), int(site_map.get("height", 0)))


func _cell() -> int:
	var size_cells := _map_size()
	if size_cells.x <= 0 or size_cells.y <= 0:
		return MIN_CELL
	var fit := floori(minf(size.x / size_cells.x, size.y / size_cells.y))
	return maxi(MIN_CELL, fit) * zoom


func _origin() -> Vector2:
	var map_px := Vector2(_map_size()) * _cell()
	var origin := Vector2.ZERO
	for axis in 2:
		if map_px[axis] <= size[axis]:
			origin[axis] = (size[axis] - map_px[axis]) / 2.0
			_pan[axis] = 0.0
		else:
			_pan[axis] = clampf(_pan[axis], size[axis] - map_px[axis], 0.0)
			origin[axis] = _pan[axis]
	return origin


func _cell_rect(rect: Dictionary) -> Rect2:
	var cell := float(_cell())
	return Rect2(_origin() + Vector2(float(rect["x"]), float(rect["y"])) * cell,
		Vector2(float(rect["w"]), float(rect["h"])) * cell)


func _cell_at(pos: Vector2) -> Vector2i:
	var cell := float(_cell())
	var local := (pos - _origin()) / cell
	var cell_pos := Vector2i(floori(local.x), floori(local.y))
	var size_cells := _map_size()
	if cell_pos.x < 0 or cell_pos.y < 0 or cell_pos.x >= size_cells.x or cell_pos.y >= size_cells.y:
		return Vector2i(-1, -1)
	return cell_pos


func _contains(rect: Dictionary, cell_pos: Vector2i) -> bool:
	return cell_pos.x >= int(rect["x"]) and cell_pos.x < int(rect["x"]) + int(rect["w"]) \
		and cell_pos.y >= int(rect["y"]) and cell_pos.y < int(rect["y"]) + int(rect["h"])


func _lot_at(cell_pos: Vector2i) -> Dictionary:
	for lot in _lots:
		if _contains(lot, cell_pos):
			return lot
	return {}


func _lot_by_id(lot_id: String) -> Dictionary:
	for lot in _lots:
		if lot["id"] == lot_id:
			return lot
	return {}


func _facility_at(cell_pos: Vector2i) -> Dictionary:
	for facility in _facilities:
		if _contains(facility["rect"], cell_pos):
			return facility
	return {}


func _facility_by_id(facility_id: int) -> Dictionary:
	for facility in _facilities:
		if int(facility["id"]) == facility_id:
			return facility
	return {}


func _update_check() -> void:
	_check = {}
	_rollouts = []
	if session == null or build_type == "" or _hover.x < 0 or not session.data.has_map():
		return
	if move_id > 0:
		_check = SimQueries.move_check(session.state, session.data, move_id, _hover.x, _hover.y, rotation_index)
	else:
		_check = SimQueries.placement_check(session.state, session.data, build_type, _hover.x, _hover.y, rotation_index)
		if bool(_check["valid"]):
			_rollouts = SimQueries.placement_rollouts(session.state, session.data, build_type, _check["rect"])


# --- Input ---------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if session == null:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging:
			_pan += motion.relative
		var cell_pos := _cell_at(motion.position)
		if cell_pos != _hover or _dragging:
			_hover = cell_pos
			_update_check()
			_emit_hover_text()
			queue_redraw()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					var step := _cell() * PAN_STEP_CELLS * (1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
					_pan += Vector2(step, 0) if button.shift_pressed else Vector2(0, step)
					queue_redraw()
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_on_left_click(_cell_at(button.position))


func _on_left_click(cell_pos: Vector2i) -> void:
	if build_type != "":
		if not _check.is_empty() and bool(_check["valid"]):
			placement_requested.emit(build_type, cell_pos.x, cell_pos.y, rotation_index)
		return
	var facility := _facility_at(cell_pos)
	if not facility.is_empty():
		selected_lot = ""
		selected_facility = int(facility["id"])
		lot_clicked.emit("")
		facility_clicked.emit(selected_facility)
		queue_redraw()
		return
	if selected_facility != 0:
		selected_facility = 0
		facility_clicked.emit(0)
	var lot := _lot_at(cell_pos)
	if not lot.is_empty() and not bool(lot["owned"]):
		selected_lot = lot["id"]
		lot_clicked.emit(selected_lot)
	else:
		selected_lot = ""
		lot_clicked.emit("")
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if session == null or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_R:
			if build_type != "":
				rotate_ghost()
				accept_event()
		KEY_ESCAPE:
			if build_type != "" or selected_lot != "" or selected_facility != 0:
				selected_lot = ""
				selected_facility = 0
				facility_clicked.emit(0)
				cancelled.emit()
				accept_event()
		KEY_Z:
			toggle_zoom()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			var step := float(_cell() * PAN_STEP_CELLS)
			var direction := Vector2(
				float(key.keycode == KEY_LEFT) - float(key.keycode == KEY_RIGHT),
				float(key.keycode == KEY_UP) - float(key.keycode == KEY_DOWN))
			_pan += direction * step
			queue_redraw()
			accept_event()


func _on_mouse_exited() -> void:
	_hover = Vector2i(-1, -1)
	_dragging = false
	_update_check()
	hover_text_changed.emit("")
	queue_redraw()


func _emit_hover_text() -> void:
	var text := ""
	if _hover.x >= 0 and build_type == "":
		var facility := _facility_at(_hover)
		var lot := _lot_at(_hover)
		if not facility.is_empty():
			text = "#%d %s · %s" % [facility["id"], facility["name"], _status_text(facility)]
		elif not lot.is_empty() and not bool(lot["owned"]):
			text = tr("Parcelle à vendre : %s cr") % _fmt(int(lot["price"]))
	hover_text_changed.emit(text)


func _status_text(facility: Dictionary) -> String:
	if facility["status"] == "building":
		return tr("en construction, prête au jour %d") % int(facility["ready_day"])
	return tr("prête")


# --- Drawing -------------------------------------------------------------------

func _tex(asset: String) -> Texture2D:
	if not _textures.has(asset):
		var path := ASSET_DIR + asset + ".svg"
		_textures[asset] = load(path) if ResourceLoader.exists(path) else null
	return _textures[asset]


func _font() -> Font:
	return get_theme_font("font", "Label")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	if session == null:
		return
	if not session.data.has_map():
		_text_at(Vector2(16, 28), tr("Ce site n'a pas de carte."), COLOR_DIM)
		return
	var cell := float(_cell())
	var map_rect := Rect2(_origin(), Vector2(_map_size()) * cell)
	draw_rect(map_rect, COLOR_PANEL)
	_draw_terrain()
	_draw_lots()
	for facility in _facilities:
		_draw_facility(facility)
	_draw_zones()
	draw_rect(map_rect, COLOR_LINE, false, 1.0)
	_draw_selection()
	_draw_hover_outline()
	_draw_ghost()


func _tile_rect(rect: Dictionary, tile: String, first_column_tile := "") -> void:
	var cell := float(_cell())
	var origin := _origin()
	for cy in int(rect["h"]):
		for cx in int(rect["w"]):
			var name := first_column_tile if cx == 0 and first_column_tile != "" else tile
			var texture := _tex(name)
			var target := Rect2(origin + Vector2(int(rect["x"]) + cx, int(rect["y"]) + cy) * cell, Vector2(cell, cell))
			if texture != null:
				draw_texture_rect(texture, target, false)
			else:
				draw_rect(target, COLOR_BG)


func _draw_terrain() -> void:
	for terrain in session.data.site_map().get("terrain", []):
		if terrain["kind"] == "sea":
			_tile_rect(terrain, "tile_sea", "tile_shore")
		else:
			_tile_rect(terrain, "tile_" + String(terrain["kind"]))


func _draw_lots() -> void:
	for lot in _lots:
		var owned: bool = lot["owned"]
		_tile_rect(lot, "tile_ground" if owned else "tile_lot_for_sale")
		var rect := _cell_rect(lot)
		draw_rect(rect, COLOR_LINE if owned else COLOR_DIM, false, 1.0)
		if owned:
			continue
		var lines := [_lot_name(lot["id"]), "%s cr" % _fmt(int(lot["price"]))]
		_label_box(rect.get_center(), lines, COLOR_TEXT, COLOR_WARN if lot["id"] == selected_lot else COLOR_LINE)
		if lot["id"] == selected_lot:
			draw_rect(rect.grow(-1.0), COLOR_ACCENT, false, 3.0)


func _draw_facility(facility: Dictionary) -> void:
	var rect := _cell_rect(facility["rect"])
	var building: bool = facility["status"] == "building"
	var alpha := 0.55 if building else 1.0
	_draw_sprite(facility, rect, Color(1, 1, 1, alpha))
	if building:
		_tile_overlay(facility["rect"])
		_label_box(rect.get_center(), [tr("J%d") % int(facility["ready_day"])], COLOR_WARN, COLOR_WARN)
	var cell := float(_cell())
	var launchers: Array = facility["launchers"]
	for i in launchers.size():
		var offset := (i - (launchers.size() - 1) / 2.0) * cell * 1.5
		var center := rect.get_center() + (Vector2(0, offset) if _is_rotated(facility) else Vector2(offset, 0))
		var launcher_size := Vector2(cell * 2, cell) if _is_rotated(facility) else Vector2(cell, cell * 2)
		var launcher_rect := Rect2(center - launcher_size / 2.0, launcher_size)
		_draw_launcher(String(launchers[i]), launcher_rect, _is_rotated(facility))
	var markers: Array = []
	if facility["job_blocked"] and not building:
		markers.append("marker_job_blocked")
	if int(facility["damaged_until_day"]) >= 0:
		markers.append("marker_damaged")
	if bool(facility["evacuated_today"]):
		markers.append("marker_evacuated")
	if not building and not bool(facility["served"]):
		markers.append("marker_unserved")
	var marker_size := maxf(cell * 1.1, 16.0)
	for i in markers.size():
		var marker := _tex(markers[i])
		if marker != null:
			draw_texture_rect(marker, Rect2(rect.end - Vector2(marker_size * (i + 1), rect.size.y), Vector2(marker_size, marker_size)), false)
	var tag := "#%d" % int(facility["id"])
	_text_at(rect.position + Vector2(4, FONT_SIZE + 1), tag, COLOR_TEXT)
	draw_rect(rect, COLOR_WARN if building else COLOR_LINE, false, 1.0)


func _is_rotated(facility: Dictionary) -> bool:
	var footprint: Array = session.data.facilities[facility["type"]]["footprint"]
	var rect: Dictionary = facility["rect"]
	return int(footprint[0]) != int(footprint[1]) and int(rect["w"]) == int(footprint[1])


## Sprite drawn at rotation 0 by the artist, turned by 90 degrees when the instance is.
func _draw_sprite(facility: Dictionary, rect: Rect2, modulate_color: Color) -> void:
	_draw_texture_rotated(_tex("map_" + String(facility["type"])), rect, _is_rotated(facility), modulate_color,
		String(facility["name"]))


func _draw_launcher(model: String, rect: Rect2, rotated: bool) -> void:
	var texture := _tex("map_launcher_" + model.to_lower())
	if texture == null:
		texture = _tex("map_launcher_l1")
	_draw_texture_rotated(texture, rect if not rotated else Rect2(rect.position, rect.size), rotated, Color.WHITE, "")


func _draw_texture_rotated(texture: Texture2D, rect: Rect2, rotated: bool, modulate_color: Color, fallback_name: String) -> void:
	if texture == null:
		draw_rect(rect.grow(-1.0), Color(COLOR_PANEL, modulate_color.a))
		draw_rect(rect.grow(-1.0), COLOR_DIM, false, 1.0)
		if fallback_name != "" and rect.size.x > 40.0:
			_text_at(rect.position + Vector2(4, rect.size.y - 6), fallback_name, COLOR_DIM, int(rect.size.x) - 8)
		return
	if not rotated:
		draw_texture_rect(texture, rect, false, modulate_color)
		return
	var unrotated := Vector2(rect.size.y, rect.size.x)
	draw_set_transform(rect.get_center(), PI / 2.0, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-unrotated / 2.0, unrotated), false, modulate_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tile_overlay(rect: Dictionary) -> void:
	var texture := _tex("overlay_construction")
	if texture == null:
		return
	var cell := float(_cell())
	var origin := _origin()
	for cy in int(rect["h"]):
		for cx in int(rect["w"]):
			draw_texture_rect(texture, Rect2(origin + Vector2(int(rect["x"]) + cx, int(rect["y"]) + cy) * cell,
				Vector2(cell, cell)), false)


## Cell rectangle clipped to the map, in pixels.
func _zone_px(rect: Dictionary) -> Rect2:
	var map_rect := Rect2(_origin(), Vector2(_map_size()) * float(_cell()))
	return _cell_rect(rect).intersection(map_rect)


func _dashed_rect(rect: Rect2, color: Color) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 2.0, 6.0)


## Safety zones (selected pad, pad firing today, or every pad while placing),
## service zones (selected warehouse, or while placing a workshop), and the
## zone of the pad being placed. All rectangles come from SimQueries.
func _draw_zones() -> void:
	var placing := build_type != ""
	for zone in _zones["safety"]:
		var firing: bool = zone["fires_today"]
		if int(zone["pad_id"]) == selected_facility or firing or placing:
			var px := _zone_px(zone["rect"])
			draw_rect(px, Color(COLOR_DANGER, 0.10))
			_dashed_rect(px, COLOR_DANGER)
	var workshop: bool = placing and session.data.facilities[build_type].has("slots")
	for zone in _zones["service"]:
		if workshop or int(zone["facility_id"]) == selected_facility:
			var px := _zone_px(zone["rect"])
			draw_rect(px, Color(COLOR_ACCENT, 0.10))
			draw_rect(px, COLOR_ACCENT, false, 1.0)
	if placing and not _check.is_empty() and not _check["rect"].is_empty():
		var ghost_zone := SimQueries.safety_zone_rect(session.data, build_type, _check["rect"])
		if not ghost_zone.is_empty():
			var px := _zone_px(ghost_zone)
			draw_rect(px, Color(COLOR_DANGER, 0.14))
			_dashed_rect(px, COLOR_DANGER)


func _draw_selection() -> void:
	if selected_facility == 0 or build_type != "":
		return
	var facility := _facility_by_id(selected_facility)
	if not facility.is_empty():
		draw_rect(_cell_rect(facility["rect"]).grow(1.0), COLOR_ACCENT, false, 3.0)


func _draw_hover_outline() -> void:
	if _hover.x < 0 or build_type != "":
		return
	var facility := _facility_at(_hover)
	if not facility.is_empty():
		draw_rect(_cell_rect(facility["rect"]), COLOR_ACCENT, false, 2.0)
		return
	var lot := _lot_at(_hover)
	if not lot.is_empty() and not bool(lot["owned"]):
		draw_rect(_cell_rect(lot).grow(-1.0), COLOR_ACCENT, false, 2.0)


func _draw_ghost() -> void:
	if _check.is_empty() or _check["rect"].is_empty():
		return
	var valid: bool = _check["valid"]
	var color := COLOR_OK if valid else COLOR_DANGER
	var rect := _cell_rect(_check["rect"])
	var def: Dictionary = session.data.facilities[build_type]
	var ghost := {"type": build_type, "name": def["name"], "rect": _check["rect"]}
	_draw_sprite(ghost, rect, Color(1, 1, 1, GHOST_ALPHA))
	draw_rect(rect, Color(color, FILL_ALPHA))
	draw_rect(rect, color, false, 2.0)
	var lines: Array = [tr("Valide") if valid else _reason_text(_check)]
	if valid or not _check.is_empty():
		lines.append_array(_extra_lines(_check))
	_bubble(rect, lines, color)


func _extra_lines(check: Dictionary) -> Array:
	var lines: Array = []
	if not bool(check["valid"]):
		return lines
	if check.has("served"):
		lines.append(tr("Desservie") if check["served"] else [tr("Non desservie : cadence réduite"), COLOR_WARN])
	if check.has("in_safety_zone_of"):
		var pads: Array = check["in_safety_zone_of"]
		if pads.is_empty():
			lines.append(tr("Hors zone"))
		else:
			lines.append([tr("Dans la zone du pas n° %s : évacuée les jours de tir") % ", ".join(pads.map(func(p): return str(p))), COLOR_WARN])
	for entry in _rollouts:
		var target := tr("pas n° %d") % int(entry["pad_id"]) if int(entry["pad_id"]) > 0 \
			else tr("hall n° %d") % int(entry["hall_id"])
		lines.append(tr("Roll-out %s : %d j / %s cr") % [
			target, int(entry["rollout_days"]), _fmt(int(entry["rollout_cost"]))])
	return lines


func _reason_text(check: Dictionary) -> String:
	var reason := String(check["reason"])
	var text: String = tr(REASONS.get(reason, reason))
	if reason == "overlap" and check.has("facility_id"):
		text += " (#%d)" % int(check["facility_id"])
	return text


# --- Text helpers ----------------------------------------------------------------

func _text_at(pos: Vector2, text: String, color: Color, width := -1) -> void:
	draw_string(_font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, FONT_SIZE, color)


## Panel with centered lines (lot prices, construction tag).
func _label_box(center: Vector2, lines: Array, color: Color, border: Color) -> void:
	var font := _font()
	var line_h := float(FONT_SIZE + 3)
	var width := 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var box := Rect2(center - Vector2(width / 2.0 + 6.0, line_h * lines.size() / 2.0 + 3.0),
		Vector2(width + 12.0, line_h * lines.size() + 6.0))
	draw_rect(box, Color(COLOR_BG, 0.88))
	draw_rect(box, border, false, 1.0)
	for i in lines.size():
		var line_width := font.get_string_size(String(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		_text_at(Vector2(center.x - line_width / 2.0, box.position.y + 3.0 + line_h * (i + 1) - 4.0), String(lines[i]), color)


## Placement summary near the ghost, kept inside the canvas.
func _bubble(target: Rect2, lines: Array, border: Color) -> void:
	var font := _font()
	var line_h := float(FONT_SIZE + 4)
	var width := 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(_line_text(line), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var box_size := Vector2(width + 16.0, line_h * lines.size() + 8.0)
	var pos := Vector2(target.end.x + 8.0, target.position.y)
	if pos.x + box_size.x > size.x:
		# No room on the right: above the ghost (or below it), never on top of it.
		pos = Vector2(target.position.x, target.position.y - box_size.y - 6.0)
		if pos.y < 0.0:
			pos.y = target.end.y + 6.0
	pos.x = clampf(pos.x, 0.0, maxf(0.0, size.x - box_size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, size.y - box_size.y))
	draw_rect(Rect2(pos, box_size), Color(COLOR_BG, 0.92))
	draw_rect(Rect2(pos, box_size), border, false, 1.0)
	for i in lines.size():
		var color: Color = border if i == 0 else COLOR_TEXT
		if lines[i] is Array:
			color = lines[i][1]
		_text_at(pos + Vector2(8.0, 4.0 + line_h * (i + 1) - 4.0), _line_text(lines[i]), color)


## A bubble line is a string or [string, color].
func _line_text(line: Variant) -> String:
	return String(line[0]) if line is Array else String(line)


# --- Names and numbers ---------------------------------------------------------------

## Presentation names of the lots of the shipped site; unknown ids show as is.
func _lot_name(lot_id: String) -> String:
	match lot_id:
		"lot_west": return tr("Ouest")
		"lot_north": return tr("Nord")
		"lot_south": return tr("Sud")
		"lot_coast": return tr("Côte")
		"lot_start": return tr("Départ")
	return lot_id


func lot_name(lot_id: String) -> String:
	return _lot_name(lot_id)


static func _fmt(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += " "
		out += digits[i]
	return ("-" if value < 0 else "") + out
