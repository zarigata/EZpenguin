#!/usr/bin/env python3
"""Rebuild the social preview. Optional dependency: Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
im = Image.new('RGB', (1200, 630), '#f6f5ed')
d = ImageDraw.Draw(im)
def font(size, bold=False, serif=False):
    path = '/usr/share/fonts/opentype/urw-base35/NimbusRoman-Italic.otf' if serif else (
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' if bold else
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
    return ImageFont.truetype(path, size)
d.rectangle((830, 0, 1200, 630), fill='#d4f578')
for xy, text, size, color, bold, serif in [
    ((65,57), 'ezpenguin.', 28, '#18241d', True, False),
    ((65,198), 'LIGHTWEIGHT DEBIAN LINUX', 16, '#235c41', False, False),
    ((59,250), 'Small footprint.', 68, '#18241d', True, False),
    ((59,337), 'Big possibilities.', 74, '#235c41', False, True),
    ((65,456), 'Homelabs. Home servers. Your next project.', 24, '#59645c', False, False),
    ((65,542), '61 SOFTWARE STACKS / AMD64 + ARM64 / OPEN SOURCE', 17, '#18241d', False, False)]:
    d.text(xy, text, font=font(size, bold, serif), fill=color)
ink = '#18241d'; white = '#fffef3'; orange = '#ffae53'
d.ellipse((893,421,1010,472),fill=orange); d.ellipse((1024,421,1141,472),fill=orange)
d.ellipse((910,160,1119,454),fill=ink)
d.ellipse((875,267,953,420),fill=ink); d.ellipse((1075,267,1153,420),fill=ink)
d.ellipse((932,270,1095,441),fill=white)
d.ellipse((944,204,1004,284),fill=white); d.ellipse((1025,204,1085,284),fill=white)
d.ellipse((978,237,991,259),fill=ink); d.ellipse((1038,237,1051,259),fill=ink)
d.polygon([(989,283),(1015,270),(1041,283),(1015,304)],fill=orange)
d.line([(992,374),(1008,390),(1041,357)],fill='#235c41',width=9)
im.save(ROOT / 'docs/assets/social-preview.png', optimize=True)
print('Wrote 1200 × 630 social preview')
