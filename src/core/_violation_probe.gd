extends Node2D
## DELIBERATE ARCHITECTURE VIOLATION -- do not merge.
##
## Exists only to prove the CI architecture gate actually fails the build.
## src/core/ must be node-free (RefCounted only); this file breaks that rule
## two ways: a Node2D base class and a get_tree() call.

func _ready() -> void:
	var t: SceneTree = get_tree()
	print(t)
