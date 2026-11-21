"""精英二代无线板载档位编辑器。仅在按确认后写已修改的映射页。"""
import os, sys, subprocess, json, time, hashlib, select
from pathlib import Path
ROOT=Path(__file__).resolve().parent
HOME=Path.home()/'Library/Application Support/Elite无线配置'
BUTTONS={0:'未分配',1:'Shift',**dict(enumerate('A B X Y 上 下 左 右 LB RB LS RS'.split(),4))}
def pages(slot):
    base=32+2*(slot-1)
    return [base,base+6,base+1,base+7]
class Radio:
    def __init__(self):
        HOME.mkdir(parents=True,exist_ok=True,mode=0o700)
        firmware_dir = ROOT if (ROOT/'firmware.bin').is_file() else HOME
        if hashlib.sha256((firmware_dir/'firmware.bin').read_bytes()).hexdigest()!='48084d9fa53b9bb04358f3bb127b7495dc8f7bb0b3ca1437bd24ef2b6eabdf66': raise ValueError('固件校验失败')
        self.log=open(HOME/'receiver.log','w')
        self.p=subprocess.Popen([str(ROOT/'bin/elite-radio')],cwd=firmware_dir,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.log,text=True)
        self.seq=0
    def cmd(self,s):
        self.p.stdin.write(s+'\n');self.p.stdin.flush()
        if not select.select([self.p.stdout],[],[],8)[0]: raise TimeoutError('未收到接收器响应，请检查接线后重新打开')
        r=self.p.stdout.readline().strip()
        if r.split(' ',1)[0]!='OK':raise RuntimeError(r or '接收器已退出，请检查接线：'+str(self.log.name))
        return r[2:].strip()
    def call(self,token,b):
        self.seq=self.seq%255+1
        pkt=bytes([77,16,self.seq,len(b)])+b
        r=bytes.fromhex(self.cmd(token+' '+pkt.hex()).replace(':',''))
        if len(r)<6 or r[0]!=77 or len(r)!=4+r[3] or r[4]!=b[0] or r[5] not in (0,128):raise RuntimeError('手柄应答不符；请重新读取')
        return r[6:]
    def read(self,token,slot):
        out={}
        for k in pages(slot):
            n=43 if k%2 else 56
            r=self.call(token,bytes([2,k,n]))
            if r[:2]!=bytes([k,n]) or len(r)!=n+2:raise RuntimeError('配置页不完整')
            out[k]=r[2:]
        return out
    def save(self,token,fw,slot,orig,new):
        changed=[k for k in orig if orig[k]!=new[k]]
        for k in changed:
            dif=[i for i,(a,b) in enumerate(zip(orig[k],new[k])) if a!=b]
            allowed=(set(range(1,17))|set(range(28,33))|{34,38,40,45,46,47,48}) if k in pages(slot)[:2] else set(range(1,25))
            if k not in pages(slot) or len(new[k])!=len(orig[k]) or not set(dif)<=allowed:raise ValueError('草稿包含范围外的改动')
        if not changed:return
        if self.read(token,slot)!=orig: raise ValueError('原配置已变化，请重新读取')
        folder=HOME/token.split()[0].replace(':','')/fw/str(slot);folder.mkdir(parents=True,exist_ok=True)
        file=folder/(str(time.time_ns())+'.json')
        with file.open('x') as f:
            json.dump({str(k):v.hex() for k,v in orig.items()},f);f.flush();os.fsync(f.fileno())
        print('写前备份：',file)
        for b in [bytes([7,0]),bytes([3])]+[bytes([1,k,len(new[k])])+new[k] for k in changed]+[bytes([7,0]),bytes([3])]:
            r=self.call(token,b)
            if b[0]==1 and r!=b[1:2]:raise RuntimeError('手柄未确认目标页；请重新读取')
            time.sleep(.15)
        if self.read(token,slot)!=new:raise RuntimeError('写后读回不一致，请检查手柄。备份已保留。')
        print('已写入手柄，并逐字节读回核对。')
