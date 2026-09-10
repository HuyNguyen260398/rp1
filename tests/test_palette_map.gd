extends GutTest

const PALETTE: String = "res://tools/palette/apollo.json"

var _m: PaletteMap


func before_each() -> void:
	_m = PaletteMap.new()
	var errs: PackedStringArray = _m.load_palette(PALETTE)
	assert_eq(errs.size(), 0, "palette loads: %s" % ", ".join(errs))


func test_it_loads_forty_six_colours() -> void:
	assert_eq(_m.size(), 46, "the whole palette is loaded")


func test_a_palette_colour_maps_to_itself() -> void:
	# Idempotence. Quantizing already-quantized art must be a no-op, or
	# re-running the pipeline would drift the assets a little every time.
	for hexs: String in ["7a4841", "75a743", "4f8fba", "172038", "ebede9"]:
		var c: Color = Color(hexs)
		assert_eq(_m.nearest(c).to_html(false), hexs, "#%s maps to itself" % hexs)


func test_known_colours_map_to_the_expected_step() -> void:
	# Verified against the Apollo values in OKLab.
	var cases: Dictionary = {
		"ff0000": "cf573c",  # pure red -> the Red ramp's light step
		"000000": "090a14",  # pure black -> the darkest neutral
		"ffffff": "ebede9",  # pure white -> the lightest neutral
		"808080": "819796",  # mid grey -> a cool grey-green, never pure grey
		"33462a": "25562e",  # an Elin meadow green -> the Green ramp
		"c0ffc0": "d0da91",  # pale mint -> the lightest green
	}
	for src: String in cases:
		assert_eq(_m.nearest(Color(src)).to_html(false), cases[src],
			"#%s maps to #%s" % [src, cases[src]])


func test_it_reports_the_ramp() -> void:
	assert_eq(_m.ramp_of(Color("33462a")), "green", "meadow green is in the Green ramp")
	assert_eq(_m.ramp_of(Color("808080")), "neutral", "grey is in the Neutral ramp")
	assert_eq(_m.ramp_of(Color("ff0000")), "red", "red is in the Red ramp")


func test_exact_membership_is_not_nearest() -> void:
	# The gate needs "is this pixel literally on the palette", which is a
	# different question from "what is closest". A near-miss must fail.
	assert_true(_m.has_colour(Color("75a743")), "an exact palette colour")
	assert_false(_m.has_colour(Color("75a744")), "one digit off is not on the palette")


func test_mapping_is_deterministic() -> void:
	# Two instances must agree, or committed assets would depend on
	# dictionary iteration order and the pipeline would not be reproducible.
	var other: PaletteMap = PaletteMap.new()
	var _e: PackedStringArray = other.load_palette(PALETTE)
	for hexs: String in ["33462a", "808080", "c0ffc0", "2b2b2b", "ff00ff"]:
		assert_eq(_m.nearest(Color(hexs)).to_html(false),
			other.nearest(Color(hexs)).to_html(false),
			"#%s maps identically across instances" % hexs)


func test_a_missing_palette_file_reports_an_error_rather_than_crashing() -> void:
	var m: PaletteMap = PaletteMap.new()
	var errs: PackedStringArray = m.load_palette("res://tools/palette/nope.json")
	assert_gt(errs.size(), 0, "a missing file is an error, not a crash")
	assert_eq(m.size(), 0, "nothing was loaded")


func test_an_override_beats_the_nearest_colour() -> void:
	# 33462a's nearest is 25562e (asserted above). An override must win.
	var path: String = "user://test_overrides.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"overrides": [{"from": "33462a", "to": "19332d", "why": "test"}]}')
	f.close()

	var errs: PackedStringArray = _m.load_overrides(path)
	assert_eq(errs.size(), 0, "overrides load: %s" % ", ".join(errs))
	assert_eq(_m.nearest(Color("33462a")).to_html(false), "19332d",
		"the override wins over the nearest colour")
	assert_eq(_m.nearest(Color("808080")).to_html(false), "819796",
		"an unlisted colour is unaffected")


func test_an_override_to_a_non_palette_colour_is_rejected() -> void:
	# An override is a choice between palette steps, never a way to smuggle
	# a forty-seventh colour past the gate.
	var path: String = "user://bad_overrides.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"overrides": [{"from": "33462a", "to": "ff00ff", "why": "test"}]}')
	f.close()

	var errs: PackedStringArray = _m.load_overrides(path)
	assert_gt(errs.size(), 0, "an off-palette target is an error")
	assert_eq(_m.nearest(Color("33462a")).to_html(false), "25562e",
		"the rejected override did not take effect")


func test_an_override_must_explain_itself() -> void:
	var path: String = "user://why_overrides.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"overrides": [{"from": "33462a", "to": "19332d"}]}')
	f.close()

	var errs: PackedStringArray = _m.load_overrides(path)
	assert_gt(errs.size(), 0, "an override without a reason is an error")


func test_a_missing_override_file_is_not_an_error() -> void:
	# Overrides are optional. A pipeline with none is the healthy case.
	var m: PaletteMap = PaletteMap.new()
	var _e: PackedStringArray = m.load_palette(PALETTE)
	var errs: PackedStringArray = m.load_overrides("res://tools/nope.json")
	assert_eq(errs.size(), 0, "absent overrides are fine")
