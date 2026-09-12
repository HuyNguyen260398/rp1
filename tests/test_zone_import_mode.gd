extends GutTest
## The zone maps are data, not textures.
##
## Godot would otherwise import them as CompressedTexture2D, and
## fix_alpha_border would rewrite the RGB of transparent pixels. Opening
## the project in the editor is exactly the kind of ordinary act that
## reverts an import mode, so this asserts it every run -- the same guard
## tests/test_import_manifest.gd applies to art.

const MAPS: PackedStringArray = [
	"res://data/zone/home/terrain.png",
	"res://data/zone/home/object.png",
	"res://data/zone/home/height.png",
]


func _import_text(png_path: String) -> String:
	var path: String = png_path + ".import"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must exist" % path)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


func test_every_map_is_kept_rather_than_imported() -> void:
	for png: String in MAPS:
		assert_string_contains(_import_text(png), 'importer="keep"',
			"%s must not be imported as a texture" % png)


func test_no_map_is_imported_as_a_texture() -> void:
	for png: String in MAPS:
		assert_false(_import_text(png).contains('importer="texture"'),
			"%s was re-imported as a texture; re-apply importer=\"keep\"" % png)