def pick(prompt,values):
    for i,v in enumerate(values,1):print(f'  {i}. {v}')
    t=input(prompt+'（回车返回）：').strip()
    if not t:return None
    if not t.isdigit() or not 1<=int(t)<=len(values): raise ValueError('编号无效')
    return int(t)-1
def edit(r,dev,slot):
    mac,gen,fw=dev.split();token=mac+' '+gen;orig=r.read(token,slot);new=dict(orig);keys=pages(slot)
    while True:
        print(f'\n{mac}　固件 {fw}　第 {slot} 档')
        for name,k in zip(('常规','Shift'),keys[:2]):
            v=new[k];print(name, ' '.join(f'P{i}={BUTTONS.get(v[i],hex(v[i]))}' for i in range(1,5)), '灯色', '默认' if v[45]==255 else v[46:49].hex())
        sel=pick('选择操作',['改拨片','改灯色','载入此档备份','保存到手柄'])
        if sel is None:return
        if sel==0:
            l=pick('选择层',['常规','Shift']);i=pick('选择拨片',['P1','P2','P3','P4']) if l is not None else None
            targets=[0,*range(4,16)];j=pick('映射到',[BUTTONS[x] for x in targets]) if i is not None else None
            if j is not None:
                k=keys[l];v=bytearray(new[k]);v[i+1]=targets[j];new[k]=bytes(v)
        elif sel==1:
            c=input('输入六位 RGB 色值（例如 0000FF），或 default 恢复默认：').strip().lower()
            color=bytes.fromhex('ff000000' if c=='default' else '00'+c)
            if len(color)!=4:raise ValueError('色值须为六位')
            for k in keys[:2]:new[k]=new[k][:45]+color+new[k][49:]
        elif sel==2:
            files=sorted((HOME/mac.replace(':','')/fw/str(slot)).glob('*.json'),reverse=True)
            if not files: print('此档暂无备份');continue
            j=pick('选择备份',[time.strftime('%F %T',time.localtime(int(p.stem)/1e9)) for p in files])
            if j is not None:
                data=json.loads(files[j].read_text())
                for k in keys[:2]:
                    v=bytes.fromhex(data[str(k)]);assert len(v)==56
                    new[k]=new[k][:1]+v[1:5]+new[k][5:45]+v[45:49]+new[k][49:]
        elif orig==new: print('没有改动。')
        elif input(f'确认写入 {mac} 第 {slot} 档？输入 YES：').strip()=='YES':r.save(token,fw,slot,orig,new);return
def main():
    r=Radio()
    try:
        waiting=False
        while True:
            devices=[s for s in r.cmd('LIST').split(';') if s]
            if not devices:
                if not waiting:
                    print('等待手柄连接，连接后自动显示配置菜单。仅首次配对输入 p 回车；退出输入 q 回车。',flush=True)
                    waiting=True
                if not select.select([sys.stdin],[],[],0.8)[0]:continue
                line=sys.stdin.readline()
                if not line:break
                s=line.strip().lower()
                if s=='q':break
                if s=='p':r.cmd('PAIR');print('请按手柄顶部配对键直到快闪。')
                continue
            waiting=False
            i=pick('选择手柄',[s.split()[0]+'  固件 '+s.split()[2] for s in devices])
            if i is None:break
            slot=pick('选择档位',['第一档','第二档','第三档'])
            if slot is not None:
                try:edit(r,devices[i],slot+1)
                except (ValueError,RuntimeError) as e:print('操作停止：',e)
    finally:
        r.p.stdin.close()
        try:r.p.wait(timeout=3)
        except subprocess.TimeoutExpired:r.p.kill();r.p.wait()
if __name__=='__main__':
    try:main()
    except (Exception,KeyboardInterrupt) as e:print('已退出：',e)
