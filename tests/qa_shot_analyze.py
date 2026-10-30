"""QA: численный разбор скриншота игрового вида (палитра/композиция/артефакты)."""
import sys
import numpy as np
from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else "qa_shot_live.png"
im = Image.open(path).convert("RGB")
w, h = im.size
a = np.asarray(im).astype(np.float32) / 255.0
luma = 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]

print(f"size={w}x{h}")
print(f"dark_ratio(luma<0.16) = {(luma < 0.16).mean():.3f}")
print(f"bright_ratio(luma>0.60) = {(luma > 0.60).mean():.4f}")
print(f"mean_luma = {luma.mean():.4f}")
print(f"mean_rgb = {a.reshape(-1,3).mean(axis=0).round(4).tolist()}")

# зоны (в долях кадра): фон-центр, океан-лево, верх-центр(скрим), панель справа
zones = {
    "top_scrim_band": (0.30, 0.75, 0.0, 0.30),
    "center_ocean": (0.30, 0.62, 0.35, 0.85),
    "left_ocean": (0.0, 0.28, 0.30, 0.95),
    "bottom_left": (0.0, 0.28, 0.80, 1.0),
    "right_panel": (0.62, 0.99, 0.05, 0.95),
}
for name, (x0, x1, y0, y1) in zones.items():
    xs, xe = int(x0 * w), int(x1 * w)
    ys, ye = int(y0 * h), int(y1 * h)
    z = luma[ys:ye, xs:xe]
    zc = a[ys:ye, xs:xe]
    print(f"zone {name:16s} luma={z.mean():.4f} dark={(z<0.16).mean():.3f} rgb={zc.reshape(-1,3).mean(axis=0).round(3).tolist()}")

# поиск жёстких вертикальных/горизонтальных швов (скачок средней luma по столбцу/строке)
def seams(axis_name, prof, thr=0.006):
    d = np.abs(np.diff(prof))
    idx = np.where(d > thr)[0]
    return [(int(i), round(float(d[i]), 4)) for i in idx[:40]]

col = luma.mean(axis=0)
row = luma.mean(axis=1)
print("vertical seams (x, jump):", seams("col", col))
print("horizontal seams (y, jump):", seams("row", row))

# средняя luma по столбцам для полосы y=20..240 (где ищем артефакт)
band = luma[20:240, :]
bcol = band.mean(axis=0)
print("band(20..240) col luma samples:", [(x, round(float(bcol[x]), 4)) for x in range(0, w, 96)])

# палитра: топ-цвета по квантованию
q = (a * 8).astype(np.int32)
flat = q.reshape(-1, 3)
keys = flat[:, 0] * 64 + flat[:, 1] * 8 + flat[:, 2]
vals, counts = np.unique(keys, return_counts=True)
order = np.argsort(-counts)[:8]
print("top palette buckets (r,g,b in 0..7):")
for i in order:
    k = int(vals[i])
    print(f"  ({(k//64)/8:.3f},{(k//8%8)/8:.3f},{(k%8)/8:.3f}) share={counts[i]/len(keys):.3f}")

# кропы для глаза (в tests/artifacts/, чтобы не мусорить в корне проекта)
import os
os.makedirs("tests/artifacts", exist_ok=True)
crops = {
    "tests/artifacts/crop_topleft.png": (0, 0, 420, 200),
    "tests/artifacts/crop_prestige.png": (0, 560, 460, 720),
    "tests/artifacts/crop_topband.png": (300, 0, 1040, 320),
    "tests/artifacts/crop_creature.png": (420, 220, 820, 560),
}
scale = w / 1280.0
for name, (x0, y0, x1, y1) in crops.items():
    box = (int(x0 * scale), int(y0 * scale), int(x1 * scale), int(y1 * scale))
    im.crop(box).resize(((box[2] - box[0]) * 2, (box[3] - box[1]) * 2), Image.LANCZOS).save(name)
    print("crop ->", name, box)
