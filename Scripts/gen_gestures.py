#!/usr/bin/env python3
"""
Builds every sprite the app ships, from the original CC0 sprite pack.

The pack has no smiling idle and no gesture animations, so both are
synthesised:

  idle   - the pack's Jump pose is drawn with a genuinely happy face
           (squinting eyes, open mouth, tongue out). That head is
           straightened onto each resting frame, so the character keeps
           its idle bob but grins the whole time.
  ear    - isolate one ear via its alpha component and rotate it about
           its base.
  paw    - same idea for the arm, hinged at the shoulder.

Both gesture sequences start and end on the exact idle_00 pose, so the
app can cut into a gesture (and back out) with no visible pop.

Everything is derived from the downloaded pack rather than from the
committed resources, so re-running is idempotent.

Usage:  python3 gen_gestures.py [--write]
"""
import io
import math
import sys
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "Sources/DeskPet/Resources/species"
PACK_URL = "https://opengameart.org/sites/default/files/CatnDog.zip"
PACK_CACHE = Path("/tmp/catndog_pack")

SPECIES = ("cat", "dog")
IDLE_FRAMES = 10
FRAMES = 20

# Height the sprites are written at. They render at 97.5pt, so 195px covers
# a 2x Retina display — the densest macOS has — and this leaves headroom on
# top of that. The source art is 474px tall; shipping it whole would be four
# times the bytes for detail no display can show. Palette/indexed PNGs were
# measured too and rejected: quantising drops fully-transparent pixels, which
# leaves a faint box around the character.
OUTPUT_HEIGHT = 240

# Rows next to the joint deliberately left in the base. Rotation resamples
# the moving layer with a soft (partly transparent) edge; if the base under
# that edge were erased, the softness would show as a bright 1px seam. These
# rows sit at the pivot, where rotation barely displaces anything, so keeping
# the originals is invisible but gives the soft edge something solid to sit on.
ERASE_INSET = 6

# Straightens the Jump pose's slightly cocked head. Found by searching for
# the rotation that best matches the resting head's silhouette (~98% overlap).
HEAD_ANGLE = 3.0

# Amplitudes are tuned against how the art looks at its true on-screen
# size (~130pt tall), not zoomed in.
#
# The ear is cut from the head along a straight line, so past roughly 20
# degrees that cut swings clear of the head's dome and the ear reads as
# detached. The arm is a genuinely separate shape hinged at the shoulder,
# so it tolerates a much larger swing.
PARAMS = {
    "earL": dict(amp=21.0, cycles=3, damp=0.7),
    "earR": dict(amp=-21.0, cycles=3, damp=0.7),
    "paw": dict(amp=48.0, cycles=3, damp=0.7),
}


# --------------------------------------------------------------------------
# source pack


def ensure_pack():
    """Downloads and extracts the original sprite pack once."""
    if (PACK_CACHE / "png").is_dir():
        return PACK_CACHE
    PACK_CACHE.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(PACK_URL) as r:
        data = r.read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        z.extractall(PACK_CACHE)
    return PACK_CACHE


def source_idle(species, i):
    return Image.open(ensure_pack() / "png" / species / f"Idle ({i + 1}).png").convert("RGBA")


def source_happy_head(species):
    return Image.open(ensure_pack() / "png" / species / "Jump (1).png").convert("RGBA")


# --------------------------------------------------------------------------
# helpers


def runs_of(row, thr=20):
    out, s = [], None
    for x, v in enumerate(row > thr):
        if v and s is None:
            s = x
        elif not v and s is not None:
            if x - 1 - s > 3:
                out.append((s, x - 1))
            s = None
    if s is not None and len(row) - 1 - s > 3:
        out.append((s, len(row) - 1))
    return out


def dilate(mask, radius):
    out = mask.copy()
    for _ in range(radius):
        shifted = out.copy()
        shifted[1:, :] |= out[:-1, :]
        shifted[:-1, :] |= out[1:, :]
        shifted[:, 1:] |= out[:, :-1]
        shifted[:, :-1] |= out[:, 1:]
        out = shifted
    return out


def head_centroid(alpha, cut=300):
    ys, xs = np.nonzero(alpha[:cut] > 20)
    return xs.mean(), ys.mean()


