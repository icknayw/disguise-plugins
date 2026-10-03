from plugin import plugins_launcher as p
from urlparse import urlsplit
with p.UnrestrictedScope():
    count=0
    for w in p.d3gui.root.children:
        if not hasattr(w,'currentUrl'):
            continue
        u=urlsplit(str(w.currentUrl))
        if u.port != 18745 or u.path != '{{PATH}}':
            continue
        m=w.sizeMetadata
        height={{HEIGHT}}
        if '{{PATH}}' == '/' and {{VW}} > 0:
            height=max(100,int(round(m.size.y+({{CH}}-{{VH}})*float(m.size.x)/{{VW}})))
        n=type(m)(type(m.size)({{WIDTH}},height),m.minSize,m.isResizeable)
        w.setSizeMetadata(n)
        count+=1
return {'resized':count}
