extends GutTest
## Pins tools/palette/apollo.json to docs/palette.md.
##
## The palette existed as prose first. A second machine-readable copy is
## only safe if something fails when the two disagree -- otherwise the
## next colour change lands in one of them and nobody notices for a month.

const JSON_PATH: String = "res://tools/palette/apollo.json"
const DOC_PATH: String = "res://docs/palette.md"

var _ramps: Dictionary = {}


func before_each() -> void:
	var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
	assert_not_null(f, "apollo.json is readable")
	if f == null:
		return
	var parser: JSON = JSON.new()
	# JSON.new().parse() rather than JSON.parse_string(): the static helper
	# pushes an engine-level error on bad input, which is log noise and
	# fails the tests that deliberately feed it one. Same reasoning as
	# ContentRegistry.
	var err: int = parser.parse(f.get_as_text())
	f.close()
	assert_eq(err, OK, "apollo.json parses")
	_ramps = parser.data.get("ramps", {}) if err == OK else {}


func _all_colours() -> Array[String]:
	var out: Array[String] = []
	for ramp: String in _ramps:
		for hexs: String in _ramps[ramp]:
			out.append(hexs)
	return out


func test_the_palette_has_forty_six_unique_colours() -> void:
	var all: Array[String] = _all_colours()
	assert_eq(all.size(), 46, "Apollo is 46 colours")
	var unique: Dictionary = {}
	for h: String in all:
		unique[h] = true
	assert_eq(unique.size(), 46, "no colour appears twice")


func test_every_colour_is_lowercase_six_digit_hex_without_a_hash() -> void:
	var re: RegEx = RegEx.create_from_string("^[0-9a-f]{6}$")
	for h: String in _all_colours():
		assert_not_null(re.search(h), "%s is bare lowercase hex" % h)


func test_the_json_and_the_documentation_agree() -> void:
	# docs/palette.md contains exactly the 46 palette colours and no other
	# hex codes -- sections 3 and 4 both draw from the same set. So set
	# equality is the assertion, not subset.
	var f: FileAccess = FileAccess.open(DOC_PATH, FileAccess.READ)
	assert_not_null(f, "docs/palette.md is readable")
	if f == null:
		return
	var doc: String = f.get_as_text()
	f.close()

	var in_doc: Dictionary = {}
	var re: RegEx = RegEx.create_from_string("#([0-9a-fA-F]{6})\\b")
	for m: RegExMatch in re.search_all(doc):
		in_doc[m.get_string(1).to_lower()] = true

	var in_json: Dictionary = {}
	for h: String in _all_colours():
		in_json[h] = true

	var missing_from_doc: Array = []
	for h: String in in_json:
		if not in_doc.has(h):
			missing_from_doc.append(h)
	var missing_from_json: Array = []
	for h: String in in_doc:
		if not in_json.has(h):
			missing_from_json.append(h)

	missing_from_doc.sort()
	missing_from_json.sort()
	assert_eq(missing_from_doc, [], "colours in apollo.json but not in palette.md")
	assert_eq(missing_from_json, [], "colours in palette.md but not in apollo.json")


func test_the_outline_colour_is_in_the_palette() -> void:
	var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
	var parser: JSON = JSON.new()
	var _e: int = parser.parse(f.get_as_text())
	f.close()
	var outline: String = str(parser.data.get("outline", ""))
	# palette.md section 4 fixes the outline as the darkest blue, not the
	# darkest neutral: a blue-black outline keeps outdoor art from reading
	# as sooty.
	assert_eq(outline, "172038", "outline is the darkest blue")
	assert_true(_all_colours().has(outline), "the outline is a palette colour")
