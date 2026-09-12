extends Node2D
## Boots into the menu and owns everything that outlives a world.
##
## The ContentRegistry and the Theme are built once here and survive
## returning to the menu, which is why this phase does not use
## change_scene_to_file: a scene swap would re-parse every JSON under data/
## and rebuild the tileset atlas on every transition.
##
## All policy lives in GameSession. This node translates between it and the
## scene tree, and does nothing else.

## Exported rather than hardcoded: a res:// path in logic is the thing the
## content rules exist to prevent.
@export var zone_dir: String = "res://data/zone/home"

var _registry: ContentRegistry = null
var _session: GameSession = null
var _world: World = null
var _ui: CanvasLayer = null
var _main_menu: MainMenu = null
var _pause_menu: PauseMenu = null
var _confirm: ConfirmPanel = null

## Set when a save fails on the way out, so a second attempt quits anyway.
var _quit_was_refused: bool = false


func _ready() -> void:
	# Without this the window closes before the save runs.
	get_tree().auto_accept_quit = false

	# The router must keep processing while the tree is paused, or Escape
	# can pause the game and nothing is left listening to un-pause it.
	# _physics_process is gated on paused below instead, which is what
	# actually stops the world.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_registry = ContentRegistry.new()
	for e: String in _registry.load_from_dir("res://data"):
		push_error("content failed to load: %s" % e)
	print("RP1 booted with %d content definitions" % _registry.all_string_ids().size())

	_session = GameSession.new()

	_ui = CanvasLayer.new()
	_ui.name = "UI"
	# The pause menu has to keep processing while the tree is paused.
	_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_ui)

	var theme: Theme = UiTheme.build()

	_main_menu = MainMenu.new()
	_main_menu.name = "MainMenu"
	_main_menu.theme = theme
	_main_menu.new_world_requested.connect(_on_new_world_requested)
	_main_menu.continue_requested.connect(_on_continue_requested)
	_main_menu.quit_requested.connect(_save_and_quit)
	_ui.add_child(_main_menu)

	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.theme = theme
	_pause_menu.resume_requested.connect(_set_paused.bind(false))
	_pause_menu.quit_to_menu_requested.connect(_on_quit_to_menu)
	_pause_menu.quit_to_desktop_requested.connect(_save_and_quit)
	_ui.add_child(_pause_menu)

	_confirm = ConfirmPanel.new()
	_confirm.name = "ConfirmPanel"
	_confirm.theme = theme
	_ui.add_child(_confirm)

	_show_main_menu()


# --- menu -------------------------------------------------------------

func _read_meta() -> WorldMeta:
	var path: String = WorldMeta.path_in(_session.save_root)
	if not FileAccess.file_exists(path):
		return WorldMeta.new()
	var result: DecodeResult = WorldMeta.from_json_string(
		FileAccess.get_file_as_string(path))
	return result.value if result.ok else WorldMeta.new()


func _show_main_menu() -> void:
	_main_menu.visible = true
	_pause_menu.visible = false
	_main_menu.set_save_state(_session.has_save(), _read_meta())


func _on_new_world_requested() -> void:
	if not _session.has_save():
		_start_new_world()
		return
	# Overwriting a world is the one destructive thing this menu can do.
	_confirm.ask(
		"Overwrite your world?",
		"Starting a new world replaces the saved one. This cannot be undone.",
		"Overwrite")
	_confirm.confirmed.connect(_start_new_world, CONNECT_ONE_SHOT)
	_confirm.dismissed.connect(
		func() -> void:
			if _confirm.confirmed.is_connected(_start_new_world):
				_confirm.confirmed.disconnect(_start_new_world),
		CONNECT_ONE_SHOT)


func _start_new_world() -> void:
	var result: SessionOpenResult = _session.open_new(zone_dir, _registry)
	if not result.ok:
		push_error(result.error)
		_confirm.report("Could not start a new world", result.error)
		return
	_enter_world(result)

	var errors: PackedStringArray = _session.save_now(_registry, "new_world")
	for e: String in errors:
		push_error("first save failed: %s" % e)
	if not errors.is_empty():
		_confirm.report("Could not save the new world", "\n".join(errors))


func _on_continue_requested() -> void:
	var result: SessionOpenResult = _session.open_saved(_registry, false)
	if result.ok:
		_enter_world(result)
		return

	push_error("continue failed: %s" % result.error)
	if not _session.has_backup():
		_confirm.report("Could not load your world", result.error)
		return
	_confirm.ask(
		"Could not load your world",
		"%s\n\nThere is an earlier backup. Load it instead?" % result.error,
		"Load backup")
	_confirm.confirmed.connect(_continue_from_backup, CONNECT_ONE_SHOT)
	_confirm.dismissed.connect(
		func() -> void:
			if _confirm.confirmed.is_connected(_continue_from_backup):
				_confirm.confirmed.disconnect(_continue_from_backup),
		CONNECT_ONE_SHOT)


func _continue_from_backup() -> void:
	var result: SessionOpenResult = _session.open_saved(_registry, true)
	if not result.ok:
		push_error("backup load failed: %s" % result.error)
		_confirm.report("The backup could not be loaded either", result.error)
		return
	_enter_world(result)


# --- world ------------------------------------------------------------

func _enter_world(result: SessionOpenResult) -> void:
	for w: String in result.warnings:
		push_error("zone: %s" % w)

	_world = World.new()
	_world.name = "World"
	add_child(_world)
	for e: String in _world.build(_registry, result):
		push_error(e)

	_session.adopt_player(_world.player_entity_id)
	_main_menu.visible = false
	_set_paused(false)


func _on_quit_to_menu() -> void:
	var errors: PackedStringArray = _session.save_now(_registry, "quit_to_menu")
	if not errors.is_empty():
		for e: String in errors:
			push_error("save failed: %s" % e)
		_confirm.report("Could not save", "\n".join(errors))
		return

	_set_paused(false)
	_world.queue_free()
	_world = null
	_session.close()
	_show_main_menu()


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_menu.visible = paused
	if paused:
		_pause_menu.focus_first()


# --- loop -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# This node is PROCESS_MODE_ALWAYS so it can hear the un-pause key, so
	# the pause has to be honoured here by hand. It is also what makes the
	# autosave clock measure unpaused play rather than wall time.
	if _world == null or get_tree().paused:
		return
	_world.tick_animals(delta)
	_session.tick(delta, _registry)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _world == null or _confirm.visible:
		return
	get_viewport().set_input_as_handled()
	_set_paused(not get_tree().paused)


# --- quitting ---------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_and_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and _world != null:
		for e: String in _session.save_if_gap_elapsed(_registry, "focus_lost"):
			push_error("focus-loss save failed: %s" % e)


func _save_and_quit() -> void:
	if _world == null:
		get_tree().quit()
		return

	var errors: PackedStringArray = _session.save_now(_registry, "quit")
	if errors.is_empty() or _quit_was_refused:
		get_tree().quit()
		return

	# One chance to act -- free some disk, close whatever holds the file --
	# and then get out of the player's way. Holding the process hostage
	# over a full disk is worse than losing the session.
	_quit_was_refused = true
	for e: String in errors:
		push_error("save failed on quit: %s" % e)
	_confirm.report(
		"Could not save",
		"%s\n\nQuit again to exit without saving." % "\n".join(errors))
