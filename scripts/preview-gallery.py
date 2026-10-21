#!/usr/bin/env python3
"""Build and check the xFractal preview gallery (planning/gallery-scenarios-plan.md).

The snapshot test (GalleryTests/SnapshotGalleryTests) writes `<slug>.png`, `<slug>.dark.png` and `manifest.json` into a
directory; this script imports them into previews/ (gitignored) and builds previews/index.html: one card per scenario
with light and dark side by side, sections and cards in the manifest's order.

    scripts/preview-gallery.py --import DIR [--partial] [--lang en]   # replace the language's gallery (--partial: only DIR's files)
    scripts/preview-gallery.py --check [--lang en] [--measure]        # every scenario complete and correctly rendered
    scripts/preview-gallery.py --coverage                             # views no scenario names (informational)

English lives in previews/, another language in previews/<lang>/. An import touches only its own language's
top-level files, never another language's directory. PREVIEW_GALLERY_OUT replaces previews/ (the contract tests).

--check rebuilds the page first, then fails on: a scenario missing either image, a stray PNG no scenario expects, a
duplicate slug, a dark image byte-identical to its light one, an image that cannot be decoded, an invalid or
unmeasured region, and the region rules (the fractal drawn, the sheet's background lit, the peek capsule found). The
fractal fills most of a screen and is legitimately bright or dark, so the mean luminance of a whole image is never
judged. --measure enforces everything except the peek and sheet thresholds and writes calibration.json with the
numbers those thresholds are set from.
"""
import argparse
import html
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Thresholds (planning/gallery-scenarios-plan.md, "The luminance check judges the UI regions only"). The floors are fixed:
# a measured separation or coverage below them is a finding, never a reason to lower them.
PEEK_DELTA_FLOOR = 0.03
PEEK_DELTA = 0.075   # half the smallest measured separation (0.150, Board · Replay ready)
PEEK_COVERAGE_FLOOR = 0.70
PEEK_OUTSIDE_CEILING = 0.005
PEEK_WIDTH = (120, 380)
PEEK_HEIGHT = (28, 60)
PEEK_CENTER_TOLERANCE = 40
SHEET_COVERAGE_FLOOR = 0.50
SHEET_COVERAGE = 0.50   # half the smallest measured coverage is 0.434: the floor wins
# A translucent sheet (opening and medium detents, the regular-width form sheet) lets the board through: its region must
# read lighter in the light render than in the dark one by at least GLASS_DELTA (half the smallest measured, 0.26).
GLASS_DELTA_FLOOR = 0.10
GLASS_DELTA = 0.13
# ... and over enough of the region: the share of pixels brighter in light than in dark by GLASS_PIXEL_DELTA (a sparse
# bright/dark pattern can lift the mean alone).
GLASS_PIXEL_DELTA = 0.05
GLASS_COVERAGE_FLOOR = 0.50
GLASS_COVERAGE = 0.50
FRACTAL_MIN_STD = 0.02
FRACTAL_MEAN = (0.02, 0.98)


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def output_dir(lang):
    base = Path(os.environ.get("PREVIEW_GALLERY_OUT") or ROOT / "previews")
    return base if lang == "en" else base / lang


def load_manifest(out):
    path = out / "manifest.json"
    if not path.exists():
        sys.exit(f"no {path}: run scripts/snapshot-gallery.sh")
    return json.loads(path.read_text(encoding="utf-8"))


METADATA_CHUNKS = {b"eXIf", b"tEXt", b"iTXt", b"zTXt"}


