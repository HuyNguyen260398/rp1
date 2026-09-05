extends SceneTree
## Writes a chunk fixture at the CURRENT format version.
## Run once per format-version bump, then commit the output:
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
	quit(0)
