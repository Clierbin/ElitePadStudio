#pragma once
#include <chrono>
#include <array>
#include <cstdint>
#include <cstddef>
// Elite 2 extended GIP input: payload byte 14, not the mapped ABXY bits.
struct PhysicalPaddles {
 using Clock=std::chrono::steady_clock;
 int profile=-1; int held=-1; bool compact=false;
 std::array<Clock::time_point,4> until{};
 void accept(const uint8_t* p,size_t n,Clock::time_point now=Clock::now()){
  if(n<4 || (p[1]&15)!=0 || n<4u+p[3])return;
  if(p[0]==0x1e && p[3]>=2 && p[4]==3 && p[5]<=3){profile=p[5];return;}
  int paddleByte=14,profileByte;
  if(p[0]==0x0c && p[3]==17){compact=true;profileByte=15;}
  else if(p[0]==0x20 && !compact){
   // SDL HIDAPI Xbox One: offsets here are relative to the GIP payload.
   switch(p[3]){case 34:profileByte=15;break;case 46:profileByte=19;paddleByte=18;break;
     case 47:profileByte=20;break;default:return;}
  }else return;
  const auto slot=p[4+profileByte];
  bool input=false;for(int i=4;i<18;i++)input |= p[i]!=0;
  int mask=p[4+paddleByte]&15;
  if(slot<=3 && (profile<0 || slot!=0 || input || mask))profile=slot;
  for(int i=0;i<4;i++)if((mask&(1<<i)) && (held<0 || !(held&(1<<i))))until[i]=now+std::chrono::milliseconds(110);
  held=mask;
 }
 int display(Clock::time_point now=Clock::now())const{
  if(held<0)return -1;int m=held;for(int i=0;i<4;i++)if(now<until[i])m|=1<<i;return m;
 }
};
