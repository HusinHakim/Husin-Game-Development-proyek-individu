from PIL import Image, ImageDraw
import random, math

rng = random.Random(42)

TILE = 64
TRANSPARENT = (0, 0, 0, 0)
VOID        = (8,  6, 14, 255)
ROCK_DARK   = (18, 14, 30, 255)
ROCK_MID    = (32, 26, 50, 255)
ROCK_LIGHT  = (55, 45, 78, 255)
ROCK_HIGH   = (80, 65, 105, 255)
CRACK       = (10, 8,  18, 255)

def clamp(v):
    return max(0, min(255, int(v)))

def blend(c1, c2, t):
    return tuple(clamp(c1[i]*(1-t) + c2[i]*t) for i in range(4))

def noise_fill(img, x0, y0, x1, y1, base_col, seed=0):
    r = random.Random(seed)
    pix = img.load()
    for py in range(y0, y1):
        for px in range(x0, x1):
            n = r.gauss(0, 8)
            c = tuple(clamp(base_col[i] + n) for i in range(3)) + (255,)
            pix[px, py] = c

def bevel(draw, x0, y0, x1, y1, depth=3):
    for i in range(depth):
        t = i / depth
        light = blend(ROCK_HIGH, ROCK_MID, t)
        dark  = blend(CRACK, ROCK_DARK, t)
        draw.line([(x0+i, y0+i), (x1-i, y0+i)], fill=light[:3]+(200,))
        draw.line([(x0+i, y0+i), (x0+i, y1-i)], fill=light[:3]+(160,))
        draw.line([(x0+i, y1-i), (x1-i, y1-i)], fill=dark[:3]+(200,))
        draw.line([(x1-i, y0+i), (x1-i, y1-i)], fill=dark[:3]+(160,))

