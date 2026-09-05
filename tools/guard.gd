extends SceneTree
## Architecture gate for src/core/ and src/systems/.
##
## These folders are the node-free heart of the project. The gate is an
## allowlist of permitted base classes plus a scan for banned identifiers,
## because a blocklist of "extends Node" would silently pass "extends Node2D".

const ALLOWED_BASES: PackedStringArray = ["RefCounted", "Object"]

const BANNED_IDENTIFIERS: PackedStringArray = [
	"get_tree(",
	"Engine.",
	".tscn",
	"get_node(",
	"add_child(",
	"queue_free(",
]

const GUARDED_ROOTS: PackedStringArray = ["res://src/core", "res://src/systems"]


static func _strip_comment(line: String) -> String:
	# Naive but sufficient: these files contain no "#" inside string literals
	# by convention, and a false negative here only relaxes the gate for a
	# line that is genuinely commented out.
	var i: int = line.find("#")
	return line if i == -1 else line.substr(0, i)


static func scan_file(path: String) -> PackedStringArray:
	var violations: PackedStringArray = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		violations.append("%s: cannot open" % path)
		return violations

	var line_no: int = 0
	while not f.eof_reached():
		line_no += 1
		var raw: String = f.get_line()
		var line: String = _strip_comment(raw).strip_edges()
		if line.is_empty():
			continue

		if line.begins_with("extends "):
			var base: String = line.substr(8).strip_edges()
			if not ALLOWED_BASES.has(base):
				violations.append(
					"%s:%d: extends %s (only %s permitted here)"
					% [path, line_no, base, ", ".join(ALLOWED_BASES)]
				)

		for banned: String in BANNED_IDENTIFIERS:
			if line.contains(banned):
				violations.append("%s:%d: banned identifier %s" % [path, line_no, banned])

	f.close()
	return violations


static func scan_dir(root: String) -> PackedStringArray:
	var violations: PackedStringArray = []
	for entry: String in DirAccess.get_directories_at(root):
		violations.append_array(scan_dir(root.path_join(entry)))
	for entry: String in DirAccess.get_files_at(root):
		if entry.ends_with(".gd"):
			violations.append_array(scan_file(root.path_join(entry)))
	return violations


static func scan(roots: PackedStringArray) -> PackedStringArray:
	var violations: PackedStringArray = []
	for root: String in roots:
		if DirAccess.dir_exists_absolute(root):
			violations.append_array(scan_dir(root))
	return violations


func _init() -> void:
	var violations: PackedStringArray = scan(GUARDED_ROOTS)
	for v: String in violations:
		printerr("ARCHITECTURE VIOLATION: ", v)
	if violations.is_empty():
		print("Architecture guard: clean")
		quit(0)
	else:
		printerr("Architecture guard: %d violation(s)" % violations.size())
		quit(1)
