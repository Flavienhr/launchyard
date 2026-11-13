class_name TestCase
extends RefCounted
## Base class for tests. A fresh instance is created for every test_* method.

var failures: Array[String] = []
var current_test := ""


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if actual != expected:
		_fail("expected <%s>, got <%s> %s" % [str(expected), str(actual), message])


func assert_true(condition: bool, message := "") -> void:
	if not condition:
		_fail("assertion failed %s" % message)


func _fail(text: String) -> void:
	failures.append("%s: %s" % [current_test, text])
