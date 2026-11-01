"""Build-time asset compiler: src/assets -> src/gen + target/assets. build.bat runs it.

Reads (all editable):
  src/assets/cards/NN.png     88 x 152 card faces, NN = card id 00-77 (alpha < 128 = transparent)
  src/assets/thumbs/NN.png    28 x 48 thumbnails
  src/assets/back.png, back_thumb.png   card backs (same sizes)
  src/assets/title.png, table.png       320 x 200 title screen and reading cloth
  src/assets/meanings.txt     names and meanings (see its header)
Writes:
  src/gen/palette.asm   the 256 colours: 0-31 UI (COL_* below), 32-47 title, 48-63 table,
                        64-79 card backs, 80-255 card art
  src/gen/cards.asm     constants, per-card 16-entry colour tables, names, text offsets
  src/gen/manifest.asm  packed files and attic addresses (lib/manifest.asm)
  target/assets/*       the packed files, files.txt for build.bat
  private/temp/preview_*.png   what the quantised art looks like (if private/ exists)

Formats (see src/assets/README.md): card faces and thumbnails are 4 bits a pixel, column-major
(x * h + y), high nibble first, nibble 0 transparent, nibble n = colour card_lut[id*16+n]. The
title and table are 4 bits a pixel in Full Colour framebuffer order (offset = (x>>3)*1600 +
y*8 + (x&7)), nibble n = colour base+n. The backs are 8 bits a pixel, column-major.
"""
import os
import textwrap

from PIL import Image

import m65assets as m

A = m.SRC_ASSETS
BIG_W, BIG_H = 88, 152
TH_W, TH_H = 28, 48
N_CARDS = 78

# UI colours the code names (entries 0-15; 16-31 spare)
UI = [('BLACK', (0, 0, 0)), ('BONE', (232, 222, 200)), ('GOLD', (226, 184, 84)),
      ('DIMGOLD', (130, 92, 38)), ('RED', (210, 36, 48)), ('DKRED', (90, 10, 20)),
      ('PURPLE', (150, 90, 196)), ('DKPURPLE', (44, 16, 64)), ('PANEL', (16, 5, 26)),
      ('BTN', (52, 22, 74)), ('BTNHI', (104, 46, 136)), ('GREY', (128, 118, 140)),
      ('GHOST', (140, 230, 180)), ('LAVENDER', (196, 176, 226)), ('SHADOW', (6, 0, 10)),
      ('GLOW', (255, 220, 120))]
TITLE_BASE, TABLE_BASE, BACK_BASE, CARD_BASE = 32, 48, 64, 80
# exact colours in the art that the code animates (private/tools/make_art.py)
FLAMES = [(255, 244, 190), (255, 176, 48), (214, 84, 16)]
TITLE_RED = (176, 16, 32)
RING_GOLD = (150, 110, 40)
MOON = [(232, 226, 196), (200, 192, 166), (196, 180, 150)]   # moon, subtitle, wax: kept exact

# attic layout
AT_CARDS = 0x8000000            # 4 bpp faces, BIG_BYTES each
AT_THUMBS = 0x8080000           # 4 bpp thumbnails, TH_BYTES each
AT_BACKS = 0x8090000            # 8 bpp: big back, thumb back, thumb back turned 90 degrees
AT_TITLE4 = 0x80A0000           # 4 bpp title
AT_TABLE4 = 0x80A8000           # 4 bpp table
AT_TEXT = 0x80B0000             # meaning records
AT_TITLE8 = 0x80C0000           # (the code expands the backgrounds to 8 bpp here at boot)
AT_TABLE8 = 0x80D0000

TEXT_W = 25                     # characters a line in the card detail view
KEY_LINES = 2
MEANING_LINES = 12
CHARS = set(' !"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]')


def rgba(path, size):
    im = Image.open(path).convert('RGBA')
    assert im.size == size, '%s must be %dx%d' % (path, size[0], size[1])
    return im


def palette_image(colours):
    p = Image.new('P', (1, 1))
    flat = [v for c in colours for v in c]
    p.putpalette(flat + flat[:3] * (256 - len(colours)))
    return p


