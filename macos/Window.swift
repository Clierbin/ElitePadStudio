import Cocoa
import Foundation
final class UI:NSObject,NSApplicationDelegate,NSWindowDelegate,NSTextFieldDelegate {
 let win=NSWindow(contentRect:NSRect(x:0,y:0,width:676,height:654),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
 let stack=NSStackView(), dev=NSPopUpButton(), slot=NSPopUpButton(), color=NSPopUpButton(), status=NSTextField(wrappingLabelWithString:"正在连接接收器…")
 var maps=[NSPopUpButton](), devices=[String](), current="", active=0, busy=false, loaded=false
 let panes=[NSStackView(),NSStackView(),NSStackView(),NSStackView()];var group:NSStackView?;var themeWatch:NSKeyValueObservation?
 let rear=Pad(),lamp=Pad(),monitor=Pad(),motor=NSPopUpButton()
 let tuning=Pad(); weak var dialogPad:Pad?
 func distribute(_ a:[Int]){for p in [rear,lamp,tuning,monitor,dialogPad].compactMap({$0}){p.values=a;p.live=true;p.needsDisplay=true}}
 let follow=NSButton(checkboxWithTitle:"跟随手柄",target:nil,action:nil), physical=NSTextField(labelWithString:"实机：等待报告")
 var draft=false
 func edited(){draft=true;follow.state = .off}
 @objc func manualSlot(){follow.state = .off;readSlot()}
 @objc func enableFollow(){guard follow.state == .on,draft else{return};let a=NSAlert();a.messageText="放弃当前草稿并跟随手柄？";a.addButton(withTitle:"保留草稿");a.addButton(withTitle:"放弃并跟随");if a.runModal() == .alertSecondButtonReturn{draft=false;readSlot()}else{follow.state = .off}}
 func syncSlot(_ n:Int){physical.stringValue=n==0 ? "实机：默认档" : (1...3).contains(n) ? "实机：第 "+String(n)+" 档" : "实机：等待报告"
 guard (1...3).contains(n),follow.state == .on,!draft,!busy,NSApp.modalWindow==nil,slot.indexOfSelectedItem != n-1 else{return};slot.selectItem(at:n-1);readSlot()}
 @objc func userMapping(_ b:NSPopUpButton){edited();mappingPreview(b)}
 var liveTimer:Timer?,livePending=false
 @objc func mappingPreview(_ b:NSPopUpButton){let n=b.tag%4+1;rear.mark("P"+String(n),(b.tag<4 ? "常规 · " : "Shift · ")+"P"+String(n)+" → "+(b.titleOfSelectedItem ?? ""))}
 @objc func testPulse(){let i=dev.indexOfSelectedItem;guard !busy,devices.indices.contains(i) else{return};call(["op":"pulse","dev":devices[i],"motor":motor.indexOfSelectedItem]){_ in self.status.stringValue="已发送一次短震动，不会写入档位。"}}
 func tickLive(){let i=dev.indexOfSelectedItem;guard win.isVisible,!busy,!livePending,devices.indices.contains(i) else{return};let d=devices[i];livePending=true
 call(["op":"live","dev":d]){v in if let a=v as? [Int],a.count==12,self.devices.indices.contains(self.dev.indexOfSelectedItem),self.devices[self.dev.indexOfSelectedItem]==d{self.distribute(a);self.syncSlot(a[9])}}}
 let queue=DispatchQueue(label:"radio"), p=Process(),ip=Pipe(),op=Pipe()
 var buttons=[NSButton](); var timer:Timer?
 let hex=NSTextField(), well=NSColorWell(), sample=NSButton(), sampler=NSColorSampler()
 let advLayer=NSPopUpButton();var advanced=[[String:[Int]]]();var advancedButtons=[NSButton]()
 var swatches=[NSButton]()
 @objc func swatch(_ b:NSButton){guard loaded else{return};color.selectItem(at:b.tag);preset()}
 var originalHex="", colorEdited=false
 static func rgb(_ input:String)->String? {
   var s=input.trimmingCharacters(in:.whitespacesAndNewlines)
   if s.hasPrefix("#"){s.removeFirst()}
   guard s.utf8.count==6,s.utf8.allSatisfy({(48...57).contains($0)||(65...70).contains($0)||(97...102).contains($0)}) else{return nil}
   return s.uppercased()
 }
 func showHex(_ s:String){hex.stringValue=s;if s.isEmpty {well.color = .white;lamp.led = .white;lamp.needsDisplay=true}else{preview(s)}}
 func preview(_ s:String){guard let h=UI.rgb(s),let v=Int(h,radix:16) else{return};well.color=NSColor(srgbRed:CGFloat(v>>16)/255,green:CGFloat((v>>8)&255)/255,blue:CGFloat(v&255)/255,alpha:1);lamp.led=well.color;lamp.needsDisplay=true}
 @objc func preset(){edited();let i=color.indexOfSelectedItem;colorEdited=i != 0;if i==colors.count{return}; showHex(i==0 ? originalHex : i==1 ? "" : String(colors[i].suffix(6)).uppercased())}
 func controlTextDidChange(_ obj:Notification){edited();colorEdited=true;color.selectItem(at:colors.count);preview(hex.stringValue)}
 func useColor(_ picked:NSColor){guard loaded,let c=picked.usingColorSpace(.sRGB) else{return};edited();colorEdited=true;let vals=[c.redComponent,c.greenComponent,c.blueComponent].map{Int((min(1,max(0,$0))*255).rounded())};color.selectItem(at:colors.count);showHex(String(format:"%02X%02X%02X",vals[0],vals[1],vals[2]))}
 @objc func palette(){useColor(well.color)}
 @objc func takeSample(){let id=current, idx=active;sampler.show{[weak self] c in if let s=self,let c=c,s.loaded,s.selected(id,idx){s.useColor(c)}}}
 let names=[0:"未分配",4:"A",5:"B",6:"X",7:"Y",8:"方向上",9:"方向下",10:"方向左",11:"方向右",12:"LB",13:"RB",14:"左摇杆按下",15:"右摇杆按下"]
 let colors=["","ff000000","000000ff","00ff0000","0000ff00","00ffffff","008000ff","00ffaa00"]
 func label(_ s:String)->NSTextField {NSTextField(labelWithString:s)}
 func row(_ a:[NSView]){let v=NSStackView(views:a);v.spacing=10;(group ?? stack).addArrangedSubview(v)}
 func btn(_ name:String,_ sel:Selector)->NSButton{let b=NSButton(title:name,target:self,action:sel);buttons.append(b);return b}
 func applicationDidFinishLaunching(_ n:Notification){
 let menu=NSMenu(), editItem=NSMenuItem(), appItem=NSMenuItem();menu.addItem(appItem);let appMenu=NSMenu();appItem.submenu=appMenu;appMenu.addItem(withTitle:"退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");menu.addItem(editItem);let edit=NSMenu(title:"编辑");editItem.submenu=edit;for (t,a,k) in [("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")]{edit.addItem(withTitle:t,action:NSSelectorFromString(a),keyEquivalent:k)};NSApp.mainMenu=menu
 win.title="精英手柄配置";win.delegate=self; win.center()
 stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=false
 let c=win.contentView!;c.addSubview(stack);NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:c.leadingAnchor,constant:24),stack.topAnchor.constraint(equalTo:c.topAnchor,constant:22),stack.trailingAnchor.constraint(lessThanOrEqualTo:c.trailingAnchor,constant:-16)])
 let title=label("精英二代");title.font = .boldSystemFont(ofSize:23);row([title]);row([dev,btn("刷新手柄",#selector(refresh)),btn("无线配对",#selector(pair))]);dev.target=self;dev.action=#selector(readSlot)
 slot.addItems(withTitles:["第一档","第二档","第三档"]);slot.target=self;slot.action=#selector(manualSlot);follow.state = .on;follow.target=self;follow.action=#selector(enableFollow);physical.textColor = .secondaryLabelColor;row([slot,btn("读取档位",#selector(readSlot)),follow,physical])
 buildTabs();themeWatch=win.observe(\.effectiveAppearance,options:[.initial,.new]){[weak self] _,_ in self?.updatePanels()};group=panes[0];section("背面拨片","选一个按键，让拨片代替它。例如 P1 设为 A，在游戏里扣 P1 就相当于按 A。");rear.mark("P1","选择拨片映射可预览位置");row([rear]);var heads:[NSView]=[label("映射层")];heads[0].widthAnchor.constraint(equalToConstant:52).isActive=true;for i in 1...4{let h=label("P"+String(i));h.widthAnchor.constraint(equalToConstant:108).isActive=true;heads.append(h)};row(heads)
 for name in ["常规","Shift"] {var a:[NSView]=[label(name)];a[0].widthAnchor.constraint(equalToConstant:52).isActive=true;for _ in 0..<4 {let m=NSPopUpButton();for k in names.keys.sorted(){m.addItem(withTitle:names[k]!);m.lastItem!.tag=k};m.widthAnchor.constraint(equalToConstant:108).isActive=true;m.tag=maps.count;m.target=self;m.action=#selector(userMapping(_:));maps.append(m);a.append(m)};row(a)}
 row([caption("常规层用于平时操作；按住手柄已配置的 Shift 键时，使用第二行。")]);group=panes[2];section("Xbox 键灯色","每个档位可以用不同颜色。例如赛车档用蓝色，切档后看一眼 Xbox 键就知道。");lamp.draftLamp=true;lamp.mark("Xbox","Xbox 键灯色");row([lamp]);color.addItems(withTitles:["保留现有灯色","默认","蓝色","红色","绿色","白色","紫色","橙色","自定义"]);color.target=self;color.action=#selector(preset);var picks:[NSView]=[label("本档 Xbox 键灯色")]
 for i in 1..<colors.count {
   let title=color.itemTitle(at:i), b=NSButton(title:i==1 ? "默认" : "",target:self,action:#selector(swatch(_:)));b.tag=i;b.toolTip=title;b.setAccessibilityLabel(title)
   if i>1 {let v=Int(colors[i].suffix(6),radix:16)!;let paint=NSColor(srgbRed:CGFloat(v>>16)/255,green:CGFloat((v>>8)&255)/255,blue:CGFloat(v&255)/255,alpha:1)
     b.image=NSImage(size:NSSize(width:21,height:17),flipped:false){r in let shape=NSBezierPath(roundedRect:r.insetBy(dx:1,dy:1),xRadius:4,yRadius:4);paint.setFill();shape.fill();NSColor.gray.setStroke();shape.stroke();return true};b.imagePosition = .imageOnly}
   picks.append(b);swatches.append(b)
 };row(picks);
 hex.placeholderString="例：4A90FF";hex.delegate=self;hex.widthAnchor.constraint(equalToConstant:110).isActive=true;well.target=self;well.action=#selector(palette);well.toolTip="打开系统调色板";well.widthAnchor.constraint(equalToConstant:48).isActive=true;sample.title="屏幕取色";sample.bezelStyle = .rounded;sample.target=self;sample.action=#selector(takeSample);row([label("RGB 色值"),hex,well,sample]);group=panes[1];section("按键与手感","选择要编辑的按键层。调整只对当前档位生效。");row([tuning]);advLayer.addItems(withTitles:["常规层","Shift 层"]);var adv:[NSView]=[advLayer];for (i,title) in ["按键映射","输入行程","震动强度","摇杆曲线"].enumerated(){let b=btn(title,#selector(advancedPanel(_:)));b.tag=i;advancedButtons.append(b);adv.append(b)};row(adv);row([caption("输入行程决定多早达到满油门；摇杆曲线决定轻推时转向有多快。")]);row([caption("震动强度可分别调节握把和扳机，按键映射可更换正面按键和肩键的功能。")]);group=panes[3];section("实时手柄","直接读取当前所选手柄。这里显示板载映射后的按键，不是模拟输入。");monitor.live=true;row([monitor]);motor.addItems(withTitles:["握把 · 强马达","握把 · 弱马达","左扳机 LT","右扳机 RT"]);row([motor,btn("测试短震动",#selector(testPulse))]);row([caption("测试仅发送一次短脉冲；是否有体感取决于当前档位的马达强度。")]);group=nil;let line=NSBox();line.boxType = .separator;line.widthAnchor.constraint(equalToConstant:620).isActive=true;row([line]);let rename=btn("设备名称…",#selector(renamePad));advancedButtons.append(rename);let saveButton=btn("保存到手柄…",#selector(save));saveButton.bezelColor = .controlAccentColor;row([saveButton,rename,btn("打开备份目录",#selector(folder))]);row([status]);status.preferredMaxLayoutWidth=515
 dev.addItem(withTitle:"等待手柄");reset();win.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
 let res=Bundle.main.resourceURL!;p.executableURL=URL(fileURLWithPath:"/usr/bin/python3");p.arguments=[res.appendingPathComponent("window_rpc.py").path];p.standardInput=ip;p.standardOutput=op
 do{try p.run();liveTimer=Timer.scheduledTimer(withTimeInterval:1/30,repeats:true){[weak self] _ in self?.tickLive()};if let t=liveTimer{for mode in [RunLoop.Mode.modalPanel,.eventTracking]{RunLoop.main.add(t,forMode:mode)}};refresh();timer=Timer.scheduledTimer(withTimeInterval:3,repeats:true){[weak self] _ in if let s=self,s.devices.isEmpty && !s.busy && s.p.isRunning{s.refresh()}}}catch{status.stringValue=error.localizedDescription}
 }
 func call(_ d:[String:Any],_ cb:@escaping (Any)->Void){if busy{return};let polling=d["op"] as? String=="live";if !polling{busy=true;dev.isEnabled=false;slot.isEnabled=false}
 queue.async {var ret:[String:Any]=[:];do{guard self.p.isRunning else{throw NSError(domain:"接收器服务已退出，请退出 GamepadBridge 后重新打开本应用。",code:1)}
 var data=try JSONSerialization.data(withJSONObject:d);data.append(10);try self.ip.fileHandleForWriting.write(contentsOf:data);let raw=self.op.fileHandleForReading.availableData;ret=(try JSONSerialization.jsonObject(with:raw) as? [String:Any]) ?? [:]}catch{ret=["error":"接收器不可用。请确认已插入，并退出 GamepadBridge 或旧控制台，再重新打开窗口。"]}
 RunLoop.main.perform(inModes:[.default,.modalPanel,.eventTracking]){if polling{self.livePending=false;if let v=ret["out"]{cb(v)}else{self.distribute([]);self.physical.stringValue="实机：等待报告";self.status.stringValue="实时输入已断开，请刷新手柄。"};return};self.busy=false;self.dev.isEnabled=true;self.slot.isEnabled=true;if let v=ret["out"]{cb(v)}else{self.reset();self.status.stringValue=ret["error"] as? String ?? "读取失败"}}}}
 @objc func reset(){draft=false;physical.stringValue="实机：等待报告";distribute([]);rear.mark("P1","等待档位数据");lamp.led = .white;lamp.needsDisplay=true;loaded=false;advanced=[];advancedButtons.forEach{$0.isEnabled=false};swatches.forEach{$0.isEnabled=false};colorEdited=false;originalHex="";color.selectItem(at:0);well.deactivate();well.color = .white;well.isEnabled=false;hex.isEnabled=false;sample.isEnabled=false;hex.stringValue="";maps.forEach{$0.isEnabled=false};color.isEnabled=false;buttons.first{$0.title.hasPrefix("保存")}?.isEnabled=false;status.stringValue="选择手柄和档位，然后点「读取档位」。"}
 @objc func refresh(){call(["op":"list"]){v in let ds=v as? [String] ?? [];if ds != self.devices || ds.isEmpty {self.devices=ds;self.dev.removeAllItems();self.dev.addItems(withTitles:ds.isEmpty ? ["等待手柄"] : ds.map{"精英二代 · "+($0.components(separatedBy:" ").first ?? "")});self.reset();if !ds.isEmpty{self.readSlot()}};if ds.isEmpty{self.status.stringValue="按 Xbox 键开机，连接后手柄会自动出现。"}}}
 @objc func pair(){call(["op":"pair"]){_ in self.status.stringValue="长按手柄顶部配对键，等待指示灯常亮。"}}
 @objc func readSlot(){let i=dev.indexOfSelectedItem;guard devices.indices.contains(i), !busy else{return};let device=devices[i],s=slot.indexOfSelectedItem+1;reset();status.stringValue="正在读取第 \(s) 档…"
 call(["op":"read","dev":device,"slot":s]){v in guard let obj=v as? [String:Any],let m=obj["maps"] as? [[Int]],self.selected(device,s) else{return};for (idx,pop) in self.maps.enumerated(){let k=m[idx/4][idx%4];if pop.menu?.item(withTag:k)==nil{pop.addItem(withTitle:"原值 \(k)");pop.lastItem!.tag=k};pop.selectItem(withTag:k);pop.isEnabled=true};self.mappingPreview(self.maps[0]);self.current=device;self.active=s;self.loaded=true;self.advanced=obj["advanced"] as? [[String:[Int]]] ?? [];self.advancedButtons.forEach{$0.isEnabled=self.advanced.count==2};self.swatches.forEach{$0.isEnabled=true};self.color.selectItem(at:0);self.color.isEnabled=true;self.buttons.first{$0.title.hasPrefix("保存")}?.isEnabled=true;let c=(obj["colors"] as? [String])?.first ?? "";self.originalHex=c.hasPrefix("00") ? String(c.suffix(6)).uppercased() : "";self.showHex(self.originalHex);self.color.selectItem(at:c.hasPrefix("ff") ? 1 : (self.originalHex.isEmpty ? 0 : self.colors.firstIndex(of:c.lowercased()) ?? self.colors.count));self.colorEdited=false;self.hex.isEnabled=true;self.well.isEnabled=true;self.sample.isEnabled=true;self.status.stringValue="已读取第 \(s) 档。当前常规灯色："+(c.hasPrefix("ff") ? "默认" : "#"+String(c.suffix(6)))}}
 func selected(_ d:String,_ s:Int)->Bool{let i=dev.indexOfSelectedItem;return devices.indices.contains(i) && devices[i]==d && slot.indexOfSelectedItem+1==s}
 @objc func save(){guard loaded && !busy && selected(current,active) else{return};let idx=color.indexOfSelectedItem;var stored="";if !colorEdited{stored=""}else if idx==colors.count{guard let h=UI.rgb(hex.stringValue) else{status.stringValue="请输入六位 RGB 色值，例如 #4A90FF。";win.makeFirstResponder(hex);return};stored="00"+h}else{stored=colors[idx]};let a=NSAlert();a.messageText="将修改保存到手柄的第 \(active) 档？";a.informativeText="写入前会备份当前配置。";a.addButton(withTitle:"保存");a.addButton(withTitle:"取消");guard a.runModal() == .alertFirstButtonReturn else{return};let m=maps.map{$0.selectedItem!.tag};call(["op":"save","dev":current,"slot":active,"maps":[Array(m.prefix(4)),Array(m.suffix(4))],"advanced":advanced,"color":stored]){_ in self.readSlot()}}
 @objc func folder(){NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Elite无线配置"))}
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
 func applicationWillTerminate(_ n:Notification){ip.fileHandleForWriting.closeFile()}
}
let app=NSApplication.shared, ui=UI();app.delegate=ui;app.setActivationPolicy(.regular);app.run()
