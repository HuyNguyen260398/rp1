class_name HarvestResult
extends RefCounted
## What HarvestSystem.harvest returns.
##
## A refusal carries a reason the caller can branch on rather than a
## sentence to parse. Only BAD_YIELD is a fault worth logging -- it means
## content is wrong -- and it alone fills `detail`. The others are the
## player reaching for something that gives nothing.

const OUT_OF_BOUNDS: String = "out_of_bounds"
const NOTHING_THERE: String = "nothing_there"
const NOT_HARVESTABLE: String = "not_harvestable"
const BAD_YIELD: String = "bad_yield"

var ok: bool = false

## Empty when `ok`; otherwise one of the constants above.
var reason: String = ""
var detail: String = ""

## Only meaningful when `ok`: the string id of the object removed, the
## item credited, and how many.
var object_id: String = ""
var item_id: String = ""
var amount: int = 0


static func refusal(p_reason: String, p_detail: String = "") -> HarvestResult:
	var r: HarvestResult = HarvestResult.new()
	r.reason = p_reason
	r.detail = p_detail
	return r
