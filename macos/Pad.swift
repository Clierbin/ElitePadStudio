import Cocoa
final class Pad:NSView {
 override var isFlipped:Bool{true}
 var draftLamp=false
 var back=false,focus="",note="",led=NSColor.white,values=[Int](), live=false
 var anim:Timer?,start=Date.distantPast
 override var intrinsicContentSize:NSSize{NSSize(width:555,height:149)}
 func mark(_ key:String,_ text:String){focus=key;note=text;back=key.hasPrefix("P");start=Date();anim?.invalidate();needsDisplay=true
  guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else{return}
  let t=Timer(timeInterval:1/30,repeats:true){[weak self] timer in guard let s=self else{timer.invalidate();return};s.needsDisplay=true;if Date().timeIntervalSince(s.start)>0.6{timer.invalidate()}};RunLoop.main.add(t,forMode:.common);anim=t}
 override func draw(_ dirty:NSRect){
 let scale=min(bounds.height/149,bounds.width/555);guard scale>0 else{return};NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()};let tx=NSAffineTransform();tx.scale(by:scale);tx.concat()
 let accent=NSColor.systemGreen,metal=NSColor(white:0.47,alpha:1),rim=NSColor(white:0.12,alpha:1)
 func round(_ x:Int,_ y:Int,_ w:Int,_ h:Int,_ c:NSColor,_ r:CGFloat=5){c.setFill();NSBezierPath(roundedRect:NSRect(x:x,y:y,width:w,height:h),xRadius:r,yRadius:r).fill()}
 func disk(_ x:CGFloat,_ y:CGFloat,_ rad:CGFloat,_ c:NSColor){c.setFill();NSBezierPath(ovalIn:NSRect(x:x-rad,y:y-rad,width:2*rad,height:2*rad)).fill()}
 func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ c:NSColor,_ bold:Bool=false){(s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:bold ? .semibold:.regular),.foregroundColor:c])}
 let path=NSBezierPath();path.move(to:NSPoint(x:54,y:22))
 func curve(_ x:Int,_ y:Int,_ a:Int,_ b:Int,_ c:Int,_ d:Int){path.curve(to:NSPoint(x:x,y:y),controlPoint1:NSPoint(x:a,y:b),controlPoint2:NSPoint(x:c,y:d))}
 curve(112,19,68,9,93,15);curve(173,19,130,22,150,22);curve(229,28,192,11,215,13);curve(260,126,246,52,259,96);curve(229,135,263,148,242,149);curve(198,107,218,126,205,112);curve(88,107,168,98,114,98);curve(53,139,77,113,67,133);curve(27,122,32,149,23,139);curve(54,22,28,88,38,41);path.close();NSGradient(starting:NSColor(white:0.31,alpha:1),ending:rim)?.draw(in:path,angle:90)
 let v=values.count>=8 ? values : Array(repeating:0,count:8);let paddles=live && v.count>=9 ? v[8] : -1;let mask=live ? v[1]:0
 func hit(_ n:Int)->Bool{(mask & (1<<n)) != 0}
 func tint(_ key:String,_ bit:Int)->NSColor{hit(bit) ? accent : metal}
 let wave=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : max(0,1-Date().timeIntervalSince(start)/0.6)
 func glow(_ x:CGFloat,_ y:CGFloat){disk(x,y,CGFloat(13+wave*6),accent.withAlphaComponent(0.20+wave*0.18))}
 if back {
 round(112,31,62,63,rim,12)
 for i in 0..<4{let x=i<2 ? 66:175,y=i%2==0 ? 51:80,k="P"+String(i+1);let pressed=paddles>=0 && (paddles & (1<<i)) != 0;round(x,y+(pressed ? 2:0),47,17,pressed ? accent:metal,8);text(k,CGFloat(x+15),CGFloat(y+1),10,.white,true)}
 }else{
 for (i,x,y,key,bit) in [(0,77,55,"LS",10),(1,169,85,"RS",11)]{let dx=live ? CGFloat(v[4+2*i])/32768*9:0,dy=live ? CGFloat(v[5+2*i])/32768*9:0;disk(CGFloat(x),CGFloat(y),17,.black);disk(CGFloat(x)+dx,CGFloat(y)-dy,12,tint(key,bit))}
 for (i,x,y,k) in [(0,213,67,"A"),(1,226,53,"B"),(2,200,53,"X"),(3,213,39,"Y")]{disk(CGFloat(x),CGFloat(y),7,tint(k,i));text(k,CGFloat(x-4),CGFloat(y-6),9,.white,true)}
 disk(106,85,15,.darkGray);for (b,x,y) in [(4,103,72),(5,103,88),(6,94,81),(7,111,81)]{round(x,y,7,7,tint("D"+String(b),b),2)}
 let rgb=v.count>=12 ? v[10] : -1, brightness=v.count>=12 && v[11]>=0 ? CGFloat(v[11])/100 : 1
 let actual=rgb<0 ? NSColor.darkGray : NSColor(srgbRed:CGFloat((rgb>>16)&255)/255*brightness,green:CGFloat((rgb>>8)&255)/255*brightness,blue:CGFloat(rgb&255)/255*brightness,alpha:1)
 if hit(14){disk(144,38,13,accent)};disk(144,38,10,draftLamp ? led : actual);text("X",139,30,12,(draftLamp || (rgb>=0 && brightness>0.6 && ((rgb>>8)&255)>130)) ? .black:.white,true)
 if !draftLamp {let slot=v.count>=12 ? v[9] : -1;let tag=slot<0 ? "实机档位未知" : slot==0 ? "实机 · 默认档" : "实机 · 第 "+String(slot)+" 档"
 text(tag,461,30,12,.labelColor,true);text(rgb<0 ? "灯色未知":String(format:"#%06X",rgb),461,51,11,.secondaryLabelColor)
 if v.count>=12 && v[11]>=0{text("亮度 "+String(v[11])+"%",461,69,11,.secondaryLabelColor)}}

 for (b,x) in [(12,154),(13,126)]{disk(CGFloat(x),59,4,tint(b==12 ? "Menu":"View",b))}
 for (j,x,k,b) in [(0,61,"LT",8),(1,194,"RT",9)]{round(x,16,32,7,tint(j==0 ? "LB":"RB",b));round(x,6,32,6,rim);let pct=live ? min(1,Double(v[2+j])/1023):focus==k ? 1:0;round(x,6,Int(32*pct),6,accent)}
 }
 // Editing location stays visible independently of current input.
 let zones:[String:[Int]]=["LS":[57,35,40,40],"RS":[149,65,40,40],"A":[203,57,20,20],"B":[216,43,20,20],"X":[190,43,20,20],"Y":[203,29,20,20],"Xbox":[131,25,26,26],"D4":[100,69,13,13],"D5":[100,86,13,13],"D6":[92,78,13,13],"D7":[108,78,13,13],"LT":[59,3,36,12],"RT":[192,3,36,12],"LB":[59,14,36,12],"RB":[192,14,36,12],"P1":[63,48,53,23],"P2":[63,77,53,23],"P3":[172,48,53,23],"P4":[172,77,53,23],"leftGrip":[43,100,33,30],"rightGrip":[212,100,33,30]]
 if let z=zones[focus]{let r=NSRect(x:z[0],y:z[1],width:z[2],height:z[3]);let outline=NSBezierPath(roundedRect:r,xRadius:min(9,r.height/2),yRadius:min(9,r.height/2));NSColor.systemOrange.setStroke();outline.lineWidth=2.6+wave;outline.stroke()}
 text(focus.isEmpty ? "实时输入" : "正在配置   "+note,286,8,13,focus.isEmpty ? .labelColor:.systemOrange,true)
 if back {let down=(0..<4).filter{paddles>=0 && (paddles & (1<<$0)) != 0}.map{"P"+String($0+1)};text(paddles<0 ? "等待独立拨片报告…" : "实际拨片："+(down.isEmpty ? "未按下":down.joined(separator:" + ")),286,104,13,paddles<0 || down.isEmpty ? .secondaryLabelColor:accent,true)}
 if values.count < 8 || v[0]==0{text("等待所选手柄的输入报告…",286,43,12,.secondaryLabelColor)}
 else{
 let keys=["A","B","X","Y","↑","↓","←","→","LB","RB","LS","RS","Menu","View","Xbox"];let down=keys.indices.filter{hit($0)}.map{keys[$0]}
 text("按下  "+(down.isEmpty ? "—":down.joined(separator:" ")),286,34,12,.labelColor)
 text("LT  "+String(Int(roundPct(v[2])))+"%       RT  "+String(Int(roundPct(v[3])))+"%",286,57,13,.labelColor,true)
 if !back {for (i,k) in ["左","右"].enumerated(){let x=CGFloat(313+i*98);disk(x,99,13,rim);disk(x+CGFloat(v[4+2*i])/32768*9,99-CGFloat(v[5+2*i])/32768*9,3,accent);text(k,x-26,91,11,.secondaryLabelColor)}}
 }
 text("橙框：设置范围    绿色：实际输入",286,124,11,.secondaryLabelColor)

 }
 func roundPct(_ n:Int)->Double{(Double(n)*100/1023).rounded()}
}
extension Pad {
 @objc func changed(_ sender:NSControl){
 let pair=(sender.identifier?.rawValue ?? "Xbox|配置预览").components(separatedBy:"|")
 let val=(sender as? NSPopUpButton)?.titleOfSelectedItem ?? String(sender.integerValue)
 mark(pair[0],pair.last!+" · "+val)
 }
}
