extends GutTest
## Pins tools/import_manifest.json to data/*.json.
##
## This is the one seam Phase 3c creates where two committed files can
## silently disagree: a rect resized without updating the sprite_rect its
## content definition declares renders the sprite at the wrong size, and
## no other test would notice.

const MANIFEST: String = "res://tools/import_manifest.json"

var _slices: Array = []
var _registry: ContentRegistry


func before_each() -> void:
	_registry = ContentRegistry.new()
	var errs: PackedStringArray = _registry.load_from_dir("res://data")
	assert_eq(errs.size(), 0, "shipped content validates: %s" % ", ".join(errs))

	var f: FileAccess = FileAccess.open(MANIFEST, FileAccess.READ)
	assert_not_null(f, "the manifest is readable")
	if f == null:
		return
	var parser: JSON = JSON.new()
	var err: int = parser.parse(f.get_as_text())
	f.close()
	assert_eq(err, OK, "the manifest parses")
	_slices = parser.data.get("slices", []) if err == OK else []


func test_the_manifest_is_not_empty() -> void:
	assert_gt(_slices.size(), 0, "at least one slice is declared")


func test_every_slice_names_a_readable_source() -> void:
	for s: Dictionary in _slices:
		var path: String = "res://assets/_source/%s" % str(s["source"])
		assert_true(FileAccess.file_exists(path), "source exists: %s" % path)


func test_every_rect_is_positive() -> void:
	for s: Dictionary in _slices:
		var r: Array = s["rect"]
		assert_eq(r.size(), 4, "%s rect is [x, y, w, h]" % str(s["out"]))
		assert_gt(int(r[2]), 0, "%s width is positive" % str(s["out"]))
		assert_gt(int(r[3]), 0, "%s height is positive" % str(s["out"]))


func test_every_output_is_claimed_by_exactly_one_slice() -> void:
	var seen: Dictionary = {}
	for s: Dictionary in _slices:
		var out: String = str(s["out"])
		assert_false(seen.has(out), "%s is produced by only one slice" % out)
		seen[out] = true


func test_every_output_is_referenced_by_a_content_definition() -> void:
	# An asset nothing draws is dead weight, and more likely a typo in a
	# sprite path than a deliberate spare.
	var sprites: Dictionary = {}
	for sid: String in _registry.all_string_ids():
		var def: Dictionary = _registry.def_of(_registry.numeric_of(sid))
		var sprite: String = str(def.get("sprite", ""))
		if not sprite.is_empty():
			sprites[sprite] = sid
	for s: Dictionary in _slices:
		var res_path: String = "res://%s" % str(s["out"])
		assert_true(sprites.has(res_path),
			"%s is named by a content definition" % res_path)


func test_every_content_sprite_is_produced_by_the_manifest() -> void:
	# The other direction: a definition pointing at art the pipeline does
	# not generate is how a dangling sprite reference survives, which is
	# the bug rabbit.json had before Phase 3b.
	var outs: Dictionary = {}
	for s: Dictionary in _slices:
		outs["res://%s" % str(s["out"])] = true
	for sid: String in _registry.all_string_ids():
		var def: Dictionary = _registry.def_of(_registry.numeric_of(sid))
		var sprite: String = str(def.get("sprite", ""))
		if sprite.is_empty():
			continue
		assert_true(outs.has(sprite), "%s (%s) is produced by the manifest" % [sprite, sid])


func test_declared_sprite_rects_match_the_slice_sizes() -> void:
	# The seam this whole file exists for.
	var by_out: Dictionary = {}
	for s: Dictionary in _slices:
		by_out["res://%s" % str(s["out"])] = s
	for sid: String in _registry.all_string_ids():
		var def: Dictionary = _registry.def_of(_registry.numeric_of(sid))
		var sprite: String = str(def.get("sprite", ""))
		if not def.has("sprite_rect") or not by_out.has(sprite):
			continue
		var declared: Array = def["sprite_rect"]
		var slice_rect: Array = by_out[sprite]["rect"]
		assert_eq(int(declared[2]), int(slice_rect[2]),
			"%s: sprite_rect width matches the slice" % sid)
		assert_eq(int(declared[3]), int(slice_rect[3]),
			"%s: sprite_rect height matches the slice" % sid)


func test_every_erase_rect_explains_itself() -> void:
	# Same rule as a palette override: erasing part of the source is a
	# judgement call, and one with no reason attached is indistinguishable
	# from a mistake later.
	for s: Dictionary in _slices:
		if not s.has("erase"):
			continue
		assert_false(str(s.get("erase_why", "")).strip_edges().is_empty(),
			"%s: erase rects have an erase_why" % str(s["out"]))
		for r: Variant in s["erase"]:
			assert_eq((r as Array).size(), 4,
				"%s: erase rect is [x, y, w, h]" % str(s["out"]))
