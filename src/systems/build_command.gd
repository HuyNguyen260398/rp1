class_name BuildCommand
extends RefCounted
## One edit to the world, as a value.
##
## An edit is an object rather than a setter call so that it can one day
## be kept: undo is a stack of these (Stage 2 design 3.2). Nothing keeps
## them yet.

const PLACE: String = "place"
const REMOVE: String = "remove"

## A layer is named for the content category that lives on it.
const LAYER_OBJECT: String = "object"

var action: String = PLACE
var tile: Vector2i = Vector2i.ZERO
var layer: String = LAYER_OBJECT

## The string id to place. Empty for a removal, which takes whatever is
## on the tile.
var content_id: String = ""


static func place(p_tile: Vector2i, p_layer: String, p_content_id: String) -> BuildCommand:
	var c: BuildCommand = BuildCommand.new()
	c.action = PLACE
	c.tile = p_tile
	c.layer = p_layer
	c.content_id = p_content_id
	return c


static func remove(p_tile: Vector2i, p_layer: String) -> BuildCommand:
	var c: BuildCommand = BuildCommand.new()
	c.action = REMOVE
	c.tile = p_tile
	c.layer = p_layer
	return c
