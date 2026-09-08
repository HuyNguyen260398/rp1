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
		# Content named in a save but absent from this build has no art.
		if registry.is_placeholder(numeric):
			continue
		var def: Dictionary = registry.def_of(numeric)
		if not TILE_CATEGORIES.has(str(def.get("category", ""))):
			continue
		var sprite_path: String = str(def.get("sprite", ""))
		if sprite_path.is_empty():
			result.errors.append("%s: no sprite path" % str(def.get("id", numeric)))
			continue

		# Checked before load() rather than testing the result for null:
		# load() on a missing path pushes an engine-level error, which is
		# log noise and fails the test that deliberately feeds it one.
		# Same reasoning as ContentRegistry preferring JSON.new().parse()
		# over the static helper.
		if not ResourceLoader.exists(sprite_path):
			result.errors.append("%s: cannot load %s" % [str(def.get("id", numeric)), sprite_path])
			continue
		var tex: Texture2D = load(sprite_path) as Texture2D
		if tex == null:
			result.errors.append("%s: not a texture: %s" % [str(def.get("id", numeric)), sprite_path])
			continue

		var src: TileSetAtlasSource = TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = _region_size(def)
		src.create_tile(Vector2i.ZERO)

		var td: TileData = src.get_tile_data(Vector2i.ZERO, 0)
		td.texture_origin = _texture_origin(def)

		var source_id: int = result.tileset.add_source(src)
		result.source_id_by_numeric[numeric] = source_id

	return result


## sprite_rect is [x, y, w, h]; only the size is used, since each
## definition currently owns its whole PNG.
static func _region_size(def: Dictionary) -> Vector2i:
	if not def.has("sprite_rect"):
		return TILE_SIZE
	var rect: Array = def["sprite_rect"]
	if rect.size() != 4:
		return TILE_SIZE
	return Vector2i(int(rect[2]), int(rect[3]))


## Where a sprite sits relative to its tile.
##
## Godot centres an oversized atlas region on the tile, so a 48px sprite on
## a 32px tile hangs 8px below it. Base alignment is therefore (H - T) / 2,
## derived from geometry so that any oversized art stands on its tile with
## no data at all.
##
## y_offset is a deliberate nudge on top of that, for art that should NOT
## stand flat -- a hanging sign, a bird. Negative moves the sprite up,
## which is the intuitive direction. It is subtracted because the engine
## subtracts texture_origin from the draw position, so the sign flips here
## rather than in every content file.
static func _texture_origin(def: Dictionary) -> Vector2i:
	var base_align: int = (_region_size(def).y - TILE_SIZE.y) / 2
	return Vector2i(0, base_align - int(def.get("y_offset", 0)))
