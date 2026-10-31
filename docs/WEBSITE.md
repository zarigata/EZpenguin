# Website and discoverability

The public project website is **https://zarigata.github.io/EZpenguin/**.
Source lives in this repository's docs directory. GitHub Pages deploys it
from main through the existing pages workflow. There is no frontend build
framework, account system, tracking pixel, or external font dependency.

## Maintain the site

- Edit docs/index.html, docs/assets/style.css, and docs/assets/app.js.
- The software catalog is rendered as HTML from config/software-catalog.list.
  After changing that catalog, run:

~~~bash
python3 scripts/build-website.py
python3 tests/test_website.py
node --check docs/assets/app.js
~~~

Commit the generated HTML with the catalog changes. CI checks that they match.
The content remains accessible without JavaScript; JavaScript adds search,
category filters, copy buttons, and keyboard-accessible installation tabs.

The social card is a committed 1200 × 630 PNG. The SVG is an editable vector
design reference; scripts/render-social.py regenerates the matching bitmap
layout with Pillow and standard DejaVu / Nimbus fonts on Linux. Pillow and
those fonts are needed only when rebuilding that asset, not for deployment.

## Search and sharing features included

- Descriptive page title and description focused on lightweight Debian Linux,
  homelabs, home servers, and self-hosting.
- One canonical public URL, semantic headings, readable HTML, and descriptive links.
- WebSite, SoftwareSourceCode, and SoftwareApplication JSON-LD describing actual
  project capabilities. No invented ratings, download totals, or testimonials.
- Open Graph and Twitter large-image metadata with an absolute PNG URL.
- sitemap.xml and an explicit index/follow directive.
- robots.txt for standalone hosting. Search engines read robots.txt at the
  hostname root; this project's /EZpenguin/robots.txt cannot control all of
  zarigata.github.io. Do not claim project-level robots.txt overrides root policy.
- Clear, honest GitHub star and contribution links.

Search engines decide whether and when to index a page. These changes support
discovery; they do not guarantee rankings, search enhancements, or stars.

## Repository About fields

Repository description:

> Lightweight Debian-based Linux for homelabs and self-hosting. 61 software recipes, headless setup, amd64 BIOS/UEFI and UEFI ARM64 images.

Website field:

> https://zarigata.github.io/EZpenguin/

Relevant repository topics (no keyword stuffing):

> linux, debian, linux-distribution, lightweight-linux, homelab, self-hosted,
> home-server, bash, arm64, amd64, automation, open-source

GitHub's repository settings and release text are outside tracked source files.
The About description, website link, and topics were updated through the
repository UI. The v0.4.1 release description was also refreshed to remove
comparison branding and explain the installer accurately. The existing binaries
were not rebuilt or replaced.

## After deploying

1. Verify the canonical page, social PNG, and sitemap return successfully.
2. Add the public website as a URL-prefix property in Google Search Console
   using an account you control. Follow its ownership-verification steps.
3. Submit https://zarigata.github.io/EZpenguin/sitemap.xml in that property.
4. Share useful demonstrations and actual hardware results. Invite interested
   users to star the repo; do not manufacture stars or promise unsupported results.

If hosting on a custom domain later, update canonical, Open Graph URL, image
URLs, JSON-LD identifiers, sitemap, README links, and the repository homepage
together. Keep a single canonical URL and use redirects where the host supports
them. Alternate previews retain the GitHub Pages canonical URL to avoid competing
copies in search.
