from editor import *
import contextlib
from advanced import decode,apply,name_bytes,read_name
from live_light import LiveLight
lamp=LiveLight()
r=Radio(); ctx=None
try:
 for line in sys.stdin:
    try:
        m=json.loads(line); op=m['op']
        if op=='list':out=[s for s in r.cmd('LIST').split(';') if s]
        elif op in ('live','pulse'):
            mac,gen,fw=m['dev'].split();t=mac+' '+gen
            if op=='live':
                out=list(map(int,r.cmd('LIVE '+t).split()));out.extend(lamp.get(r,t,out[9]))
            else:
                motor=m['motor'];assert type(motor)==int and 0<=motor<4
                out=r.cmd('PULSE '+t+' '+str(motor))
        elif op=='pair':out=r.cmd('PAIR')
        elif op=='read':
            ctx=None; mac,gen,fw=m['dev'].split(); slot=int(m['slot']); assert slot in (1,2,3)
            token=mac+' '+gen; orig=r.read(token,slot);ctx=(token,slot,fw,orig);ks=pages(slot)[:2]
            out={'advanced':decode(slot,orig),'maps':[list(orig[k][1:5]) for k in ks], 'colors':[orig[k][45:49].hex() for k in ks]}
        elif op=='save':
            token,slot,fw,orig=ctx; assert m['dev']==token+' '+fw and m['slot']==slot
            new=dict(orig)
            for layer,k in enumerate(pages(slot)[:2]):
                v=bytearray(orig[k]); maps=m['maps'][layer];assert len(maps)==4
                for i,b in enumerate(maps,1):
                    if b!=v[i]:
                        assert b in [0,*range(4,16)];v[i]=b
                if m['color']:
                    col=bytes.fromhex(m['color']);assert len(col)==4 and col[0] in (0,255);v[45:49]=col
                new[k]=bytes(v)
            apply(slot,orig,new,m.get("advanced"))
            lamp.clear()
            with contextlib.redirect_stdout(sys.stderr):r.save(token,fw,slot,orig,new)
            ctx=(token,slot,fw,new);out=True
        elif op in ('getName','setName'):
            token,slot,fw,orig=ctx
            if token+' '+fw!=m['dev']: raise ValueError('手柄连接已变化')
            old=read_name(r,token)
            if op=='setName':
                if old!=m['old']:raise ValueError('手柄名已经变化，请重新读取')
                payload=name_bytes(m['name'])
                dest=HOME/token.split()[0].replace(':','')/'names';dest.mkdir(parents=True,exist_ok=True)
                with (dest/(str(time.time_ns())+'.json')).open('x') as f:
                    json.dump({'old':old,'requested':m['name']},f);f.flush();os.fsync(f.fileno())
                r.call(token,bytes([3]));r.call(token,bytes([4])+payload)
                if read_name(r,token)!=m['name']:raise ValueError('名称写后读回不一致')
                old=m['name']
            out=old
        else:raise ValueError('未知操作')
        print(json.dumps({'out':out}),flush=True)
    except Exception as e:print(json.dumps({'error':str(e) or '配置数据无效'}),flush=True)
finally:r.p.stdin.close()