# --------------------------------------------------------------------------
# smiling idle


def smiling(idle, happy_src):
    """One resting frame wearing the Jump pose's grinning face.

    The grinning head is straightened, lined up with this frame's head,
    and drawn only inside the resting silhouette — so the outline stays
    exactly the resting one and no seam can appear. The tongue hangs
    below the chin, so pixels around it come across too, matched to the
    tongue's own shape rather than a bounding box, which would drag the
    Jump pose's chest shading along with it.
    """
    W, H = idle.size
    ai = np.array(idle)

    rot = happy_src.rotate(
        HEAD_ANGLE, resample=Image.BICUBIC,
        center=(happy_src.size[0] / 2, happy_src.size[1] / 2),
    )
    rot_alpha = np.array(rot)[:, :, 3]

    icx, icy = head_centroid(ai[:, :, 3])
    rcx, rcy = head_centroid(rot_alpha)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.paste(rot, (int(round(icx - rcx)), int(round(icy - rcy))))
    aj = np.array(canvas).astype(int)

    opaque_idle = ai[:, :, 3] > 20
    opaque_happy = aj[:, :, 3] > 200

    # Neck = narrowest row between head and body.
    neck = min((opaque_idle[y].sum(), y) for y in range(270, 336))[1]

    r, g, b, a = aj[:, :, 0], aj[:, :, 1], aj[:, :, 2], aj[:, :, 3]
    pink = (a > 200) & (r > 200) & (g < 170) & (b > 110)
    tongue = dilate(pink, 9)

    rows = np.zeros((H, W), bool)
    rows[:neck] = True

    use = opaque_idle & opaque_happy & (rows | tongue)
    out = ai.copy()
    out[use] = aj[use]
    return Image.fromarray(out, "RGBA")


def smiling_idle(species):
    happy_src = source_happy_head(species)
    return [smiling(source_idle(species, i), happy_src) for i in range(IDLE_FRAMES)]


# --------------------------------------------------------------------------
# gestures


def part_masks(alpha, kind):
    """Returns (part_mask, erase_mask, pivot).

    part_mask  - pixels that rotate
    erase_mask - pixels removed from the base
    """
    H, W = alpha.shape
    top = int(np.nonzero((alpha > 20).any(axis=1))[0].min())

    part = np.zeros((H, W), bool)
    erase = np.zeros((H, W), bool)

    last_two = None
    for y in range(top, H):
        if len(runs_of(alpha[y])) >= 2:
            last_two = y
        elif last_two is not None:
            break
    merge_y = last_two + 1

    if kind in ("earL", "earR"):
        idx = 0 if kind == "earL" else -1
        xs = []
        for y in range(top, merge_y):
            rr = runs_of(alpha[y])
            if len(rr) >= 2:
                a, b = rr[idx]
                part[y, a:b + 1] = True
                if y < merge_y - ERASE_INSET:
                    erase[y, a:b + 1] = True
                xs += [a, b]
        x0, x1 = min(xs), max(xs)
        pivot = ((x0 + x1) / 2.0, float(merge_y))

    elif kind == "paw":
        rows = []
        for y in range(merge_y, H):
            rr = runs_of(alpha[y])
            if len(rr) >= 2:
                a, b = rr[-1]
                if a > W * 0.52 and (b - a) < 70:
                    rows.append(y)
        start = rows[0]
        end = start
        for y in rows[1:]:
            if y - end <= 3:
                end = y
            else:
                break
        xs = []
        for y in range(start, end + 1):
            rr = runs_of(alpha[y])
            if len(rr) >= 2:
                a, b = rr[-1]
                part[y, a:b + 1] = True
                if y > start + ERASE_INSET:
                    erase[y, a:b + 1] = True
                xs += [a, b]
        x0, x1 = min(xs), max(xs)
        pivot = ((x0 + x1) / 2.0, float(start))

    else:
        raise ValueError(kind)

    return part, erase, pivot


