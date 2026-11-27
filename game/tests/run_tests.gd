extends SceneTree


func _initialize() -> void:
	var suite := SessionKernelTests.new()
	var result: Dictionary = suite.run()
	print("SESSION_KERNEL_TESTS: %d passed, %d failed" % [result["passed"], result["failed"]])
	quit(1 if result["failed"] > 0 else 0)
