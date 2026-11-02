#!/usr/bin/env python3
"""Build the complete static wiki from the catalog, authored notes, and docs."""
import html
import json
import os
import re
from pathlib import Path
from urllib.parse import quote, urlsplit
from xml.sax.saxutils import escape as xml_escape

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs'
BASE = 'https://zarigata.github.io/EZpenguin/'
CATEGORY = {'server':'Servers', 'dev':'Development', 'network':'Network & VPN', 'security':'Security', 'tools':'Monitoring & tools', 'desktop':'Desktops'}
GUIDES = {
    'installation': ('Installation', 'docs/INSTALLATION.md'),
    'first-boot': ('First boot & headless', 'wiki-content/first-boot.md'),
    'system-tools': ('System tools', 'wiki-content/system-tools.md'),
    'troubleshooting': ('Troubleshooting', 'wiki-content/troubleshooting.md'),
    'building': ('Build your own image', 'docs/BUILDING.md'),
    'architecture': ('Architecture', 'docs/ARCHITECTURE.md'),
    'testing': ('Testing', 'docs/TESTING.md'),
    'security': ('Security', 'docs/SECURITY.md'),
    'roadmap': ('Roadmap', 'docs/ROADMAP.md'),
    'contributing': ('Contributing', 'docs/CONTRIBUTING.md'),
    'quality': ('Quality standards', 'docs/QUALITY.md'),
    'changelog': ('Changelog', 'docs/CHANGELOG.md'),
    'license': ('License', 'LICENSE'),
}
esc = html.escape

def rel(path, page):
    value = os.path.relpath(DOCS / path, (DOCS / page).parent).replace(os.sep, '/')
    if value.endswith('/index.html'): value = value[:-10]
    return value

def code(text, ident):
    return (f'<pre id="{ident}"><code>{esc(text)}</code></pre>'
            f'<button class="wiki-copy" data-code="{ident}" hidden>Copy commands</button>')

def slug(text):
    value = re.sub(r'<[^>]+>', '', text).lower().strip()
    value = re.sub(r'[^\w\s-]', '', value)
    return re.sub(r'[\s]+', '-', value)

def resolve_link(href, source_path, page):
    parsed = urlsplit(href)
    if parsed.scheme in ('http','https','mailto'):
        # Project documentation stays on-site even when source Markdown uses GitHub URLs.
        prefix = 'https://github.com/zarigata/EZpenguin/blob/main/'
        if href.startswith(prefix):
            return resolve_link(href[len(prefix):], ROOT/'README.md', page)
        return href
    path, sep, frag = href.partition('#')
    if not path: return href
    target = (source_path.parent / path).resolve()
    route = None
    for key, (_, src) in GUIDES.items():
        if target == (ROOT/src).resolve(): route = 'wiki/'+key+'/index.html'
    if target == (DOCS/'index.html').resolve(): route = 'index.html'
    if target == (ROOT/'config/software-catalog.list').resolve(): route = 'wiki/index.html'
    if target == (ROOT/'config/packages-base.list').resolve(): route = 'wiki/base-packages/index.html'
    if route: return rel(route, page) + (('#'+frag) if sep else '')
    if path.endswith('.md'): return rel('wiki/index.html',page)
    if target.is_relative_to(DOCS):
        return rel(str(target.relative_to(DOCS)), page) + (('#'+frag) if sep else '')
    if path.startswith('https:'): return href
    return rel('wiki/index.html',page)

def inline(text, source_path, page):
    saved = []
    marker = chr(96)
    def protect(match):
        saved.append('<code>'+esc(match[1])+'</code>')
        return '\x00'+str(len(saved)-1)+'\x00'
    text = re.sub(marker+r'([^'+marker+r']+)'+marker, protect, text)
    text = esc(text)
    def link(match):
        label = match[1]
        href = html.unescape(match[2])
        return '<a href="'+esc(resolve_link(href,source_path,page),quote=True)+'">'+label+'</a>'
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)',link,text)
    text = re.sub(r'\*\*(.+?)\*\*',r'<strong>\1</strong>',text)
    for i, value in enumerate(saved): text=text.replace('\x00'+str(i)+'\x00', value)
    return text

