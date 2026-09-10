# RP1 — Palette

**Palette:** Apollo, 46 colours, by AdamCYounis
**Source:** <https://lospec.com/palette-list/apollo>
**Status:** fixed. Provisional pending the Elin validation in §6.

`CLAUDE.md` states: *"Palette is fixed — see `docs/palette.md`. Do not
introduce new colours."* This file is what that rule points at.

---

## 1. The rule

Every pixel in `assets/` is one of the 46 colours below. No exceptions, no
"close enough", no anti-aliased in-between shades.

This applies to art the project draws **and** to art it imports. Third-party
packs are re-quantized onto this palette at import time rather than used
as-authored, because a palette that governs only the art we happen to draw
ourselves is a style guide, not a constraint — and the first imported pack
would break it.

Enforcement is mechanical, matching how the project enforces everything else:

| Piece | Status |
|---|---|
| `tools/quantize.gd` — maps an imported PNG onto the palette | **Done.** |
| `tools/check_palette.sh` — fails on any off-palette pixel | **Done.** **CI gate 5** |

There are **no exemptions**, and no mechanism for granting one. The Phase 3a
and 3b debug swatches were the only off-palette files in the project and
Phase 3c deleted them; an exemption list is how a rule like this decays back
into a suggestion. Art that cannot pass the gate is art the pipeline has not
been taught to derive yet, which is a different problem and is fixed in
`tools/import_manifest.json` or `tools/palette_overrides.json`.

---

## 2. Why Apollo

Chosen to sit close to the art direction of **Elin** (Lafrontier, Steam app
2135150), which is the visual reference for this project. Apollo is muted and
naturalistic rather than saturated and punchy, which is the closest published
palette to Elin's warm, earthy look.

Two honest caveats, recorded so they are not rediscovered later:

**Apollo is not Elin's palette.** No Elin palette has ever been published, and
Elin is a Unity game with real-time lighting, weather and a day/night cycle —
its on-screen colours are base sprites multiplied by scene lighting, sampled at
one moment. It very likely has no fixed palette at all. Apollo is an
approximation of the *look*, chosen deliberately, not a copy.

**Much of what makes Elin look like Elin is the lighting, not the colours.**
That lighting is Stage 3+ work and explicitly out of Stage 1 scope. Matching
the palette gets part of the way there and no further; expecting the palette
alone to reproduce the reference will disappoint.

Apollo was picked over the alternatives with eyes open about the cost. It has
46 colours against Resurrect 64's 64, which means measurably less headroom when
re-quantizing imported art — imported packs will lose more detail than they
would under a larger palette. That trade was accepted in exchange for matching
the art direction, which is the harder thing to fix later.

---

## 3. The ramps

Apollo is built as six hue ramps of six steps plus a ten-step neutral. Each ramp
runs dark to light. **Shade within a ramp; do not mix ramps to make a shade** —
that is what produces mud.

### Blue — 6 steps

`#172038`  `#253a5e`  `#3c5e8b`  `#4f8fba`  `#73bed3`  `#a4dddb`

Water, sky, cold light, deep shadow on cool surfaces.

### Green — 6 steps

`#19332d`  `#25562e`  `#468232`  `#75a743`  `#a8ca58`  `#d0da91`

Foliage, grass, moss. The workhorse ramp for RP1.

### Tan — 6 steps

`#4d2b32`  `#7a4841`  `#ad7757`  `#c09473`  `#d7b594`  `#e7d5b3`

Wood, skin, sand, rope, cloth. Warm mid-tones.

### Gold — 6 steps

`#341c27`  `#602c2c`  `#884b2b`  `#be772b`  `#de9e41`  `#e8c170`

Dirt, thatch, fire, brass, autumn. Higher saturation than Tan.

### Red — 6 steps

`#241527`  `#411d31`  `#752438`  `#a53030`  `#cf573c`  `#da863e`

Berries, danger, blood, painted surfaces. Use sparingly.

### Purple — 6 steps

`#1e1d39`  `#402751`  `#7a367b`  `#a23e8c`  `#c65197`  `#df84a5`

Night, magic, dusk. Almost unused in Stage 1.

### Neutral — 10 steps

`#090a14`  `#10141f`  `#151d28`  `#202e37`  `#394a50`  `#577277`  `#819796`  `#a8b5b2`  `#c7cfcc`  `#ebede9`

Outlines, stone, metal, UI. Cool grey-green, never pure grey.
---

## 4. Assignments for current content

Concrete starting points for the content that exists today, so Phase 3b does not
begin with an open-ended colour choice. These are defaults, not laws — but
change them here, not per-asset.