def draw_crack(draw, x0, y0, length=20, angle=45, seed=0):
    r = random.Random(seed)
    cx, cy = x0, y0
    a = math.radians(angle)
    pts = [(cx, cy)]
    for _ in range(length // 4):
        a += r.uniform(-0.4, 0.4)
        cx += int(math.cos(a) * 4)
        cy += int(math.sin(a) * 4)
        pts.append((cx, cy))
    if len(pts) > 1:
        draw.line(pts, fill=CRACK[:3]+(220,), width=1)

# ── Tile generators ──────────────────────────────────────

def make_wall_top(seed=0):
    img = Image.new('RGBA', (TILE, TILE), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    noise_fill(img, 0, 0, TILE, TILE, ROCK_MID, seed)
    r = random.Random(seed+1)
    for row in [16, 32, 48]:
        off = r.randint(-2, 2)
        draw.line([(0, row+off), (TILE, row+off)], fill=CRACK[:3]+(160,), width=1)
    for col in [16, 32, 48]:
        off = r.randint(-2, 2)
        draw.line([(col+off, 0), (col+off, TILE)], fill=CRACK[:3]+(140,), width=1)
    bevel(draw, 0, 0, TILE-1, TILE-1, depth=4)
    if r.random() > 0.4:
        draw_crack(draw, r.randint(4,54), r.randint(4,54), length=18, angle=r.randint(0,360), seed=seed+9)
    return img

def make_wall_face(seed=0):
    img = Image.new('RGBA', (TILE, TILE), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    pix = img.load()
    r = random.Random(seed)
    for py in range(TILE):
        t = py / TILE
        base = blend(ROCK_DARK, ROCK_MID, t * 0.6)
        for px in range(TILE):
            n = r.gauss(0, 6)
            c = tuple(clamp(base[i] + n) for i in range(3)) + (255,)
            pix[px, py] = c
    for row in [20, 42]:
        off = r.randint(-1, 1)
        draw.line([(0, row+off), (TILE, row+off)], fill=CRACK[:3]+(180,), width=1)
    offsets = [0, 32] if seed % 2 == 0 else [16, 48]
    for col in offsets:
        draw.line([(col, 0), (col, 20)], fill=CRACK[:3]+(150,), width=1)
        draw.line([(col+16, 21), (col+16, 41)], fill=CRACK[:3]+(150,), width=1)
        draw.line([(col, 42), (col, TILE)], fill=CRACK[:3]+(150,), width=1)
    for py in range(8):
        alpha = int(180 * (1 - py/8))
        draw.line([(0,py),(TILE-1,py)], fill=(0,0,0,alpha))
    draw.line([(0,TILE-2),(TILE-1,TILE-2)], fill=ROCK_HIGH[:3]+(60,))
    if r.random() > 0.5:
        draw_crack(draw, r.randint(8,48), r.randint(8,40), length=14, angle=r.randint(60,120), seed=seed+7)
    return img

def make_wall_cracked(base_fn, seed=0):
    img = base_fn(seed)
    draw = ImageDraw.Draw(img)
    r = random.Random(seed + 100)
    for _ in range(4):
        draw_crack(draw, r.randint(4, 54), r.randint(4, 54),
                   length=r.randint(12, 28), angle=r.randint(0, 360), seed=r.randint(0, 9999))
    cx, cy = r.randint(16, 48), r.randint(16, 48)
    draw.ellipse([(cx-6,cy-6),(cx+6,cy+6)], fill=CRACK[:3]+(80,))
    return img

def make_corner(seed=0):
    img = Image.new('RGBA', (TILE, TILE), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    noise_fill(img, 0, 0, TILE, TILE, ROCK_DARK, seed)
    bevel(draw, 0, 0, TILE-1, TILE-1, depth=5)
    r = random.Random(seed)
    for py in range(TILE):
        t = py/TILE
        alpha = int(120 * (1 - t))
        draw.point((TILE//2, py), fill=ROCK_HIGH[:3]+(alpha,))
    if r.random() > 0.6:
        draw_crack(draw, TILE//2, r.randint(4,30), length=12, angle=90, seed=seed+3)
    return img

def make_rubble(seed=0):
    img = Image.new('RGBA', (TILE, TILE), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    r = random.Random(seed)
    for _ in range(8):
        sx = r.randint(2, TILE-18)
        sy = r.randint(2, TILE-12)
        sw = r.randint(6, 18)
        sh = r.randint(4, 14)
        col = r.choice([ROCK_DARK, ROCK_MID, ROCK_LIGHT])
        chunk = Image.new('RGBA', (sw, sh), col)
        chunk_d = ImageDraw.Draw(chunk)
        chunk_d.rectangle([(0,0),(sw-1,sh-1)], outline=CRACK[:3]+(200,))
        img.paste(chunk, (sx, sy), chunk)
    for py in range(TILE-8, TILE):
        t = (py-(TILE-8))/8
        draw.line([(0,py),(TILE-1,py)], fill=(0,0,0,int(60*t)))
    return img

def make_pillar(seed=0):
    img = Image.new('RGBA', (TILE, TILE), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    noise_fill(img, 0, 0, TILE, TILE, VOID, seed)
    r = random.Random(seed)
    px0, py0, px1, py1 = 12, 8, TILE-12, TILE-8
    noise_fill(img, px0, py0, px1, py1, ROCK_MID, seed+1)
    bevel(draw, px0, py0, px1-1, py1-1, depth=5)
    cx, cy = TILE//2, TILE//2
    for radius in range(10, 0, -1):
        t = radius/10
        a = int(30*(1-t))
        draw.ellipse([(cx-radius, cy-radius),(cx+radius, cy+radius)],
                     outline=ROCK_HIGH[:3]+(a,))
    return img

def make_torch_wall(seed=0):
    img = make_wall_face(seed)
    draw = ImageDraw.Draw(img)
    cx = TILE // 2
    draw.rectangle([(cx-3, 18), (cx+3, 30)], fill=ROCK_LIGHT[:3]+(200,))
    for radius in range(8, 0, -1):
        t = radius/8
        a = int(160*(1-t))
        draw.ellipse([(cx-radius, 8-radius),(cx+radius, 8+radius)], fill=(220, 120, 20, a))
    draw.ellipse([(cx-2, 2),(cx+2, 10)], fill=(255,200,60,180))
    return img

# ── Assemble 8x4 sheet ───────────────────────────────────
COLS, ROWS = 8, 4
sheet = Image.new('RGBA', (COLS*TILE, ROWS*TILE), TRANSPARENT)

def place(col, row, tile_img):
    sheet.paste(tile_img, (col*TILE, row*TILE), tile_img)

for i in range(4):
    place(i,   0, make_wall_top(seed=i*7))
    place(i+4, 0, make_wall_face(seed=i*11))

for i in range(4):
    place(i,   1, make_wall_cracked(make_wall_top,  seed=i*7))
    place(i+4, 1, make_wall_cracked(make_wall_face, seed=i*11))

for i in range(4):
    place(i,   2, make_corner(seed=i*13))
    place(i+4, 2, make_rubble(seed=i*17))

for i in range(4):
    place(i,   3, make_pillar(seed=i*19))
    place(i+4, 3, make_torch_wall(seed=i*23))

out = r"C:\Users\husin\OneDrive\Documents\tugas-proyek\assets\sprites\environment\Wall_Tileset.png"
sheet.save(out)
print("Saved:", out)
print("Sheet size:", sheet.size)
