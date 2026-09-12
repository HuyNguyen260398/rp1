class_name MainMenu
extends Control
## New World / Continue / Quit.
##
## Emits three signals and knows nothing else. It has never heard of a
## GameSession: the router decides what each button means, which is what
## keeps every game-loop rule in a RefCounted that can be tested headless.

signal new_world_requested
signal continue_requested
signal quit_requested

var _continue_button: Button = null
var _summary: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background: ColorRect = ColorRect.new()
	background.color = UiTheme.BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.custom_minimum_size = Vector2(320, 0)
	centre.add_child(column)

	var title: Label = Label.new()
	title.text = "RP1"
	title.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var new_button: Button = Button.new()
	new_button.text = "New World"
	new_button.pressed.connect(func() -> void: new_world_requested.emit())
	column.add_child(new_button)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.pressed.connect(func() -> void: continue_requested.emit())
	column.add_child(_continue_button)

	_summary = Label.new()
	_summary.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_summary)

	var quit_button: Button = Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit_button)

	new_button.grab_focus()


## Continue is disabled and dimmed when there is nothing to continue. The
## summary line is the only place meta.json is shown to the player, which
## is most of the reason the file is worth having.
func set_save_state(has_save: bool, meta: WorldMeta) -> void:
	_continue_button.disabled = not has_save
	if not has_save:
		_summary.text = "No saved world yet"
		return
	var played: int = int(meta.playtime)
	_summary.text = "%d:%02d played  -  %s" % [
		played / 3600,
		(played % 3600) / 60,
		Time.get_datetime_string_from_unix_time(meta.last_played_unix, true),
	]
