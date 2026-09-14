class_name PauseMenu
extends Control
## Resume / Quit to Menu / Quit to Desktop.
##
## Both quit buttons save before quitting -- but that is the router's job.
## This node emits and forgets, exactly like MainMenu.
##
## The background is translucent rather than opaque: the world stays
## visible behind it, which is the cheapest way to make a pause read as a
## pause rather than as having left the game.

signal resume_requested
signal quit_to_menu_requested
signal quit_to_desktop_requested
signal volume_changed(value: float)
signal mute_toggled(muted: bool)

var _resume_button: Button = null
var _volume: HSlider = null
var _mute: CheckButton = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var background: ColorRect = ColorRect.new()
	background.color = Color(UiTheme.BACKGROUND, 0.7)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.custom_minimum_size = Vector2(320, 0)
	centre.add_child(column)

	var title: Label = Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_resume_button = Button.new()
	_resume_button.text = "Resume"
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	column.add_child(_resume_button)

	var volume_row: HBoxContainer = HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	column.add_child(volume_row)

	var volume_label: Label = Label.new()
	volume_label.text = "Volume"
	volume_row.add_child(volume_label)

	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.custom_minimum_size = Vector2(180, 0)
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.value_changed.connect(func(v: float) -> void: volume_changed.emit(v))
	volume_row.add_child(_volume)

	_mute = CheckButton.new()
	_mute.text = "Mute"
	_mute.toggled.connect(func(on: bool) -> void: mute_toggled.emit(on))
	column.add_child(_mute)

	var to_menu: Button = Button.new()
	to_menu.text = "Quit to Menu"
	to_menu.pressed.connect(func() -> void: quit_to_menu_requested.emit())
	column.add_child(to_menu)

	var to_desktop: Button = Button.new()
	to_desktop.text = "Quit to Desktop"
	to_desktop.pressed.connect(func() -> void: quit_to_desktop_requested.emit())
	column.add_child(to_desktop)


## Called by the router when it opens the menu, so keyboard and gamepad
## navigation starts somewhere harmless.
func focus_first() -> void:
	_resume_button.grab_focus()


## Pushes the loaded settings into the controls without re-emitting:
## set_value_no_signal, or opening the menu would look like a change and
## write the file back on every pause.
func show_settings(volume: float, muted: bool) -> void:
	_volume.set_value_no_signal(volume)
	_mute.set_pressed_no_signal(muted)
