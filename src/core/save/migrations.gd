class_name Migrations
extends RefCounted
## Save-format upgrade path.
##
## Deliberately empty today. The skeleton and its test exist before they are
## needed because retrofitting versioning onto a live save format is the kind
## of problem that kills hobby projects.
##
## To add version 2:
##   1. bump ChunkCodec.FORMAT_VERSION to 2
##   2. add a `_migrate_1_to_2(chunk)` function below and dispatch to it
##   3. run tools/make_fixture.gd and commit tests/fixtures/v2_chunk.chunk
##   4. leave the v1 fixture test in place -- it is the regression guard

const CURRENT_CHUNK_VERSION: int = ChunkCodec.FORMAT_VERSION


static func needs_migration(version: int) -> bool:
	return version < CURRENT_CHUNK_VERSION


static func migrate_chunk(version: int, chunk: Chunk) -> DecodeResult:
	if version == CURRENT_CHUNK_VERSION:
		return DecodeResult.success(chunk)
	if version > CURRENT_CHUNK_VERSION:
		return DecodeResult.failure(
			"chunk version %d is newer than this build supports (%d)"
			% [version, CURRENT_CHUNK_VERSION]
		)
	return DecodeResult.failure(
		"chunk version %d has no migration path to %d" % [version, CURRENT_CHUNK_VERSION]
	)