def render_markdown(source, source_path, page):
    lines=source.splitlines(); out=[]; toc=[]; paragraph=[]; i=0; seen={}
    def flush():
        if paragraph:
            out.append('<p>'+inline(' '.join(paragraph),source_path,page)+'</p>')
            paragraph.clear()
    while i<len(lines):
        line=lines[i]
        if line.startswith(('~~~', chr(96)*3)):
            flush(); fence=line[:3]; content=[]; i+=1
            while i<len(lines) and not lines[i].startswith(fence):
                content.append(lines[i]); i+=1
            out.append(code('\n'.join(content),'code-'+str(i))); i+=1;continue
        h=re.match(r'^(#{1,6})\s+(.+)',line)
        if h:
            flush(); level=len(h[1]); title=h[2]
            ident=slug(title); n=seen.get(ident,0);seen[ident]=n+1
            if n:ident+='-'+str(n)
            if level==2:toc.append((ident,title))
            out.append(f'<h{level} id="{ident}">'+inline(title,source_path,page)+f'</h{level}>')
            i+=1;continue
        if '|' in line and i+1<len(lines) and re.match(r'^\s*\|?\s*:?-{2,}',lines[i+1]):
            flush()
            def cells(row):return row.strip().strip('|').split('|')
            head=cells(line);out.append('<div class="table-scroll"><table><thead><tr>'+''.join('<th>'+inline(c.strip(),source_path,page)+'</th>' for c in head)+'</tr></thead><tbody>')
            i+=2
            while i<len(lines) and '|' in lines[i] and lines[i].strip():
                out.append('<tr>'+''.join('<td>'+inline(c.strip(),source_path,page)+'</td>' for c in cells(lines[i]))+'</tr>');i+=1
            out.append('</tbody></table></div>');continue
        li=re.match(r'^\s*(?:[-*]|\d+\.)\s+(.+)',line)
        if li:
            flush();ordered=bool(re.match(r'^\s*\d+\.',line));tag='ol' if ordered else 'ul'
            out.append('<'+tag+'>')
            while i<len(lines):
                match=re.match(r'^\s*(?:[-*]|\d+\.)\s+(.+)',lines[i])
                if not match:break
                out.append('<li>'+inline(match[1],source_path,page)+'</li>');i+=1
            out.append('</'+tag+'>');continue
        if not line.strip():flush()
        elif line.strip().startswith('>'):flush();out.append('<p class="notice">'+inline(line.strip()[1:].strip(),source_path,page)+'</p>')
        elif line.strip()=='---':flush();out.append('<hr>')
        else:paragraph.append(line)
        i+=1
    flush()
    return '\n'.join(out),toc

def nav(page):
    result=''
    for key,(title,_) in list(GUIDES.items())[:4]:
        dest='wiki/'+key+'/index.html'
        current=' aria-current="page"' if dest==page else ''
        result+=f'<a href="{rel(dest,page)}"{current}>{esc(title)}</a>'
    result+=f'<a href="{rel("wiki/base-packages/index.html",page)}">Base packages</a><h3>Software / 261 entries</h3>'
    for key,title in CATEGORY.items():
        result+=f'<a href="{rel("wiki/index.html",page)}#{key}">{esc(title)}</a>'
    result+='<h3>Project reference</h3>'
    for key,(title,_) in list(GUIDES.items())[4:]:
        dest='wiki/'+key+'/index.html'
        result+=f'<a href="{rel(dest,page)}">'+esc(title)+'</a>'
    return result

