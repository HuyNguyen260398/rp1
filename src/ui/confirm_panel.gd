class_name ConfirmPanel
extends Control
## An in-scene confirm/report panel.
##
## Not Godot's ConfirmationDialog, which spawns a native OS window: it
## behaves badly fullscreen and tools/screenshot.gd cannot capture it.

signal confirmed
signal dismissed

var _title: Label = null
var _body: Label = null
var _buttons: HBoxContainer = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(UiTheme.BACKGROUND, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel: PanelContainer = PanelContainer.new()
	centre.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.custom_minimum_size = Vector2(420, 0)
	panel.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	column.add_child(_title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(420, 0)
	column.add_child(_body)

	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 12)
	column.add_child(_buttons)


func _clear_buttons() -> void:
	for child: Node in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()


func _add_button(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	_buttons.add_child(b)
	return b


## Two buttons. Cancel takes focus, so a stray Enter never destroys a world.
func ask(title: String, body: String, confirm_label: String) -> void:
	_title.text = title
	_body.text = body
	_clear_buttons()
	var confirm: Button = _add_button(confirm_label)
	var cancel: Button = _add_button("Cancel")
	confirm.pressed.connect(func() -> void:
		visible = false
		confirmed.emit())
	cancel.pressed.connect(func() -> void:
		visible = false
		dismissed.emit())
	visible = true
	cancel.grab_focus()


## One button. Used to report a failure the player can only acknowledge.
func report(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_clear_buttons()
	var ok: Button = _add_button("OK")
	ok.pressed.connect(func() -> void:
		visible = false
		dismissed.emit())
	visible = true
	ok.grab_focus()