| Subject | Base | Shadow | Highlight |
|---|---|---|---|
| Grass (`grass`) | `#468232` | `#25562e` | `#75a743` |
| Water surface (`water`) | `#4f8fba` | `#3c5e8b` | `#73bed3` |
| Water rim / sand | `#d7b594` | `#c09473` | `#e7d5b3` |
| Dirt path | `#ad7757` | `#884b2b` | `#c09473` |
| Oak trunk (`oak_tree`) | `#7a4841` | `#4d2b32` | `#ad7757` |
| Oak canopy (`oak_tree`) | `#468232` | `#25562e` | `#75a743` |
| Stone | `#577277` | `#394a50` | `#819796` |

The Grass row moved a step darker in Phase 3c, because the imported grass
quantized to `#468232` with `#75a743` as its highlight rather than the other
way round. The table was written before any art existed; the art is the fact.
Everything the real art actually uses agrees with the rest of this table —
water sits on `#4f8fba` with `#73bed3` sparkle, the oak trunk on `#7a4841`
over `#4d2b32`, the canopy across `#25562e`, `#468232` and `#75a743`. Rows
with no art yet (water rim, dirt path, stone) are still untested guesses.

Two of those agreements are not accidents: the trunk and the canopy needed
entries in `tools/palette_overrides.json` to reach them, because
nearest-colour put the trunk in Gold and the tuft at its base in Neutral.

### Outline

`CLAUDE.md` requires one outline style, enforced. It is **`#172038`** — the
darkest blue, not the darkest neutral. A blue-black outline keeps outdoor art
from reading as sooty, and every sprite uses the same one.

Interior or night-lit art may substitute `#10141f` once those exist. Nothing in
Stage 1 does.

This one is enforced by a palette override rather than by the mapping: both
imported packs outline in pure black, whose nearest Apollo colour is the
darkest *neutral* `#090a14`. That is precisely the sooty black this rule
exists to avoid, so `000000 -> 172038` is pinned in
`tools/palette_overrides.json` and every sprite in the project outlines in
the same blue-black.

---

## 5. Working rules

- **Shade within a ramp.** Six steps is enough for any Stage 1 sprite.
- **Do not anti-alias to off-palette colours.** Pick the nearest palette step.
- **The neutral ramp is cool grey-green, not grey.** Do not substitute pure
  greys; they read as dead next to everything else here.
- **Purple is nearly unused in Stage 1.** If a sprite needs it, ask whether the
  sprite is right rather than whether the palette is.
- **Saturation carries meaning.** The Gold and Red ramps are the most saturated
  in the palette. Spending them on ordinary terrain flattens the contrast that
  makes interactive objects read.

---

## 6. Open items

- [ ] **Validate against Elin.** Partially done. One screenshot (a sunny
      meadow at midday) was measured during the Phase 3c design:

      | Measure | Result |
      |---|---|
      | Mean OKLab error to nearest Apollo colour | 0.056 |
      | Median / p90 | 0.055 / 0.074 |
      | Mean gap between adjacent steps within a ramp | 0.109 |
      | Ramp usage by pixel share | green 85.1%, neutral 6.5%, tan 4.6%, gold 3.5%, blue 0.0% |
      | Chroma change after quantization | **+37.1%** |
      | Lightness change | +0.6% |

      Error at roughly half a ramp step is a good result. The chroma figure
      is not: Apollo renders the scene 37% more saturated, which
      contradicts section 2's reason for choosing it. Blue and Purple —
      12 of 46 colours — do essentially nothing outdoors.

      **Not acted on, for two reasons.** The method measures the wrong
      surface: Elin's on-screen colour is base sprites multiplied by
      real-time lighting, so the olive cast is partly shadow rather than
      pigment, and its underlying art is very likely more saturated than
      measured. RP1 has no lighting in Stage 1, so flatter, more saturated
      base art may be the correct compensation. And the sample is one
      screenshot of the 8-12 this item asks for, of the most
      saturated-green scene the game has.

      Remaining work: 7-11 more screenshots across biomes and times of day.
      **Reference images are never committed** — section 7 forbids copying
      Elin art into this project. Measure, record the numbers here, delete
      the image. See docs/reference/README.md.
- [x] Build `tools/quantize.gd` and `tools/check_palette.sh` (Phase 3c).
- [x] Delete the Phase 3a and 3b debug swatches, or exempt them in the gate.
      Deleted, along with `tools/make_placeholder_art.gd` that produced them.
      There is no exemption mechanism and there is not meant to be one.

---

## 7. Attribution

Apollo is by **AdamCYounis**, published at
<https://lospec.com/palette-list/apollo>.

Lospec's palette API returns no licence field, and no licence is claimed here. A
palette is a list of colour values rather than creative work of the kind that
carries a licence, and the attribution above is recorded because it is right to
credit the author, not because a licence compels it. If the project ever needs
certainty on this point — a publisher asking, say — confirm it with the author
directly rather than relying on this note.

This is the palette only. **No Elin art, sprite, tile or asset is copied into
this project**, and none may be.
