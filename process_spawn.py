"""
Run this after saving spawn_spritesheet.png to the characters folder.
It removes the white background, crops the 10 frames (5x2 grid),
and outputs cultist_spawn_256.png (a 10-frame horizontal strip at 256x256 per frame).
"""
from PIL import Image

SRC = "assets/sprites/characters/spawn_spritesheet.png"
OUT = "assets/sprites/characters/cultist_spawn_256.png"
ROWS, COLS = 2, 5

src = Image.open(SRC).convert("RGBA")
W, H = src.size
fw = W // COLS
fh = H // ROWS
print(f"Source: {W}x{H}, frame size: {fw}x{fh}")

# Remove white background (tolerance 30)
pixels = src.load()
for y in range(H):
    for x in range(W):
        r, g, b, a = pixels[x, y]
        if r > 220 and g > 220 and b > 220:
            pixels[x, y] = (0, 0, 0, 0)

# Build 10-frame horizontal strip at 256x256
out = Image.new("RGBA", (256 * ROWS * COLS, 256), (0, 0, 0, 0))
idx = 0
for row in range(ROWS):
    for col in range(COLS):
        frame = src.crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh))
        # Scale to fit 256x256 preserving aspect ratio
        frame.thumbnail((256, 256), Image.Resampling.LANCZOS)
        # Center in 256x256 cell
        cell = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        ox = (256 - frame.width) // 2
        oy = (256 - frame.height) // 2
        cell.paste(frame, (ox, oy), frame)
        out.paste(cell, (idx * 256, 0))
        idx += 1

out.save(OUT)
print(f"Saved {OUT} ({ROWS*COLS} frames at 256x256)")
