extends SceneTree
## Prints what is actually in the save at user://saves/home.
##
## Exists because the playtest has to confirm claims the screen cannot show:
## facing is persisted but no sprite is directional, and a rabbit's home
## anchor is invisible until it wanders. Read-only; opens nothing for writing.
##
##   ./tools/godot.sh --headless --path . -s tools/dump_save.gd

const FACING_NAMES: Array[String] = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]


func _init() -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	for e: String in registry.load_from_dir("res://data"):
		printerr("content: %s" % e)

	var session: GameSession = GameSession.new()
	if not session.has_save():
		print("No save at %s" % session.save_root)
		quit(1)
		return

	var result: SessionOpenResult = session.open_saved(registry)
	if not result.ok:
		printerr("could not open the save: %s" % result.error)
		quit(1)
		return

	var zone: Zone = result.zone
	var entities: EntityStore = zone.entities
	var player: int = session.player_entity_id
	print("zone '%s'  playtime %.1fs  backup present: %s"
		% [zone.id, session.playtime, session.has_backup()])
	print("player #%d at %s facing %s"
		% [player, entities.get_position(player),
		FACING_NAMES[entities.get_facing(player)]])

	for id: int in entities.ids():
		if id == player:
			continue
		var type_id: int = entities.get_type_id(id)
		var name: String = registry.string_of(type_id)
		if registry.is_placeholder(type_id):
			name += "  (PLACEHOLDER — not in this build)"
		print("  #%d %s at %s  home %s"
			% [id, name, entities.get_position(id), entities.get_home(id)])
	quit(0)
