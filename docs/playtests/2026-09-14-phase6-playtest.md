# Phase 6 playtest — session script

**Closes:** Task 12, and sets up Task 13's thirty minutes, in
`docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md`.
**Rule, carried from Phase 5:** anything that fails here is a bug fixed *in
Phase 6*, not a note carried into Stage 2. The exception is the triage in
Task 13, which has its own three buckets and its own file.

Written before the play pass rather than after, so the pass has a shape and the
findings have somewhere to go.

Four sessions, about 50 minutes total. Sessions A–C are scripted and quick;
session D is Task 13 and is the thirty minutes the tests cannot stand in for.

Run the game with:

```bash
./tools/godot.sh --path .
```

The two persistence surfaces on this machine:

```bash
SAVE=~/"Library/Application Support/Godot/app_userdata/RP1/saves/home"
SETTINGS=~/"Library/Application Support/Godot/app_userdata/RP1/settings.json"
```

Note the shape of those two paths, because one Definition-of-done line is
exactly that: `settings.json` sits at the `user://` root **beside** `saves/`,
never inside it. A volume that vanishes when a world is deleted is the bug this
prevents.

**Back up the world before session B**, which starts over the top of one:

```bash
cp -R "$SAVE" /tmp/rp1-save-backup-$(date +%s)
```

---

## 1. Verified mechanically — do not re-do by hand

| Definition-of-done line | Covered by | Result |
|---|---|---|
| No footstep while standing still | `tests/test_audio_director.gd::test_standing_still_is_silent` | pass |
| None while walking into a solid | distance-driven cadence; `test_a_frame_spike_does_not_leave_a_step_owed` and `tools/smoke.gd`'s walk-into-the-oak check | pass |
| No faster cadence on a diagonal | `player.gd` normalizes past unit length, and cadence reads distance, not time — there is no time term to be wrong | pass |
| The same variation never plays twice in a row | `test_a_variation_is_never_repeated_consecutively`, `test_every_variation_is_reachable` | pass |
| Footsteps match the terrain underfoot | `test_the_cue_names_the_terrains_sound`, `test_a_terrain_without_a_footstep_is_silent` | pass |
| Mute is actually silent | `test_mute_silences_footsteps_and_the_bed` | pass |
| Quit to Menu stops the bed, Continue starts it cleanly | `test_re_entering_the_same_zone_leaves_the_bed_alone` plus the `enter_zone("", "")` reset in `main.gd:_on_quit_to_menu` | pass |
| A malformed `settings.json` starts at defaults | `test_malformed_json_loads_defaults_rather_than_failing`, `test_a_json_array_loads_defaults_rather_than_failing` | pass |
| `settings.json` is at the `user://` root, not inside `saves/` | `test_the_default_path_is_outside_the_save_root` | pass |
| Volume and mute survive New World | settings are loaded once in `_ready()` and never touched by `open_new` | pass |
| The save indicator fires on a save and not otherwise | `test_the_gap_predicate_agrees_with_what_the_gap_save_does` | pass |
| No UI colour outside the Apollo palette | `tests/test_ui_theme.gd` + `./tools/check_palette.sh` | pass |
| No test writes to `user://saves/` or the real `settings.json` | every test injects `user://test_*/`; checked by hand in Task 6 Step 5 | pass |

Several of those stay on the manual list below anyway — **mute**, **the bed
across Quit to Menu**, **volume surviving a relaunch**. What the unit tests
prove is the rule inside `AudioDirector`; what session A proves is that
`AudioStage`, the pause menu and the router are wired to it. Different claim,
same sentence.

What the tests cannot touch at all, and why this script exists: **whether any
of it is audible, and whether it sounds right.**

---

## 2. Session A — audio (~10 min)

Needs the Task 7 assets in `assets/audio/`. Before starting, confirm the build
can actually see them — this is the check that catches a content file naming a
path that is not there:

```bash
./tools/godot.sh --headless --path . -s tools/smoke.gd | grep "RP1 audio"
```

Expect `RP1 audio: 100 cues over 100 steps, bed yes`. **`0 cues` or `bed no`
means the sounds are not resolving and there is no point listening yet.**

Then launch, New World, and listen for each of these in order. Each line names
what makes it a failure, not just what to notice.

- [ ] **Cadence at a walk.** Hold one direction across open grass. Roughly
      three steps a second, even.
      *Failure:* a drum roll, a limp, or a cadence that speeds up on a
      diagonal. Walk north, then north-east, and compare — they must match.
- [ ] **The change between grass and dirt.** Walk from grass onto one of the
      dirt paths and back.
      *Failure:* no audible change at the boundary, or a change that lags a
      tile or more behind where the character actually is.
- [ ] **Silence when still.** Release everything.
      *Failure:* any step after the character stops, including one straggler.
- [ ] **Silence when blocked.** Walk into a tree and hold the key.
      *Failure:* footsteps continuing while the character is not moving. This
      is the case a timer-driven cadence gets wrong and distance gets right,
      so it is the one that proves the design.
