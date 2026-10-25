#!/usr/bin/env python3
"""Contract tests for scripts/preview-gallery.py (planning/gallery-scenarios-plan.md).

    python3 -m unittest discover -s scripts -p 'test_preview_gallery.py'

Each test builds small synthetic PNGs in a temp directory (a stand-in for a 402 x 874 pt screen at scale 1), points the
script at a temp output root through PREVIEW_GALLERY_OUT, and runs the real script (and the real pixel helper). No
simulator, no project files.
"""
import html
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "preview-gallery.py"
W, H = 402, 874


class Image:
    """A solid-colour RGB image with rectangles painted on it."""

    def __init__(self, width=W, height=H, color=(128, 128, 128)):
        self.width, self.height = width, height
        self.rows = [bytearray(bytes(color) * width) for _ in range(height)]

    def rect(self, x, y, w, h, color):
        for row in self.rows[y:y + h]:
            row[x * 3:(x + w) * 3] = bytes(color) * w
        return self

    def stripes(self, x, y, w, h, a=(40, 40, 40), b=(210, 210, 210), step=8):
        for i in range(0, w, step):
            self.rect(x + i, y, min(step, w - i), h, a if (i // step) % 2 == 0 else b)
        return self

    def png(self):
        def chunk(kind, data):
            body = kind + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
        raw = b"".join(b"\x00" + bytes(r) for r in self.rows)
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def gray(v):
    return (v, v, v)


FRACTAL = (0, 60, W, 600)
PEEK_BAND = (0, H - 140, W, 140)
CAPSULE = (91, 790, 220, 40)
SHEET = (16, 300, 370, 500)


def region(kind, rect):
    x, y, w, h = rect
    return {"kind": kind, "x": x, "y": y, "w": w, "h": h}


def board(light_capsule=gray(235), dark_capsule=gray(50), fractal_light=None, fractal_dark=None):
    """Light and dark board images: the same stripes as fractal, a capsule in the bottom band."""
    images = []
    for capsule, bg in ((light_capsule, gray(128)), (dark_capsule, gray(128))):
        img = Image(color=bg).stripes(*FRACTAL)
        img.rect(*CAPSULE, capsule)
        images.append(img)
    return images


def sheet_images(light_sheet=gray(246), dark_sheet=gray(20)):
    out = []
    for color, bg in ((light_sheet, gray(120)), (dark_sheet, gray(120))):
        img = Image(color=bg).stripes(0, 60, W, 200).rect(*SHEET, color)
        out.append(img)
    return out


def entry(name, group, slug, kinds=(), regions=None):
    e = {"name": name, "group": group, "slug": slug, "size": {"w": W, "h": H}, "kinds": list(kinds)}
    if regions is not None:
        e["regions"] = regions
    return e


def plain(name, group, slug):
    """A manifest entry with no region kinds: only the structural checks apply."""
    return entry(name, group, slug)


MANIFEST = [
    plain("Zeta screen", "Second group", "zeta-screen"),
    plain("Alpha <b> & \"q\"", "First group", "alpha-b-q"),
    plain("Mid screen", "Second group", "mid-screen"),
]


class GalleryTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.out = self.root / "previews"
        self.env = {**os.environ, "PREVIEW_GALLERY_OUT": str(self.out)}

    def small(self, light=(240, 240, 240), dark=(20, 20, 20)):
        return Image(46, 100, light).png(), Image(46, 100, dark).png()

    def source(self, manifest=MANIFEST, only=None, images=None, name="src"):
        """A snapshot-test output directory: both images of every manifest entry (or of `only`).
        `images` maps slug -> (light Image or bytes, dark Image or bytes)."""
        directory = self.root / name
        directory.mkdir(exist_ok=True)
        for e in manifest:
            if only is not None and e["slug"] not in only:
                continue
            light, dark = (images or {}).get(e["slug"], self.small())
            light = light.png() if isinstance(light, Image) else light
            dark = dark.png() if isinstance(dark, Image) else dark
            (directory / f"{e['slug']}.png").write_bytes(light)
            (directory / f"{e['slug']}.dark.png").write_bytes(dark)
        (directory / "manifest.json").write_text(json.dumps(manifest))
        return directory

    def run_script(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, env=self.env)

    def imported(self, *args, **kwargs):
        done = self.run_script("--import", str(self.source(**kwargs)), *args)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def check(self, *args):
        return self.run_script("--check", *args)

    def one(self, kinds, regions, images, slug="screen", measure=False):
        """Imports one scenario with real pixels and checks it."""
        manifest = [entry("Screen", "Group", slug, kinds, regions)]
        self.imported(manifest=manifest, images={slug: images})
        return self.check(*(["--measure"] if measure else []))

    def board_case(self, light_capsule=gray(235), dark_capsule=gray(50), regions=None, mutate=None, measure=False):
        light, dark = board(light_capsule, dark_capsule)
        if mutate:
            mutate(light, dark)
        both = {"light": [region("peek", PEEK_BAND), region("fractal", FRACTAL)],
                "dark": [region("peek", PEEK_BAND), region("fractal", FRACTAL)]}
        return self.one(["peek", "fractal"], regions or both, (light, dark), measure=measure)

    def sheet_case(self, light_sheet=gray(246), dark_sheet=gray(20), mutate=None, measure=False, regions=None):
        light, dark = sheet_images(light_sheet, dark_sheet)
        if mutate:
            mutate(light, dark)
        both = {"light": [region("sheet", SHEET), region("fractal", (0, 60, W, 200))],
                "dark": [region("sheet", SHEET), region("fractal", (0, 60, W, 200))]}
        return self.one(["sheet", "fractal"], regions or both, (light, dark), measure=measure)


class CheckTests(GalleryTestCase):
    def test_check_ok(self):
        self.imported()
        done = self.check()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("CHECK OK [en]: 3 cards", done.stdout)
        page = (self.out / "index.html").read_text(encoding="utf-8")
        for e in MANIFEST:
            self.assertIn(f"<figcaption>{html.escape(e['name'])}</figcaption>", page)
        self.assertIn("Alpha &lt;b&gt; &amp; &quot;q&quot;", page)
        self.assertNotIn("<b>", page.split("<body>")[1].split("<script>")[0])
        self.assertEqual(page.count("<h2>"), 2)
        self.assertLess(page.index("<h2>Second group</h2>"), page.index("<h2>First group</h2>"))
        self.assertLess(page.index('id="zeta-screen"'), page.index('id="mid-screen"'))
        self.assertLess(page.index('id="zeta-screen"'), page.index('id="alpha-b-q"'))
        for e in MANIFEST:
            figure = page.split(f'<figure id="{e["slug"]}"')[1].split("</figure>")[0]
            self.assertIn(f'href="{e["slug"]}.png"', figure)
            self.assertIn(f'href="{e["slug"]}.dark.png"', figure)

    def test_duplicate_slug(self):
        self.imported(manifest=MANIFEST + [plain("Zeta again", "Second group", "zeta-screen")])
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("duplicate slug: zeta-screen", done.stdout)

    def test_missing_image(self):
        self.imported()
        (self.out / "mid-screen.dark.png").unlink()
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("missing: mid-screen.dark.png", done.stdout)

    def test_stray_png(self):
        self.imported()
        (self.out / "ghost.png").write_bytes(self.small()[0])
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("stray image (no scenario): ghost.png", done.stdout)

    def test_undecodable_png(self):
        self.imported()
        (self.out / "mid-screen.png").write_bytes(b"not a png")
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("undecodable image: mid-screen.png", done.stdout)

    def test_dark_identical_to_light(self):
        light = self.small()[0]
        self.imported(images={e["slug"]: (light, light) for e in MANIFEST})
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("dark identical to light: zeta-screen", done.stdout)

    def test_check_rebuilds_page(self):
        self.imported()
        (self.out / "index.html").unlink()
        self.assertEqual(self.check().returncode, 0)
        self.assertTrue((self.out / "index.html").exists())

    def test_page_and_manifest_have_no_absolute_paths(self):
        self.imported()
        self.check()
        for name in ("index.html", "manifest.json"):
            text = (self.out / name).read_text(encoding="utf-8")
            self.assertNotIn("/Users/", text, name)
            self.assertNotIn(str(self.root), text, name)


class ImportTests(GalleryTestCase):
    def test_partial_import_preserves(self):
        self.imported()
        before = {p.name: p.read_bytes() for p in self.out.glob("*.png")}
        directory = self.root / "partial"
        directory.mkdir()
        (directory / "mid-screen.png").write_bytes(Image(23, 50, (240, 240, 240)).png())
        (directory / "mid-screen.dark.png").write_bytes(Image(23, 50, (20, 20, 20)).png())
        (directory / "manifest.json").write_text(json.dumps(MANIFEST))
        done = self.run_script("--import", str(directory), "--partial")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        after = {p.name: p.read_bytes() for p in self.out.glob("*.png")}
        self.assertEqual(set(after), set(before))
        for name in before:
            if name.startswith("mid-screen"):
                self.assertNotEqual(after[name], before[name], name)
            else:
                self.assertEqual(after[name], before[name], name)
        self.assertEqual(self.check().returncode, 0)

    def test_partial_import_merges_manifest(self):
        regions = {"light": [region("fractal", FRACTAL)], "dark": [region("fractal", FRACTAL)]}
        manifest = [entry("One", "G", "one", ["fractal"], regions), entry("Two", "G", "two", ["fractal"], regions)]
        light, dark = board()
        self.imported(manifest=manifest, images={"one": (light, dark), "two": (light, dark)})
        # A partial run renders "two" only; its manifest lists both but carries regions for "two" alone.
        new_two = entry("Two", "G", "two", ["fractal"], {"light": [region("fractal", (0, 100, W, 500))],
                                                         "dark": [region("fractal", (0, 100, W, 500))]})
        partial = [entry("One", "G", "one", ["fractal"]), new_two]
        done = self.run_script("--import", str(self.source(manifest=partial, only={"two"}, images={"two": (light, dark)}, name="p")),
                               "--partial")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        merged = {e["slug"]: e for e in json.loads((self.out / "manifest.json").read_text())}
        self.assertEqual(merged["one"]["regions"], manifest[0]["regions"], "an unrendered scenario keeps its last regions")
        self.assertEqual(merged["two"]["regions"]["light"][0]["y"], 100, "a rendered scenario takes the new regions")
        self.assertEqual(self.check().returncode, 0)

    def test_first_partial_import_keeps_rendered_only(self):
        regions = {"light": [region("fractal", FRACTAL)], "dark": [region("fractal", FRACTAL)]}
        light, dark = board()
        # The App Store captures in a new language: the run lists every scenario but renders "two" alone.
        manifest = [entry("One", "G", "one", ["fractal"]), entry("Two", "G", "two", ["fractal"], regions)]
        done = self.run_script("--import", str(self.source(manifest=manifest, only={"two"}, images={"two": (light, dark)})),
                               "--partial", "--lang", "ja")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual([e["slug"] for e in json.loads((self.out / "ja" / "manifest.json").read_text())], ["two"])
        self.assertEqual(self.check("--lang", "ja").returncode, 0)

    def test_partial_import_follows_the_scenario_list(self):
        regions = {"light": [region("fractal", FRACTAL)], "dark": [region("fractal", FRACTAL)]}
        light, dark = board()
        # A language folder from an earlier session: "old" was a scenario then, "two" still is.
        earlier = [entry("Old", "G", "old", ["fractal"], regions), entry("Two", "G", "two", ["fractal"], regions)]
        self.imported("--lang", "ja", manifest=earlier, images={"old": (light, dark), "two": (light, dark)}, name="first")
        # Today's run: "old" is gone, "three" is new but not selected, "two" is rendered again.
        today = [entry("Two", "G", "two", ["fractal"], regions), entry("Three", "G", "three", ["fractal"])]
        done = self.run_script("--import", str(self.source(manifest=today, only={"two"}, images={"two": (light, dark)}, name="p")),
                               "--partial", "--lang", "ja")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual([e["slug"] for e in json.loads((self.out / "ja" / "manifest.json").read_text())], ["two"],
                         "a removed scenario leaves the manifest, an unrendered new one does not enter it")
        self.assertEqual(sorted(p.name for p in (self.out / "ja").glob("*.png")), ["two.dark.png", "two.png"],
                         "the removed scenario's images go with it")
        check = self.check("--lang", "ja")
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)

    def test_partial_import_lists_a_new_scenario_in_english(self):
        regions = {"light": [region("fractal", FRACTAL)], "dark": [region("fractal", FRACTAL)]}
        light, dark = board()
        self.imported(manifest=[entry("Two", "G", "two", ["fractal"], regions)], images={"two": (light, dark)}, name="first")
        # The English gallery is the whole set: a new scenario an --only run skipped is listed, and the check wants it.
        today = [entry("Two", "G", "two", ["fractal"], regions), entry("Three", "G", "three", ["fractal"])]
        done = self.run_script("--import", str(self.source(manifest=today, only={"two"}, images={"two": (light, dark)}, name="p")),
                               "--partial")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual([e["slug"] for e in json.loads((self.out / "manifest.json").read_text())], ["two", "three"])
        check = self.check()
        self.assertNotEqual(check.returncode, 0)
        self.assertIn("missing: three.png", check.stdout)

    def test_full_import_replaces_own_language_only(self):
        self.imported("--lang", "fr")
        french = {p.name: p.read_bytes() for p in (self.out / "fr").glob("*")}
        self.out.mkdir(exist_ok=True)
        (self.out / "stale-en.png").write_bytes(self.small()[0])
        self.imported(name="src-en")
        self.assertFalse((self.out / "stale-en.png").exists())
        self.assertEqual({p.name: p.read_bytes() for p in (self.out / "fr").glob("*")}, french)
        self.assertEqual(self.check("--lang", "fr").returncode, 0)
        self.assertEqual(self.check().returncode, 0)

    def test_languages_coexist(self):
        self.imported()
        french = [plain("Écran un", "Premier", "ecran-un"), plain("Écran deux", "Premier", "ecran-deux")]
        self.imported("--lang", "fr", manifest=french, name="src-fr")
        en, fr = self.check(), self.check("--lang", "fr")
        self.assertIn("CHECK OK [en]: 3 cards", en.stdout)
        self.assertIn("CHECK OK [fr]: 2 cards", fr.stdout)
        self.assertIn("Écran un", (self.out / "fr" / "index.html").read_text(encoding="utf-8"))
        self.assertNotIn("Écran un", (self.out / "index.html").read_text(encoding="utf-8"))


class ImageValidityTests(GalleryTestCase):
    def test_truncated_png_with_valid_header_fails(self):
        # No region kinds: the structural check alone must decode every image.
        light, dark = self.small()
        self.imported(images={"mid-screen": (light[:50], dark)})
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("undecodable image: mid-screen.png", done.stdout)

    def test_dark_image_of_another_size_fails(self):
        light, dark = board()
        regions = {"light": [region("fractal", FRACTAL)], "dark": [region("fractal", FRACTAL)]}
        manifest = [entry("Screen", "Group", "screen", ["fractal"], regions)]
        smaller = Image(W // 2, H // 2, gray(10)).png()
        self.imported(manifest=manifest, images={"screen": (light, smaller)})
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("image size mismatch: screen", done.stdout)

    def test_image_aspect_must_match_the_manifest(self):
        light, dark = board()
        regions = {"light": [region("fractal", FRACTAL)], "dark": [region("fractal", FRACTAL)]}
        manifest = [entry("Screen", "Group", "screen", ["fractal"], regions)]
        wrong = [Image(W, H - 100, gray(128)).stripes(*FRACTAL[:2], W, 400).png() for _ in range(2)]
        self.imported(manifest=manifest, images={"screen": tuple(wrong)})
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("does not match the manifest size: screen", done.stdout)

    def test_output_path_with_spaces(self):
        self.out = self.root / "my previews"
        self.env = {**os.environ, "PREVIEW_GALLERY_OUT": str(self.out)}
        done = self.board_case()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)


class MetadataTests(GalleryTestCase):
    def test_import_strips_metadata_chunks(self):
        def with_chunks(img):
            data = img.png()
            def chunk(kind, body):
                inner = kind + body
                return struct.pack(">I", len(body)) + inner + struct.pack(">I", zlib.crc32(inner))
            head = data[:33]   # signature + IHDR
            return head + chunk(b"eXIf", b"MM\x00*") + chunk(b"tEXt", b"Comment\x00hello") + chunk(b"iTXt", b"k\x00\x00\x00\x00\x00v") + data[33:]
        light, dark = Image(46, 100, (240, 240, 240)), Image(46, 100, (20, 20, 20))
        directory = self.root / "meta"
        directory.mkdir()
        for e in MANIFEST:
            (directory / f"{e['slug']}.png").write_bytes(with_chunks(light))
            (directory / f"{e['slug']}.dark.png").write_bytes(with_chunks(dark))
        (directory / "manifest.json").write_text(json.dumps(MANIFEST))
        done = self.run_script("--import", str(directory))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        for png in self.out.glob("*.png"):
            data = png.read_bytes()
            for kind in (b"eXIf", b"tEXt", b"iTXt", b"zTXt"):
                self.assertNotIn(kind, data, f"{png.name} still has {kind!r}")
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(self.check().returncode, 0)


class RegionTests(GalleryTestCase):
    def test_bright_fractal_under_dark_sheet_passes(self):
        # The fractal is bright in both appearances; only the sheet differs.
        def bright(light, dark):
            for img in (light, dark):
                img.stripes(0, 60, W, 200, a=(180, 180, 180), b=(250, 250, 250))
        done = self.sheet_case(mutate=bright)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_light_sheet_in_dark_slot_fails(self):
        done = self.sheet_case(dark_sheet=gray(246))
        self.assertEqual(done.returncode, 1)
        self.assertIn("sheet background not dark in the dark render of screen", done.stdout)

    def test_sheet_text_heavy_region_fails_coverage(self):
        # Only a fifth of the region is light: text and controls cover the rest.
        def heavy(light, dark):
            light.rect(SHEET[0], SHEET[1] + 100, SHEET[2], 400, gray(110))
        done = self.sheet_case(mutate=heavy)
        self.assertEqual(done.returncode, 1)
        self.assertIn("sheet background not light in the light render of screen", done.stdout)

    def test_blank_fractal_fails(self):
        def blank(light, dark):
            for img in (light, dark):
                img.rect(0, 60, W, 200, gray(255))
        done = self.sheet_case(mutate=blank)
        self.assertEqual(done.returncode, 1)
        self.assertIn("fractal not drawn in the light render of screen", done.stdout)

    def test_peek_capsule_found(self):
        done = self.board_case()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_peek_missing_capsule_fails(self):
        done = self.board_case(light_capsule=gray(128), dark_capsule=gray(128),
                               mutate=lambda light, dark: dark.rect(0, 0, W, 40, gray(0)))
        self.assertEqual(done.returncode, 1)
        self.assertIn("peek capsule not found in screen", done.stdout)

    def test_peek_fractal_difference_outside_fails(self):
        # The pixels around the capsule differ: the render was not deterministic.
        done = self.board_case(mutate=lambda light, dark: dark.rect(10, 750, 40, 30, gray(160)))
        self.assertEqual(done.returncode, 1)
        self.assertIn("the fractal around the peek capsule differs", done.stdout)

    def test_peek_low_component_coverage_fails(self):
        # Only a thin frame of the capsule differs between the two renders.
        def ring(light, dark):
            for img in (light, dark):
                img.rect(*CAPSULE, gray(128))
            light.rect(CAPSULE[0], CAPSULE[1], CAPSULE[2], 3, gray(240)).rect(CAPSULE[0], CAPSULE[1] + 37, CAPSULE[2], 3, gray(240))
            light.rect(CAPSULE[0], CAPSULE[1], 3, 40, gray(240)).rect(CAPSULE[0] + 217, CAPSULE[1], 3, 40, gray(240))
        done = self.board_case(mutate=ring)
        self.assertEqual(done.returncode, 1)
        self.assertIn("peek capsule poorly covered", done.stdout)

    def test_non_positive_peek_separation_fails(self):
        # The capsule differs, but it is brighter in dark than in light.
        done = self.board_case(light_capsule=gray(100), dark_capsule=gray(160))
        self.assertEqual(done.returncode, 1)
        self.assertIn("peek capsule not distinguishable", done.stdout)

    def test_sheet_coverage_below_floor_fails(self):
        def under(light, dark):
            light.rect(SHEET[0], SHEET[1] + 100, SHEET[2], 400, gray(110))   # 20 % light
        done = self.sheet_case(mutate=under)
        self.assertEqual(done.returncode, 1)
        self.assertIn("coverage 0.2", done.stdout)

    def test_region_on_undecodable_image_fails(self):
        light, dark = board()
        manifest = [entry("Screen", "Group", "screen", ["fractal"],
                          {"light": [region("fractal", FRACTAL)], "dark": [region("fractal", FRACTAL)]})]
        self.imported(manifest=manifest, images={"screen": (light, dark)})
        (self.out / "screen.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 40)
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("undecodable image: screen.png", done.stdout)

    def regions_case(self, light_region, dark_region=None):
        light, dark = board()
        regions = {"light": [region("fractal", light_region)], "dark": [region("fractal", dark_region or light_region)]}
        return self.one(["fractal"], regions, (light, dark))

    def test_region_nan_fails(self):
        done = self.regions_case((float("nan"), 60, W, 600))
        self.assertEqual(done.returncode, 1)
        self.assertIn("invalid fractal region in screen (light): not finite", done.stdout)

    def test_region_non_positive_size_fails(self):
        done = self.regions_case((0, 60, 0, 600))
        self.assertEqual(done.returncode, 1)
        self.assertIn("non-positive size", done.stdout)

    def test_region_outside_image_fails(self):
        done = self.regions_case((0, 600, W, 600))
        self.assertEqual(done.returncode, 1)
        self.assertIn("outside the image", done.stdout)

    def test_region_pair_geometry_mismatch_fails(self):
        done = self.regions_case(FRACTAL, (0, 62, W, 600))
        self.assertEqual(done.returncode, 1)
        self.assertIn("fractal region differs between light and dark: screen", done.stdout)

    def test_missing_regions_fail(self):
        light, dark = board()
        manifest = [entry("Screen", "Group", "screen", ["fractal"])]
        self.imported(manifest=manifest, images={"screen": (light, dark)})
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("no measured regions: screen", done.stdout)


class FoldTests(GalleryTestCase):
    """A scenario with a `fold` rect (pt): the peek capsule must sit just past its trailing edge."""
    FOLD = {"x": 181, "y": 0, "w": 40, "h": H}

    def fold_case(self, capsule_x):
        manifest = [entry("Screen", "Group", "screen", ["peek", "fractal"],
                          {"light": [region("peek", PEEK_BAND), region("fractal", FRACTAL)],
                           "dark": [region("peek", PEEK_BAND), region("fractal", FRACTAL)]})]
        manifest[0]["fold"] = self.FOLD
        images = []
        for capsule in (gray(235), gray(50)):
            img = Image(color=gray(128)).stripes(*FRACTAL)
            img.rect(capsule_x, 790, 120, 40, capsule)
            images.append(img)
        self.imported(manifest=manifest, images={"screen": tuple(images)})
        return self.check()

    def test_capsule_clearing_the_fold_on_the_trailing_side_passes(self):
        done = self.fold_case(221)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_capsule_a_pixel_inside_the_fold_edge_passes(self):
        done = self.fold_case(220)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_centred_capsule_over_the_fold_fails(self):
        done = self.fold_case(141)
        self.assertEqual(done.returncode, 1)
        self.assertIn("peek capsule on the fold in screen", done.stdout)

    def test_capsule_shifted_twice_the_minimum_fails(self):
        done = self.fold_case(281)
        self.assertEqual(done.returncode, 1)
        self.assertIn("peek capsule has the wrong size or position in screen", done.stdout)


class SafeAreaTests(GalleryTestCase):
    """Unequal leading and trailing safe-area insets move the centre the capsule is judged against."""
    def inset_case(self, safe):
        manifest = [entry("Screen", "Group", "screen", ["peek", "fractal"],
                          {"light": [region("peek", PEEK_BAND), region("fractal", FRACTAL)],
                           "dark": [region("peek", PEEK_BAND), region("fractal", FRACTAL)]})]
        if safe:
            manifest[0]["safeArea"] = safe
        images = []
        for capsule in (gray(235), gray(50)):
            img = Image(color=gray(128)).stripes(*FRACTAL)
            img.rect(151, 790, 220, 40, capsule)   # centre 261: 60 pt right of the window centre
            images.append(img)
        self.imported(manifest=manifest, images={"screen": tuple(images)})
        return self.check()

    def test_capsule_off_centre_without_insets_fails(self):
        done = self.inset_case(None)
        self.assertEqual(done.returncode, 1)
        self.assertIn("off centre", done.stdout)

    def test_capsule_centred_between_unequal_insets_passes(self):
        done = self.inset_case({"left": 84, "right": 0})
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)


class GlassSheetTests(GalleryTestCase):
    """A translucent sheet (the opening and medium detents, the regular-width form sheet) shows the board through it:
    its background is not lit or dark, but the region still reads lighter in the light render than in the dark one."""

    def glass_case(self, light=gray(205), dark=gray(130), measure=False):
        lightimg, darkimg = Image(color=gray(128)).stripes(0, 60, W, 200), Image(color=gray(128)).stripes(0, 60, W, 200)
        lightimg.rect(*SHEET, light)
        darkimg.rect(*SHEET, dark)
        regions = {"light": [region("sheetGlass", SHEET), region("fractal", (0, 60, W, 200))],
                   "dark": [region("sheetGlass", SHEET), region("fractal", (0, 60, W, 200))]}
        return self.one(["sheetGlass", "fractal"], regions, (lightimg, darkimg), measure=measure)

    def test_glass_sheet_passes(self):
        done = self.glass_case()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_glass_sheet_without_separation_fails(self):
        done = self.glass_case(light=gray(140), dark=gray(130))
        self.assertEqual(done.returncode, 1)
        self.assertIn("translucent sheet does not separate light from dark in screen", done.stdout)

    def test_glass_sparse_difference_fails(self):
        # Bright and dark pixels over 14 % of the region lift the mean difference past the threshold, but the rest of the
        # region does not separate light from dark.
        lightimg, darkimg = Image(color=gray(128)), Image(color=gray(128))
        for img in (lightimg, darkimg):
            img.stripes(0, 60, W, 200)
        lightimg.rect(*SHEET, gray(128)).rect(SHEET[0], SHEET[1], SHEET[2] // 7, SHEET[3], gray(255))
        darkimg.rect(*SHEET, gray(128)).rect(SHEET[0], SHEET[1], SHEET[2] // 7, SHEET[3], gray(0))
        regions = {"light": [region("sheetGlass", SHEET), region("fractal", (0, 60, W, 200))],
                   "dark": [region("sheetGlass", SHEET), region("fractal", (0, 60, W, 200))]}
        done = self.one(["sheetGlass", "fractal"], regions, (lightimg, darkimg))
        self.assertEqual(done.returncode, 1)
        self.assertIn("translucent sheet separates light from dark over too little of its region in screen", done.stdout)

    def test_glass_sheet_reversed_fails(self):
        done = self.glass_case(light=gray(100), dark=gray(200))
        self.assertEqual(done.returncode, 1)
        self.assertIn("translucent sheet does not separate", done.stdout)

    def test_glass_measure_mode_reports(self):
        done = self.glass_case(light=gray(140), dark=gray(130), measure=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("glass_delta", done.stdout)


class MeasureTests(GalleryTestCase):
    def test_measure_mode_reports_without_enforcing(self):
        def heavy(light, dark):
            light.rect(SHEET[0], SHEET[1] + 100, SHEET[2], 400, gray(110))
        done = self.sheet_case(mutate=heavy, measure=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("calibration screen", done.stdout)
        calibration = json.loads((self.out / "calibration.json").read_text())
        self.assertLess(calibration["screen"]["sheet_light_coverage"], 0.3)
        self.assertGreater(calibration["screen"]["sheet_dark_coverage"], 0.9)

    def test_measure_mode_reports_peek(self):
        done = self.board_case(light_capsule=gray(100), dark_capsule=gray(160), measure=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        calibration = json.loads((self.out / "calibration.json").read_text())
        self.assertLess(calibration["screen"]["peek"]["separation"], 0)
        self.assertEqual(calibration["screen"]["peek"]["components"], 1)

    def test_measure_mode_still_enforces_structure(self):
        self.imported()
        (self.out / "mid-screen.dark.png").unlink()
        done = self.check("--measure")
        self.assertEqual(done.returncode, 1)
        self.assertIn("missing: mid-screen.dark.png", done.stdout)

    def test_measure_mode_still_enforces_fractal(self):
        def blank(light, dark):
            for img in (light, dark):
                img.rect(0, 60, W, 200, gray(255))
        done = self.sheet_case(mutate=blank, measure=True)
        self.assertEqual(done.returncode, 1)
        self.assertIn("fractal not drawn", done.stdout)


if __name__ == "__main__":
    unittest.main()
