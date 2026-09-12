extends GutTest
## The main menu must be *interactive*, not merely visible.
##
## Phase 5 shipped a menu that drew perfectly and ignored every click: the
## UI CanvasLayer was PROCESS_MODE_WHEN_PAUSED, which processes ONLY while
## the tree is paused, and the tree is not paused at boot. can_process() is
## the behavioural check that catches it; asserting the constant instead
## would only restate the implementation.
##
## This instantiates the real main scene. It never opens a world, so it
## never writes to the real save root.
##
## A click-through test was tried here and removed: synthetic mouse events
## do not reach a scene parented under GUT's own runner, and the attempt
## hung the suite. The end-to-end click is verified instead by driving a
## standalone windowed build. can_process() is the precise check anyway --
## it is the exact condition that was false when the menu ignored clicks.

var _main: Node = null
var _was_auto_accept_quit: bool = true


func before_each() -> void:
	_was_auto_accept_quit = get_tree().auto_accept_quit
	_main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(_main)


func after_each() -> void:
	# The router turns this off so it can save before the window closes.
	get_tree().auto_accept_quit = _was_auto_accept_quit
	get_tree().paused = false


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c: Node in node.get_children():
		var found: Button = _find_button(c, text)
		if found != null:
			return found
	return null


func test_the_menu_buttons_exist() -> void:
	for label: String in ["New World", "Continue", "Quit"]:
		assert_not_null(_find_button(_main, label), "no %s button" % label)


func test_the_menu_is_interactive_at_boot() -> void:
	assert_false(get_tree().paused, "the tree should not be paused at boot")
	for label: String in ["New World", "Continue", "Quit"]:
		var b: Button = _find_button(_main, label)
		assert_true(b.can_process(),
			"%s cannot process while unpaused: it draws but ignores clicks" % label)


func test_the_menu_is_still_interactive_while_paused() -> void:
	# The pause menu lives on the same layer and must work in the other
	# state, which is the requirement that produced the bug.
	get_tree().paused = true
	for label: String in ["Resume", "Quit to Menu", "Quit to Desktop"]:
		var b: Button = _find_button(_main, label)
		assert_not_null(b, "no %s button" % label)
		assert_true(b.can_process(), "%s cannot process while paused" % label)


func test_menu_buttons_accept_mouse_input() -> void:
	var b: Button = _find_button(_main, "New World")
	assert_eq(b.mouse_filter, Control.MOUSE_FILTER_STOP,
		"a button that ignores the mouse cannot be clicked")
	assert_true(b.is_visible_in_tree())
	assert_false(b.disabled, "New World must never be disabled")

