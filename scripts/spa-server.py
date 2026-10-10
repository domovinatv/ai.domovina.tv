#!/usr/bin/env python3
"""Lokalni posluzitelj za flutter build web: SPA fallback + COOP/COEP kao _worker.js, port 8788.

    python3 -I scripts/spa-server.py build/web
"""
import http.server, os, sys
root=sys.argv[1]
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s,*a,**k): super().__init__(*a,directory=root,**k)
    def end_headers(s):
        s.send_header('Cross-Origin-Opener-Policy','same-origin')
        s.send_header('Cross-Origin-Embedder-Policy','credentialless')
        super().end_headers()
    def send_head(s):
        p=s.translate_path(s.path.split('?')[0])
        if not os.path.isfile(p): s.path='/index.html'
        return super().send_head()
H.extensions_map['.wasm']='application/wasm'
http.server.ThreadingHTTPServer(('127.0.0.1',8788),H).serve_forever()