- [ ] **The bed underneath, not competing.** Stand still and listen.
      *Failure:* the ambience sitting at or above the level of the footsteps,
      or masking them. The fix is a `gain_db` edit in
      `data/sound/bed_meadow.json`, not a code change.
- [ ] **No seam when the bed loops.** Stand still through a full loop — 30 s or
      more — and listen for the join.
      *Failure:* a click, a gap, or an audible restart. This is a property of
      the source file; a seam means the asset is wrong, not the code.
- [ ] **Mute is silent.** Esc, toggle Mute.
      *Failure:* anything audible at all, including a quiet bed. Un-mute: the
      bed comes back **without** having restarted from the top.
- [ ] **The slider is audible while dragging.** Esc, drag the volume slider
      slowly end to end.
      *Failure:* the level only changing when the drag is released, or not at
      all until the menu is closed.

## 3. Session B — the UI frame (~5 min)

- [ ] **The title card on New World.** "Home Valley" fades in near the top and
      away on its own.
      *Failure:* no card, the wrong name, a card that never fades, or one that
      draws over the pause menu when Escape is pressed during it.
- [ ] **The title card on Continue.** Quit to Menu, Continue.
      *Failure:* no card. It belongs to arriving, so it appears every time —
      including on a loaded world, where the name comes from `zone_meta.json`
      rather than from `zone.json`.
- [ ] **The hint on a first world only.**

      ```bash
      rm "$SETTINGS"
      ```
      New World: the WASD / Esc hint sits at the bottom and fades. Quit to
      Menu, Continue, and quit and relaunch.
      *Failure:* the hint appearing a second time, or not appearing on the
      first world after the file was deleted. Confirm the flag was written:

      ```bash
      grep controls_hint_shown "$SETTINGS"   # expect true
      ```
- [ ] **The save indicator on focus loss.** Open a world, walk for more than
      five seconds (`MIN_SAVE_GAP`), then click to another window. "Saved"
      appears top-right and fades.
      *Failure:* no indicator; or — the more likely bug — an indicator that
      appears on **every** alt-tab, including one a second after the last save,
      when nothing was actually written. Click away twice in quick succession:
      the second must stay silent.
- [ ] **The save indicator at the five-minute autosave.** Session D covers
      this; there is no point sitting through five minutes twice.
      *Failure:* a visible hitch on the frame it fires, or no indicator at all.

## 4. Session C — settings (~5 min)

- [ ] **Volume and mute survive a relaunch.** Set the volume somewhere
      distinctive — not the default 0.8, and not 0 — mute, then quit with the
      X. Relaunch, Continue, Esc.
      *Failure:* either control back at its default, or showing the right value
      while the actual level is wrong. Listen as well as look.
- [ ] **They survive New World.** From the menu, New World over the existing
      save. Esc.
      *Failure:* the volume resetting with the world. Settings outlive worlds;
      that is the whole reason the file is not under `saves/`.
- [ ] **A hand-corrupted `settings.json` starts at defaults.**

      ```bash
      echo '{not json at all' > "$SETTINGS"
      ```
      Launch.
      *Failure:* the game refusing to start, showing an error, or hanging. It
      must open normally at volume 0.8, unmuted. A malformed preferences file
      is never a reason a game will not start.
- [ ] **The file is where it should be.**

      ```bash
      ls "$SETTINGS" && ls ~/"Library/Application Support/Godot/app_userdata/RP1/saves/"
      ```
      *Failure:* `settings.json` found inside `saves/`, or absent from the root.

## 5. Session D — the thirty minutes (Task 13)

Not one sitting. Quit and come back, because the things that annoy on the third
return are different from the ones that annoy in the first ten minutes — and
returning is what Stage 1 is actually about.

Write findings down **as they happen**, in a list. Do not fix anything while
playing: fixing mid-session turns thirty minutes of play into three hours of
debugging and one finding.

Watch for, beyond the checklists above:

- [ ] No hitch on the five-minute autosave, with the indicator visible
- [ ] The bed still sounding right after twenty minutes — a loop that is fine
      once can become maddening on the fortieth pass
- [ ] Footstep variation still reading as variation, not as a pattern
- [ ] 60 FPS with all 16 chunks loaded and audio running

Then triage every finding into exactly one of **fix now**, **`IDEAS.md`**, or
**won't fix (with the reason written down)**, into
`docs/playtests/<date>-phase6-findings.md`. A finding with no bucket is not
triaged, and the phase does not close with one.

## 6. Recording the result

Fix anything that failed, in Phase 6, then re-run the affected session.

When every box above holds:

```bash
python3 tools/mark_task_done.py 12 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
```

The Definition of done is a section rather than a task, and is ticked by
heading — and only once Tasks 13, 14 and 15 have been done too:

```bash
python3 tools/mark_task_done.py --section "Definition of done" \
  --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
```

Both commands tick a whole block at once, so run them only when every line has
actually passed — not partway through.
