extends GutTest
## check_palette.sh scans assets/**.png and cannot see a Color literal in
## GDScript. This file is the palette rule's enforcement for UI code.


func _apollo_hexes() -> Dictionary:
	var json: JSON = JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(
		"res://tools/palette/apollo.json")), OK)
	var out: Dictionary = {}
	var ramps: Dictionary = (json.data as Dictionary)["ramps"]
	for ramp: String in ramps:
		for hex: String in (ramps[ramp] as Array):
			out[hex.to_lower()] = true
	return out


func test_the_palette_file_holds_forty_six_colours() -> void:
	# If this ever fails the palette changed, and every colour in UiTheme
	# needs rechecking rather than this assertion relaxing.
	assert_eq(_apollo_hexes().size(), 46)


func test_every_theme_colour_is_on_the_palette() -> void:
	var allowed: Dictionary = _apollo_hexes()
	var declared: Dictionary = UiTheme.colours()
	assert_gt(declared.size(), 0)
	for name: String in declared:
		var c: Color = declared[name]
		assert_true(allowed.has(c.to_html(false).to_lower()),
			"%s is #%s, which is not an Apollo colour" % [name, c.to_html(false)])


func test_build_returns_a_theme_with_the_controls_the_menus_use() -> void:
	var theme: Theme = UiTheme.build()
	assert_not_null(theme)
	assert_true(theme.has_stylebox("normal", "Button"))
	assert_true(theme.has_stylebox("hover", "Button"))
	assert_true(theme.has_stylebox("disabled", "Button"))
	assert_true(theme.has_stylebox("panel", "PanelContainer"))
	assert_true(theme.has_color("font_color", "Button"))
	assert_true(theme.has_color("font_disabled_color", "Button"))
