class_name SaveManager
extends RefCounted
## Orchestrates zone persistence.
##
## Metadata is JSON because it is small, cold, and worth reading with `cat`.
## Bulk tile and entity data is binary. Every write is atomic: a crash
## mid-save must never leave a half-written world.

const SAVE_VERSION: int = 1


## `keep_backup` renames any existing file to `path + ".bak"` before the new
## one takes its place. The window between the two renames is one rename
## wide, and a crash inside it leaves the .bak intact -- which is what
## load_zone's `use_backup` is for.
static func atomic_write(
	path: String, bytes: PackedByteArray, keep_backup: bool = false
) -> String:
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk: int = DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return "cannot create directory %s (error %d)" % [dir, mk]

	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "cannot open %s (error %d)" % [tmp, FileAccess.get_open_error()]
	f.store_buffer(bytes)
	f.flush()
	f.close()

	if keep_backup and FileAccess.file_exists(path):
		var rot: int = DirAccess.rename_absolute(path, path + ".bak")
		if rot != OK:
			return "cannot rotate %s to .bak (error %d)" % [path, rot]

	var err: int = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "cannot rename %s -> %s (error %d)" % [tmp, path, err]
	return ""


static func _zone_dir(save_root: String, zone_id: String) -> String:
	return save_root.path_join("zones").path_join(zone_id)


## `keep_backup` applies to entities.dat alone: it is the only file an
## autosave rewrites in Stage 1. id_map.json, zone_meta.json and the chunks
## are written once per world, and rotating an unchanged file only doubles
## the disk cost. A Stage 2 that makes chunks mutable must rotate them too.
static func save_zone(
	save_root: String, zone: Zone, registry: ContentRegistry,
	all_chunks: bool = false, keep_backup: bool = false
) -> PackedStringArray:
	var errors: PackedStringArray = []
	var zdir: String = _zone_dir(save_root, zone.id)

	var map_err: String = atomic_write(
		save_root.path_join("id_map.json"),
		IdMap.from_registry(registry).to_json_string().to_utf8_buffer()
	)
	if map_err != "":
		errors.append(map_err)

	var meta: Dictionary = {
		"save_version": SAVE_VERSION,
		"id": zone.id,
		"display_name": zone.display_name,
		"size_x": zone.size_tiles.x,
		"size_y": zone.size_tiles.y,
		"biome": zone.biome,
		"generation_seed": zone.generation_seed,
	}
	var meta_err: String = atomic_write(
		zdir.path_join("zone_meta.json"),
		JSON.stringify(meta, "  ", true).to_utf8_buffer()
	)
	if meta_err != "":
		errors.append(meta_err)

	var targets: Array[Vector2i] = zone.chunk_coords() if all_chunks else zone.dirty_chunk_coords()
	for c: Vector2i in targets:
		var chunk: Chunk = zone.get_chunk(c)
		var err: String = atomic_write(
			zdir.path_join("chunks").path_join("%d_%d.chunk" % [c.x, c.y]),
			ChunkCodec.encode(chunk)
		)
		if err != "":
			errors.append(err)

	var ent_err: String = atomic_write(
		zdir.path_join("entities.dat"), EntityCodec.encode(zone.entities), keep_backup
	)
	if ent_err != "":
		errors.append(ent_err)

	if errors.is_empty():
		zone.clear_dirty()
	return errors


## Rewrites a u16 id column through the translation table in place.
static func _translate_column(column: PackedByteArray, table: PackedInt32Array) -> void:
	for i: int in range(Coords.TILES_PER_CHUNK):
		var saved: int = column.decode_u16(i * 2)
		if saved < table.size():
			column.encode_u16(i * 2, table[saved])
		else:
			column.encode_u16(i * 2, ContentRegistry.ID_UNKNOWN)


## `use_backup` reads entities.dat.bak instead of entities.dat. Chunks have
## no backup because nothing rewrites them yet; see save_zone.
static func load_zone(
	save_root: String, zone_id: String, registry: ContentRegistry,
	use_backup: bool = false
) -> DecodeResult:
	var zdir: String = _zone_dir(save_root, zone_id)
	var meta_path: String = zdir.path_join("zone_meta.json")
	if not FileAccess.file_exists(meta_path):
		return DecodeResult.failure("zone '%s': no zone_meta.json at %s" % [zone_id, zdir])

	var meta_json: JSON = JSON.new()
	if meta_json.parse(FileAccess.get_file_as_string(meta_path)) != OK:
		return DecodeResult.failure("zone '%s': malformed zone_meta.json" % zone_id)
	var meta: Variant = meta_json.data
	if not (meta is Dictionary):
		return DecodeResult.failure("zone '%s': malformed zone_meta.json" % zone_id)

	var map_path: String = save_root.path_join("id_map.json")
	if not FileAccess.file_exists(map_path):
		return DecodeResult.failure("save: no id_map.json; cannot resolve content ids")
	var map_result: DecodeResult = IdMap.from_json_string(FileAccess.get_file_as_string(map_path))
	if not map_result.ok:
		return map_result
	var table: PackedInt32Array = (map_result.value as IdMap).build_translation(registry)

	var zone: Zone = Zone.new(
		str(meta.get("id", zone_id)),
		Vector2i(int(meta.get("size_x", 128)), int(meta.get("size_y", 128)))
	)
	zone.display_name = str(meta.get("display_name", zone.id))
	zone.biome = str(meta.get("biome", "temperate"))
	zone.generation_seed = int(meta.get("generation_seed", 0))

	var chunk_dir: String = zdir.path_join("chunks")
	for file_name: String in DirAccess.get_files_at(chunk_dir):
		if not file_name.ends_with(".chunk"):
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(chunk_dir.path_join(file_name))
		var decoded: DecodeResult = ChunkCodec.decode(bytes)
		if not decoded.ok:
			return DecodeResult.failure("%s: %s" % [file_name, decoded.error])
		var chunk: Chunk = decoded.value
		_translate_column(chunk.terrain_id, table)
		_translate_column(chunk.floor_id, table)
		_translate_column(chunk.object_id, table)
		chunk.dirty = false
		zone.install_chunk(chunk)

	var ent_name: String = "entities.dat.bak" if use_backup else "entities.dat"
	var ent_path: String = zdir.path_join(ent_name)
	if FileAccess.file_exists(ent_path):
		var ent: DecodeResult = EntityCodec.decode(FileAccess.get_file_as_bytes(ent_path))
		if not ent.ok:
			return DecodeResult.failure("entities.dat: %s" % ent.error)
		var store: EntityStore = ent.value
		# Entity type ids are runtime numbers like the tile columns, and
		# shift for the same reason. Remapping the columns and not the rows
		# meant one new creature JSON turned every rabbit in every save
		# into whatever now held its number.
		for entity_id: int in store.ids():
			var saved: int = store.get_type_id(entity_id)
			if saved < table.size():
				store.set_type_id(entity_id, table[saved])
			else:
				store.set_type_id(entity_id, ContentRegistry.ID_UNKNOWN)
		zone.entities = store

	# flags is derived, never authored and never trusted from disk: a save
	# written before a content change carries stale values. Same reasoning
	# as ZoneLoader, which refuses an authored flags column outright.
	Walkability.recompute_zone(zone, registry)
	# The recompute touches every chunk. A freshly loaded world is by
	# definition not in need of saving, and leaving it dirty would make
	# the first autosave rewrite all 16 chunks for nothing.
	zone.clear_dirty()

	return DecodeResult.success(zone)
