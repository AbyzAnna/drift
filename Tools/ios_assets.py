"""Builds the iPhone app's Pip images from the layered character renders.
Usage: python3 Tools/ios_assets.py Resources/Characters iOS/Shared/Pip.xcassets iOS/App/Assets.xcassets
Every layer is rendered from the same camera, so stacking them in the Mac app's order gives the whole character."""
import json, os, sys, shutil
from PIL import Image, ImageDraw, ImageFilter

src, out, appassets = sys.argv[1], sys.argv[2], sys.argv[3]
LOOKS = {"plain": [], "snow": ["scarf_snow", "beanie"], "autumn": ["scarf_autumn", "leafhat"],
         "sakura": ["clip"], "flowers": ["crown"], "spring": ["sprout"]}
MOODS = ["open", "closed", "happy", "surprised"]
FULL, HEAD = 330, 120

def imageset(name, im):
    d = os.path.join(out, name + ".imageset")
    os.makedirs(d, exist_ok=True)
    im.save(os.path.join(d, name + ".png"), optimize=True)
    json.dump({"images": [{"filename": name + ".png", "idiom": "universal"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=1)

shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(out, "Contents.json"), "w"))
heads = {}
for sp in ["bunny", "penguin", "lamb", "otter", "seal", "hedgehog"]:
    d = os.path.join(src, sp)
    man = json.load(open(os.path.join(d, "manifest.json")))
    px, k, cy = man["px"], man["px"] / man["ortho"], man["center_y"]
    P = lambda x, y: (px / 2 + x * k, px / 2 - (y - cy) * k)
    L = lambda n: Image.open(os.path.join(d, n + ".png")).convert("RGBA")
    # soft shadow where the head meets the body
    nx, ny = P(*man["pivots"]["neck"])
    sh = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([nx - 8 * k, ny - 2.2 * k, nx + 8 * k, ny + 2.6 * k], fill=(42, 32, 48, 70))
    sh = sh.filter(ImageFilter.GaussianBlur(2.5 * k))
    hx, hy = P(*man["hat"]["center"])
    hr = man["hat"]["r"] * k
    for look, fits in LOOKS.items():
        for mood in MOODS:
            im = Image.new("RGBA", (px, px), (0, 0, 0, 0))
            for n in ["footL", "footR", "body", "armL", "armR"]:
                if n in man["parts"]:
                    im.alpha_composite(L(n))
            im.alpha_composite(sh)
            for n in man["ears"]:
                im.alpha_composite(L(n))
            im.alpha_composite(L("head_" + mood))
            for f in fits:
                if man["fits"].get(f) == "head":
                    im.alpha_composite(L("fit_" + f))
            for f in fits:
                if man["fits"].get(f) == "body":
                    im.alpha_composite(L("fit_" + f))
            name = f"{sp}_{look}_{mood}"
            # whole body, trimmed to the character with a little room, in a square canvas
            x0, y0, x1, y1 = im.getbbox()
            side = int(max(x1 - x0, y1 - y0) * 1.04)
            sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            sq.alpha_composite(im.crop((x0, y0, x1, y1)), ((side - (x1 - x0)) // 2, side - (y1 - y0)))
            imageset(name, sq.resize((FULL, FULL), Image.LANCZOS))
            # head close-up for the compact Dynamic Island
            r = hr * 1.18
            head = im.crop((int(hx - r), int(hy - r * 1.2), int(hx + r), int(hy + r * 0.8)))
            head = head.resize((HEAD, HEAD), Image.LANCZOS)
            imageset(name + "_head", head)
            if look == "snow" and mood == "happy":
                heads[sp] = im.crop((int(hx - r * 1.3), int(hy - r * 1.3), int(hx + r * 1.3), int(hy + r * 1.3)))

# app icon: the bunny in its snow outfit on a night-sky gradient
icon = Image.new("RGBA", (1024, 1024))
g = ImageDraw.Draw(icon)
for y in range(1024):
    t = y / 1023
    g.line([(0, y), (1024, y)], fill=(int(14 + 40 * t), int(24 + 60 * t), int(62 + 72 * t), 255))
for i in range(90):
    import random
    random.seed(i)
    x, y, r = random.randint(0, 1023), random.randint(0, 1023), random.uniform(3, 9)
    g.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, random.randint(90, 200)))
b = heads["bunny"].resize((900, 900), Image.LANCZOS)
icon.alpha_composite(b, (62, 120))
ad = os.path.join(appassets, "AppIcon.appiconset")
os.makedirs(ad, exist_ok=True)
icon.convert("RGB").save(os.path.join(ad, "icon.png"))
json.dump({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(ad, "Contents.json"), "w"), indent=1)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(appassets, "Contents.json"), "w"))
print("ok", len(os.listdir(out)) - 1, "images")
