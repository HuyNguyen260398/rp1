extends GutTest

const ArchitectureGuard = preload("res://tools/guard.gd")

var _dir: String = "user://guard_fixture"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))


func _write(name: String, body: String) -> void:
	var f: FileAccess = FileAccess.open(_dir.path_join(name), FileAccess.WRITE)
	f.store_string(body)
	f.close()


func test_refcounted_file_is_clean() -> void:
	_write("ok.gd", "class_name Ok\nextends RefCounted\n\nfunc f() -> int:\n\treturn 1\n")
	var v: PackedStringArray = ArchitectureGuard.scan_dir(_dir)
	assert_eq(v.size(), 0, "a RefCounted file produces no violations")


func test_extends_node2d_is_a_violation() -> void:
	# The precise case a `grep "extends Node"` blocklist would miss.
	_write("bad.gd", "extends Node2D\n")
	var v: PackedStringArray = ArchitectureGuard.scan_dir(_dir)
	assert_eq(v.size(), 1, "extends Node2D is caught")
	assert_string_contains(v[0], "Node2D")


func test_extends_node_is_a_violation() -> void:
	_write("bad.gd", "extends Node\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 1)


func test_get_tree_is_a_violation() -> void:
	_write("bad.gd", "extends RefCounted\n\nfunc f() -> void:\n\tget_tree().quit()\n")
	var v: PackedStringArray = ArchitectureGuard.scan_dir(_dir)
	assert_eq(v.size(), 1, "get_tree() is banned even in a RefCounted file")


func test_engine_singleton_is_a_violation() -> void:
	_write("bad.gd", "extends RefCounted\n\nfunc f() -> int:\n\treturn Engine.get_frames_drawn()\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 1)


func test_scene_preload_is_a_violation() -> void:
	_write("bad.gd", "extends RefCounted\n\nconst S = preload(\"res://scenes/x.tscn\")\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 1)


func test_comments_do_not_trigger_violations() -> void:
	_write("ok.gd", "extends RefCounted\n\n# This class must never extends Node or call get_tree().\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 0, "commented mentions are ignored")


func test_multiple_violations_are_all_reported() -> void:
	_write("bad.gd", "extends Node2D\n\nfunc f() -> void:\n\tget_tree().quit()\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 2)
