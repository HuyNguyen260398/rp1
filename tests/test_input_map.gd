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