def strip_metadata(data):
    """The PNG without its text and EXIF chunks (the gallery is shown and shared: images carry no metadata)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return data
    out, i = [data[:8]], 8
    while i + 8 <= len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        end = i + 12 + length
        if data[i + 4:i + 8] not in METADATA_CHUNKS:
            out.append(data[i:end])
        i = end
    return b"".join(out)


def do_import(source, partial, lang):
    out = output_dir(lang)
    source_manifest = source / "manifest.json"
    if not source_manifest.exists():
        sys.exit(f"{source} has no manifest.json: the snapshot test did not finish")
    pngs = sorted(source.glob("*.png"))
    out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(source_manifest.read_text(encoding="utf-8"))
    rendered = {p.name[:-len(".dark.png")] if p.name.endswith(".dark.png") else p.name[:-len(".png")] for p in pngs}
    if partial and not (out / "manifest.json").exists():
        # A first partial run in this folder (the App Store captures in another language): the gallery holds only
        # what it rendered.
        manifest = [e for e in manifest if e["slug"] in rendered]
    elif partial:
        # Merge: the entries of the slugs this run rendered replace the existing ones; every other entry keeps its
        # last measured regions. A slug that is new is added.
        existing = load_manifest(out)
        by_slug = {e["slug"]: e for e in manifest}
        merged = [by_slug.pop(e["slug"]) if e["slug"] in rendered and e["slug"] in by_slug else e for e in existing]
        known = {e["slug"] for e in existing}
        merged += [e for e in manifest if e["slug"] not in known]
        manifest = merged
    elif not partial:
        # Only this language's top-level files: previews/fr/ survives an English import.
        for stale in [*out.glob("*.png"), out / "manifest.json", out / "index.html", out / "calibration.json"]:
            if stale.is_file():
                stale.unlink()
    for png in pngs:
        (out / png.name).write_bytes(strip_metadata(png.read_bytes()))
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    build_page(manifest, out, lang)
    print(f"imported {len(pngs)} image(s) into {out}/")


def build_page(manifest, out, lang):
    groups = {}
    for entry in manifest:
        groups.setdefault(entry["group"], []).append(entry)

    def slot(dest, label, tag):
        if (out / dest).exists():
            return f'<a href="{html.escape(dest)}"><img src="{html.escape(dest)}" alt="{html.escape(label)} · {tag}" loading="lazy"></a>'
        return '<div class="missing">missing</div>'

    def figure(entry):
        label, slug = entry["name"], entry["slug"]
        size = entry.get("size")
        wide = isinstance(size, dict) and size.get("w", 0) > size.get("h", 1) * 0.6
        return (
            f'<figure id="{html.escape(slug)}"{" class=wide" if wide else ""}><figcaption>{html.escape(label)}</figcaption><div class="pair">'
            f'<div class="shot shot-light">{slot(slug + ".png", label, "Light")}<span class="tag">Light</span></div>'
            f'<div class="shot shot-dark">{slot(slug + ".dark.png", label, "Dark")}<span class="tag">Dark</span></div>'
            f'</div></figure>'
        )

    sections, links = [], []
    for title, entries in groups.items():
        section_id = slugify(title)
        items = "".join(figure(e) for e in entries)
        sections.append(f'<section id="{section_id}"><h2>{html.escape(title)}</h2><div class="row">{items}</div></section>')
        links.append(f'<a href="#{section_id}">{html.escape(title)}</a>')

    page = f'''<!doctype html>
<html lang="{html.escape(lang)}"><head>
<script>
(function(){{
  var m;
  try {{ m = localStorage.getItem('xfractal-gallery-mode'); }} catch(e) {{}}
  if (m !== 'light' && m !== 'dark' && m !== 'both') {{
    m = (window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
  }}
  document.documentElement.setAttribute('data-mode', m);
}})();
</script>
<meta charset="utf-8"><title>xFractal — screen gallery</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root {{ --bg:#f4f4f6; --ink:#1c1c1e; --muted:#6a6a70; --card:#fff; --line:#dedee3; --missing-bg:#ececf0; --accent:#3a4fb5; --accent-ink:#2c3d94; }}
html[data-mode="dark"] {{ --bg:#111114; --ink:#ececf0; --muted:#9c9ca6; --card:#1d1d22; --line:#33333a; --missing-bg:#18181c; --accent:#8191f0; --accent-ink:#a5b0f6; }}
@media (prefers-color-scheme: dark) {{
  html[data-mode="both"] {{ --bg:#111114; --ink:#ececf0; --muted:#9c9ca6; --card:#1d1d22; --line:#33333a; --missing-bg:#18181c; --accent:#8191f0; --accent-ink:#a5b0f6; }}
}}
body {{ margin:0; padding:24px 16px 48px; background:var(--bg); color:var(--ink);
  font:15px/1.4 -apple-system, "SF Pro Text", system-ui, sans-serif; }}
h1 {{ font-size:22px; margin:0 0 4px; }} p.meta {{ margin:0 0 24px; color:var(--muted); }}
h2 {{ font-size:20px; font-weight:650; margin:36px 0 16px; }}
.switch {{ display:inline-flex; gap:4px; padding:4px; margin-bottom:20px; background:var(--card); border:1px solid var(--line); border-radius:22px; }}
.switch button {{ appearance:none; border:0; background:transparent; color:var(--muted); font:inherit; font-weight:600; font-size:13px; padding:7px 16px; border-radius:18px; cursor:pointer; }}
.switch button[aria-pressed="true"] {{ background:var(--accent); color:#fff; }}
nav {{ display:flex; flex-wrap:wrap; gap:8px; margin-bottom:28px; }}
nav a {{ color:var(--ink); text-decoration:none; background:var(--card); border:1px solid var(--line); border-radius:20px; padding:7px 12px; }}
nav a:hover, nav a:focus-visible {{ border-color:var(--accent); color:var(--accent-ink); }}
section {{ scroll-margin-top:20px; }}
.row {{ display:flex; flex-wrap:wrap; gap:16px; align-items:flex-start; }}
figure {{ margin:0; width:320px; }}
figure.wide {{ width:480px; }}
figcaption {{ padding:0 4px 8px; font-weight:600; }}
.pair {{ display:flex; gap:8px; }}
.shot {{ width:150px; }}
.wide .shot {{ width:236px; }}
.shot img, .shot .missing {{ width:100%; display:block; border:1px solid var(--line); border-radius:16px; background:var(--card); box-sizing:border-box; }}
.shot .missing {{ aspect-ratio:9/19.5; display:flex; align-items:center; justify-content:center; color:var(--muted); font-size:12px; background:var(--missing-bg); }}
.shot .tag {{ display:block; text-align:center; font-size:11px; color:var(--muted); margin-top:4px; }}
html[data-mode="light"] .shot-dark, html[data-mode="dark"] .shot-light {{ display:none; }}
html[data-mode="light"] figure, html[data-mode="dark"] figure {{ width:256px; }}
html[data-mode="light"] figure.wide, html[data-mode="dark"] figure.wide {{ width:480px; }}
html[data-mode="light"] .shot, html[data-mode="dark"] .shot {{ width:240px; }}
html[data-mode="light"] .wide .shot, html[data-mode="dark"] .wide .shot {{ width:480px; }}
</style></head><body>
<div class="switch" role="group" aria-label="Appearance">
<button type="button" data-mode-btn="light" aria-pressed="false">Light</button>
<button type="button" data-mode-btn="dark" aria-pressed="false">Dark</button>
<button type="button" data-mode-btn="both" aria-pressed="false">Both</button>
</div>
<h1>xFractal — screen gallery{(' · ' + html.escape(lang)) if lang != 'en' else ''}</h1>
<p class="meta">{len(manifest)} screens · light and dark side by side · sections and cards in the order of the scenario list.</p>
<nav aria-label="Gallery themes">{''.join(links)}</nav>
{''.join(sections)}
<script>
(function(){{
  var root = document.documentElement;
  var btns = document.querySelectorAll('[data-mode-btn]');
  function sync(){{
    var m = root.getAttribute('data-mode');
    for (var i = 0; i < btns.length; i++) {{
      btns[i].setAttribute('aria-pressed', btns[i].getAttribute('data-mode-btn') === m ? 'true' : 'false');
    }}
  }}
  for (var i = 0; i < btns.length; i++) {{
    btns[i].addEventListener('click', function(e){{
      var m = e.currentTarget.getAttribute('data-mode-btn');
      root.setAttribute('data-mode', m);
      try {{ localStorage.setItem('xfractal-gallery-mode', m); }} catch(err) {{}}
      sync();
    }});
  }}
  sync();
}})();
</script>
</body></html>'''
    (out / "index.html").write_text(page, encoding="utf-8")


def png_intact(path):
    """True when the file is a whole PNG: signature, every chunk's length and CRC, and a closing IEND. ImageIO happily
    "decodes" a truncated file, so the structure is checked here."""
    try:
        data = path.read_bytes()
    except OSError:
        return False
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return False
    i, kinds = 8, []
    while i + 12 <= len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        end = i + 12 + length
        if end > len(data) or zlib.crc32(data[i + 4:i + 8 + length]) != struct.unpack(">I", data[end - 4:end])[0]:
            return False
        kinds.append(data[i + 4:i + 8])
        i = end
    return i == len(data) and bool(kinds) and kinds[0] == b"IHDR" and kinds[-1] == b"IEND"


def helper_command():
    """The pixel helper, compiled once into the temp directory (keyed by its source), or the interpreter as a fallback."""
    import hashlib
    import tempfile
    source = ROOT / "scripts" / "preview-luminance.swift"
    binary = Path(tempfile.gettempdir()) / f"xfractal-preview-luminance-{hashlib.sha256(source.read_bytes()).hexdigest()[:12]}"
    if not binary.exists():
        partial = binary.with_suffix(f".{os.getpid()}")
        built = subprocess.run(["swiftc", "-O", str(source), "-o", str(partial)], capture_output=True, text=True)
        if built.returncode == 0:
            os.replace(partial, binary)
    return [str(binary)] if binary.exists() else ["swift", str(source)]


def run_jobs(jobs):
    """Runs the pixel jobs through the Swift helper; one answer line per job (a JSON array), split into floats (None: undecodable)."""
    if not jobs:
        return [], None
    result = subprocess.run(helper_command(),
                            input="\n".join(json.dumps(j) for j in jobs) + "\n",
                            capture_output=True, text=True)
    if result.returncode != 0:
        return None, result.stderr.strip()[:200]
    lines = result.stdout.splitlines()
    if len(lines) != len(jobs):
        return None, f"luminance helper answered {len(lines)} lines for {len(jobs)} jobs"
    answers = []
    for line in lines:
        values = [float(v) for v in line.split()]
        answers.append(None if values == [-1.0] else values)
    return answers, None


def valid_region(region, width_pt, height_pt):
    """None when the region is valid, else the reason. Points, in the image's coordinate space."""
    values = [region.get(k) for k in ("x", "y", "w", "h")]
    if not all(isinstance(v, (int, float)) and math.isfinite(v) for v in values):
        return "not finite"
    x, y, w, h = values
    if w <= 0 or h <= 0:
        return "non-positive size"
    if x < 0 or y < 0 or x + w > width_pt + 0.5 or y + h > height_pt + 0.5:
        return "outside the image"
    return None