def dither(im, colours):
    """RGB(A) image -> list of indices into colours (Floyd-Steinberg); transparent -> None"""
    q = im.convert('RGB').quantize(palette=palette_image(colours), dither=Image.Dither.FLOYDSTEINBERG)
    idx = [min(i, len(colours) - 1) if i < len(colours) else 0 for i in q.getdata()]
    if im.mode == 'RGBA':
        idx = [None if a < 128 else i for i, a in zip(idx, im.getchannel('A').getdata())]
    return idx


def median(im, n, kmeans=0):
    """the n main colours of an image's opaque pixels"""
    px = [p[:3] for p in im.getdata() if len(p) < 4 or p[3] >= 128]
    strip = Image.new('RGB', (len(px), 1))
    strip.putdata(px)
    q = strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT, kmeans=kmeans)
    pal = q.getpalette()[:n * 3]
    pal += [0] * (n * 3 - len(pal))             # (fewer colours than asked for: pad)
    return [tuple(pal[i * 3:i * 3 + 3]) for i in range(n)]


def nearest(c, colours):
    return min(range(len(colours)), key=lambda i: sum((a - b) ** 2 for a, b in zip(c, colours[i])))


def column_major(idx, w, h):
    return [idx[y * w + x] for x in range(w) for y in range(h)]


def fcm_order(idx, w=320, h=200):
    out = [0] * (w * h)
    for y in range(h):
        for x in range(w):
            out[(x >> 3) * h * 8 + y * 8 + (x & 7)] = idx[y * w + x]
    return out


def nibbles(vals):
    return bytes((vals[i] << 4) | vals[i + 1] for i in range(0, len(vals), 2))


def background(path, forced, n=16):
    """a 320x200 picture -> (16 colours, nibble stream in FCM order, {forced colour: nibble})
    Pixels exactly a forced colour get that colour's nibble; nothing else may use it."""
    im = Image.open(path).convert('RGB')
    assert im.size == (320, 200), path + ' must be 320x200'
    px = list(im.getdata())
    present = [c for c in forced if c in px]
    rest = Image.new('RGB', im.size)
    rest.putdata([p for p in px if p not in present] or [(0, 0, 0)])
    free = median(rest, n - len(present))
    cols = free + present
    idx = dither(im, free)
    idx = [len(free) + present.index(p) if p in present else i for p, i in zip(px, idx)]
    if os.path.isdir(m.ROOT + '/private/temp'):
        prev = Image.new('RGB', im.size)
        prev.putdata([cols[i] for i in idx])
        prev.save(m.ROOT + '/private/temp/preview_' + os.path.basename(path))
    return cols, nibbles(fcm_order(idx)), {c: len(free) + i for i, c in enumerate(present)}


