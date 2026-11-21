// SPDX-License-Identifier: GPL-2.0-only
#include "../pi/native/vendor/xow/controller/paddles.h"
#include <cassert>
int main(){
 for(int len:{34,46,47}) {
  PhysicalPaddles s;unsigned char p[52]={32,0,1,(unsigned char)len};
  p[4+(len==34?15:len==46?19:20)]=2;
  p[4+(len==46?18:14)]=5;
  s.accept(p,len+3);assert(s.profile==-1);
  s.accept(p,len+4);assert(s.profile==2 && s.display()==5);
  unsigned char d[]={30,0,0,2,3,0};s.accept(d,6);assert(s.profile==0);
 }
}
