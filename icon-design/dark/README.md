# Dark icon

Selected option B: strong gold glow with clearer outer fractal branches on a near-black burgundy background. Geometry, default and tinted artwork, and native material settings are preserved.

`layers.json` records the source assets, appearance settings and exact color transform. Rebuild using Python 3 and ImageMagick into a new package:

```sh
python3 icon-design/dark/rebuild.py /tmp/DarkRevision.icon
```

Render all six appearances using the apple-reference-icon skill's `scripts/render_icon.py`, passing `--icon`, a fresh `--output` directory, and `--platform iOS` or `--platform macOS`. No simulator is needed.
