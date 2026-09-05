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


func _ready() -> void:
	terrain_layer = _make_layer("TerrainLayer", false)
	floor_layer = _make_layer("FloorLayer", false)
	object_layer = _make_layer("ObjectLayer", true)


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
