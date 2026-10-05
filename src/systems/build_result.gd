class_name BuildResult
extends RefCounted
## What BuildSystem.check and BuildSystem.apply return.
##
## A refusal carries a reason the caller can branch on rather than a
## sentence to parse. BAD_COST and BAD_COMMAND are faults -- content or
## code is wrong -- and they fill `detail`. The others are the player
## pointing at something that cannot be done.

const OUT_OF_BOUNDS: String = "out_of_bounds"
const BAD_COMMAND: String = "bad_command"
const NOT_PLACEABLE: String = "not_placeable"
const BAD_COST: String = "bad_cost"
const OCCUPIED: String = "occupied"
const BAD_GROUND: String = "bad_ground"
const BLOCKED_BY_ENTITY: String = "blocked_by_entity"
const CANT_AFFORD: String = "cant_afford"
const NOTHING_THERE: String = "nothing_there"
const NOT_REMOVABLE: String = "not_removable"

var ok: bool = false

## Empty when `ok`; otherwise one of the constants above.
var reason: String = ""
var detail: String = ""

## Only meaningful when `ok`: the string id placed or removed, and the
## items it spends (a placement) or gives back (a removal), id -> amount.
var content_id: String = ""
var cost: Dictionary = {}


static func refusal(p_reason: String, p_detail: String = "") -> BuildResult:
	var r: BuildResult = BuildResult.new()
	r.reason = p_reason
	r.detail = p_detail
	return r


static func accepted(p_content_id: String, p_cost: Dictionary) -> BuildResult:
	var r: BuildResult = BuildResult.new()
	r.ok = true
	r.content_id = p_content_id
	r.cost = p_cost
	return r
