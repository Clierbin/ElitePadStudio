import Cocoa
extension UI {
 func caption(_ s:String)->NSTextField {let x=NSTextField(wrappingLabelWithString:s);x.font = .systemFont(ofSize:12);x.textColor = .secondaryLabelColor;x.preferredMaxLayoutWidth=590;return x}
 func section(_ title:String,_ sub:String){let t=label(title);t.font = .systemFont(ofSize:20,weight:.semibold);row([t]);row([caption(sub)])}
 func buildTabs(){
   let seg=NSSegmentedControl(labels:["拨片映射","手感调校","灯光外观","实时测试"],trackingMode:.selectOne,target:self,action:#selector(switchTab(_:)))
   for i in 0..<4 {seg.setWidth(130,forSegment:i);seg.setImage(NSImage(systemSymbolName:["gamecontroller","slider.horizontal.3","paintpalette","waveform.path.ecg"][i],accessibilityDescription:nil),forSegment:i)}
   seg.selectedSegment=0;row([seg])
   for pane in panes{pane.orientation = .vertical;pane.alignment = .leading;pane.spacing=12;pane.edgeInsets=NSEdgeInsets(top:18,left:20,bottom:18,right:20);pane.wantsLayer=true;pane.layer?.cornerRadius=14;pane.layer?.cornerCurve = .continuous;pane.setAccessibilityElement(false);stack.addArrangedSubview(pane);pane.widthAnchor.constraint(equalToConstant:620).isActive=true;pane.isHidden=true}
   panes[0].isHidden=false
 }
 @objc func switchTab(_ s:NSSegmentedControl){for i in panes.indices{panes[i].isHidden=i != s.selectedSegment}}
 func windowDidChangeEffectiveAppearance(_ notification:Notification){updatePanels()}
 func updatePanels(){win.effectiveAppearance.performAsCurrentDrawingAppearance{for p in panes{p.layer?.backgroundColor=NSColor.controlBackgroundColor.cgColor}}}
}
final class ResponseChart:NSView{
 let curve:[Int]
 init(_ points:[Int]){curve=points;super.init(frame:NSRect(x:0,y:0,width:180,height:94));widthAnchor.constraint(equalToConstant:180).isActive=true;heightAnchor.constraint(equalToConstant:94).isActive=true}
 required init?(coder:NSCoder){fatalError()}
 var onChange:(()->Void)?;var choice:NSPopUpButton?;var input:NSTextField?
 override func draw(_ rect:NSRect){let box=bounds.insetBy(dx:8,dy:7);NSColor.controlBackgroundColor.setFill();NSBezierPath(roundedRect:bounds,xRadius:7,yRadius:7).fill()
  func pt(_ x:Int,_ y:Int)->NSPoint{NSPoint(x:box.minX+CGFloat(x)/255*box.width,y:box.minY+CGFloat(y)/255*box.height)}
  let grid=NSBezierPath();for j in [0,127,255]{grid.move(to:pt(j,0));grid.line(to:pt(j,255));grid.move(to:pt(0,j));grid.line(to:pt(255,j))};NSColor.separatorColor.setStroke();grid.stroke()
  let presets=[[43,43,127,127,191,191],[43,20,127,96,191,175],[43,70,127,160,191,215],[13,0,127,120,191,187],[26,0,127,112,191,184],[38,0,127,105,191,180]]
  let i=choice?.indexOfSelectedItem ?? 0;let custom=input?.stringValue.split(separator:",").compactMap{Int($0.trimmingCharacters(in:.whitespaces))} ?? curve
  let v=i>0 ? presets[i-1] : custom;guard v.count==6 && v.allSatisfy({(0...255).contains($0)}) else{return}
  let path=NSBezierPath();path.move(to:pt(0,0));for k in stride(from:0,to:6,by:2){path.line(to:pt(v[k],v[k+1]))};path.line(to:pt(255,255));NSColor.controlAccentColor.setStroke();path.lineWidth=2.5;path.stroke()
 }
 @objc func redraw(){needsDisplay=true;onChange?()}
}