def cards(names):
    faces = [rgba(os.path.join(A, 'cards', '%02d.png' % i), (BIG_W, BIG_H)) for i in range(N_CARDS)]
    thumbs = [rgba(os.path.join(A, 'thumbs', '%02d.png' % i), (TH_W, TH_H)) for i in range(N_CARDS)]
    # one shared palette for all the card art, then 15 of those colours per card
    sheet = Image.new('RGBA', (BIG_W * 13, BIG_H * 6))
    for i, f in enumerate(faces):
        sheet.paste(f, ((i % 13) * BIG_W, (i // 13) * BIG_H))
    shared = median(sheet, 256 - CARD_BASE, kmeans=1)
    luts, big, small = [], bytearray(), bytearray()
    prev = Image.new('RGB', (BIG_W * 13, BIG_H * 6))
    for i in range(N_CARDS):
        own = sorted({nearest(c, shared) for c in median(faces[i], 15)})
        cols = [shared[k] for k in own]
        luts.append([0] + [CARD_BASE + k for k in own] + [0] * (15 - len(own)))
        for im, out, w, h in ((faces[i], big, BIG_W, BIG_H), (thumbs[i], small, TH_W, TH_H)):
            idx = dither(im, cols)
            out += nibbles(column_major([0 if v is None else v + 1 for v in idx], w, h))
            if im is faces[i]:
                p = Image.new('RGB', (w, h))
                p.putdata([(0, 0, 0) if v is None else cols[v] for v in idx])
                prev.paste(p, ((i % 13) * BIG_W, (i // 13) * BIG_H))
    if os.path.isdir(m.ROOT + '/private/temp'):
        prev.save(m.ROOT + '/private/temp/preview_cards.png')
    return shared, luts, big, small


def backs():
    big = rgba(os.path.join(A, 'back.png'), (BIG_W, BIG_H))
    th = rgba(os.path.join(A, 'back_thumb.png'), (TH_W, TH_H))
    both = Image.new('RGBA', (BIG_W + TH_W, BIG_H))
    both.paste(big, (0, 0))
    both.paste(th, (BIG_W, 0))
    cols = median(both, 16)
    data = bytearray()
    for im, w, h in ((big, BIG_W, BIG_H), (th, TH_W, TH_H), (th.rotate(-90, expand=True), TH_H, TH_W)):
        idx = dither(im, cols)
        data += bytes(column_major([0 if v is None else BACK_BASE + v for v in idx], w, h))
    return cols, data


# ---- text ----------------------------------------------------------------------------

def load_meanings():
    cards, cur = {}, None
    for line in open(os.path.join(A, 'meanings.txt'), encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('['):
            cur = cards.setdefault(int(line[1:-1]), {})
            continue
        k, _, v = line.partition(':')
        cur.setdefault(k.strip().upper(), []).append(v.strip())
    assert sorted(cards) == list(range(N_CARDS)), 'meanings.txt needs blocks [00]..[77]'
    return cards


def screen_text(s):
    s = s.upper().replace('â€”', '-').replace('â€™', "'")
    return ''.join(c if c in CHARS else ' ' for c in s)


def wrap(s, indent=''):
    return textwrap.wrap(screen_text(s), TEXT_W, subsequent_indent=indent) or ['']


def block(items, waite):
    """bullets that fit in MEANING_LINES, then as much of Waite's text as fits"""
    lines = []
    for it in items:
        w = wrap('* ' + it, '  ')
        if len(lines) + len(w) > MEANING_LINES - 4:      # (room for Waite's words)
            break
        lines += w
    # Waite's words: as many of his comma / semicolon separated terms as fit
    clauses = [c.strip() for c in waite.replace('.', ';').replace(',', ';').split(';') if c.strip()]
    best = []
    for k in range(1, len(clauses) + 1):
        w = wrap('WAITE: ' + ', '.join(clauses[:k]) + '.', '')
        if len(lines) + 1 + len(w) <= MEANING_LINES:
            best = w
    if best:
        lines += [''] + best
    return lines


def encode(lines):
    """lines -> one string, 13 between lines (lib/fcm_text.asm's new line), 0 at the end"""
    return b'\x0d'.join(bytes(screen_text(l), 'ascii') for l in lines) + b'\0'


def text_records(meanings):
    data, offs = bytearray(), []
    for i in range(N_CARDS):
        c = meanings[i]
        words = [w.strip() for w in c['KEYWORDS'][0].split(',')]
        while len(wrap(', '.join(words))) > KEY_LINES:      # whole keywords only
            words.pop()
        keys = wrap(', '.join(words))
        rec = encode(keys) + encode(block(c.get('UP', []), c.get('WAITE UP', [''])[0])) + \
            encode(block(c.get('REV', []), c.get('WAITE REV', [''])[0]))
        assert len(rec) <= 1024, 'card %d text too long' % i
        offs.append(len(data))
        data += rec
    assert len(data) < 0x10000
    return data, offs


def pointer():
    """src/assets/pointer.txt -> a 16-colour hardware sprite (lib/hwsprite.asm hws_full_colour):
    16 px wide, 8 bytes a row, high nibble left, nibble = UI colour entry (sprite 0's colours
    are palette entries 0-15)"""
    ui = {n: i for i, (n, _) in enumerate(UI)}
    key = {'.': 0, 'k': ui['SHADOW'], 'w': ui['BONE'], 'g': ui['GOLD'], 'd': ui['DIMGOLD'], 'r': ui['RED']}
    rows = [l.rstrip('\n') for l in open(os.path.join(A, 'pointer.txt')) if not l.startswith('#')]
    rows = [r.ljust(16, '.')[:16] for r in rows][:21]
    rows += ['.' * 16] * (21 - len(rows))
    data = [key[r[x]] << 4 | key[r[x + 1]] for r in rows for x in range(0, 16, 2)]
    return ['        .align 64'] + m.asm_bytes('pointer_shape', data, 8)


# ---- output --------------------------------------------------------------------------

def build():
    meanings = load_meanings()
    names = [screen_text(meanings[i]['NAME'][0]) for i in range(N_CARDS)]
    title_cols, title4, title_forced = background(os.path.join(A, 'title.png'), FLAMES + [TITLE_RED] + MOON)
    table_cols, table4, table_forced = background(os.path.join(A, 'table.png'), [RING_GOLD])
    back_cols, back8 = backs()
    shared, luts, big, small = cards(names)
    pal = [c for _, c in UI] + [(0, 0, 0)] * (TITLE_BASE - len(UI))
    pal += title_cols + table_cols + back_cols + shared
    assert len(pal) == 256, len(pal)
    m.write_palette(pal)
    text, offs = text_records(meanings)

    files = []
    for prefix, data, at in (('FACES', big, AT_CARDS), ('THUMBS', small, AT_THUMBS), ('BACKS', back8, AT_BACKS),
                             ('TITLE', title4, AT_TITLE4), ('TABLE', table4, AT_TABLE4), ('TEXT', text, AT_TEXT)):
        # (4 bpp art has few zero runs, so packing can grow it a little: smaller parts)
        files += [(n, at + off, ln) for n, off, ln in m.write_parts(prefix, data, 0xE000)]
    m.write_manifest(files)

    def entry(forced, c, base):
        return base + forced[c] if c in forced else 0
    lines = ['N_CARDS         = %d' % N_CARDS,
             'BIG_W           = %d' % BIG_W, 'BIG_H           = %d' % BIG_H,
             'TH_W            = %d' % TH_W, 'TH_H            = %d' % TH_H,
             'BIG_BYTES       = %d' % (BIG_W * BIG_H // 2), 'TH_BYTES        = %d' % (TH_W * TH_H // 2),
             'TITLE_BASE      = %d' % TITLE_BASE, 'TABLE_BASE      = %d' % TABLE_BASE]
    lines += ['COL_%-12s= %d' % (n, i) for i, (n, _) in enumerate(UI)]
    for k, c in enumerate(FLAMES):
        lines.append('TITLE_FLAME%d    = %d    ; %d, %d, %d' % ((k, entry(title_forced, c, TITLE_BASE)) + c))
    lines.append('TITLE_RED_E     = %d' % entry(title_forced, TITLE_RED, TITLE_BASE))
    lines.append('TABLE_GOLD_E    = %d' % entry(table_forced, RING_GOLD, TABLE_BASE))
    lines += ['%-16s= $%07x' % (n, v) for n, v in (
        ('AT_CARDS', AT_CARDS), ('AT_THUMBS', AT_THUMBS), ('AT_BACKS', AT_BACKS), ('AT_TITLE4', AT_TITLE4),
        ('AT_TABLE4', AT_TABLE4), ('AT_TEXT', AT_TEXT), ('AT_TITLE8', AT_TITLE8), ('AT_TABLE8', AT_TABLE8))]
    lines += ['', 'flame_rgb:      .byte ' + ', '.join('%d, %d, %d' % c for c in FLAMES),
              'title_red_rgb:  .byte %d, %d, %d' % TITLE_RED, 'ring_gold_rgb:  .byte %d, %d, %d' % RING_GOLD, '']
    lines += m.asm_bytes('card_lut', [v for l in luts for v in l])
    lines += ['card_name_lo:   .byte ' + ','.join('<cname%d' % i for i in range(N_CARDS)),
              'card_name_hi:   .byte ' + ','.join('>cname%d' % i for i in range(N_CARDS)),
              'text_off_lo:    .byte ' + ','.join('$%02x' % (o & 255) for o in offs),
              'text_off_hi:    .byte ' + ','.join('$%02x' % (o >> 8) for o in offs)]
    lines += ['cname%d:  .null "%s"' % (i, n) for i, n in enumerate(names)]
    lines += [''] + pointer()
    m.write_gen('cards.asm', lines, 'card constants, colour tables, names, text offsets, pointer')
    print('assets: %d files, %d bytes' % (len(files), sum(os.path.getsize(os.path.join(m.ASSETS, n))
                                                          for n, _, _ in files)))


if __name__ == '__main__':
    build()
