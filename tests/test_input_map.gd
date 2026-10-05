extends GutTest
## Input is read through named actions so gamepad bindings and Stage 6's
## rebinding have something to work with.


func test_the_pause_action_exists() -> void:
	assert_true(InputMap.has_action("pause"))


func test_the_pause_action_is_bound_to_escape() -> void:
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("pause"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			found = true
	assert_true(found, "pause is not bound to Escape")


func test_the_pause_action_is_bound_to_a_gamepad_button() -> void:
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("pause"):
		if event is InputEventJoypadButton:
			found = true
	assert_true(found, "pause has no gamepad binding")


func test_the_movement_actions_still_exist() -> void:
	# project.godot is edited by hand for the pause action, and a malformed
	# [input] section can silently drop the others.
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		assert_true(InputMap.has_action(action), action)


func test_the_debug_grant_action_is_bound_to_g() -> void:
	# DEBUG ONLY -- removed with debug_place in Phase 10.
	assert_true(InputMap.has_action("debug_grant"))
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("debug_grant"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_G:
			found = true
	assert_true(found, "debug_grant is not bound to G")


func test_the_interact_action_is_bound_to_e() -> void:
	assert_true(InputMap.has_action("interact"))
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("interact"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_E:
			found = true
	assert_true(found, "interact is not bound to E")


func test_the_interact_action_is_bound_to_a_gamepad_button() -> void:
	# A real action, not a debug one: it gets a gamepad binding like pause.
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("interact"):
		if event is InputEventJoypadButton:
			found = true
	assert_true(found, "interact has no gamepad binding")


func test_the_build_mode_action_is_bound_to_b() -> void:
	assert_true(InputMap.has_action("build_mode"))
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("build_mode"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_B:
			found = true
	assert_true(found, "build_mode is not bound to B")


func test_the_debug_place_action_is_gone() -> void:
	# It held B and placed a free wall. Build mode replaced it.
	assert_false(InputMap.has_action("debug_place"))
