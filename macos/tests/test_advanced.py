import contextlib,copy,io,json,pathlib,sys,tempfile,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
import advanced as ad,editor
class Fake(editor.Radio):
 def __init__(self,p):self.p=dict(p);self.writes=[]
 def call(self,t,b):
  if b[0]==2:
   _,k,n=b;return bytes([k,n])+self.p[k]
  if b[0]==1:
   _,k,n=b[:3];assert n==len(b[3:])==len(self.p[k]);self.writes.append(k);self.p[k]=b[3:];return bytes([k])
  return b''
class Tests(unittest.TestCase):
 def setUp(self):
  base=bytes.fromhex('10050704060405060708090a0b0c0d0e0f000000000000000000000064646464ff00ff000000ff00ff00000064ff00000030300000000000')
  curve=bytes([16])+bytes([43,43,127,127,191,191])*4+bytes(18)
  self.raw={k:curve if k%2 else base for k in range(32,44)}
 def test_fields_and_writeback(self):
  for slot in (1,2,3):
   r=Fake(self.raw);orig=r.read('pad',slot);new=orig.copy();v=ad.decode(slot,orig);v[1]['keys'][4]=4;v[0]['motors'][2]=30;v[0]['range'][2]=180;v[1]['curves'][:6]=[13,0,127,120,191,187];ad.apply(slot,orig,new,v)
   ks=ad.layout(slot);expected={ks[0]:{30,38},ks[1]:{9},ks[2]:set(),ks[3]:{1,2,4,6}}
   self.assertEqual(expected,{k:{i for i,(x,y) in enumerate(zip(orig[k],new[k])) if x!=y} for k in ks})
   with tempfile.TemporaryDirectory() as tmp,contextlib.redirect_stdout(io.StringIO()):
    h=editor.HOME
    try:
     editor.HOME=pathlib.Path(tmp);r.save('pad gen','5.23',slot,orig,new);files=list(editor.HOME.rglob('*.json'));self.assertEqual(len(files),1);self.assertEqual(json.loads(files[0].read_text()),{str(k):x.hex() for k,x in orig.items()})
    finally:editor.HOME=h
   self.assertEqual(r.p,{**self.raw,**new})
 def test_reject(self):
  o=Fake(self.raw).read('pad',1)
  for k,val in [('motors',101),('range',256),('keys',3),('curves',200)]:
   v=ad.decode(1,o);v[0][k][0]=val
   with self.assertRaises(ValueError):ad.apply(1,o,o.copy(),v)
 def test_name(self):
  self.assertEqual(len(ad.name_bytes('二号🎮')),32)
  with self.assertRaises(ValueError):ad.name_bytes('🎮'*8)
if __name__=='__main__':unittest.main()
