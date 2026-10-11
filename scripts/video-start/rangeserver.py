import http.server, os, re, sys
ROOT=sys.argv[1]
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s,*a,**k): super().__init__(*a,directory=ROOT,**k)
    def end_headers(s):
        s.send_header('Access-Control-Allow-Origin','*'); s.send_header('Accept-Ranges','bytes'); s.send_header('Cache-Control','no-store'); super().end_headers()
    def do_GET(s):
        p=s.translate_path(s.path.split('?')[0]); r=s.headers.get('Range')
        if not r or not os.path.isfile(p): return super().do_GET()
        size=os.path.getsize(p); m=re.match(r'bytes=(\d*)-(\d*)',r); a=int(m.group(1) or 0); b=int(m.group(2)) if m.group(2) else size-1; b=min(b,size-1)
        s.send_response(206); ct='audio/mpeg' if p.endswith('.mp3') else ('audio/mp4' if p.endswith('.m4a') else ('text/html' if p.endswith('.html') else 'video/mp4'))
        s.send_header('Content-Type',ct); s.send_header('Content-Range',f'bytes {a}-{b}/{size}'); s.send_header('Content-Length',str(b-a+1)); s.end_headers()
        with open(p,'rb') as f:
            f.seek(a); n=b-a+1
            try:
                while n>0:
                    c=f.read(min(65536,n));
                    if not c: break
                    s.wfile.write(c); n-=len(c)
            except (BrokenPipeError,ConnectionResetError): pass
http.server.ThreadingHTTPServer(('127.0.0.1',8791),H).serve_forever()