def build(base, kind, amp, cycles, damp):
    arr = np.array(base)
    part, erase, pivot = part_masks(arr[:, :, 3], kind)

    layer_arr = arr.copy()
    layer_arr[~part] = 0
    layer = Image.fromarray(layer_arr, "RGBA")

    base_arr = arr.copy()
    base_arr[erase] = 0
    erased = Image.fromarray(base_arr, "RGBA")

    out = []
    for i in range(FRAMES):
        t = i / (FRAMES - 1)
        # Damped oscillation; sin(2*pi*cycles*t) is exactly 0 at t=0 and
        # t=1, so the first and last frames equal the resting pose.
        ang = amp * math.sin(2 * math.pi * cycles * t) * math.exp(-damp * t)
        if abs(ang) < 1e-9:
            # Emit the untouched base at zero deflection. Resampling and
            # the erase/recomposite round trip would otherwise shift a
            # handful of edge pixels, and the app cuts into and out of the
            # idle loop on exactly these frames.
            out.append(base.copy())
            continue
        rot = layer.rotate(ang, resample=Image.BICUBIC, center=pivot)
        frame = erased.copy()
        frame.alpha_composite(rot)
        out.append(frame)
    return out


# --------------------------------------------------------------------------


def for_shipping(frame):
    """Downscales a frame to the size the app actually draws."""
    w = round(frame.size[0] * OUTPUT_HEIGHT / frame.size[1])
    return frame.resize((w, OUTPUT_HEIGHT), Image.LANCZOS)


def contact_sheet(frames, path, cols=10):
    w, h = frames[0].size
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGBA", (w * cols, h * rows), (245, 245, 245, 255))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, ((i % cols) * w, (i // cols) * h))
    sheet.convert("RGB").resize((w * cols // 4, h * rows // 4)).save(path)


def tongue_extent(frame, min_run=3):
    """Lowest row the grin reaches, as a fraction of the art's height.
    The resting reveal has to clear this or the tongue shows up clipped.

    Rows are required to hold a few pink pixels: the art has the odd
    isolated pixel that happens to match, and a single one would otherwise
    drag the answer far down the body.
    """
    a = np.array(frame).astype(int)
    r, g, b, al = a[:, :, 0], a[:, :, 1], a[:, :, 2], a[:, :, 3]
    pink = (al > 200) & (r > 200) & (g < 170) & (b > 110)
    rows = np.nonzero(pink.sum(axis=1) >= min_run)[0]
    if not len(rows):
        raise ValueError("no pink found")
    return rows.max() / frame.size[1]


def arm_start(frame):
    """Topmost row of the detached arm, as a fraction of the art's height.
    The resting reveal stays above this so a paw wave stays a surprise.
    """
    alpha = np.array(frame)[:, :, 3]
    _, erase, pivot = part_masks(alpha, "paw")
    return pivot[1] / frame.size[1]


# Each character appears wearing one of these faces, chosen per peek. The
# gestures are generated per face too, so clicking never changes the
# expression mid-animation.
FACES = ("plain", "smiling")


def face_idle(species, face):
    if face == "plain":
        return [source_idle(species, i) for i in range(IDLE_FRAMES)]
    if face == "smiling":
        return smiling_idle(species)
    raise ValueError(face)


if __name__ == "__main__":
    write = "--write" in sys.argv

    for species in SPECIES:
        for face in FACES:
            dest = ROOT / species / face
            dest.mkdir(parents=True, exist_ok=True)

            idle = face_idle(species, face)
            contact_sheet(idle, f"/tmp/sheet_{species}_{face}_idle.png")

            arms = min(arm_start(f) for f in idle)
            try:
                deepest = max(tongue_extent(f) for f in idle)
                grin = f"grin reaches {deepest:.3f}, "
            except ValueError:
                grin = ""
            print(f"{species}/{face}/idle: {len(idle)} frames — "
                  f"{grin}arms start {arms:.3f}")

            if write:
                for i, f in enumerate(idle):
                    for_shipping(f).save(dest / f"idle_{i:02d}.png")

            for kind, p in PARAMS.items():
                frames = build(idle[0], kind, **p)
                print(f"{species}/{face}/{kind}: {len(frames)} frames")
                if write:
                    for i, f in enumerate(frames):
                        for_shipping(f).save(dest / f"gesture_{kind}_{i:02d}.png")

        # Clear the older flat layout, which had one face per species.
        if write:
            for stale in (ROOT / species).glob("*.png"):
                stale.unlink()

    print("written" if write else "(preview only — pass --write)")
