#!/usr/bin/env python3
"""Render crawlable software entries from the OS catalog. No dependencies."""
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def render_catalog():
    rows = [line.split('|', 5) for line in (ROOT / 'config/software-catalog.list').read_text().splitlines()
            if line.strip() and not line.lstrip().startswith('#')]
    cards = []
    icons = {'server': 'SV', 'dev': '</>', 'network': 'NET', 'security': 'SEC', 'tools': 'CLI', 'desktop': 'GUI'}
    for i, (app_id, name, packages, category, description, _post) in enumerate(rows):
        esc = html.escape
        search = esc(' '.join([app_id, name, packages, description]).lower(), quote=True)
        preview = ' preview-hidden' if i >= 9 else ''
        command = 'sudo ez-software install ' + app_id
        cards.append(
            f'<article class="app{preview}" data-category="{esc(category)}" data-search="{search}" data-app-id="{esc(app_id)}">'
            f'<span class="app-icon" aria-hidden="true">{esc(icons[category])}</span>'
            f'<div class="app-content"><h3>{esc(name)}</h3><p>{esc(description)}</p>'
            f'<code>{esc(command)}</code><a class="read-guide" href="wiki/software/{esc(app_id)}/">Read wiki guide →</a><button class="copy-app" data-copy="{esc(command)}" '
            f'aria-label="Copy install command for {esc(name)}" hidden>Copy command ↗</button></div></article>')
    return '\n'.join(cards)

if __name__ == '__main__':
    index = ROOT / 'docs/index.html'
    text = index.read_text()
    text = re.sub(r'(?s)(<!-- CATALOG START -->).*?(<!-- CATALOG END -->)',
                  lambda m: m[1] + '\n' + render_catalog() + '\n' + m[2], text)
    index.write_text(text)
    print('Rendered software catalog into docs/index.html')
