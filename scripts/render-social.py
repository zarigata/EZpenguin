#!/usr/bin/env python3
"""Rebuild the Y2K social card from the approved mascot. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
im=Image.new('RGB',(1200,630),'#10150c')
draw=ImageDraw.Draw(im)
def font(size,bold=False):
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans'+('-Bold' if bold else '')+'.ttf',size)
for x in range(0,1200,18):
    for y in range(0,630,18):
        draw.point((x,y),fill='#3e4c2c')
draw.rectangle((30,28,1170,602),outline='#8ba65f',width=2)
draw.rectangle((31,29,1169,68),fill='#644593')
draw.text((49,38),'FEVERDREAM.DEV / EZPENGUIN.EXE',font=font(15,True),fill='#fff7ff')
draw.text((64,128),'YOUR HARDWARE.',font=font(52,True),fill='#f4f6e6')
draw.text((64,200),'FULL THROTTLE.',font=font(52,True),fill='#caff16')
draw.text((66,294),'Lightweight Debian Linux.',font=font(23),fill='#cbd6bd')
draw.text((66,336),'Homelabs. Home servers. Big ideas.',font=font(21),fill='#aebfa0')
draw.rectangle((65,411,574,459),fill='#caff16',outline='#edffb0',width=2)
draw.text((84,424),'61 SOFTWARE GUIDES / ON-SITE WIKI',font=font(18,True),fill='#10150c')
draw.text((66,521),'zarigata.github.io/EZpenguin',font=font(18),fill='#b9a0f0')
logo=Image.open(ROOT/'docs/assets/ezpenguin-logo.webp').convert('RGBA')
logo.thumbnail((526,526))
im.paste(logo,(635,83),logo)
im.save(ROOT/'docs/assets/social-preview.png',optimize=True)
print('Rendered approved mascot social card')
