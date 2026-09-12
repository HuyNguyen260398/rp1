class_name ZoneLoader
extends RefCounted
## Turns an authored zone directory into a Zone.
##
## The format is one PNG per tile column, one pixel per tile, with a
## per-layer colour -> string-id legend in zone.json. This is the only
## file that knows that; tools/check_zone.gd calls it rather than reading
## the PNGs itself, so a rule cannot drift between the gate and the game.
##
## Note what is NOT read here. There is no floor map: floor is Stage 2's
## player-placed layer, and Walkability deliberately does not consult it,
## so a path authored as floor over water would come out unwalkable with
## nothing to flag it. Omitting the map makes that inexpressible. And
## `flags` is derived by Walkability, never authored -- setting flags from
## terrain alone is what once left oaks standing on walkable tiles.

const SCHEMA_PATH: String = "res://data/schema/zone.json"

## Distinct problems reported per map before truncating, matching
## MAX_REPORTED in tools/check_palette.gd. A PNG saved in the wrong colour
## mode yields one error per pixel, and a 16,384-line CI log is the same
## as no CI log.
const MAX_REPORTED: int = 8


static func load_zone(dir: String, registry: ContentRegistry) -> ZoneLoadResult:
	var result: ZoneLoadResult = ZoneLoadResult.new()

	var doc: Dictionary = _read_json(dir.path_join("zone.json"), result.errors)
	if doc.is_empty():
		return result
	var schema: Dictionary = _read_json(SCHEMA_PATH, result.errors)
	if schema.is_empty():
		return result
	var problems: PackedStringArray = SchemaValidator.validate(doc, schema)
	if not problems.is_empty():
		result.errors.append_array(problems)
		return result

	var size: Vector2i = Vector2i(int(doc["size"][0]), int(doc["size"][1]))
	var zone: Zone = Zone.new(str(doc["id"]), size)
	zone.display_name = str(doc["display_name"])
	zone.biome = str(doc.get("biome", "temperate"))
	zone.generation_seed = int(doc.get("generation_seed", 0))

	var spawn: Array = doc["player_spawn"]
	result.player_spawn = Vector2(float(spawn[0]), float(spawn[1]))

	var maps: Dictionary = doc["maps"]
	if maps.has("terrain"):
		var lookup: Dictionary = _resolve_legend("terrain", doc, registry, result.errors)
		var img: Image = _decode_map(
			dir.path_join(str(maps["terrain"])), size, result.errors)
		if img != null:
			_paint(zone, img, size, lookup, zone.set_terrain, "terrain", result.errors)

	result.zone = zone
	return result


## Mirrors ContentRegistry._read_json: the instance JSON API rather than the
## static helper, which pushes an engine-level error on malformed input.
static func _read_json(path: String, errors: PackedStringArray) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s: cannot open" % path)
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parser: JSON = JSON.new()
	var err: int = parser.parse(text)
	if err != OK:
		errors.append("%s: malformed JSON at line %d: %s"
			% [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if not (parser.data is Dictionary):
		errors.append("%s: top level must be an object" % path)
		return {}
	return parser.data as Dictionary


## Colour key -> numeric content id, for one layer.
##
## An id this build does not have becomes a placeholder plus an error. That
## is the Stage 1 design 6.4 policy, and it matters here: Walkability treats
## a placeholder as non-blocking, so missing content leaves a walkable gap
## rather than an impassable hole in the middle of the world.
static func _resolve_legend(layer: String, doc: Dictionary,
		registry: ContentRegistry, errors: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var legend: Dictionary = doc["legend"].get(layer, {})
	for hex: String in legend:
		if hex.length() != 6 or not hex.is_valid_hex_number(false):
			errors.append("legend %s: '%s' is not a six-digit RRGGBB hex colour"
				% [layer, hex])
			continue
		var key: int = hex.hex_to_int()
		var value: Variant = legend[hex]
		if value == null:
			out[key] = ContentRegistry.ID_UNKNOWN
			continue
		var string_id: String = str(value)
		if registry.has_string(string_id):
			out[key] = registry.numeric_of(string_id)
		else:
			out[key] = registry.register_placeholder(string_id)
			errors.append("legend %s: '%s' is not in this build; using a placeholder"
				% [layer, string_id])
	return out


## Reads the committed bytes, never the engine's imported copy.
##
## Image.load_from_file would also work at build time, but this runs inside
## the shipped game, where there is no file on disk to read -- only the
## bytes in the pack. FileAccess plus load_png_from_buffer works in both.
static func _decode_map(path: String, expect: Vector2i,
		errors: PackedStringArray) -> Image:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		errors.append("%s: cannot be read" % path)
		return null
	var img: Image = Image.new()
	var err: int = img.load_png_from_buffer(bytes)
	if err != OK:
		errors.append("%s: is not a readable PNG (error %d)" % [path, err])
		return null
	if img.get_size() != expect:
		errors.append("%s: is %dx%d but the zone is %dx%d"
			% [path, img.get_width(), img.get_height(), expect.x, expect.y])
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## Walks raw RGBA bytes rather than calling get_pixel().
##
## get_pixel returns a float Color, and a float round-trip through sRGB is
## exactly how a legend key silently stops matching the pixel it was
## written for. Integer bytes compare exactly.
static func _paint(zone: Zone, img: Image, size: Vector2i, lookup: Dictionary,
		setter: Callable, layer: String, errors: PackedStringArray) -> void:
	var data: PackedByteArray = img.get_data()
	var unknown: Dictionary = {}
	var partial_alpha: int = 0

	for y: int in range(size.y):
		for x: int in range(size.x):
			var i: int = (y * size.x + x) * 4
			if data[i + 3] != 255:
				partial_alpha += 1
				continue
			var key: int = (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
			if not lookup.has(key):
				unknown[key] = unknown.get(key, 0) + 1
				continue
			setter.call(Vector2i(x, y), int(lookup[key]))

	_report_unknown(layer, unknown, errors)
	if partial_alpha > 0:
		errors.append("%s: %d pixel(s) are not fully opaque; a map is an index, not art"
			% [layer, partial_alpha])


static func _report_unknown(layer: String, unknown: Dictionary,
		errors: PackedStringArray) -> void:
	if unknown.is_empty():
		return
	var keys: Array = unknown.keys()
	keys.sort()
	var shown: int = mini(keys.size(), MAX_REPORTED)
	for n: int in range(shown):
		var key: int = keys[n]
		errors.append("%s: #%06x has no legend entry (%d tile(s))"
			% [layer, key, unknown[key]])
	if keys.size() > shown:
		errors.append("%s: ... and %d more colour(s) with no legend entry"
			% [layer, keys.size() - shown])
