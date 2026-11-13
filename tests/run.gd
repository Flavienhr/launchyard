extends SceneTree
## Headless test runner (no addon dependency):
##   godot --headless --path . -s tests/run.gd
## Discovers tests/**/test_*.gd and runs every test_* method.
## Output is deliberately short (summary + failures only): agents read it.

const TEST_DIRS := ["res://tests/sim", "res://tests/ui"]


func _init() -> void:
	var total := 0
	var failures: Array[String] = []
	for dir_path in TEST_DIRS:
		for file_name in _test_files(dir_path):
			var path: String = dir_path.path_join(file_name)
			var script: GDScript = load(path)
			if script == null or not script.can_instantiate():
				failures.append("%s: cannot load script" % path)
				continue
			for method in script.get_script_method_list():
				var method_name: String = method["name"]
				if not method_name.begins_with("test_"):
					continue
				var test: TestCase = script.new()
				test.current_test = "%s::%s" % [file_name, method_name]
				test.call(method_name)
				total += 1
				failures.append_array(test.failures)

	for failure in failures:
		print("FAIL ", failure)
	print("%d tests, %d failures" % [total, failures.size()])
	quit(1 if failures.size() > 0 or total == 0 else 0)


func _test_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			files.append(file_name)
	files.sort()
	return files
