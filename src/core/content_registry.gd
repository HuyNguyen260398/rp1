class_name ContentRegistry
extends RefCounted
## Loads all game content from JSON and assigns numeric runtime ids.
##
## Numeric ids are assigned in sorted string order so the same content always
## produces the same mapping. Saves persist the string ids, not these
## numbers -- see IdMap.

const ID_UNKNOWN: int = 0
const CATEGORIES: PackedStringArray = ["terrain", "object", "creature"]

var _defs: Dictionary = {}          ## numeric_id -> Dictionary
var _numeric_by_string: Dictionary = {}
var _string_by_numeric: Dictionary = {}
var _placeholders: Dictionary = {}  ## numeric_id -> true
var _next_numeric: int = 1


func all_string_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for sid: String in _numeric_by_string:
		out.append(sid)
	out.sort()
	return out


func has_string(string_id: String) -> bool:
	return _numeric_by_string.has(string_id)


func numeric_of(string_id: String) -> int:
	return _numeric_by_string.get(string_id, ID_UNKNOWN)


func string_of(numeric_id: int) -> String:
	return _string_by_numeric.get(numeric_id, "")


func def_of(numeric_id: int) -> Dictionary:
	return _defs.get(numeric_id, {})


func is_placeholder(numeric_id: int) -> bool:
	return _placeholders.has(numeric_id)


func register(def: Dictionary) -> int:
	var string_id: String = str(def["id"])
	if _numeric_by_string.has(string_id):
		return _numeric_by_string[string_id]
	var numeric: int = _next_numeric
	_next_numeric += 1
	_numeric_by_string[string_id] = numeric
	_string_by_numeric[numeric] = string_id
	_defs[numeric] = def
	return numeric


## Allocates an id for content named in a save but absent from this build.
## The original string is retained so the save round-trips losslessly.
func register_placeholder(string_id: String) -> int:
	if _numeric_by_string.has(string_id):
		return _numeric_by_string[string_id]
	var numeric: int = register({
		"id": string_id,
		"category": "unknown",
		"display_name": "Unknown (%s)" % string_id,
		"sprite": "",
	})
	_placeholders[numeric] = true
	return numeric


func _read_json(path: String, errors: PackedStringArray) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s: cannot open" % path)
		return null
	var text: String = f.get_as_text()
	f.close()

	# JSON.new().parse() rather than the static JSON.parse_string(): the
	# static helper pushes an engine-level error on malformed input, which
	# is noise in the log and fails the test that deliberately feeds it bad
	# JSON. The instance API returns an error code quietly and carries the
	# message and line number, which makes a better report anyway.
	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		errors.append(
			"%s: malformed JSON at line %d: %s"
			% [path, json.get_error_line(), json.get_error_message()]
		)
		return null
	return json.data


func load_from_dir(root: String) -> PackedStringArray:
	var errors: PackedStringArray = []

	for category: String in CATEGORIES:
		var cat_dir: String = root.path_join(category)
		if not DirAccess.dir_exists_absolute(cat_dir):
			continue

		var schema_path: String = root.path_join("schema").path_join("%s.json" % category)
		var schema: Variant = _read_json(schema_path, errors)
		if not (schema is Dictionary):
			errors.append("%s: missing or invalid schema" % schema_path)
			continue

		# Sorted so numeric assignment is deterministic.
		var files: PackedStringArray = DirAccess.get_files_at(cat_dir)
		files.sort()
		for file_name: String in files:
			if not file_name.ends_with(".json"):
				continue
			var path: String = cat_dir.path_join(file_name)
			var def: Variant = _read_json(path, errors)
			if not (def is Dictionary):
				continue
			var problems: PackedStringArray = SchemaValidator.validate(def, schema)
			if problems.size() > 0:
				for p: String in problems:
					errors.append("%s: %s" % [path, p])
				continue
			var _numeric: int = register(def)

	return errors
