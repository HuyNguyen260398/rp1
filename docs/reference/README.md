# Reference images

Working images: visual reference for the art direction, and screenshots of RP1
taken while verifying something by eye.

**The image files in this folder are not committed.** Only this README, the
`.gitignore` rule that excludes them, and the `.gdignore` that keeps Godot from
importing them are in git. Put images here; expect them to stay local.

## Why they are not committed

Two separate reasons, and the stricter one governs the folder:

**Third-party reference is a licence problem.** `docs/palette.md` §7 states that
no Elin art, sprite, tile or asset is copied into this project, and none may be.
A screenshot is that game's art. It can be looked at and measured; it cannot
live in this repository's history, where removing it later means rewriting
history. So the folder is ignored by default rather than case by case — the
moment the rule depends on somebody remembering it at `git add` time, it fails.

**RP1's own screenshots are throwaway.** A debug capture proves something once,
at one commit, and is misleading a month later when the art has changed. Record
what a screenshot established in the plan or the spec, in words and numbers, and
let the image go. That is how the Phase 3b Y-sort verification was handled.

## Working with a reference image

Measure it, write the numbers down somewhere committed, delete the image.

`docs/palette.md` §6 (validating Apollo against Elin) is the live example: the
Phase 3c design records the measured quantization error, ramp usage and chroma
shift from one screenshot. The numbers are in git. The screenshot never was.
