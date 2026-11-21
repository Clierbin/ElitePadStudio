"""Resolve a reported hardware slot to its stored Xbox-button RGB; never edit a profile."""
import time

class LiveLight:
    def __init__(self):
        self.key=None
        self.result=(-1,-1)
        self.retry=0

    def clear(self):
        self.key=None

    def get(self,radio,token,slot):
        if slot==0:return self._fixed((token,slot),(0xffffff,-1))
        if slot not in (1,2,3):return self._fixed(None,(-1,-1))
        key=(token,slot)
        if key!=self.key or (self.result[0]<0 and time.monotonic()>=self.retry):
            self.key=key;self.result=(-1,-1);self.retry=time.monotonic()+3
            page=32+(slot-1)*2
            try:
                ans=radio.call(token,bytes((2,page,56)))
                if len(ans)==58 and ans[:2]==bytes((page,56)):
                    d=ans[2:]
                    rgb=0xffffff if d[45]==255 else int.from_bytes(d[46:49],'big') if d[45]==0 else -1
                    self.result=(rgb,d[44] if d[44]<=100 else -1)
            except (OSError,RuntimeError,AssertionError):pass
        return self.result

    def _fixed(self,key,val):
        self.key=key;self.result=val;return val