def pixels(region, scale):
    x, y, w, h = (region[k] * scale for k in ("x", "y", "w", "h"))
    x0, y0 = round(x), round(y)
    return x0, y0, max(1, round(x + w) - x0), max(1, round(y + h) - y0)


def do_check(lang, measure=False):
    out = output_dir(lang)
    manifest = load_manifest(out)
    build_page(manifest, out, lang)
    problems = []
    slugs = [e["slug"] for e in manifest]
    for slug in sorted({s for s in slugs if slugs.count(s) > 1}):
        problems.append(f"duplicate slug: {slug}")
    expected = {f"{s}{suffix}" for s in slugs for suffix in (".png", ".dark.png")}
    on_disk = {p.name for p in out.glob("*.png")}
    for file in sorted(expected - on_disk):
        problems.append(f"missing: {file}")
    for file in sorted(on_disk - expected):
        problems.append(f"stray image (no scenario): {file}")
    for slug in sorted(set(slugs)):
        light, dark = out / f"{slug}.png", out / f"{slug}.dark.png"
        if light.exists() and dark.exists() and light.read_bytes() == dark.read_bytes():
            problems.append(f"dark identical to light: {slug}")

    # Region jobs: collected for every scenario whose two images decode, then answered by one helper run.
    jobs, owners, calibration = [], [], {}
    # Every expected image is decoded in full (a truncated PNG with a valid header is undecodable), whatever its region
    # kinds; the decoded sizes must agree within a pair and with the manifest's size.
    sizes = {}
    present = sorted(on_disk & expected)
    intact = [f for f in present if png_intact(out / f)]
    decoded_ok, error = run_jobs([["decode", str(out / f)] for f in intact])
    decoded_by_file = dict(zip(intact, decoded_ok or []))
    decoded = [decoded_by_file.get(f) for f in present]
    if error:
        problems.append("luminance helper failed: " + error)
        decoded = [None] * len(present)
    for file, answer in zip(present, decoded):
        if answer is None:
            problems.append(f"undecodable image: {file}")
        sizes[file] = (int(answer[0]), int(answer[1])) if answer else None
    for e in manifest:
        slug = e["slug"]
        light, dark = sizes.get(f"{slug}.png"), sizes.get(f"{slug}.dark.png")
        if light is None or dark is None:
            continue
        if light != dark:
            problems.append(f"image size mismatch: {slug} (light {light[0]} x {light[1]}, dark {dark[0]} x {dark[1]})")
            sizes[f"{slug}.png"] = sizes[f"{slug}.dark.png"] = None
            continue
        want = e.get("size") or {}
        if want.get("w") and want.get("h") and abs(light[0] / light[1] - want["w"] / want["h"]) > 0.01 * want["w"] / want["h"]:
            problems.append(f"image does not match the manifest size: {slug} ({light[0]} x {light[1]} for {want['w']} x {want['h']} pt)")
            sizes[f"{slug}.png"] = sizes[f"{slug}.dark.png"] = None
    for e in manifest:
        slug, kinds = e["slug"], e.get("kinds", [])
        light_file, dark_file = f"{slug}.png", f"{slug}.dark.png"
        if not kinds:
            continue
        regions = e.get("regions")
        if not regions or "light" not in regions or "dark" not in regions:
            problems.append(f"no measured regions: {slug}")
            continue
        if sizes.get(light_file) is None or sizes.get(dark_file) is None:
            continue   # missing or undecodable: reported above
        entry_size = e.get("size") or {}
        width_pt, height_pt = entry_size.get("w", 0), entry_size.get("h", 0)
        if not width_pt or not height_pt:
            problems.append(f"no size in the manifest: {slug}")
            continue
        scale = sizes[light_file][0] / width_pt
        by_kind = {}
        for appearance in ("light", "dark"):
            for r in regions[appearance]:
                reason = valid_region(r, width_pt, height_pt)
                if reason:
                    problems.append(f"invalid {r.get('kind')} region in {slug} ({appearance}): {reason}")
                by_kind.setdefault((appearance, r.get("kind")), r)
        for kind in kinds:
            lr, dr = by_kind.get(("light", kind)), by_kind.get(("dark", kind))
            if lr is None or dr is None:
                problems.append(f"no measured {kind} region: {slug}")
                continue
            if any(valid_region(r, width_pt, height_pt) for r in (lr, dr)):
                continue
            if any(abs(lr[k] - dr[k]) > 1 for k in ("x", "y", "w", "h")):
                problems.append(f"{kind} region differs between light and dark: {slug}")
                continue
            x, y, w, h = pixels(lr, scale)
            region = [x, y, w, h]
            if kind == "fractal":
                jobs.append(["stats", str(out / light_file), *region]); owners.append((slug, "fractal", "light"))
                jobs.append(["stats", str(out / dark_file), *region]); owners.append((slug, "fractal", "dark"))
            elif kind == "sheetGlass":
                jobs.append(["stats", str(out / light_file), *region]); owners.append((slug, "glass", "light"))
                jobs.append(["stats", str(out / dark_file), *region]); owners.append((slug, "glass", "dark"))
                jobs.append(["share", str(out / light_file), str(out / dark_file), *region, GLASS_PIXEL_DELTA]); owners.append((slug, "glassshare", None))
            elif kind == "sheet":
                jobs.append(["stats", str(out / light_file), *region]); owners.append((slug, "sheet", "light"))
                jobs.append(["stats", str(out / dark_file), *region]); owners.append((slug, "sheet", "dark"))
            elif kind == "peek":
                jobs.append(["diff", str(out / light_file), str(out / dark_file), *region])
                owners.append((slug, "peek", scale))

    answers, error = run_jobs(jobs)
    if error:
        problems.append("luminance helper failed: " + error)
        answers = []
    for (slug, kind, extra), answer in zip(owners, answers):
        if answer is None:
            problems.append(f"region on an undecodable image: {slug} ({kind})")
            continue
        record = calibration.setdefault(slug, {})
        if kind == "fractal":
            mean, std = answer[0], answer[1]
            record[f"fractal_{extra}"] = {"mean": mean, "std": std}
            if std < FRACTAL_MIN_STD or not (FRACTAL_MEAN[0] < mean < FRACTAL_MEAN[1]):
                problems.append(f"fractal not drawn in the {extra} render of {slug}: mean {mean:.3f}, std {std:.3f}")
        elif kind == "glassshare":
            share = answer[0]
            record["glass_coverage"] = share
            if not measure and share < max(GLASS_COVERAGE, GLASS_COVERAGE_FLOOR):
                problems.append(f"translucent sheet separates light from dark over too little of its region in {slug}: "
                                f"{share:.2f} < {GLASS_COVERAGE:.2f}")
        elif kind == "glass":
            record[f"glass_{extra}_mean"] = answer[0]
            if "glass_light_mean" in record and "glass_dark_mean" in record:
                delta = record["glass_light_mean"] - record["glass_dark_mean"]
                record["glass_delta"] = delta
                if not measure and delta < max(GLASS_DELTA, GLASS_DELTA_FLOOR):
                    problems.append(f"translucent sheet does not separate light from dark in {slug}: light - dark {delta:.3f} < {GLASS_DELTA:.2f}")
        elif kind == "sheet":
            share = answer[2] if extra == "light" else answer[3]
            record[f"sheet_{extra}_coverage"] = share
            if not measure and share < SHEET_COVERAGE:
                problems.append(f"sheet background not {'light' if extra == 'light' else 'dark'} in the {extra} render of {slug}: "
                                f"coverage {share:.2f} < {SHEET_COVERAGE:.2f}")
        elif kind == "peek":
            scale = extra
            found, bx, by, bw, bh, light_mean, dark_mean, area, components, outside = answer
            width_pt = (sizes[f"{slug}.png"][0]) / scale
            record["peek"] = {"found": int(found), "box_pt": [bx / scale, by / scale, bw / scale, bh / scale],
                              "separation": light_mean - dark_mean, "components": int(components),
                              "coverage": area / (bw * bh) if bw * bh else 0, "outside_diff": outside}
            if not found:
                problems.append(f"peek capsule not found in {slug}")
                continue
            w_pt, h_pt = bw / scale, bh / scale
            centre_off = abs((bx + bw / 2) / scale - width_pt / 2)
            if not (PEEK_WIDTH[0] <= w_pt <= PEEK_WIDTH[1] and PEEK_HEIGHT[0] <= h_pt <= PEEK_HEIGHT[1]) or centre_off > PEEK_CENTER_TOLERANCE:
                problems.append(f"peek capsule has the wrong size or position in {slug}: {w_pt:.0f} x {h_pt:.0f} pt, {centre_off:.0f} pt off centre")
            if not measure:
                separation = light_mean - dark_mean
                if separation < max(PEEK_DELTA, PEEK_DELTA_FLOOR):
                    problems.append(f"peek capsule not distinguishable in {slug}: light - dark {separation:.3f} < {PEEK_DELTA:.3f}")
                if record["peek"]["coverage"] < PEEK_COVERAGE_FLOOR:
                    problems.append(f"peek capsule poorly covered by the difference in {slug}: {record['peek']['coverage']:.2f}")
                if outside > PEEK_OUTSIDE_CEILING:
                    problems.append(f"the fractal around the peek capsule differs between light and dark in {slug}: {outside:.4f} of the band")
    if measure:
        (out / "calibration.json").write_text(json.dumps(calibration, indent=2, sort_keys=True), encoding="utf-8")
        for slug, record in sorted(calibration.items()):
            print(f"calibration {slug}: " + json.dumps(record, sort_keys=True))
    if problems:
        print(f"CHECK FAILED [{lang}] ({len(problems)}):")
        for problem in problems:
            print("  " + problem)
        sys.exit(1)
    print(f"CHECK OK [{lang}]: {len(manifest)} cards, light and dark complete and correctly rendered"
          + (" (measure mode: peek and sheet thresholds not enforced)" if measure else ""))


