class_name ZoneRenderer
extends Node2D
## Paints a Zone into three TileMapLayers.
##
## Presentation reads world data and never writes it. Nothing in this file
## may mutate the Zone it is handed.

## Terrain and floor are flat ground. Objects stand up and must sort
## against the player, so only that layer gets y_sort_enabled.
var terrain_layer: TileMapLayer = null
var floor_layer: TileMapLayer = null
var object_layer: TileMapLayer = null

var _build: TilesetBuildResult = null

## Set this and _process keeps the view current. Left null, the renderer
## is inert and only repaints when called explicitly.
var zone: Zone = null


func _ready() -> void:
	_ensure_layers()


## Builds the three layers once, whether that happens via _ready() in the
## normal scene-tree path or via setup() when a tool drives the renderer
## directly. _ready() does not fire synchronously on add_child() from
## SceneTree._init(), so depending on it alone made the renderer unusable
## headless -- which is exactly where CI drives it.
func _ensure_layers() -> void:
	if terrain_layer != null:
		return
	# Nested Y-sorted nodes flatten into the parent's sort, which is what
	# lets object tiles interleave with entity sprites. Without this the
	# whole renderer sorts as one item at y = 0 and the player draws in
	# front of every tree regardless of where they stand.
	y_sort_enabled = true
	terrain_layer = _make_layer("TerrainLayer", false)
	floor_layer = _make_layer("FloorLayer", false)
	object_layer = _make_layer("ObjectLayer", true)
	# Ground never sorts. Without an explicit z_index these layers sit at
	# y = 0 in the flattened sort and stay behind everything only by a
	# tie-break on tree order, which is not a thing to depend on.
	terrain_layer.z_index = -1
	floor_layer.z_index = -1


func _make_layer(layer_name: String, y_sort: bool) -> TileMapLayer:
	var layer: TileMapLayer = TileMapLayer.new()
	layer.name = layer_name
	layer.y_sort_enabled = y_sort
	add_child(layer)
	return layer


## Builds the TileSet and hands it to every layer. Returns builder errors,
## which are reported rather than fatal: one missing PNG must not blank
## the world.
func setup(registry: ContentRegistry) -> PackedStringArray:
	_ensure_layers()
	_build = TilesetBuilder.build(registry)
	for layer: TileMapLayer in [terrain_layer, floor_layer, object_layer]:
		layer.tile_set = _build.tileset
	return _build.errors


## Repaints every chunk. Permitted once, at load. Never from _process --
## see the set_cell rule in the Phase 3a spec.
func render_zone(zone: Zone) -> int:
	for layer: TileMapLayer in [terrain_layer, floor_layer, object_layer]:
		layer.clear()
	var painted: int = 0
	for c: Vector2i in zone.chunk_coords():
		painted += _paint_chunk(zone, c)
	return painted


func _paint_chunk(zone: Zone, c: Vector2i) -> int:
	var chunk: Chunk = zone.get_chunk(c)
	if chunk == null:
		return 0
	var origin: Vector2i = Coords.chunk_origin(c)
	var painted: int = 0
	for ly: int in range(Coords.CHUNK_SIZE):
		for lx: int in range(Coords.CHUNK_SIZE):
			var l: Vector2i = Vector2i(lx, ly)
			var cell: Vector2i = origin + l
			painted += _paint_cell(terrain_layer, cell, chunk.get_terrain(l))
			painted += _paint_cell(floor_layer, cell, chunk.get_floor(l))
			painted += _paint_cell(object_layer, cell, chunk.get_object(l))
	return painted


## Content id 0 is ID_UNKNOWN, meaning "empty, do not paint". TileMapLayer
## independently uses source id -1 for "no cell", and its source ids start
## at 0 -- a valid source. Two sentinels, different meanings; source_for()
## translates between them.
func _paint_cell(layer: TileMapLayer, cell: Vector2i, content_id: int) -> int:
	var source: int = _build.source_for(content_id)
	if source == -1:
		layer.erase_cell(cell)
		return 0
	layer.set_cell(cell, source, Vector2i.ZERO)
	return 1


func cells_painted() -> int:
	var total: int = 0
	for layer: TileMapLayer in [terrain_layer, floor_layer, object_layer]:
		total += layer.get_used_cells().size()
	return total


## Repaints only the chunks the zone has marked dirty, then clears the
## flags. This is the only repaint permitted from _process: a full
## render_zone() every frame would be 16,384 set_cell calls per frame.
func refresh_dirty(p_zone: Zone) -> int:
	var dirty: Array[Vector2i] = p_zone.dirty_chunk_coords()
	if dirty.is_empty():
		return 0
	var painted: int = 0
	for c: Vector2i in dirty:
		painted += _paint_chunk(p_zone, c)
	p_zone.clear_dirty()
	return painted


func _process(_delta: float) -> void:
	if zone != null:
		refresh_dirty(zone)
