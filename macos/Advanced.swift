import Cocoa
extension UI {
 func dialog(_ title:String,_ note:String,_ body:NSView,_ yes:String="应用到草稿")->Bool {
  let a=NSAlert();a.messageText=title;a.informativeText=note;a.accessoryView=body;a.addButton(withTitle:yes);a.addButton(withTitle:"取消");return a.runModal() == .alertFirstButtonReturn
 }
 @objc func advancedPanel(_ sender:NSButton) {
  guard loaded,!busy,advanced.count==2 else{return}
  let layer=advLayer.indexOfSelectedItem, cat=sender.tag
  let key=["keys","range","motors","curves"][cat]
  guard var values=advanced[layer][key] else{return}
  let titles=[["A","B","X","Y","方向上","方向下","方向左","方向右","LB","RB","左摇杆按下","右摇杆按下"],["LT 刹车","左摇杆","RT 油门","右摇杆"],["弱马达","强马达","RT 震动","LT 震动"],["左摇杆 X","左摇杆 Y","右摇杆 X","右摇杆 Y"]][cat]
  let section=["按键映射","满输入行程","震动强度","摇杆曲线与中心死区"][cat]
  let title="第 \(active) 档 · \(advLayer.titleOfSelectedItem ?? "") · "+section
  let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=7
  func add(_ views:[NSView]){let line=NSStackView(views:views);line.spacing=10;stack.addArrangedSubview(line)}
  let pad=Pad();dialogPad=pad;defer{dialogPad=nil};pad.live=true;pad.values=monitor.values;pad.heightAnchor.constraint(equalToConstant:cat==3 ? 75:105).isActive=true;pad.widthAnchor.constraint(equalToConstant:430).isActive=true;add([pad]);pad.mark(["A","LT","rightGrip","LS"][cat],section);
  var pop=[NSPopUpButton](), sliders=[NSSlider](), fields=[NSTextField]()
  if cat==0 {
   for j in 0..<6 {var cells=[NSView]();for i in [j,j+6]{let k=values[i],m=NSPopUpButton();for n in names.keys.sorted(){m.addItem(withTitle:names[n]!);m.lastItem!.tag=n};if m.itemArray.allSatisfy({$0.tag != k}){m.addItem(withTitle:"原值 \(k)");m.lastItem!.tag=k};m.selectItem(withTag:k);m.tag=i;m.identifier=NSUserInterfaceItemIdentifier(["A","B","X","Y","D4","D5","D6","D7","LB","RB","LS","RS"][i]+"|"+titles[i]);m.target=pad;m.action=#selector(Pad.changed(_:));pop.append(m);let lab=label(titles[i]);lab.widthAnchor.constraint(equalToConstant:80).isActive=true;cells += [lab,m]};add(cells)}
  }else if cat==1 || cat==2{
   let maxV=cat==1 ? 255.0 : 100.0
   for i in titles.indices{let l=label(titles[i]);l.widthAnchor.constraint(equalToConstant:75).isActive=true;let f=NSTextField(string:"\(values[i])");f.isEditable=false;f.isBezeled=false;f.drawsBackground=false;f.widthAnchor.constraint(equalToConstant:38).isActive=true
   let sl=NSSlider(value:Double(values[i]),minValue:0,maxValue:maxV,target:nil,action:nil);sl.widthAnchor.constraint(equalToConstant:230).isActive=true;sl.identifier=NSUserInterfaceItemIdentifier((cat==1 ? ["LT","LS","RT","RS"] : ["rightGrip","leftGrip","RT","LT"])[i]+"|"+titles[i]);sl.target=pad;sl.action=#selector(Pad.changed(_:));sl.isContinuous=true;sliders.append(sl);f.bind(.value,to:sl,withKeyPath:"integerValue",options:nil);fields.append(f);add([l,sl,f])}
  }else{
   add([label("每个轴有三个控制点：输入,输出（0–255）")])
   for i in titles.indices{let v=Array(values[6*i..<6*i+6]);let f=NSTextField(string:v.map(String.init).joined(separator:","));f.widthAnchor.constraint(equalToConstant:190).isActive=true;fields.append(f)
   let m=NSPopUpButton();m.addItems(withTitles:["使用左侧数值","线性","中心精细","快速响应","中心死区 5%","中心死区 10%","中心死区 15%"]);pop.append(m);let chart=ResponseChart(v);chart.onChange={pad.mark(i<2 ? "LS":"RS",titles[i]+" · "+(m.titleOfSelectedItem ?? ""))};chart.input=f;chart.choice=m;m.target=chart;m.action=#selector(ResponseChart.redraw);f.target=chart;f.action=#selector(ResponseChart.redraw);add([label(titles[i]),f,m,chart])}
  }
  stack.frame=NSRect(origin:.zero,size:stack.fittingSize)
  let note=["左边是你实际按的键，右边是游戏收到的键。例如把 A 设为 B，按 A 就会执行游戏的 B 动作。","向左调：轻扣就能达到满输入，油门或刹车更灵敏。向右调：有更长行程细调力度。255 是完整行程；0 会变成轻碰即满。","向右调，游戏触发震动时更强。强马达带来沉重感，弱马达更轻细；LT 和 RT 单独控制扳机反馈。0 只关闭这一项。","横向是推杆距离，纵向是游戏收到的输入。中心精细适合小幅修方向；快速响应让轻推更明显。增大死区能忽略中心轻微漂移，但起步要多推一点。"][cat]
  guard dialog(title,note,stack) else{return}
  if cat==0{for m in pop{values[m.tag]=m.selectedItem!.tag}}
  else if cat==1 || cat==2{for i in sliders.indices{values[i]=sliders[i].integerValue}}
  else{
   for i in titles.indices{let preset=pop[i].indexOfSelectedItem;let pts:[Int]
   if preset==0{let parts=fields[i].stringValue.components(separatedBy:",").map{$0.trimmingCharacters(in:.whitespaces)};pts=parts.compactMap(Int.init);guard parts.count==6 && pts.count==6 else{status.stringValue="曲线需要 6 个用逗号分隔的整数，本次未应用。";return}}
   else{pts=[[43,43,127,127,191,191],[43,20,127,96,191,175],[43,70,127,160,191,215],[13,0,127,120,191,187],[26,0,127,112,191,184],[38,0,127,105,191,180]][preset-1]}
   guard pts.allSatisfy({(0...255).contains($0)}),0<pts[0],pts[0]<pts[2],pts[2]<pts[4],pts[4]<255,pts[1]<=pts[3],pts[3]<=pts[5] else{status.stringValue="曲线控制点无效，本次未应用。";return};values.replaceSubrange(6*i..<6*i+6,with:pts)}
  }
  if advanced[layer][key] != values{edited()};advanced[layer][key]=values;status.stringValue=section+"已加入草稿，点「保存到手柄」写入。"
 }
 @objc func renamePad(){guard loaded,!busy else{return};let dev=current
  call(["op":"getName","dev":dev]){v in guard let old=v as? String,self.current==dev,self.loaded else{return}
  let f=NSTextField(string:old);f.frame=NSRect(x:0,y:0,width:300,height:24)
  guard self.dialog("设备名称","此名称由整只手柄共用，用于蓝牙广播；不改变 GamepadBridge 的显示名称。最多 15 个 UTF-16 单元。",f,"保存名称") else{return}
  let name=f.stringValue;guard name != old else{return};guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=15 else{self.status.stringValue="名称为空或过长。";return}
  self.call(["op":"setName","dev":dev,"old":old,"name":name]){_ in self.status.stringValue="手柄名称已写入并读回核对。"}}
 }
}
