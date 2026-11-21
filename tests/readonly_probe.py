import socket,struct,sys,hashlib
port=int(sys.argv[1]); s=socket.create_connection(('127.0.0.1',port),3);s.settimeout(5);f=s.makefile('rb');
def req(op,b=b''):
 s.sendall(struct.pack('>BH',op,len(b))+b); st,n=struct.unpack('>BH',f.read(3));r=f.read(n); assert len(r)==n
 if st: raise RuntimeError(r.decode())
 return r
pads=req(1).splitlines();print('attached:',pads,flush=True)
for pad in pads:
 req(2,b' '.join(pad.split()[:2])); runs=[]
 for turn in range(2):
  pages=[]
  for j in range(12):
   p=0x20+j;n=43 if p%2 else 56;q=30+j+turn*12;r=req(3,bytes([77,16,q,3,2,p,n]));assert r[0]==77 and r[2]==q and r[4:8]==bytes([2,0,p,n]) and len(r)==8+n,(p,r.hex()); pages.append(r[8:]);
  runs.append(pages)
 assert runs[0]==runs[1];print('12 pages identical on two reads:', hashlib.sha256(b''.join(runs[0])).hexdigest())
