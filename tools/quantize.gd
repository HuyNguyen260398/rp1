extends SceneTree
## Derives assets/ from assets/_source/.
##
## Build-time only, never shipped. Run:
##   ./tools/godot.sh --headless --path . -s tools/quantize.gd
##
## For every slice in tools/import_manifest.json: crop the rect out of the
## source sheet, cut its chroma key and any declared erase rects, map it
## onto Apollo, binarize alpha, write the PNG. Then print a mapping report,
## which is how a colour that crossed a ramp gets noticed and pinned in
## tools/palette_overrides.json.
##
## Re-running is safe and produces byte-identical output: quantizing is
## idempotent and nothing here depends on iteration order.

const MANIFEST: String = "res://tools/import_manifest.json"
const PALETTE: String = "res://tools/palette/apollo.json"
const OVERRIDES: String = "res://tools/palette_overrides.json"
const SOURCE_ROOT: String = "res://assets/_source/"


func _init() -> void:
	var map: PaletteMap = PaletteMap.new()
	var errs: PackedStringArray = map.load_palette(PALETTE)
	errs.append_array(map.load_overrides(OVERRIDES))
	if not errs.is_empty():
		for e: String in errs:
			printerr("palette: %s" % e)
		quit(1)
		return

	var slices: Array = _read_slices()
	if slices.is_empty():
		printerr("no slices in %s" % MANIFEST)
		quit(1)
		return

	var totals: Dictionary = {}
	var written: int = 0
	for s: Dictionary in slices:
		if not _write_slice(map, s, totals):
			quit(1)
			return
		written += 1

	_print_report(map, totals)
	print("quantize: wrote %d asset(s) from %d source sheet(s)" % [
		written, _distinct_sources(slices)])
	quit(0)


func _read_slices() -> Array:
	if not FileAccess.file_exists(MANIFEST):
		printerr("manifest not found: %s" % MANIFEST)
		return []
	var f: FileAccess = FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		printerr("cannot open manifest: %s" % MANIFEST)
		return []
	var text: String = f.get_as_text()
	f.close()
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		printerr("manifest is not valid JSON: %s at line %d" % [
			parser.get_error_message(), parser.get_error_line()])
		return []
	return parser.data.get("slices", [])


func _write_slice(map: PaletteMap, s: Dictionary, totals: Dictionary) -> bool:
	var src_path: String = SOURCE_ROOT + str(s["source"])
	# Image.load_from_file rather than load(): assets/_source/ carries a
	# .gdignore, so the engine never imported these files and
	# ResourceLoader cannot see them. That is deliberate -- it keeps the
	# sources out of the exported PCK. The engine warns that this "will not
	# work on export", which is correct and irrelevant: this script only
	# ever runs under -s at build time.
	var sheet: Image = Image.load_from_file(src_path)
	if sheet == null:
		printerr("cannot read source: %s" % src_path)
		return false

	var r: Array = s["rect"]
	var rect: Rect2i = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	if not Rect2i(Vector2i.ZERO, sheet.get_size()).encloses(rect):
		printerr("%s: rect %s is outside %s (%dx%d)" % [
			str(s["out"]), str(rect), src_path, sheet.get_width(), sheet.get_height()])
		return false

	var cropped: Image = sheet.get_region(rect)
	# Chroma key and erase rects first: they are properties of the source
	# format, and a pixel that is about to be cut must not reach the
	# mapping report as if it were art.
	var cut: Image = PaletteMap.cut_transparent(
		cropped, str(s.get("transparent", "")), s.get("erase", []))
	var quantized: Image = map.quantize_image(cut)

	for row: Dictionary in map.last_report():
		var key: String = str(row["from"])
		if not totals.has(key):
			totals[key] = {"to": row["to"], "ramp": row["ramp"], "count": 0}
		totals[key]["count"] = int(totals[key]["count"]) + int(row["count"])

	var out_path: String = "res://%s" % str(s["out"])
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var err: int = quantized.save_png(out_path)
	if err != OK:
		printerr("cannot write %s: %d" % [out_path, err])
		return false
	print("  %s  %dx%d  <- %s %s" % [
		str(s["out"]), rect.size.x, rect.size.y, str(s["source"]), str(r)])
	return true


func _distinct_sources(slices: Array) -> int:
	var seen: Dictionary = {}
	for s: Dictionary in slices:
		seen[str(s["source"])] = true
	return seen.size()


## Every distinct source colour across every slice, biggest first.
##
## This is the artifact a human reads. A row whose ramp looks wrong for the
## thing being drawn -- a trunk shadow in Neutral, say -- is a candidate
## for tools/palette_overrides.json.
func _print_report(map: PaletteMap, totals: Dictionary) -> void:
	var rows: Array = []
	for src: String in totals:
		rows.append({
			"from": src,
			"to": totals[src]["to"],
			"ramp": totals[src]["ramp"],
			"count": totals[src]["count"],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["count"] != b["count"]:
			return a["count"] > b["count"]
		return a["from"] < b["from"])

	var total: int = 0
	for row: Dictionary in rows:
		total += int(row["count"])
	print("")
	print("mapping report -- %d distinct source colours, %d visible pixels" % [
		rows.size(), total])
	print("  %-9s %-9s %-8s %8s  %s" % ["source", "apollo", "ramp", "pixels", "share"])
	for row: Dictionary in rows:
		print("  #%-8s #%-8s %-8s %8d  %5.2f%%" % [
			row["from"], row["to"], row["ramp"], row["count"],
			100.0 * float(row["count"]) / float(total)])
	print("")
