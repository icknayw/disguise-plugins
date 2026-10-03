from plugin import plugins_launcher as p
from urlparse import urlsplit
with p.UnrestrictedScope():
    count=0
    for w in p.d3gui.root.children:
        if not hasattr(w,'currentUrl') or urlsplit(str(w.currentUrl)).port != 18751:
            continue
        if not 0.7 <= float(w.size.x)/{{VW}} <= 2.5:
            continue
        m=w.sizeMetadata
        scale=float(m.size.x)/{{VW}}
        width=max(242,int(round({{CW}})))
        height=max(180,int(round(m.size.y+({{CH}}-{{VH}})*scale)))
        n=type(m)(type(m.size)(width,height),m.minSize,False)
        w.setSizeMetadata(n)
        count+=1
return {'resized':count}
