class_name TilesetBuilder
extends RefCounted
## Assembles a TileSet from the content registry at runtime.
##
## Runtime assembly rather than an editor-authored .tres is what makes
## "adding a tile type = one JSON file + one PNG, no code change" true. An
## editor-authored TileSet would have to be hand-edited for every new
## definition, which is a code change in all but name.
##
## TileSet, TileSetAtlasSource and TileData are Resource types, not nodes,
## so this file stays inside the src/systems/ node-free rule and can be
## unit-tested directly.

const TILE_SIZE: Vector2i = Vector2i(32, 32)

## Categories that become tiles. Creatures are entities, not cells.
const TILE_CATEGORIES: PackedStringArray = ["terrain", "object"]


static func build(registry: ContentRegistry) -> TilesetBuildResult:
	var result: TilesetBuildResult = TilesetBuildResult.new()
	result.tileset = TileSet.new()
	result.tileset.tile_size = TILE_SIZE

	# Ascending numeric id, so source ids are assigned in a stable order.
	# A non-deterministic mapping would make the renderer untestable.
	var numerics: Array[int] = []
	for string_id: String in registry.all_string_ids():
		numerics.append(registry.numeric_of(string_id))
	numerics.sort()

	for numeric: int in numerics:
		var def: Dictionary = registry.def_of(numeric)
		if not TILE_CATEGORIES.has(str(def.get("category", ""))):
			continue
		var sprite_path: String = str(def.get("sprite", ""))
		if sprite_path.is_empty():
			result.errors.append("%s: no sprite path" % str(def.get("id", numeric)))
			continue
		var tex: Texture2D = load(sprite_path) as Texture2D
		if tex == null:
			result.errors.append("%s: cannot load %s" % [str(def.get("id", numeric)), sprite_path])
			continue

		var src: TileSetAtlasSource = TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = TILE_SIZE
		src.create_tile(Vector2i.ZERO)

		var source_id: int = result.tileset.add_source(src)
		result.source_id_by_numeric[numeric] = source_id

	return result
