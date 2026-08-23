extends Node2D
## Placeholder entry point. Phase 3 replaces this with ZoneRenderer.
## Lives in presentation/ because it is a Godot node.

func _ready() -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	var errs: PackedStringArray = registry.load_from_dir("res://data")
	if not errs.is_empty():
		push_error("content failed to load: %s" % ", ".join(errs))
	print("RP1 booted with %d content definitions" % registry.all_string_ids().size())