def do_coverage():
    """View types under xFractal/ that neither GalleryScenarios nor GalleryFixtures mentions."""
    views = set()
    for file in (ROOT / "xFractal").rglob("*.swift"):
        views |= set(re.findall(r"^\s*(?:public |private |fileprivate )?struct (\w+)\s*:\s*[^{]*\b(?:View|PlatformRepresentable)\b",
                                file.read_text(encoding="utf-8"), re.M))
    sources = "".join((ROOT / "GalleryTests" / name).read_text(encoding="utf-8")
                      for name in ("GalleryScenarios.swift", "GalleryFixtures.swift") if (ROOT / "GalleryTests" / name).exists())
    missing = sorted(v for v in views if not re.search(rf"\b{v}\b", sources))
    print(f"{len(views) - len(missing)} of {len(views)} view types appear in a scenario or fixture; not rendered:")
    for view in missing:
        print("  " + view)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--import", dest="source", type=Path)
    parser.add_argument("--partial", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--coverage", action="store_true")
    parser.add_argument("--lang", default="en")
    opts = parser.parse_args()
    if opts.source:
        do_import(opts.source, opts.partial, opts.lang)
    if opts.check:
        do_check(opts.lang, opts.measure)
    if opts.coverage:
        do_coverage()
    if not (opts.source or opts.check or opts.coverage):
        parser.print_help()


if __name__ == "__main__":
    main()
