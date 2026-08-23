class_name DecodeResult
extends RefCounted
## Typed success/failure for codecs. Decoding untrusted bytes must never
## crash, so every codec returns one of these rather than pushing an error.

var ok: bool = false
var error: String = ""
var value: Variant = null


static func success(v: Variant) -> DecodeResult:
	var r: DecodeResult = DecodeResult.new()
	r.ok = true
	r.value = v
	return r


static func failure(msg: String) -> DecodeResult:
	var r: DecodeResult = DecodeResult.new()
	r.ok = false
	r.error = msg
	return r
