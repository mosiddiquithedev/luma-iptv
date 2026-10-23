#!/usr/bin/env python3
"""Validate local references and release assets without network dependencies."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse, unquote
import hashlib
import json
root=Path(__file__).parent/'dist'
class Page(HTMLParser):
    def __init__(self):super().__init__();self.ids=set();self.refs=[];self.images=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.add(a['id'])
        for key in ('href','src','data-image'):
            if key in a:self.refs.append(a[key])
        if tag=='img':self.images.append(a)
p=Page();p.feed((root/'index.html').read_text())
for ref in p.refs:
    if ref.startswith('#'):
        assert ref=='#' or ref[1:] in p.ids, f'Unknown anchor: {ref}'
    elif not urlparse(ref).scheme:
        path=root/unquote(ref.split('#')[0]);assert path.is_file(), f'Missing asset: {path}'
for image in p.images:assert image.get('alt'), 'Missing image alt text'
assert all((root/f'assets/{n}.png').stat().st_size>10000 for n in ['tv-discover','tv-details','tv-series','macos-discover','macos-customize','macos-light'])
manifest={}
for p in (root/'downloads').iterdir():
    if p.is_file() and p.name!='checksums.json':manifest[p.name]={'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(root/'downloads'/'checksums.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'PASS: Local links, screenshot assets, alt text and {len(manifest)} download checksums')
