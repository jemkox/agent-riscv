#!/usr/bin/env python3
import sys, re
PAT = re.compile(r'^[0-9a-f]{8} [0-9a-f]{8} +\d+ [0-9a-f]{8} [01] [0-9a-f]{8} [0-9a-f]{8} [0-9a-f]$')
def read(f):
    out = []
    for ln in open(f):
        ln = ln.strip()
        if ln and not ln.startswith('#') and PAT.match(ln):
            out.append(ln)
    return out
base = sys.argv[1] if len(sys.argv)>1 else 'build/rand'
n = int(sys.argv[2]) if len(sys.argv)>2 else 0
bad = []
for i in range(1,n+1):
    a=read(f'{base}/{i}.rtl.log'); b=read(f'{base}/{i}.iss.log')
    m=max(len(a),len(b)); err=0; first=None
    for k in range(m):
        x=a[k] if k<len(a) else '<missing>'
        y=b[k] if k<len(b) else '<extra>'
        if x!=y:
            err+=1
            if first is None: first=(k,x,y)
    if err: bad.append((i,err,first))
print('bad count', len(bad), 'checked', n)
for i,err,fd in bad[:10]:
    print('seed',i,'errs',err,'idx',fd[0],'rtl',fd[1],'iss',fd[2])
