# Phase 6 play pass — findings

**Closes:** Task 13 in
`docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md`.
**Script:** `docs/playtests/2026-09-14-phase6-playtest.md`.
**Played:** 2026-09-21, thirty minutes across several sittings.

## Result

**No findings.** All three triage buckets are empty.

| Bucket | Count | Contents |
|---|---|---|
| Fix now | 0 | — |
| `IDEAS.md` | 0 | — |
| Won't fix | 0 | — |

`IDEAS.md` is therefore unchanged by this pass, and no `fix:` commit belongs
to Task 13. Task 13 Step 3 had nothing to do; that is a real outcome, not a
skipped step.

## What an empty result does and does not mean

It means nothing rose to the level of a finding across the script's four
sessions. It is **not** a measurement, and it is not the same as the gates
passing — the gates are in section 1 of the script precisely because they
cover what a person should not be re-checking by hand.

One item is worth naming because it was deferred here on purpose. The
ambient bed (`bed_meadow.ogg`, 30.69 s) was committed in 25b5755 as the
unmodified CC0 field recording, with the loop seam left to be judged by
ear rather than crossfaded blind. **The play pass raised no seam finding.**
That is weaker than "proven seamless" — it means no seam was noticed in
normal play, not that someone stood at a fixed point and timed the join.
If a seam turns up later, the fix is a short crossfade, and the asset
becomes derived, so `assets/audio/LICENSE.txt` would have to record the
edit the way `assets/tiles/LICENSE.txt` records quantization.

## Gates at the time of the pass

Task 13 Step 4, run 2026-09-21. All six exit 0:

| Gate | Result |
|---|---|
| `run_tests.sh` | 373/373 passing, 37 scripts |
| `guard.gd` | Architecture guard: clean |
| `smoke.gd` | OK (300 iterations); audio 100 cues / 100 steps, bed yes |
| `check_asset_licences.sh` | OK |
| `check_palette.sh` | OK (16 files) |
| `check_zone.sh` | OK (1 zone) |

The seventh CI gate, the export, is not in Step 4's list and was not run:
it needs export templates this machine does not have. CI runs it.

## Still open

**Task 14, the clean-machine test, has not been run.** It is the only check
in the phase that catches a fault which cannot reproduce on this machine --
an asset that resolves from the local `.godot` import cache but never
reaches the PCK would play here and be silent on a fresh VM. The audio
added in 25b5755 is the newest thing in the build and has never been
exercised outside this working copy.

Phase 6 does not close, and the Definition of done is not ticked, until
Task 14 and Task 15 are done.

---

# Stage 1 acceptance criteria — the §11 walk

**Task 15 Step 2.** Walked 2026-09-21 against
`docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` §11.
Ten of eleven criteria hold. The eleventh is Task 14 and is not done.

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Corner-to-corner walk, no collision bugs | PASS | Task 13 play pass, no findings; `test_movement_system`, `test_walkability` |
| 2 | Quit/relaunch restores world, player pos + facing, animals | PASS | `smoke.gd` reopen assertions; `test_game_session` |
| 3 | Chunk payloads round-trip byte-identical | PASS | `tests/test_chunk_codec.gd:51` |
| 4 | Full zone save under 100 ms | PASS | measured **3.6 ms**; smoke reports 5–7 ms |
| 5 | Older `format_version` loads via committed fixture | PASS | `tests/fixtures/v1_chunk.chunk`, `v1_entities.dat`, `test_migrations.gd` |
| 6 | Unknown string id → placeholder, string intact | PASS | `test_content_registry.gd:87`, `test_id_map.gd:59` |
| 7 | Zone loads under 1 second | PASS | measured **42.5 ms** |
| 8 | 60 FPS with all 16 chunks | PASS | `--print-fps`: **120 FPS, 8.33 mspf**, vsync-capped |
| 9 | All CI gates green | PASS | run 35549382932, `verify` + `export` both green |
| 10 | **Exported build runs on a clean machine** | **NOT DONE** | Task 14 — no VM run |
| 11 | **New tree = one JSON + one PNG, no code change** | PASS | commit `abac715` |

Criterion 9 reads "all five CI gates" because the spec predates gates 6
and 7. There are seven, and all seven are green.

## Criterion 11, in detail

Proved rather than asserted, as Task 15 Step 2 requires. A `dead_tree` was
added and rendered. **Zero `.gd` files changed** — the substance of the
criterion holds.

The letter of it does not, and the difference is worth keeping:

- You do **not** add a PNG. You add a slice to `tools/import_manifest.json`
  and `tools/quantize.gd` produces the PNG. Hand-added art cannot pass the
  palette gate, because `check_palette.gd` fails any file in `assets/` that
  the manifest does not declare. That is stronger than the criterion claims.
- Defining the tree is one content JSON. *Placing* it is two more data
  edits: a legend colour in `zone.json` and pixels in `object.png`. Neither
  is code, but "one JSON file" undercounts.

A better wording for the Stage 2 spec: **adding a new tree type is one
content JSON, one manifest slice and a pipeline run, with no code change.**

The sprite is 56x57 — the first object in the game that is not 32x32.
`tileset_builder._texture_origin` centres oversized art from geometry
alone, so `y_offset` stayed 0 and that needed no code either.

Numbers before → after: content definitions 19 → 20, cells rendered
17389 → 17392 (the three trees), palette gate 16 → 17 files.

## Definition-of-done lines verified mechanically

- **No test writes to `user://saves/` or the real `user://settings.json`.**
  Recorded both mtimes, ran the full suite and the smoke test, re-read
  them: unchanged (`08:47:41` and `21:30:43` before and after).
- **`settings.json` at the `user://` root, not inside `saves/`.** It sits
  beside `saves/` in the RP1 user-data directory.

## Still blocking the phase

Only **Task 14**. Criterion 10 cannot be closed from this machine, and the
Definition of done cannot be ticked while it is open.
