#!/usr/bin/env python3
"""Referentna izvedba words.json (docs/2026-10-06-titlovi-rijec-po-rijec.md §3).

Prototip za ugovor, NE produkcijski korak — taj živi u fetch.domovina.tv.
    python3 -I scripts/subtitle-words-reference.py <diarized.srt> <audio.speechmatics.json> <out.json>
"""
import json,sys,re,unicodedata,difflib
def norm(w):
    w=unicodedata.normalize('NFKD',w.lower()); w=''.join(c for c in w if not unicodedata.combining(c))
    return re.sub(r'[^\w]','',w)
def ms(s):
    h,m,r=s.split(':');sec,f=r.split(',');return ((int(h)*60+int(m))*60+int(sec))*1000+int(f)
def cues(raw):
    for b in re.split(r'\r?\n\s*\r?\n',raw.strip()):
        l=b.strip().split('\n')
        if len(l)<3: continue
        m=re.search(r'(\S+)\s*-->\s*(\S+)',l[1]); 
        if not m: continue
        t=' '.join(x.strip() for x in l[2:]).strip()
        if not re.match(r'^\[\w+\]',t): continue
        t=re.sub(r'^\[\w+\]','',t).strip()
        yield ms(m.group(1)),ms(m.group(2)),t.split()
srt,smj,out=sys.argv[1:4]
W=[(round(r['start_time']*1000),round(r['end_time']*1000),r['alternatives'][0]['content']) for r in json.load(open(smj))['results'] if r['type']=='word']
res=[];anch=tot=0
for s,e,toks in cues(open(srt,encoding='utf-8').read()):
    if not toks: continue
    sw=[w for w in W if w[0]>=s-50 and w[1]<=e+50]
    A=[norm(x) for x in toks];B=[norm(w[2]) for w in sw]
    t=[None]*len(toks)
    for bl in difflib.SequenceMatcher(None,A,B,autojunk=False).get_matching_blocks():
        for k in range(bl.size): t[bl.a+k]=(sw[bl.b+k][0],sw[bl.b+k][1])
    n=sum(x is not None for x in t); anch+=n; tot+=len(toks)
    # interpolacija: neusidrene riječi ravnomjerno između susjednih sidara (po znakovima)
    i=0
    while i<len(t):
        if t[i] is not None: i+=1; continue
        i0=i
        j=i
        while j<len(t) and t[j] is None: j+=1
        # Premalo mjesta (npr. riječi na kraju cue-a koje je Speechmatics
        # stavio u sljedeći cue): run upija susjedne usidrene riječi dok svaka
        # ne dobije barem MIN_MS, pa se raspon dijeli razmjerno znakovima.
        MIN_MS=120
        while True:
            lo=t[i-1][1] if i>0 else s; hi=t[j][0] if j<len(t) else e
            if hi-lo>=MIN_MS*(j-i): break
            if i>0: i-=1
            elif j<len(t):
                j+=1
                while j<len(t) and t[j] is None: j+=1
            else: break
        lo=t[i-1][1] if i>0 else s; hi=t[j][0] if j<len(t) else e
        if hi<lo: hi=lo
        L=sum(len(toks[k])+1 for k in range(i,j)); acc=0
        for k in range(i,j):
            a=lo+(hi-lo)*acc//L; acc+=len(toks[k])+1; b=lo+(hi-lo)*acc//L
            t[k]=(a,b)
        i=max(j,i0+1)
    # monotonost
    for k in range(1,len(t)):
        if t[k][0]<t[k-1][0]: t[k]=(t[k-1][0],max(t[k][1],t[k-1][0]))
    res.append({"s":s,"e":e,"w":[v for p in t for v in p],"a":round(n/len(toks),2)})
json.dump({"v":1,"source":"speechmatics","anchored":round(anch/tot,3),"cues":res},open(out,'w'),separators=(',',':'))
print(f"anchored {anch/tot:.1%} of {tot}, cues {len(res)}")
