extends SceneTree
## Writes the save-format fixtures at their CURRENT format versions, one
## per codec. Run once per format-version bump, then commit the output:
##   ./tools/godot.sh --headless --path . -s tools/make_fixture.gd

func _init() -> void:
	var c: Chunk = Chunk.new(Vector2i(1, 2))
	for y: int in range(32):
		for x: int in range(32):
			var l: Vector2i = Vector2i(x, y)
			c.set_terrain(l, (x * 31 + y * 17) % 65536)
			c.set_height(l, (x + y) % 256)
			c.set_flags(l, Chunk.FLAG_WALKABLE if (x + y) % 2 == 0 else 0)

	var path: String = "res://tests/fixtures/v%d_chunk.chunk" % ChunkCodec.FORMAT_VERSION
	DirAccess.make_dir_recursive_absolute("res://tests/fixtures")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(ChunkCodec.encode(c))
	f.close()
	print("wrote ", path)

	var store: EntityStore = EntityStore.new()
	var first: int = store.spawn(11, Vector2(4.5, 9.5))
	var second: int = store.spawn(12, Vector2(20.25, 33.75))
	var third: int = store.spawn(13, Vector2(127.5, 0.5))
	store.set_facing(second, 2)
	store.set_facing(third, 3)
	print("fixture entity ids: ", first, " ", second, " ", third)

	var ent_path: String = "res://tests/fixtures/v%d_entities.dat" % EntityCodec.FORMAT_VERSION
	var ef: FileAccess = FileAccess.open(ent_path, FileAccess.WRITE)
	ef.store_buffer(EntityCodec.encode(store))
	ef.close()
	print("wrote ", ent_path)

	quit(0)
