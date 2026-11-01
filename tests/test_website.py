#!/usr/bin/env python3
"""Host-side website integrity checks; no OS build or third-party dependencies."""
import importlib.util
import json
import re
import struct
import unittest
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs'
CANONICAL = 'https://zarigata.github.io/EZpenguin/'

class Page(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.feed(source)
    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))

class WebsiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (DOCS / 'index.html').read_text()
        cls.page = Page(cls.source)
        cls.rows = [line.split('|', 5) for line in (ROOT / 'config/software-catalog.list').read_text().splitlines()
                    if line.strip() and not line.lstrip().startswith('#')]

    def test_all_catalog_recipes_rendered_and_current(self):
        spec = importlib.util.spec_from_file_location('website_build', ROOT / 'scripts/build-website.py')
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        rendered = re.search(r'<!-- CATALOG START -->\n(.*?)\n<!-- CATALOG END -->', self.source, re.S)[1]
        self.assertEqual(rendered, mod.render_catalog(), 'Run python3 scripts/build-website.py')
        cards = [a for tag, a in self.page.tags if tag == 'article' and 'data-app-id' in a]
        self.assertEqual([c['data-app-id'] for c in cards], [r[0] for r in self.rows])
        self.assertEqual(len({r[0] for r in self.rows}), len(self.rows))
        self.assertEqual(len(self.rows), 61, 'Update site and README counts if the catalog changes')
        self.assertEqual(Counter(r[3] for r in self.rows),
                         Counter(server=18, dev=11, network=7, security=6, tools=17, desktop=2))

    def test_local_links_and_unique_ids(self):
        ids = [a['id'] for _, a in self.page.tags if 'id' in a]
        self.assertEqual(len(ids), len(set(ids)), 'Duplicate HTML IDs')
        for tag, attrs in self.page.tags:
            for key in ('src', 'href'):
                value = attrs.get(key, '')
                if not value or value.startswith(('https:', 'http:', 'data:', 'mailto:')): continue
                parsed = urlsplit(value)
                if parsed.fragment and not parsed.path:
                    self.assertIn(parsed.fragment, ids, value)
                elif parsed.path:
                    target = (DOCS / unquote(parsed.path)).resolve()
                    self.assertTrue(target.is_relative_to(DOCS), value)
                    self.assertTrue(target.exists(), value)
            if attrs.get('role') == 'tab':
                self.assertIn(attrs['aria-controls'], ids)
            if attrs.get('role') == 'tabpanel':
                self.assertIn(attrs['aria-labelledby'], ids)
        self.assertEqual(sum(tag == 'h1' for tag, _ in self.page.tags), 1)

    def test_seo_and_structured_data(self):
        meta = {a.get('name', a.get('property')): a.get('content') for tag, a in self.page.tags if tag == 'meta'}
        links = {a.get('rel'): a.get('href') for tag, a in self.page.tags if tag == 'link'}
        self.assertEqual(links['canonical'], CANONICAL)
        self.assertEqual(meta['og:url'], CANONICAL)
        self.assertEqual(meta['twitter:card'], 'summary_large_image')
        self.assertIn('index,follow', meta['robots'])
        self.assertGreater(len(meta['description']), 80)
        self.assertLess(len(meta['description']), 180)
        for key in ('og:image', 'twitter:image'):
            self.assertEqual(meta[key], CANONICAL + 'assets/social-preview.png')
        schemas = re.findall(r'<script type="application/ld\+json">(.*?)</script>', self.source, re.S)
        data = json.loads(schemas[0])
        self.assertEqual(data['@context'], 'https://schema.org')
        types = {item['@type'] for item in data['@graph']}
        self.assertEqual(types, {'WebSite', 'SoftwareSourceCode', 'SoftwareApplication'})
        version = re.search(r'EZP_VERSION="([^"]+)"', (ROOT/'config/ezpenguin.cfg').read_text())[1]
        for item in data['@graph']:
            self.assertNotIn('aggregateRating', item)
            if item['@type'] == 'SoftwareApplication':
                self.assertEqual(item['softwareVersion'], version)
        sitemap = ET.parse(DOCS / 'sitemap.xml')
        self.assertEqual(sitemap.find('.//{*}loc').text, CANONICAL)

    def test_social_image_is_valid_png_with_expected_size(self):
        content = (DOCS / 'assets/social-preview.png').read_bytes()
        self.assertEqual(content[:8], b'\x89PNG\r\n\x1a\n')
        self.assertEqual(struct.unpack('>II', content[16:24]), (1200,630))

    def test_documented_internal_paths(self):
        for name in ('README.md', 'docs/INSTALLATION.md', 'docs/WEBSITE.md'):
            file = ROOT / name
            for dest in re.findall(r'\]\(([^)]+)\)', file.read_text()):
                if urlsplit(dest).scheme or dest.startswith('#'): continue
                self.assertTrue((file.parent / dest.split('#')[0]).exists(), name + ': ' + dest)
        self.assertNotIn('ezpenguin.org/install.sh', (DOCS / 'INSTALLATION.md').read_text())



class WikiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pages = {p: Page(p.read_text()) for p in (DOCS / 'wiki').rglob('index.html')}

    def test_generated_wiki_is_current_and_complete(self):
        spec = importlib.util.spec_from_file_location('wiki_build', ROOT / 'scripts/build-wiki.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        expected = module.generate()
        for relative, source in expected.items():
            self.assertEqual((DOCS / relative).read_text(), source, 'Regenerate: ' + relative)
        self.assertEqual(len(self.pages), 76)
        recipes = [line.split('|', 5) for line in (ROOT / 'config/software-catalog.list').read_text().splitlines()
                   if line.strip() and not line.lstrip().startswith('#')]
        notes = json.loads((ROOT / 'wiki-content/software.json').read_text())
        self.assertEqual(set(notes), {r[0] for r in recipes})
        for app_id, name, packages, category, description, post in recipes:
            path = DOCS / 'wiki/software' / app_id / 'index.html'
            source = path.read_text()
            self.assertIn('sudo ez-software install ' + app_id, source)
            self.assertGreater(len(notes[app_id]['purpose']), 25)
            self.assertGreater(len(notes[app_id]['notes']), 40)
            if post:
                import html
                self.assertIn(html.escape(post), source, app_id)
        base = (DOCS / 'wiki/base-packages/index.html').read_text()
        for line in (ROOT / 'config/packages-base.list').read_text().splitlines():
            if line.strip() and not line.lstrip().startswith('#'):
                pkg = line.partition('#')[0].strip()
                self.assertIn('data-base-package="' + pkg + '"', base)

    def test_entire_site_links_anchors_and_headings(self):
        pages = dict(self.pages)
        pages[DOCS / 'index.html'] = Page((DOCS / 'index.html').read_text())
        all_ids = {p: [a['id'] for _, a in parsed.tags if 'id' in a] for p, parsed in pages.items()}
        for path, parsed in pages.items():
            self.assertEqual(sum(tag == 'h1' for tag, _ in parsed.tags), 1, str(path))
            self.assertEqual(len(all_ids[path]), len(set(all_ids[path])), str(path))
            for _, attrs in parsed.tags:
                for key in ('href','src'):
                    value = attrs.get(key,'')
                    if not value or urlsplit(value).scheme: continue
                    parts = urlsplit(value)
                    target = (path.parent / unquote(parts.path)).resolve() if parts.path else path
                    if target.is_dir(): target = target / 'index.html'
                    self.assertTrue(target.is_relative_to(DOCS), value)
                    self.assertTrue(target.exists(), str(path) + ': ' + value)
                    if parts.fragment and target.suffix == '.html':
                        ids = all_ids.get(target)
                        if ids is None: ids = [a['id'] for _, a in Page(target.read_text()).tags if 'id' in a]
                        self.assertIn(unquote(parts.fragment), ids, str(path)+': '+value)
                    self.assertNotIn('github.com/zarigata/EZpenguin/blob', value, 'Docs must remain on-site')
        site_source = (DOCS / 'index.html').read_text()
        self.assertIn('assets/ezpenguin-logo.webp', site_source)
        self.assertIn('https://feverdream.dev/', site_source)

    def test_wiki_canonical_schema_and_sitemap(self):
        sitemap = ET.parse(DOCS / 'sitemap.xml')
        locations = [el.text for el in sitemap.findall('.//{*}loc')]
        self.assertEqual(len(locations), 77)
        self.assertEqual(len(locations), len(set(locations)))
        for path, parsed in self.pages.items():
            expected = CANONICAL + str(path.relative_to(DOCS)).removesuffix('index.html')
            canon = [a['href'] for tag,a in parsed.tags if tag=='link' and a.get('rel')=='canonical']
            self.assertEqual(canon,[expected],str(path))
            self.assertIn(expected,locations)
            schemas = re.findall(r'<script type="application/ld\+json">(.*?)</script>',path.read_text(),re.S)
            schema = json.loads(schemas[0])
            self.assertEqual(schema['@type'],'TechArticle')
            self.assertEqual(schema['url'],expected)

if __name__ == '__main__':
    unittest.main(verbosity=2)
