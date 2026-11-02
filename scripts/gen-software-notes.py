#!/usr/bin/env python3
"""Generate wiki-content/software.json entries for catalog ids that lack one.

Reuses any authored notes for ids still present; synthesizes concise,
factual entries (purpose/quick_start/configuration/notes) from the catalog
row itself. Keeps humans in the loop: output marks generated entries with
a trailing bullet so they can be rewritten in place later.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NOTES = ROOT / 'wiki-content/software.json'
CATALOG = ROOT / 'config/software-catalog.list'

CATEGORY = {
    'server': 'server stacks', 'dev': 'development tools', 'network': 'network tools',
    'security': 'security tools', 'tools': 'system tools', 'desktop': 'desktop environments',
}

PURPOSE = {
    # a few curated lines; everything else falls back to the description
}

def main() -> int:
    rows = {}
    for line in CATALOG.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        app_id, name, packages, category, description, post = line.split('|', 5)
        rows[app_id] = (name, packages, category, description, post)

    notes = json.loads(NOTES.read_text())
    stale = sorted(set(notes) - set(rows))
    if stale:
        print('removing stale notes: ' + ', '.join(stale))
        for k in stale:
            del notes[k]

    missing = sorted(set(rows) - set(notes))
    print(f'catalog: {len(rows)}  notes: {len(notes)}  generating: {len(missing)}')
    for app_id in missing:
        name, packages, category, description, post = rows[app_id]
        desc = description.strip() or f'{name} — {CATEGORY[category]} recipe'
        purpose = desc if len(desc) > 25 else f'{desc.rstrip(".")}. Part of the {CATEGORY[category]} catalog.'
        quick = [f'sudo ez-software install {app_id}']
        conf = 'Ships with distribution defaults; adjust its configuration files after install.'
        note_bits = [f'Installs the {packages} package(s) from your configured APT repositories.']
        if post:
            note_bits.append('A post-install hook runs automatically; check its output when installing.')
        else:
            note_bits.append('No post-install hook; start the tool or its service when you need it.')
        notes[app_id] = {
            'purpose': purpose,
            'quick_start': quick,
            'configuration': conf,
            'notes': ' '.join(note_bits) + ' Generated entry — refine me.',
        }
    missing_set = set(missing)
    for k, v in notes.items():
        if k in missing_set and not v['notes'].endswith('Generated entry — refine me.'):
            v['notes'] += ' Generated entry — refine me.'

    NOTES.write_text(json.dumps(notes, indent=1, ensure_ascii=False) + '\n')
    print(f'wrote {len(notes)} notes -> {NOTES.relative_to(ROOT)}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
