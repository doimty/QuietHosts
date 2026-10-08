"""Deterministic native10 icon: closed white shield and three local-rule rows."""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]

def cubic(p0,p1,p2,p3,count=50):
    result=[]
    for n in range(count):
        t=n/(count-1);s=1-t
        result.append((s*s*s*p0[0]+3*s*s*t*p1[0]+3*s*t*t*p2[0]+t*t*t*p3[0],s*s*s*p0[1]+3*s*s*t*p1[1]+3*s*t*t*p2[1]+t*t*t*p3[1]))
    return result

def render():
    scale=3;size=1024*scale
    image=Image.new('RGB',(size,size));draw=ImageDraw.Draw(image)
    top=(98,91,234);bottom=(84,76,230)
    for y in range(size):
        f=y/(size-1);color=tuple(round(a+(b-a)*f) for a,b in zip(top,bottom))
        draw.line((0,y,size,y),fill=color)
    # One filled continuous path avoids the old outline's top seam.
    pieces=[((512,206),(505,206),(498,210),(486,215)),
        ((486,215),(420,244),(310,283),(266,302)),
        ((266,302),(249,310),(245,324),(247,346)),
        ((247,346),(254,421),(264,518),(277,580)),
        ((277,580),(306,684),(411,762),(495,802)),
        ((495,802),(506,808),(518,808),(529,802)),
        ((529,802),(613,762),(718,684),(747,580)),
        ((747,580),(760,518),(770,421),(777,346)),
        ((777,346),(779,324),(775,310),(758,302)),
        ((758,302),(714,283),(604,244),(538,215)),
        ((538,215),(526,210),(519,206),(512,206))]
    path=[(x*scale,y*scale) for points in pieces for x,y in cubic(*points)]
    draw.polygon(path,fill=(255,255,255))
    # Purple rows, simple at 60pt. No check mark, padlock or fake live status.
    for width,cy in [(208,426),(208,498),(142,570)]:
        box=((512-width/2)*scale,(cy-18)*scale,(512+width/2)*scale,(cy+18)*scale)
        draw.rounded_rectangle(box,radius=18*scale,fill=(91,84,232))
    return image.resize((1024,1024),Image.Resampling.LANCZOS)

def main():
    image=render()
    resources=ROOT/'App/Resources'
    for name,size in [('Icon1024.png',1024),('Icon60@3x.png',180),('Icon60@2x.png',120)]:
        image.resize((size,size),Image.Resampling.LANCZOS).save(resources/name,optimize=True)
    print('Generated RGB opaque 1024/180/120 icons; system applies the outer mask.')
if __name__=='__main__':main()
