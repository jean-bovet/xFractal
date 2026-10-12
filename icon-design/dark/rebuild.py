#!/usr/bin/env python3
"""Rebuild the selected dark icon into a new .icon directory."""
import json
from pathlib import Path
import shutil
import subprocess
import sys

base = Path(__file__).resolve().parent
manifest = json.loads((base / 'layers.json').read_text())
source = (base / manifest['reference']).resolve()
output = Path(sys.argv[1])
shutil.copytree(source.parent.parent, output)
subprocess.run(['magick', str(source), '-channel', 'RGB', '-fx',
                manifest['dark']['expression'], '+channel',
                str(output / 'Assets/fractal-dark.png')], check=True)
metadata = output / 'icon.json'
doc = json.loads(metadata.read_text())
for fill in doc['fill-specializations']:
    if fill.get('appearance') == 'dark':
        fill['value']['solid'] = manifest['background']['dark']
metadata.write_text(json.dumps(doc, indent=2) + '\n')
