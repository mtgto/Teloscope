#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
Compare baseline PNGs against newly-generated snapshots.
Creates 3-panel diff images (baseline | diff | new) and writes
a GitHub Actions Job Summary. Exits with code 1 if any view
exceeds the change threshold.
"""
import base64
import io
import os
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

THRESHOLD = 0.01  # fail if more than 1% of pixels change


def pixel_diff_ratio(baseline: Image.Image, new: Image.Image) -> float:
    if baseline.size != new.size:
        new = new.resize(baseline.size, Image.LANCZOS)
    diff = ImageChops.difference(baseline.convert("RGB"), new.convert("RGB"))
    data = diff.tobytes()
    n_pixels = len(data) // 3
    changed = sum(1 for i in range(n_pixels) if max(data[3*i], data[3*i+1], data[3*i+2]) > 10)
    return changed / (baseline.width * baseline.height)


def create_panel(baseline: Image.Image, new: Image.Image) -> Image.Image:
    if baseline.size != new.size:
        new = new.resize(baseline.size, Image.LANCZOS)

    diff_rgb = ImageChops.difference(baseline.convert("RGB"), new.convert("RGB"))

    # Red-highlight changed pixels on a copy of the baseline
    highlighted = baseline.convert("RGBA").copy()
    diff_px = diff_rgb.load()
    hi_px = highlighted.load()
    for y in range(diff_rgb.height):
        for x in range(diff_rgb.width):
            if max(diff_px[x, y]) > 10:
                hi_px[x, y] = (220, 50, 50, 230)

    gap = 6
    label_h = 18
    w, h = baseline.width, baseline.height
    total_w = w * 3 + gap * 4
    total_h = h + label_h + gap * 2

    panel = Image.new("RGB", (total_w, total_h), (245, 245, 245))
    draw = ImageDraw.Draw(panel)

    labels = ["baseline", "diff", "new"]
    images = [baseline.convert("RGB"), highlighted.convert("RGB"), new.convert("RGB")]
    for i, (label, img) in enumerate(zip(labels, images)):
        x = gap + i * (w + gap)
        draw.text((x + 4, 3), label, fill=(100, 100, 100))
        panel.paste(img, (x, label_h + gap))

    return panel


def to_data_uri(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: vrt-report.py <baseline_dir> <new_dir>", file=sys.stderr)
        return 2

    baseline_dir = Path(sys.argv[1])
    new_dir = Path(sys.argv[2])
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")

    failures: list[tuple[Path, float, Image.Image, Image.Image]] = []

    for baseline_path in sorted(baseline_dir.rglob("*.png")):
        rel = baseline_path.relative_to(baseline_dir)
        new_path = new_dir / rel
        if not new_path.exists():
            print(f"WARNING: no new snapshot for {rel}", file=sys.stderr)
            continue
        baseline_img = Image.open(baseline_path)
        new_img = Image.open(new_path)
        ratio = pixel_diff_ratio(baseline_img, new_img)
        if ratio > THRESHOLD:
            failures.append((rel, ratio, baseline_img, new_img))

    lines: list[str] = []
    if failures:
        lines.append(f"## VRT Results — {len(failures)} difference(s) found\n")
        for rel, ratio, baseline_img, new_img in failures:
            panel = create_panel(baseline_img, new_img)
            lines.append(f"### {rel.stem} ({ratio * 100:.1f}% changed) ❌")
            lines.append(f"![diff]({to_data_uri(panel)})\n")
        lines.append("---")
        lines.append("To approve: add label `vrt-approved` to this PR")
    else:
        lines.append("## VRT Results — All passed ✅")

    output = "\n".join(lines)
    print(output)
    if summary_path:
        with open(summary_path, "a") as f:
            f.write(output + "\n")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
