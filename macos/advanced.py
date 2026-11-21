"""Elite 2 mapping/curve page layout. Edit only changed, known fields."""
SAT=(32,34,38,40)
def layout(slot):
 b=32+(slot-1)*2
 return (b,b+6,b+1,b+7)
def decode(slot,p):
 out=[]
 for m,c in zip(layout(slot)[:2],layout(slot)[2:]):
  out.append({'keys':list(p[m][5:17]),'range':[p[m][i] for i in SAT], 'motors':list(p[m][28:32]),'curves':list(p[c][1:25])})
 return out
def apply(slot,orig,new,edits):
 if not edits:return
 old=decode(slot,orig)
 if len(edits)!=2:raise ValueError('按键层不完整')
 for l,(m,c) in enumerate(zip(layout(slot)[:2],layout(slot)[2:])):
  v=bytearray(new[m]);cv=bytearray(new[c]);e=edits[l]
  for key,offsets in [('keys',list(range(5,17))),('range',SAT),('motors',range(28,32)),('curves',range(1,25))]:
   values=e[key];prior=old[l][key]
   if len(values)!=len(prior):raise ValueError('配置长度不符')
   for i,(x,y) in enumerate(zip(values,prior)):
    if x==y:continue
    if type(x)!=int or not 0<=x<=(100 if key=='motors' else 255):raise ValueError('数值超出范围')
    if key=='keys' and x not in (0,*range(4,16)):raise ValueError('未知按键目标')
    if key=='keys' and i>=4 and orig[m][0]&1 and 0 in orig[m][9:17]:raise ValueError('此层有特殊 Shift 排布，不能按固定位置改扩展按键')
    if key=='range' and v[offsets[i]+1]!=0:raise ValueError('无法识别这档的轴范围格式')
    (cv if key=='curves' else v)[offsets[i]]=x
  for i in range(1,25,6):
   pts=cv[i:i+6]
   if pts!=orig[c][i:i+6] and not (0<pts[0]<pts[2]<pts[4]<255 and pts[1]<=pts[3]<=pts[5]):raise ValueError('曲线输入点须递增，输出不能倒退')
  new[m]=bytes(v);new[c]=bytes(cv)
def name_bytes(s):
 if not isinstance(s,str) or not s.strip() or any(ord(c)<32 for c in s):raise ValueError('名称不能为空或含控制字符')
 b=s.encode('utf-16le')
 if len(b)>30:raise ValueError('名称超过 15 个 UTF-16 单元')
 return b.ljust(32,b'\x00')
def read_name(r,t):
 data=r.call(t,b'\x05')
 if len(data)!=32:raise ValueError('手柄未返回完整名称，已停止')
 return data.decode('utf-16le').rstrip('\x00')