def shell(page,title,description,body,toc=(),breadcrumb=''):
    canonical=BASE+page.removesuffix('index.html')
    toc_html=''
    if toc:
        toc_html='<div class="wiki-toc"><strong>ON THIS PAGE</strong><nav>'+''.join(f'<a href="#{esc(k)}">{esc(v)}</a>' for k,v in toc)+'</nav></div>'
        # Keep TOC below H1 and opening summary, before the first H2.
        pos=body.find('<h2')
        body=body[:pos]+toc_html+body[pos:] if pos>=0 else body
    data={"@context":"https://schema.org","@type":"TechArticle","headline":title,"description":description,
          "url":canonical,"inLanguage":"en","isPartOf":{"@type":"WebSite","name":"EZpenguin","url":BASE}}
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(title)} — EZpenguin Wiki</title><meta name="description" content="{esc(description,quote=True)}">
<link rel="canonical" href="{canonical}"><meta name="robots" content="index,follow,max-image-preview:large">
<meta name="theme-color" content="#10110f"><meta property="og:type" content="article">
<meta property="og:title" content="{esc(title,quote=True)} — EZpenguin Wiki"><meta property="og:description" content="{esc(description,quote=True)}">
<meta property="og:url" content="{canonical}"><meta property="og:image" content="{BASE}assets/social-preview.png">
<meta name="twitter:card" content="summary_large_image"><link rel="icon" type="image/webp" href="{rel('assets/ezpenguin-logo.webp',page)}">
<link rel="stylesheet" href="{rel('assets/style.css',page)}"><script src="{rel('assets/wiki.js',page)}" defer></script>
<script type="application/ld+json">{json.dumps(data).replace('</','<'+chr(92)+'/')}</script></head>
<body><a class="skip" href="#main">Skip to content</a>
<header class="nav"><div class="wrap nav-inner"><a class="brand" href="{rel('index.html',page)}"><img src="{rel('assets/ezpenguin-logo.webp',page)}" width="57" height="57" alt="">ezpenguin<span>.</span></a>
<nav class="nav-links" aria-label="Main navigation"><a href="{rel('index.html',page)}">Home</a><a href="{rel('wiki/index.html',page)}">Wiki / help</a><a href="{rel('index.html',page)}#install">Download</a><a href="https://feverdream.dev/">FeverDream ↗</a><a class="star" href="https://github.com/zarigata/EZpenguin">☆ Star on GitHub</a></nav></div></header>
<div class="wrap wiki-banner"><a href="{rel('index.html',page)}">EZpenguin</a> / <a href="{rel('wiki/index.html',page)}">Wiki</a>{' / '+esc(breadcrumb or title) if page!='wiki/index.html' else ''}</div>
<div class="wrap wiki-layout"><aside class="wiki-sidebar" aria-label="Wiki navigation"><h2>THE FIELD MANUAL</h2>
<form action="{rel('wiki/index.html',page)}" method="get" role="search"><label class="sr-only" for="wiki-query">Search the wiki</label><input id="wiki-query" name="q" placeholder="Search 261 software guides…" type="search"><button type="submit">Search wiki →</button></form><nav aria-label="Wiki sections">{nav(page)}</nav></aside>
<main id="main" class="wiki-article"><div class="eyebrow">EZPENGUIN WIKI / v1.1.0</div>{body}
<p class="wiki-meta">Recipe reference: current repository catalog. Application availability and versions depend on your configured repositories. Documentation is hosted here; no repository visit is needed to read these guides.</p><p id="wiki-copy-status" role="status"></p></main></div>
<footer class="footer"><div class="wrap footer-top"><span class="fine">EZpenguin · An open-source project from <a href="https://feverdream.dev/">FeverDream.dev ↗</a></span><nav aria-label="Footer"><a href="{rel('wiki/index.html',page)}">Wiki home</a><a href="{rel('wiki/license/index.html',page)}">License</a><a href="https://github.com/zarigata/EZpenguin/issues">Report an issue</a></nav></div></footer></body></html>
'''

def generate():
    rows=[line.split('|',5) for line in (ROOT/'config/software-catalog.list').read_text().splitlines()
          if line.strip() and not line.lstrip().startswith('#')]
    notes=json.loads((ROOT/'wiki-content/software.json').read_text())
    if set(notes)!={r[0] for r in rows}:raise ValueError('Each recipe needs exactly one authored software guide')
    pages={}
    for key,(title,src) in GUIDES.items():
        page='wiki/'+key+'/index.html'
        source=(ROOT/src).read_text()
        if key=='license':source='# License\n\n'+source
        body,toc=render_markdown(source,ROOT/src,page)
        pages[page]=shell(page,title,'EZpenguin '+title.lower()+': practical documentation for the Debian-based operating system, hosted in the official EZpenguin wiki.',body,toc)
    for index,(app_id,name,packages,category,description,post) in enumerate(rows):
        page='wiki/software/'+app_id+'/index.html'; n=notes[app_id]
        package_rows=''.join('<tr><td><code>'+esc(p)+'</code></td><td><a href="https://packages.debian.org/bookworm/'+quote(p)+'">Debian package reference ↗</a></td></tr>' for p in packages.split())
        body=f'<h1>{esc(name)}</h1><p>{esc(n["purpose"])}</p><div class="wiki-tags"><span>{esc(CATEGORY[category])}</span><span>Catalog ID: {esc(app_id)}</span><span>Optional recipe</span></div>'
        if app_id=='htop':body+='<p class="notice">htop is also explicitly requested by the base-image package list.</p>'
        if app_id in ('gitea-light','gitdaemon','code-help','fastfetch-lite'):body+='<p class="notice">'+esc(n['notes'])+'</p>'
        body+='<h2 id="install">Install on EZpenguin</h2><p>Run this command in your EZpenguin terminal. The browser only copies commands; it does not administer your system.</p>'
        body+=code('sudo ez-software install '+app_id,'install-command')
        body+='<h2 id="packages">Packages requested by this recipe</h2><div class="table-scroll"><table><thead><tr><th>Package</th><th>Reference</th></tr></thead><tbody>'+package_rows+'</tbody></table></div>'
        body+='<p>These are the explicit package names in the recipe, not a complete dependency list. APT resolves dependencies and selects versions from your configured repositories.</p>'
        body+='<h2 id="post-install">What happens after installation</h2>'
        if post:
            body+='<p>After APT installation, ez-software runs this exact shell snippet from the catalog:</p>'+code(post,'post-command')
            body+='<p>Hooks can enable services, change group membership, or set the boot target. The installer may continue after a hook error; verify the outcome below.</p>'
        else:body+='<p>No extra post-install shell hook is defined for this entry. Package-maintainer scripts can still perform their normal Debian setup. Configure the software for your use case before relying on it.</p>'
        body+='<h2 id="first-steps">First steps and verification</h2>'+code('\n'.join(n['quick_start']),'first-commands')
        body+='<p>Run the examples one at a time. Replace uppercase placeholders with values for your system. These commands have not been executed against every installed stack as part of this website update.</p>'
        body+='<h2 id="configuration">Configuration and data</h2><p>'+esc(n['configuration'])+'</p>'
        body+='<h2 id="notes">Operational notes</h2><p>'+esc(n['notes'])+'</p>'
        if category=='server':
            body+='<p>For long-running services, review listening addresses, authentication, firewall rules, logs, and data backups. Enabling a service does not make it safe to expose publicly.</p>'
        body+='<h2 id="help">If something fails</h2><p>Read the <a href="'+rel('wiki/troubleshooting/index.html',page)+'">troubleshooting guide</a>. Start with apt-cache policy for the requested packages, then inspect the named service and its journal where relevant. Application data is not included automatically in ez-backup configuration archives.</p>'
        related=[r for r in rows if r[3]==category and r[0]!=app_id][:4]
        body+='<h2 id="related">Related software</h2><div class="wiki-grid">'+''.join('<a class="wiki-card" href="'+rel('wiki/software/'+r[0]+'/index.html',page)+'"><strong>'+esc(r[1])+'</strong><p>'+esc(r[4])+'</p></a>' for r in related)+'</div>'
        prev=rows[(index-1)%len(rows)];nxt=rows[(index+1)%len(rows)]
        body+='<nav class="wiki-pager" aria-label="Adjacent software"><a href="'+rel('wiki/software/'+prev[0]+'/index.html',page)+'">← '+esc(prev[1])+'</a><a href="'+rel('wiki/software/'+nxt[0]+'/index.html',page)+'">'+esc(nxt[1])+' →</a></nav>'
        toc=[('install','Install'),('packages','Packages'),('post-install','Post-install'),('first-steps','First steps'),('configuration','Configuration'),('notes','Notes'),('help','Help'),('related','Related')]
        pages[page]=shell(page,name,'Install and configure '+name+' on EZpenguin. Package names, post-install actions, first steps, configuration notes, and troubleshooting.',body,toc,name)
    # Base package inventory: source comments and architecture mapping are authoritative.
    page='wiki/base-packages/index.html'; groups={};current='Core'
    for line in (ROOT/'config/packages-base.list').read_text().splitlines():
        group=re.match(r'# --- (.+?) ---',line)
        if group:current=group[1];groups.setdefault(current,[])
        elif line.strip() and not line.lstrip().startswith('#'):
            pkg,_,comment=line.partition('#')
            groups.setdefault(current,[]).append((pkg.strip(),comment.strip() or 'Debian archive trust anchors'))
    count=sum(len(v) for v in groups.values())
    body=f'<h1>Base image package reference</h1><p>The build explicitly requests <strong>{count} base packages</strong> before dependencies and cleanup. These are separate from the 261 optional catalog recipes. The installed package count is larger because Debian resolves dependencies.</p>'
    body+='<p class="notice">Architecture mapping: ARM64 replaces linux-image-amd64 with linux-image-arm64, uses ARM64 EFI GRUB packages, and omits grub-pc-bin. This reference starts from the common amd64-oriented base list.</p>'
    toc=[]
    for group,pkgs in groups.items():
        ident=slug(group);toc.append((ident,group))
        body+='<h2 id="'+ident+'">'+esc(group.capitalize())+'</h2><div class="table-scroll"><table><thead><tr><th>Package</th><th>Role in the image</th></tr></thead><tbody>'
        for pkg,comment in pkgs:
            body+='<tr data-base-package="'+esc(pkg)+'"><td><code>'+esc(pkg)+'</code></td><td>'+esc(comment)+'</td></tr>'
        body+='</tbody></table></div>'
    body+='<h2 id="excluded">Deliberately excluded packages</h2><p>The cleanup list excludes the following explicit packages. This keeps the base small; local manpages are therefore not guaranteed.</p><ul>'
    excluded=[l.strip() for l in (ROOT/'config/packages-exclude.list').read_text().splitlines() if l.strip() and not l.lstrip().startswith('#')]
    body+=''.join('<li><code>'+esc(pkg)+'</code></li>' for pkg in excluded)+'</ul>'
    body+='<h2 id="inventory">Inspect your actual machine</h2>'+code("dpkg-query -W\napt-cache policy PACKAGE_NAME",'inventory-command')
    body+='<p>The package database on your running machine is authoritative for its installed versions. This list is a build specification, not a claim that every package is present in every historical release artifact.</p>'
    pages[page]=shell(page,'Base image packages','Complete reference for explicitly requested EZpenguin base packages, architecture mappings, deliberately excluded packages, and installed-package inspection.',body,toc+[('excluded','Excluded packages'),('inventory','Local inventory')])
    page='wiki/index.html'
    body='<h1>The field manual.</h1><p>Real documentation for your little Linux box. Read installation guides, learn the built-in tools, and explore all <strong>261 software recipes</strong> without leaving this website.</p>'
    body+='<p class="notice">Catalog software is optional, not bundled by default. For software included in the image, read the base-package reference and system-tools guide.</p>'
    body+='<h2 id="start">Start here</h2><div class="wiki-grid">'
    for key in ('installation','first-boot','system-tools','troubleshooting'):
        title,_=GUIDES[key]
        descriptions={'installation':'Images, live ISO, online installer, and virtual machines.','first-boot':'Interactive setup, headless configuration, user accounts, and SSH.','system-tools':'Configuration, package updates, diagnostics, and what backups cover.','troubleshooting':'Package failures, service logs, boot problems, and remote access.'}
        body+='<a class="wiki-card" href="'+rel('wiki/'+key+'/index.html',page)+'"><strong>'+esc(title)+'</strong><p>'+esc(descriptions[key])+'</p></a>'
    body+='<a class="wiki-card" href="'+rel('wiki/base-packages/index.html',page)+'"><strong>Base image packages</strong><p>'+str(count)+' explicitly requested packages, architecture notes, and exclusions.</p></a></div>'
    body+='<h2 id="directory">Software encyclopedia / 261 entries</h2><p>Search by software name, package, purpose, or recipe ID. Every entry includes installation, the exact post-install hook, verification commands, and operating notes.</p><p class="wiki-search-status" id="wiki-search-status" role="status">261 software guides</p>'
    for category,label in CATEGORY.items():
        group=[r for r in rows if r[3]==category]
        body+='<section class="wiki-category" id="'+category+'"><h3>'+esc(label)+' / '+str(len(group))+'</h3><div class="wiki-grid">'
        for app_id,name,packages,_,description,_post in group:
            searchable=' '.join([app_id,name,packages,description,notes[app_id]['purpose']]).lower()
            body+='<a class="wiki-card software-guide" data-guide="'+esc(app_id)+'" data-search="'+esc(searchable,quote=True)+'" href="'+rel('wiki/software/'+app_id+'/index.html',page)+'"><strong>'+esc(name)+'</strong><p>'+esc(description)+'</p><small>'+esc(app_id)+' / read guide →</small></a>'
        body+='</div></section>'
    body+='<p id="wiki-empty" hidden>No software matches this search. Try a different term or clear the search field.</p>'
    pages[page]=shell(page,'Wiki & software guides','Official EZpenguin wiki: installation, headless setup, built-in system tools, base packages, troubleshooting, and all 261 software recipes.',body)
    locs=['index.html']+sorted(pages)
    sitemap='<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    sitemap+=''.join('  <url><loc>'+xml_escape(BASE+p.removesuffix('index.html'))+'</loc></url>\n' for p in locs)
    sitemap+='</urlset>\n'
    pages['sitemap.xml']=sitemap
    return pages

if __name__=='__main__':
    pages=generate()
    for path,source in pages.items():
        dest=DOCS/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(source)
    print('Built',len(pages)-1,'wiki pages and sitemap')
