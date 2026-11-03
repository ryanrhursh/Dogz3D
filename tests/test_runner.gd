extends Node
## Headless test runner. main.gd starts it for `--test=<suite>` or `--test=all`:
##   godot --headless --fixed-fps 60 --path . -- --fresh --no-save --seed=42 --test=all
## Prints PASS/FAIL per test and a summary, then quits with exit code 1 on failure.

const SUITES := {
	"core": "res://tests/test_core.gd",
}

var passed := 0
var failed := 0


func run(main: Node3D, which: String) -> void:
	# Let the navmesh sync and physics settle.
	for i in 3:
		await get_tree().physics_frame

	for suite_name: String in SUITES:
		if which != "all" and which != suite_name:
			continue
		var script: GDScript = load(SUITES[suite_name])
		var suite: TestSuite = script.new()
		suite.setup(self, main)
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			suite.failures.clear()
			await suite.before_each()
			await Callable(suite, method_name).call()
			await suite.after_each()
			var full_name := "%s.%s" % [suite_name, method_name]
			if suite.failures.is_empty():
				passed += 1
				print("PASS %s" % full_name)
			else:
				failed += 1
				for msg in suite.failures:
					print("FAIL %s: %s" % [full_name, msg])

	print("Tests: %d passed, %d failed" % [passed, failed])
	if passed + failed == 0:
		push_error("No tests matched '%s'." % which)
		get_tree().quit(1)
		return
	if failed > 0:
		push_error("%d test(s) failed." % failed)
	get_tree().quit(1 if failed > 0 else 0)
