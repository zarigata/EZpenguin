# Website and wiki maintenance

The canonical public site is https://zarigata.github.io/EZpenguin/.
The wiki lives at https://zarigata.github.io/EZpenguin/wiki/ and all normal
documentation navigation stays on that site.

## Branding

The approved wild-cartoon mascot is docs/assets/ezpenguin-logo.webp.
It is a web-optimized version of the approved transparent image. The Y2K theme
uses acid green, purple window chrome, pixel-like borders, and desktop-style
buttons. FeverDream.dev is credited in the header, hero, footer, README, and wiki.

## Content and generation

- config/software-catalog.list is authoritative for recipe IDs, package names,
  categories, descriptions, and exact post-install hooks.
- config/packages-base.list and packages-exclude.list drive the base reference.
- wiki-content/software.json supplies authored use, verification, configuration,
  and operating notes for every recipe.
- wiki-content/*.md supplies first-boot, system-tool, and troubleshooting guides.
- Existing project Markdown docs supply the other on-site reference pages.

~~~bash
python3 scripts/build-website.py
python3 scripts/build-wiki.py
python3 tests/test_website.py
node --check docs/assets/app.js
node --check docs/assets/wiki.js
~~~

Commit generated HTML and sitemap with their source changes. The wiki generator
uses only the Python standard library. Wiki pages remain readable without
JavaScript; JavaScript adds search and command copying. The site does not
install anything on a visitor's machine.

The social PNG is 1200 × 630. To regenerate it from the approved mascot, run
scripts/render-social.py with Pillow and the DejaVu Sans fonts installed.
Pillow is not required to deploy the committed assets.

## Deployment

The pages workflow validates the source and publishes docs/ after changes
reach main. The separate Website checks workflow validates pull requests.
No framework build, tracking script, cloud login, or external font is required
on the public GitHub Pages site.

## Search discovery

Each wiki article has a descriptive title, description, canonical URL, social
metadata, and TechArticle JSON-LD. The homepage retains its WebSite,
SoftwareSourceCode, and SoftwareApplication metadata. The sitemap includes all
wiki routes. No ratings or download statistics are invented.

Search engines read robots.txt at a hostname root; the project's nested
robots.txt cannot override the root policy for zarigata.github.io.

After publication, use an account you control to verify the site in Google
Search Console and submit https://zarigata.github.io/EZpenguin/sitemap.xml.
Search engines decide indexing and rankings; no result or star count is promised.

If a custom domain is added, update canonical URLs, social URLs, the sitemap,
and homepage links together. Alternate previews retain the GitHub Pages canonical.
