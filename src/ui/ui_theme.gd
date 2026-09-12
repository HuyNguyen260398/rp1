class_name UiTheme
extends RefCounted
## The one place in the project a UI Color is written.
##
## check_palette.sh scans assets/**.png and cannot see a Color literal, so
## tests/test_ui_theme.gd asserts every constant here is one of Apollo's 46.
## Adding a colour anywhere else under src/ui/ escapes both.
##
## Phase 6 replaces the insides of build() -- a real pixel font, 9-slice
## panels -- without any menu script changing.

const BACKGROUND: Color = Color("10141f")      # neutral 2
const PANEL: Color = Color("202e37")           # neutral 4
const BORDER: Color = Color("577277")          # neutral 6
const TEXT: Color = Color("c7cfcc")            # neutral 9
const TEXT_DIM: Color = Color("819796")        # neutral 7
const TEXT_DISABLED: Color = Color("394a50")   # neutral 5
const ACCENT: Color = Color("de9e41")          # gold 5
const DANGER: Color = Color("a53030")          # red 4

const FONT_SIZE: int = 16
const TITLE_FONT_SIZE: int = 32


## Every colour the theme declares, for the palette conformance test.
static func colours() -> Dictionary:
	return {
		"BACKGROUND": BACKGROUND,
		"PANEL": PANEL,
		"BORDER": BORDER,
		"TEXT": TEXT,
		"TEXT_DIM": TEXT_DIM,
		"TEXT_DISABLED": TEXT_DISABLED,
		"ACCENT": ACCENT,
		"DANGER": DANGER,
	}


static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_content_margin_all(12)
	return box


static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font_size = FONT_SIZE

	theme.set_stylebox("normal", "Button", _box(PANEL, BORDER))
	theme.set_stylebox("hover", "Button", _box(PANEL, ACCENT))
	theme.set_stylebox("pressed", "Button", _box(BORDER, ACCENT))
	theme.set_stylebox("focus", "Button", _box(PANEL, ACCENT))
	theme.set_stylebox("disabled", "Button", _box(BACKGROUND, TEXT_DISABLED))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, BORDER))
	theme.set_color("font_color", "Label", TEXT)
	return theme
