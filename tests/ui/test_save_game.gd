extends TestCase
## Issue #69: SaveGame / GameSession save and load. Files live under
## user://test_saves/ and are removed after each test.

const F := preload("res://tests/sim/fixtures.gd")
const DIR := "user://test_saves"
const PATH := "user://test_saves/save.json"


func _cleanup() -> void:
	for file_name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file_name))
	DirAccess.remove_absolute(DIR)


func _write_raw(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Scripted game: same commands on the same days for every run.
func _play(session: GameSession, from_day: int, to_day: int) -> void:
	for day in range(from_day, to_day):
		if day == 0:
			session.submit(Command.order("acme", "steel", 3))
		if day == 3:
			session.submit(Command.order("acme", "steel", 2))
		session.end_day()


func _json(state: GameState) -> String:
	return JSON.stringify(state.to_dict())


func test_roundtrip_gives_identical_state() -> void:
	var session := GameSession.new(F.data(), 5)
	_play(session, 0, 6)
	assert_true(session.save_to(PATH)["ok"])
	var result := GameSession.load_from(PATH, F.data())
	assert_true(result["ok"])
	var loaded: GameSession = result["session"]
	assert_eq(_json(loaded.state), _json(session.state))
	assert_eq(loaded.command_log.keys(), session.command_log.keys())
	assert_eq(loaded.command_log[0][0]["args"]["quantity"], 3)
	assert_eq(typeof(loaded.command_log[0][0]["args"]["quantity"]), TYPE_INT)
	_cleanup()


func test_resumed_game_matches_uninterrupted_one() -> void:
	var full := GameSession.new(F.data(), 9)
	_play(full, 0, 20)
	var first := GameSession.new(F.data(), 9)
	_play(first, 0, 10)
	first.save_to(PATH)
	var loaded: GameSession = GameSession.load_from(PATH, F.data())["session"]
	_play(loaded, 10, 20)
	assert_eq(_json(loaded.state), _json(full.state))
	assert_eq(loaded.command_log.keys(), full.command_log.keys())
	_cleanup()


func test_corrupt_file_is_refused() -> void:
	for text in ["", "not json {", "[1, 2]", "{\"save_version\": 1}",
			"{\"save_version\": 1, \"state\": {}, \"command_log\": {}}"]:
		_write_raw(text)
		var result := GameSession.load_from(PATH, F.data())
		assert_true(not result["ok"], "refused: %s" % text)
		assert_true(result["session"] == null)
	_cleanup()


func test_unknown_version_is_refused() -> void:
	var session := GameSession.new(F.data(), 1)
	session.save_to(PATH)
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	payload["save_version"] = 99
	_write_raw(JSON.stringify(payload))
	var result := GameSession.load_from(PATH, F.data())
	assert_true(not result["ok"])
	assert_eq(result["reason"], "version")
	_cleanup()


func test_missing_file_is_reported() -> void:
	var result := GameSession.load_from("user://test_saves/nope.json", F.data())
	assert_true(not result["ok"])
	assert_eq(result["reason"], "missing")


func test_autosave_each_day_and_deleted_on_game_over() -> void:
	var session := GameSession.new(F.data(), 1)
	session.autosave_path = PATH
	session.end_day()
	assert_true(SaveGame.exists(PATH))
	assert_eq(SaveGame.read(PATH)["saved_day"], 1)
	session.data.rules = {"bankruptcy_grace_days": 3, "bankruptcy_warning_days": 2}
	session.state.money = -1000000000
	for i in 5:
		session.end_day()
	assert_true(session.state.game_over)
	assert_true(not SaveGame.exists(PATH))
	_cleanup()


func test_fast_forward_autosaves_once_at_the_end() -> void:
	var session := GameSession.new(F.data(), 1)
	session.autosave_path = PATH
	var days := session.fast_forward()
	assert_eq(SaveGame.read(PATH)["saved_day"], days)
	_cleanup()


## Compatibility guard: a save written with the current SAVE_VERSION must keep
## loading. If this fails after adding a GameState field, either give the field a
## default in GameState.from_dict and list it in SaveGame.OPTIONAL_STATE_KEYS, or
## bump SaveGame.SAVE_VERSION and generate tests/ui/fixtures/save_v<N>.json again
## (a 4-day game on the test fixtures, seed 5, one order of 3 steel on day 0).
func test_reference_save_still_loads_and_plays() -> void:
	var path := "res://tests/ui/fixtures/save_v%d.json" % SaveGame.SAVE_VERSION
	var loaded := GameSession.load_from(path, F.data())
	assert_true(loaded["ok"], "reference save refused (%s): read the comment above this test" % loaded["reason"])
	if not loaded["ok"]:
		return
	var session: GameSession = loaded["session"]
	assert_eq(session.state.day, 4)
	assert_eq(session.state.money, 9500)
	for i in 5:
		session.end_day()
	assert_eq(session.state.day, 9)
