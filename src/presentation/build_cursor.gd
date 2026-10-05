class_name BuildCursor
extends Node2D
## Build mode's mouse: which tile, which content, and the click.
##
## It emits intent and decides nothing. Whether a command may happen is
## BuildSystem's rule; this asks it through `probe`, which the router
## supplies, and never restates it (Stage 2 design 3.5). It reads the
## registry to know what can be selected and writes to nothing.
##
## This is the project's first mouse gameplay input, and it has no
## controller path. That debt is accepted in the design and listed in
## IDEAS.md.

## A command to place or remove. The router applies it, or refuses.
signal build_requested(cmd: BuildCommand)
signal mode_changed(active: bool)
signal selection_changed(content_id: String)

## func(cmd: BuildCommand) -> bool: would this command be accepted? Only
## the outline's colour depends on it. Unset, the outline reads refused.
var probe: Callable = Callable()

## Read this; change it with set_active() so the signal fires.
var active: bool = false

var _registry: ContentRegistry = null
var _placeables: PackedStringArray = []
var _index: int = 0
var _tile: Vector2i = Vector2i.ZERO
var _accepted: bool = false


## The tile containing a point in world pixels. Floored, not truncated:
## a point just left of the zone is tile -1, not tile 0.
static func tile_at(world_px: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_px.x / TilesetBuilder.TILE_SIZE.x),
		floori(world_px.y / TilesetBuilder.TILE_SIZE.y))


func setup(registry: ContentRegistry) -> void:
	_registry = registry
	_placeables = BuildSystem.placeables(registry)
	_index = 0
	# The parent Y-sorts its children; the outline belongs above all of
	# them wherever it sits.
	z_index = 1


func selected_id() -> String:
	return "" if _placeables.is_empty() else _placeables[_index]


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	queue_redraw()
	mode_changed.emit(active)


func step_selection(delta: int) -> void:
	if _placeables.size() < 2:
		return
	_index = posmod(_index + delta, _placeables.size())
	selection_changed.emit(selected_id())


## The command a left click on `tile` means, or null with nothing to
## place. The layer is the selected content's category: a definition says
## where it goes by what it is.
func place_command(tile: Vector2i) -> BuildCommand:
	var content_id: String = selected_id()
	if content_id.is_empty():
		return null
	var def: Dictionary = _registry.def_of(_registry.numeric_of(content_id))
	return BuildCommand.place(tile, str(def.get("category", "")), content_id)


func _process(_delta: float) -> void:
	if not active:
		return
	# Asked every frame rather than on mouse motion: the camera follows
	# the player, so the tile under a still mouse changes as they walk,
	# and what is affordable changes as they harvest.
	var tile: Vector2i = tile_at(get_global_mouse_position())
	var cmd: BuildCommand = place_command(tile)
	var accepted: bool = cmd != null and probe.is_valid() and bool(probe.call(cmd))
	if tile == _tile and accepted == _accepted:
		return
	_tile = tile
	_accepted = accepted
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var size: Vector2 = Vector2(TilesetBuilder.TILE_SIZE)
	# An outline one pixel wide, inset half a pixel so it lands on whole
	# pixels, in a theme colour at full opacity: nothing drawn here is
	# off the palette.
	draw_rect(
		Rect2(Vector2(_tile) * size + Vector2(0.5, 0.5), size - Vector2.ONE),
		UiTheme.ACCENT if _accepted else UiTheme.DANGER,
		false, 1.0)


## The parent world is PROCESS_MODE_PAUSABLE, so none of this is heard
## while paused.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		get_viewport().set_input_as_handled()
		set_active(not active)
		return
	if not active:
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	get_viewport().set_input_as_handled()
	# The click's own position, not the last one _process saw: the two
	# can differ by a frame, and the command must name the tile clicked.
	var local: InputEventMouseButton = make_input_local(click) as InputEventMouseButton
	var tile: Vector2i = tile_at(local.position)
	if click.button_index == MOUSE_BUTTON_LEFT:
		var cmd: BuildCommand = place_command(tile)
		if cmd != null:
			build_requested.emit(cmd)
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		build_requested.emit(BuildCommand.remove(tile, BuildCommand.LAYER_OBJECT))
	elif click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step_selection(1)
	elif click.button_index == MOUSE_BUTTON_WHEEL_UP:
		step_selection(-1)
