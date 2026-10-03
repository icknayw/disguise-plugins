from plugin import plugins_launcher as p
from urlparse import urlsplit
with p.UnrestrictedScope():
    count=0
    for w in p.d3gui.root.children:
        if not hasattr(w,'currentUrl'):
            continue
        u=urlsplit(str(w.currentUrl))
        if u.hostname not in ['127.0.0.1','localhost'] or u.port != 18753 or u.path != '{{PATH}}':
            continue
        m=w.sizeMetadata
        w.setSizeMetadata(type(m)(type(m.size)({{WIDTH}},{{HEIGHT}}),type(m.minSize)(0,0),False))
        count+=1
return {'resized':count}

