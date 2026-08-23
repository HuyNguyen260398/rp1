class_name IdMap
extends RefCounted
## The string_id -> numeric_id mapping in force when a save was written.
##
## Saves store string ids because numeric ids are assigned at boot and shift
## whenever content is added. On load this map is turned into a translation
## table from saved numeric ids to current ones. Without it, adding a single
## tile type would corrupt every existing world.

var _entries: Dictionary = {}  ## String -> int


func entries() -> Dictionary:
	return _entries.duplicate()


func set_entry(string_id: String, numeric_id: int) -> void:
	_entries[string_id] = numeric_id


static func from_registry(registry: ContentRegistry) -> IdMap:
	var m: IdMap = IdMap.new()
	for sid: String in registry.all_string_ids():
		m.set_entry(sid, registry.numeric_of(sid))
	return m


func to_json_string() -> String:
	return JSON.stringify(_entries, "  ", true)


static func from_json_string(text: String) -> DecodeResult:
	# Instance API, not JSON.parse_string() -- see the note in
	# ContentRegistry._read_json. The static helper pushes an engine error
	# that GUT counts as a test failure.
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return DecodeResult.failure(
			"id_map: malformed JSON at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return DecodeResult.failure("id_map: malformed JSON")
	var m: IdMap = IdMap.new()
	for sid: Variant in parsed:
		# JSON numbers arrive as floats.
		m.set_entry(str(sid), int(parsed[sid]))
	return DecodeResult.success(m)


## Builds a lookup where index = saved numeric id, value = current numeric id.
## Content the current build no longer defines is registered as a placeholder
## so the original string survives a resave.
func build_translation(registry: ContentRegistry) -> PackedInt32Array:
	var highest: int = 0
	for sid: String in _entries:
		highest = maxi(highest, _entries[sid])

	var table: PackedInt32Array = PackedInt32Array()
	table.resize(highest + 1)
	table.fill(ContentRegistry.ID_UNKNOWN)

	for sid: String in _entries:
		var saved: int = _entries[sid]
		if registry.has_string(sid):
			table[saved] = registry.numeric_of(sid)
		else:
			table[saved] = registry.register_placeholder(sid)

	table[0] = ContentRegistry.ID_UNKNOWN
	return table
