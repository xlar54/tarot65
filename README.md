Tarot 65
========

Tarot readings on the MEGA65 with the 1909 Rider-Waite-Smith deck, all 78 cards, played
with the mouse. Choose a spread on a moonlit graveyard title screen, click the deck to
shuffle, and watch the cards fly to their places on an occult reading cloth. Click a card to
turn it over, then click it again to read what it means in its position, upright or reversed.

Spreads:

| Spread | Cards | Positions |
|---|---|---|
| One card | 1 | Your card |
| Three cards | 3 | Past, present, future |
| Horseshoe | 7 | Past, present, hidden influences, the obstacle, others, advice, outcome |
| Celtic Cross | 10 | Present, challenge (laid across), foundation, recent past, crown, near future; then yourself, surroundings, hopes and fears, outcome |

Build
-----

Run `build.bat`. `tools/build_assets.py` first turns `src/assets/` into `src/gen/` and the
packed files in `target/assets/` (about 15 s: it quantises 78 cards). Then 64tass assembles
`src/main.asm` and c1541 writes `target/tarot65.d81` (the program, `AUTOBOOT.C65` and 15
asset files, about 690 KB).

Run
---

`run.bat` builds and starts Xemu with `-autoload`. On a real MEGA65, mount the D81 and run
it; `AUTOBOOT.C65` starts it automatically. The cards load into attic RAM at boot ("SUMMONING
THE SPIRITS..."): about 15-20 seconds in Xemu at real speed.

Controls
--------

A 1351 mouse in port 1.

* Title: click a spread. **REVERSALS ON/OFF** decides whether cards may fall upside down.
* Table: click the deck to shuffle and deal. Click a face-down card to turn it over, or
  **REVEAL ALL**. Point at a card to see its position (and its name once turned). Click a
  face-up card for its meaning. **NEW READING** returns to the title.
* Meaning: **< PREV** / **NEXT >** step through the spread (NEXT turns over cards still face
  down). **BACK** or the right button returns to the table.

Architecture
------------

| File | What |
|---|---|
| `src/main.asm` | Boot (loads every asset into attic), takeover, per-frame input and pointer, palette effects, sound table |
| `src/screens.asm` | Title, reading table (shuffle, deal, flip, hover, status lines), detail view |
| `src/spreads.asm` | The four layouts: card positions, position names and meanings |
| `src/gfx.asm` | 4 bpp to 8 bpp card expansion (backwards = reversed card), the 90-degree turn, the card blitter that squeezes cards for the flip, backgrounds, buttons, text helpers |
| `tools/build_assets.py` | Quantising, packing, text wrapping (formats in `src/assets/README.md`) |

Library modules used (`src/lib/`): system, dma, loader, unpack, manifest, video_fcm,
fcm_text, draw, palette, hwsprite, mouse, sid, math.

* **Boot:** every asset file is KERNAL-loaded once, in the untouched BASIC65 state, into attic
  RAM (`lib/manifest.asm`). Then the program takes over the machine and never calls the
  KERNAL again. The title and table pictures are expanded to 8 bpp in attic once; each redraw
  starts with one 64,000-byte DMA copy of the background.
* **Cards:** 78 cards at 8 bpp would not fit on one D81, so each face (88 x 152) and
  thumbnail (28 x 48) is stored at 4 bpp: 15 colours of its own, picked from a shared
  176-colour card palette. When a spread is dealt, its cards are expanded into chip RAM
  (`$20000`-`$3FFFF`, the unprotected ROM area). A reversed card is the same column-major
  picture written backwards, which turns it 180 degrees. The Celtic Cross's crossing card
  is turned 90 degrees by the CPU.
* **Screen:** 320 x 200 Full Colour double buffer. Screens redraw only when something
  changes (the pointer is a 16-colour hardware sprite); during shuffling, dealing and
  flipping they redraw every frame. The flip squeezes a card's width with a DDA over its
  columns: one DMA job per column.
* **Atmosphere:** candle flames flicker and the title and the reading ring glow by palette
  animation. SID effects: the riffle while shuffling, a swish per card dealt, a whoosh per
  flip, and a bell that tolls when a major arcanum is turned over (and now and then on the
  title).
* **Randomness:** the hardware RNG seeds each shuffle (falling back to the frame counter in
  Xemu), and the generator is stirred every frame, so the moment you click matters. It is a
  Fisher-Yates shuffle of all 78 cards.

Sources: card scans from Wikimedia Commons, "Rider-Waite tarot deck (Roses & Lilies)" (Pamela
Colman Smith, 1909, public domain). Meanings from A. E. Waite, *The Pictorial Key to the
Tarot* (1910, public domain), and Mark McElroy's *A Guide to Tarot Meanings* via the CC0
[dariusk/corpora](https://github.com/dariusk/corpora) collection. All of it is editable in
`src/assets/` (see its README).

Testing in Xemu: `python private\tools\xemu_run.py shot.png ...` with the debug bytes
`dbg_mx` (word), `dbg_my`, `dbg_cmd` (bit 0 move the pointer there, bit 1 left click, bit 2
right click), for example `poke:dbg_mx=a0,00,50,03` clicks at (160, 80). `dbg_hold=1`
freezes card flips so a mid-flip frame can be photographed. `frames_drawn` counts pictures
shown.

Note: this is a 45GS02 target. `STZ` stores the Z register, not zero; use `LDA #0 / STA`.

The repository holds only what the build needs: `src/`, `tools/`, `build.bat`, `run.bat` and
the bundled `64tass.exe` / `c1541.exe`. `src/gen/` and `target/` are written by the build.
`tools/` holds only the scripts the build needs. `private/` is gitignored. It holds local notes,
the library examples, test and development tools (`fetch_cards.py`, `import_cards.py`,
`make_art.py`), temporary data and the MEGA65 book, so none of them are published.
