extends GutTest
## The build cursor turns mouse events into commands. It holds no rule
## about what may be built -- that is BuildSystem's, and tested there.


func _registry() -> ContentRegistry:
	var r: ContentRegistry = ContentRegistry.new()
	r.register({"id": "wood", "category": "item", "display_name": "Wood"})
	r.register({"id": "wall", "category": "object", "display_name": "Wall",
		"sprite": "res://none.png", "cost": {"wood": 2}})
	r.register({"id": "rug", "category": "object", "display_name": "Rug",
		"sprite": "res://none.png", "cost": {"wood": 1}})
	r.register({"id": "tree", "category": "object", "display_name": "Tree",
		"sprite": "res://none.png"})
	return r


func _cursor(r: ContentRegistry) -> BuildCursor:
	var cursor: BuildCursor = BuildCursor.new()
	add_child_autofree(cursor)
	cursor.setup(r)
	watch_signals(cursor)
	return cursor


## A press of `button` on the middle of `tile`, delivered straight to the
## cursor. The position is mapped through the same transforms the engine
## applies, so the test does not assume the runner's viewport is unmoved.
func _click(cursor: BuildCursor, button: MouseButton, tile: Vector2i) -> void:
	var world_px: Vector2 = (Vector2(tile) + Vector2(0.5, 0.5)) \
		* Vector2(TilesetBuilder.TILE_SIZE)
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = cursor.get_viewport().get_canvas_transform() \
		* cursor.get_global_transform() * world_px
	cursor._unhandled_input(ev)


func _press_build_mode(cursor: BuildCursor) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "build_mode"
	ev.pressed = true
	cursor._unhandled_input(ev)


# --- mouse to tile ----------------------------------------------------

func test_a_pixel_maps_to_the_tile_that_contains_it() -> void:
	assert_eq(BuildCursor.tile_at(Vector2(0.0, 0.0)), Vector2i(0, 0))
	assert_eq(BuildCursor.tile_at(Vector2(31.9, 31.9)), Vector2i(0, 0))
	assert_eq(BuildCursor.tile_at(Vector2(32.0, 64.0)), Vector2i(1, 2))
	assert_eq(BuildCursor.tile_at(Vector2(1040.0, 816.0)), Vector2i(32, 25))


func test_a_pixel_left_of_or_above_the_zone_maps_outside_it() -> void:
	# Truncating instead of flooring would fold -0.5 onto tile 0 and let a
	# click outside the zone edit its first column.
	assert_eq(BuildCursor.tile_at(Vector2(-0.5, -0.5)), Vector2i(-1, -1))
	assert_eq(BuildCursor.tile_at(Vector2(-32.0, 5.0)), Vector2i(-1, 0))


# --- selection --------------------------------------------------------

func test_the_first_placeable_is_selected_to_begin_with() -> void:
	assert_eq(_cursor(_registry()).selected_id(), "rug")


func test_stepping_the_selection_wraps_both_ways() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	cursor.step_selection(1)
	assert_eq(cursor.selected_id(), "wall")
	assert_signal_emitted_with_parameters(cursor, "selection_changed", ["wall"])
	cursor.step_selection(1)
	assert_eq(cursor.selected_id(), "rug")
	cursor.step_selection(-1)
	assert_eq(cursor.selected_id(), "wall")


func test_a_build_with_nothing_placeable_selects_nothing() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var cursor: BuildCursor = _cursor(r)
	assert_eq(cursor.selected_id(), "")
	assert_null(cursor.place_command(Vector2i(1, 1)))
	cursor.step_selection(1)
	assert_signal_not_emitted(cursor, "selection_changed")


func test_a_place_command_carries_the_layer_its_content_lives_on() -> void:
	var cmd: BuildCommand = _cursor(_registry()).place_command(Vector2i(4, 7))
	assert_eq(cmd.action, BuildCommand.PLACE)
	assert_eq(cmd.tile, Vector2i(4, 7))
	assert_eq(cmd.content_id, "rug")
	assert_eq(cmd.layer, BuildCommand.LAYER_OBJECT)


# --- mode -------------------------------------------------------------

func test_the_cursor_starts_inactive() -> void:
	assert_false(_cursor(_registry()).active)


func test_the_build_mode_action_toggles_it() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	_press_build_mode(cursor)
	assert_true(cursor.active)
	assert_signal_emitted_with_parameters(cursor, "mode_changed", [true])
	_press_build_mode(cursor)
	assert_false(cursor.active)
	assert_signal_emitted_with_parameters(cursor, "mode_changed", [false])


func test_an_inactive_cursor_ignores_clicks() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	_click(cursor, MOUSE_BUTTON_LEFT, Vector2i(3, 3))
	_click(cursor, MOUSE_BUTTON_RIGHT, Vector2i(3, 3))
	_click(cursor, MOUSE_BUTTON_WHEEL_DOWN, Vector2i(3, 3))
	assert_signal_not_emitted(cursor, "build_requested")
	assert_eq(cursor.selected_id(), "rug")


# --- clicks -----------------------------------------------------------

func test_a_left_click_asks_to_place_the_selection_under_the_mouse() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_LEFT, Vector2i(6, 2))
	assert_signal_emit_count(cursor, "build_requested", 1)
	var cmd: BuildCommand = get_signal_parameters(cursor, "build_requested")[0]
	assert_eq(cmd.action, BuildCommand.PLACE)
	assert_eq(cmd.tile, Vector2i(6, 2))
	assert_eq(cmd.content_id, "rug")


func test_a_right_click_asks_to_remove_what_is_under_the_mouse() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_RIGHT, Vector2i(6, 2))
	var cmd: BuildCommand = get_signal_parameters(cursor, "build_requested")[0]
	assert_eq(cmd.action, BuildCommand.REMOVE)
	assert_eq(cmd.tile, Vector2i(6, 2))
	assert_eq(cmd.layer, BuildCommand.LAYER_OBJECT)
	assert_eq(cmd.content_id, "")


func test_the_wheel_steps_the_selection() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_WHEEL_DOWN, Vector2i(0, 0))
	assert_eq(cursor.selected_id(), "wall")
	_click(cursor, MOUSE_BUTTON_WHEEL_UP, Vector2i(0, 0))
	assert_eq(cursor.selected_id(), "rug")
	assert_signal_not_emitted(cursor, "build_requested")


func test_with_nothing_to_place_a_left_click_asks_for_nothing() -> void:
	var cursor: BuildCursor = _cursor(ContentRegistry.new())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_LEFT, Vector2i(6, 2))
	assert_signal_not_emitted(cursor, "build_requested")


func test_the_cursor_never_decides_on_its_own() -> void:
	# No probe is set, so the cursor cannot know whether the command is
	# acceptable -- and it emits anyway. The router decides.
	var cursor: BuildCursor = _cursor(_registry())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_LEFT, Vector2i(-3, -3))
	assert_signal_emit_count(cursor, "build_requested", 1)
