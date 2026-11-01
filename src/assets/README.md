Assets
======

Everything here is editable. `tools/build_assets.py` compiles it on every build. The first
versions came from one-off tools in `private/tools/`: `fetch_cards.py` (downloads),
`import_cards.py` (cards, thumbnails, meanings) and `make_art.py` (title, table, backs).
Running those again **overwrites** these files, including your edits.

| File | Size | What |
|---|---|---|
| `cards/NN.png` | 88 x 152 | Card faces. NN = id: 00-21 major arcana, 22-35 wands, 36-49 cups, 50-63 swords, 64-77 pentacles (ace..ten, page, knight, queen, king). Alpha < 128 = transparent (the rounded corners). |
| `thumbs/NN.png` | 28 x 48 | The same cards for the Horseshoe and Celtic Cross |
| `back.png`, `back_thumb.png` | 88 x 152, 28 x 48 | Card backs. The build turns the small one 90 degrees itself for the crossing card. |
| `title.png` | 320 x 200 | Title screen (16 colours after quantising) |
| `table.png` | 320 x 200 | Reading cloth (16 colours) |
| `meanings.txt` | | One block per card: `[NN]`, `NAME:`, `KEYWORDS:`, `UP:` and `REV:` lines (one bullet each), `OMEN:` (unused for now), `WAITE UP:`, `WAITE REV:` |
| `pointer.txt` | 16 x 21 | The mouse pointer as text: `.` transparent, `k` shadow, `w` bone, `g` gold, `d` dim gold, `r` red |

Exact colours with a meaning (keep them when painting):

| Colour | Where | Effect |
|---|---|---|
| (255,244,190) (255,176,48) (214,84,16) | title candle flames | flicker |
| (176,16,32) | title lettering | slow glow |
| (232,226,196) (200,192,166) (196,180,150) | moon, subtitle, wax | kept exact (they'd be lost in 16 colours) |
| (150,110,40) | the table's ring | slow glow |

Formats the build writes
------------------------

* **Palette** (`src/gen/palette.asm`): 0-15 UI colours (`COL_*` in `src/gen/cards.asm`),
  32-47 title, 48-63 table, 64-79 card backs, 80-255 the shared card palette.
* **Faces and thumbnails** (`FACES0-9`, `THUMBS0`): 4 bits a pixel, column-major (x * h + y),
  high nibble first. Nibble 0 is transparent; nibble n is colour `card_lut[id * 16 + n]`. Each
  card picks 15 colours from the 176 shared ones (Floyd-Steinberg dithered).
* **Backs** (`BACKS0`): 8 bits a pixel, column-major: the big back, the small back, the small
  back turned 90 degrees clockwise.
* **Title and table** (`TITLE0`, `TABLE0`): 4 bits a pixel in Full Colour framebuffer order
  (offset = (x >> 3) * 1600 + y * 8 + (x & 7)); nibble n = colour base + n.
* **Text** (`TEXT0`): per card, three zero-terminated strings (keywords, upright, reversed),
  upper case, 25 characters a line, 13 between lines; `text_off_lo/hi` index them. Upright
  shows the `UP:` bullets, reversed the `REV:` bullets, each followed by as much of Waite's
  meaning as fits in 12 lines.
* All files are zero-run packed (`tools/pack.py`) in parts of up to 56 KB; the manifest
  (`src/gen/manifest.asm`) gives their attic addresses (`AT_*` in `src/gen/cards.asm`).
