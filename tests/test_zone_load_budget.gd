extends GutTest
## The Stage 1 acceptance criterion "zone loads in under 1 second", made
## mechanical rather than assumed.
##
## Runs against a generated 128x128 zone rather than the shipped one, so
## the budget still means something while data/zone/home/ is smaller than
## its final size.

const SIZE: Vector2i = Vector2i(128, 128)
const BUDGET_MS: int = 1000

var _dir: String
var _registry: ContentRegistry


func before_all() -> void:
	_dir = "user://zone_budget_fixture"
	DirAccess.make_dir_recursive_absolute(_dir)
	_registry = ContentRegistry.new()
	_registry.register({"id": "grass", "category": "terrain",
		"display_name": "Grass", "sprite": "res://none.png", "walkable": true})
	_registry.register({"id": "oak_tree", "category": "object",
		"display_name": "Oak", "sprite": "res://none.png", "blocks_movement": true})

	var doc: Dictionary = {
		"id": "budget", "category": "zone", "display_name": "Budget",
		"size": [SIZE.x, SIZE.y],
		"maps": {"terrain": "terrain.png", "object": "object.png",
			"height": "height.png"},
		"legend": {
			"terrain": {"00ff00": "grass"},
			"object": {"000000": null, "008000": "oak_tree"},
		},
		"player_spawn": [64.5, 64.5],
	}
	var f: FileAccess = FileAccess.open(_dir.path_join("zone.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()

	_fill("terrain.png", Color8(0, 255, 0))
	# A tree every eleventh tile: enough object work to be representative.
	var objects: Image = Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	objects.fill(Color8(0, 0, 0))
	for y: int in range(0, SIZE.y, 11):
		for x: int in range(0, SIZE.x, 11):
			objects.set_pixel(x, y, Color8(0, 128, 0))
	objects.save_png(_dir.path_join("object.png"))
	_fill("height.png", Color8(0, 0, 0))


func after_all() -> void:
	var d: DirAccess = DirAccess.open(_dir)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_dir)


func _fill(file_name: String, c: Color) -> void:
	var img: Image = Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(c)
	img.save_png(_dir.path_join(file_name))


func test_a_full_size_zone_loads_within_the_budget() -> void:
	var start: int = Time.get_ticks_msec()
	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)
	var elapsed: int = Time.get_ticks_msec() - start

	assert_eq(r.errors, PackedStringArray())
	assert_eq(r.zone.size_tiles, SIZE)
	assert_lt(elapsed, BUDGET_MS,
		"a 128x128 zone took %d ms; the Stage 1 budget is %d ms" % [elapsed, BUDGET_MS])
