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


func _solid(size: Vector2i, c: Color) -> Image:
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func test_it_quantizes_every_pixel_onto_the_palette() -> void:
	var img: Image = _solid(Vector2i(4, 4), Color("33462a"))
	var out: Image = _m.quantize_image(img)
	assert_eq(out.get_size(), Vector2i(4, 4), "size is preserved")
	for y: int in range(4):
		for x: int in range(4):
			assert_eq(out.get_pixel(x, y).to_html(false), "25562e",
				"pixel %d,%d is on the palette" % [x, y])


func test_the_source_image_is_not_modified() -> void:
	var img: Image = _solid(Vector2i(2, 2), Color("33462a"))
	var _out: Image = _m.quantize_image(img)
	assert_eq(img.get_pixel(0, 0).to_html(false), "33462a",
		"quantize_image returns a new image and leaves its input alone")


func test_alpha_is_binarized() -> void:
	var img: Image = Image.create(4, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color("33462a", 0.0))    # fully transparent
	img.set_pixel(1, 0, Color("33462a", 0.4))    # below the threshold
	img.set_pixel(2, 0, Color("33462a", 0.6))    # at or above it
	img.set_pixel(3, 0, Color("33462a", 1.0))    # fully opaque
	var out: Image = _m.quantize_image(img)
	assert_eq(out.get_pixel(0, 0).a8, 0, "transparent stays transparent")
	assert_eq(out.get_pixel(1, 0).a8, 0, "below threshold becomes transparent")
	assert_eq(out.get_pixel(2, 0).a8, 255, "at threshold becomes opaque")
	assert_eq(out.get_pixel(3, 0).a8, 255, "opaque stays opaque")


func test_transparent_pixels_are_not_colour_mapped() -> void:
	# A fully transparent pixel is invisible, so mapping its RGB would spend
	# a report entry on a colour nobody can see.
	var img: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color("ff00ff", 0.0))
	var out: Image = _m.quantize_image(img)
	assert_eq(out.get_pixel(0, 0).a8, 0, "still transparent")
	assert_eq(_m.last_report().size(), 0, "no report entry for an invisible pixel")


func test_quantizing_is_idempotent() -> void:
	# Re-running the pipeline must not drift the committed assets.
	var img: Image = _solid(Vector2i(3, 3), Color("33462a"))
	var once: Image = _m.quantize_image(img)
	var twice: Image = _m.quantize_image(once)
	assert_eq(once.get_data(), twice.get_data(), "quantizing twice changes nothing")


func test_the_report_counts_pixels_per_source_colour() -> void:
	var img: Image = Image.create(3, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color("33462a"))
	img.set_pixel(1, 0, Color("33462a"))
	img.set_pixel(2, 0, Color("808080"))
	var _out: Image = _m.quantize_image(img)
	var report: Array[Dictionary] = _m.last_report()
	assert_eq(report.size(), 2, "one entry per distinct source colour")
	# Sorted by count descending, so the biggest offender reads first.
	assert_eq(report[0]["from"], "33462a", "most common source colour first")
	assert_eq(report[0]["count"], 2, "counted twice")
	assert_eq(report[0]["to"], "25562e", "mapped target")
	assert_eq(report[0]["ramp"], "green", "target ramp")
	assert_eq(report[1]["from"], "808080", "the rarer colour second")
	assert_eq(report[1]["count"], 1, "counted once")
