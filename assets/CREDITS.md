# Asset credits

Every third-party asset pack used in RP1, with its source and licence.
Maintained from the very first import -- reconstructing it before a Steam
launch with 60 packs and no records is a genuinely miserable week.

## Licence policy

| Licence | Allowed | Notes |
|---|---|---|
| CC0 | Yes, preferred | Public domain, no attribution required |
| CC-BY | Yes | Credit required; it must be tracked in this file |
| CC-BY-SA | Flag before use | Derivative art must carry the same licence |
| CC-NC | **Never** | Non-commercial; excludes a Steam release |

## Packs

| Pack | Author | Source | Licence |
|---|---|---|---|
| Slates [32x32px orthogonal tileset] | Ivan Voirol | <https://opengameart.org/content/slates-32x32px-orthogonal-tileset-by-ivan-voirol> | CC-BY 4.0 |
| Top-Down RPG Character Sprites | Bukket Games | <https://opengameart.org/content/top-down-rpg-character-sprites> | CC-BY 3.0 |
| Fantozzi's Footsteps (Grass/Sand & Stone) | Fantozzi, via qubodup | <https://opengameart.org/content/fantozzis-footsteps-grasssand-stone> | CC0 1.0 |
| Ambient Bird Sounds | isaiah658 | <https://opengameart.org/content/ambient-bird-sounds> | CC0 1.0 |

**The two art entries are licence conditions, not courtesies.** CC-BY
requires attribution wherever the work is distributed, which includes any
exported build's credits. Ivan Voirol's notice reads simply "Ivan Voirol".
Bukket Games' additionally requires that <http://www.playbukketgames.com>
be displayed. Deleting either line breaks the licence it records.

**The two audio entries are courtesies, and are kept anyway.** CC0 waives
attribution outright; isaiah658's notice says credit "is not needed but is
appreciated", which is appreciation, not a condition. They are listed
because this file is the record of every licence that was *checked* --
a pack absent from the table is indistinguishable from a pack nobody
looked at, and that ambiguity is exactly what costs a week before a
launch. The Allowed column is the audit trail.

Audio is used as authored and is byte-identical to the packs as
published; see `assets/audio/LICENSE.txt`. Art is not.

All imported art is re-quantized onto the Apollo palette at import time by
`tools/quantize.gd` and is therefore not pixel-identical to the packs as
published. The unmodified originals are in `assets/_source/`.
