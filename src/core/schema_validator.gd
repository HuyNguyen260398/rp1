class_name SchemaValidator
extends RefCounted
## Validates a content definition against a category schema.
##
## Godot has no JSON Schema support, and the project does not need one: the
## rules that matter are required fields, field types, unknown fields, and a
## category match.

static func _type_matches(value: Variant, expected: String) -> bool:
	match expected:
		"String":
			return value is String
		"bool":
			return value is bool
		"int":
			# JSON.parse_string yields floats for every number, so an
			# integral float is a valid int; 16.5 is not.
			if value is int:
				return true
			return value is float and is_equal_approx(value, roundf(value))
		"float":
			return value is float or value is int
		"Array":
			return value is Array
		"Dictionary":
			return value is Dictionary
		_:
			return false


static func validate(def: Dictionary, schema: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	var required: Dictionary = schema.get("required", {})
	var optional: Dictionary = schema.get("optional", {})
	var def_id: String = str(def.get("id", "<no id>"))

	for field: String in required:
		if not def.has(field):
			errors.append("%s: missing required field '%s'" % [def_id, field])
		elif not _type_matches(def[field], required[field]):
			errors.append(
				"%s: field '%s' must be %s" % [def_id, field, required[field]]
			)

	for field: String in optional:
		if def.has(field) and not _type_matches(def[field], optional[field]):
			errors.append("%s: field '%s' must be %s" % [def_id, field, optional[field]])

	for field: String in def:
		if not required.has(field) and not optional.has(field):
			errors.append("%s: unknown field '%s'" % [def_id, field])

	if schema.has("category") and def.get("category", "") != schema["category"]:
		errors.append(
			"%s: category must be '%s', got '%s'"
			% [def_id, schema["category"], str(def.get("category", ""))]
		)

	return errors
