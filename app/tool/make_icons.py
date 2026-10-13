# Builds the Android and iOS launcher icons from the mark (the figure and star) in
# tool/raeed-logo-square.jpg, the academy's 640 px logo.
# Usage, from app/: python3 tool/make_icons.py . [preview.png]  (needs Pillow)
import sys, os, json
from PIL import Image
app=sys.argv[1]
im=Image.open(f'{app}/tool/raeed-logo-square.jpg').convert('RGBA');px=im.load()
xs=[];ys=[]
# The mark sits right of x=366 and above the academy's name (y=400).
for y in range(0,400):
    for x in range(366,im.size[0]):
        r,g,b,a=px[x,y]
        if a>40 and max(r,g,b)-min(r,g,b)>60: xs.append(x);ys.append(y)
mark=im.crop((min(xs),min(ys),max(xs)+1,max(ys)+1))
d=mark.load()
for y in range(mark.size[1]):
    for x in range(mark.size[0]):
        r,g,b,a=d[x,y]
        if min(r,g,b)>235: d[x,y]=(255,255,255,0)
def icon(size, pad, bg):
    c=Image.new('RGBA',(1024,1024),bg)
    inner=int(1024*(1-2*pad)); w,h=mark.size; s=inner/max(w,h)
    m=mark.resize((int(w*s),int(h*s)),Image.LANCZOS)
    c.alpha_composite(m,((1024-m.size[0])//2,(1024-m.size[1])//2))
    return c.resize((size,size),Image.LANCZOS)
white=(255,255,255,255)
res=f'{app}/android/app/src/main/res'
for name,s in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
    icon(s,0.14,white).convert('RGB').save(f'{res}/mipmap-{name}/ic_launcher.png')
# Adaptive icon: the mark inside the 66% safe zone of a 108dp foreground, on white.
for name,s in {'mdpi':108,'hdpi':162,'xhdpi':216,'xxhdpi':324,'xxxhdpi':432}.items():
    icon(s,0.25,(255,255,255,0)).save(f'{res}/mipmap-{name}/ic_launcher_foreground.png')
os.makedirs(f'{res}/mipmap-anydpi-v26',exist_ok=True)
open(f'{res}/mipmap-anydpi-v26/ic_launcher.xml','w').write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/white"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')
ios=f'{app}/ios/Runner/Assets.xcassets/AppIcon.appiconset'
meta=json.load(open(f'{ios}/Contents.json'))
for img in meta['images']:
    if 'filename' not in img: continue
    s=float(img['size'].split('x')[0])*int(img['scale'][0])
    icon(int(round(s)),0.14,white).convert('RGB').save(f"{ios}/{img['filename']}")
icon(512,0.14,white).convert('RGB').save(sys.argv[2] if len(sys.argv)>2 else '/dev/null', format='PNG')
