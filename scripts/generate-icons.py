#!/usr/bin/env python3
"""Render this project's geometric mascot as PNG, ICO, ICNS and favicon assets."""
from pathlib import Path
import math
import struct
import zlib
ROOT = Path(__file__).resolve().parents[1]

def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)

def png(size):
    raw=bytearray()
    for row in range(size):
        raw.append(0)
        for col in range(size):
            x=(col+.5)/size; y=(row+.5)/size
            rgb=(18,18,18)
            if (x-.5)**2+(y-.47)**2<.31**2: rgb=(255,255,255)
            for cx,cy,length,width in [(.465,.43,.078,.024),(.60,.36,.066,.019)]:
                dx=x-cx;dy=y-cy
                a=dx*.891-dy*.454;b=dx*.454+dy*.891
                if a*a+max(0,abs(b)-length/2)**2<width**2:rgb=(18,18,18)
            if (x-.746)**2+(y-.735)**2<.094**2:rgb=(18,18,18)
            if (x-.746)**2+(y-.735)**2<.074**2:rgb=(255,157,0)
            # A small five-point star formed by a radial boundary.
            dx=x-.746;dy=y-.735
            angle=math.atan2(dy,dx)+math.pi/2
            boundary=.027+.010*math.cos(5*angle)
            if dx*dx+dy*dy<boundary*boundary:rgb=(255,255,255)
            raw.extend(rgb)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')

large=png(1024)
(ROOT/'GrokBot/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png').write_bytes(large)
mac=b'ic10'+struct.pack('>I',8+len(large))+large
(ROOT/'GrokBotMac/Resources/AppIcon.icns').write_bytes(b'icns'+struct.pack('>I',8+len(mac))+mac)
sizes=[16,32,48,256]; images=[png(n) for n in sizes]; offset=6+16*len(sizes); entries=[]
for size,data in zip(sizes,images):
    entries.append(struct.pack('<BBBBHHII',size%256,size%256,0,0,1,32,len(data),offset));offset+=len(data)
(ROOT/'desktop-windows/app/icon.ico').write_bytes(struct.pack('<HHH',0,1,len(images))+b''.join(entries)+b''.join(images))
print('Generated platform icons from geometric source.')
