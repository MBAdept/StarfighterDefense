"""sheet.py name1.png name2.png ... out.png  - paste preview images side by side."""
import sys
from PIL import Image
ims = [Image.open(f) for f in sys.argv[1:-1]]
w = sum(i.width for i in ims)
h = max(i.height for i in ims)
c = Image.new("RGB", (w, h))
x = 0
for i in ims:
    c.paste(i.convert("RGB"), (x, 0))
    x += i.width
c.save(sys.argv[-1])
