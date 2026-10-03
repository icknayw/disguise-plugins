from plugin import plugins_launcher as p
from urlparse import urlsplit
with p.UnrestrictedScope():
    count=0
    for w in p.d3gui.root.children:
        if not hasattr(w,'currentUrl') or urlsplit(str(w.currentUrl)).port != 18743:
            continue
        m=w.sizeMetadata
        # Ignore ordinary browser viewports unrelated to this native panel.
        if not 0.7 <= float(w.size.x)/{{VW}} <= 2.5:
            continue
        width={{WIDTH}}
        height={{HEIGHT}}
        if not {{SETTINGS}}:
            height=max(100,int(round(m.size.y+({{CH}}-{{VH}})*float(m.size.x)/{{VW}})))
        n=type(m)(type(m.size)(width,height),m.minSize,False)
        w.setSizeMetadata(n)
        count+=1
return {'resized':count}
