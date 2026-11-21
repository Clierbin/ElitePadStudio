package local.pi5.elite;
import android.app.*;import android.os.Bundle;import android.webkit.*;import android.view.KeyEvent;
import org.json.*;import java.util.*;import java.nio.charset.StandardCharsets;
/** Only the bundled, network-free TV editor may access this bridge. All radio requests are serialized. */
public class StudioActivity extends Activity {
 WebView w; Bridge bridge=new Bridge();
 @Override public void onCreate(Bundle b){super.onCreate(b);w=new WebView(this);setContentView(w);
 w.getSettings().setJavaScriptEnabled(true);w.getSettings().setBlockNetworkLoads(true);w.getSettings().setAllowContentAccess(false);w.getSettings().setAllowUniversalAccessFromFileURLs(false);w.getSettings().setAllowFileAccessFromFileURLs(false);
 w.setWebViewClient(new WebViewClient(){@Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){return true;}});
 w.setWebChromeClient(new WebChromeClient());w.addJavascriptInterface(bridge,"Studio");w.loadUrl("file:///android_asset/index.html");w.requestFocus();}
 @Override protected void onPause(){super.onPause();w.onPause();w.pauseTimers();}
 @Override protected void onResume(){super.onResume();w.onResume();w.resumeTimers();}
 @Override public void onBackPressed(){w.evaluateJavascript("Boolean(window.mayLeave && mayLeave())",r->{if("true".equals(r))finish();});}
 @Override public boolean dispatchKeyEvent(KeyEvent e){if(e.getKeyCode()==KeyEvent.KEYCODE_BUTTON_A){return super.dispatchKeyEvent(new KeyEvent(e.getDownTime(),e.getEventTime(),e.getAction(),KeyEvent.KEYCODE_ENTER,e.getRepeatCount()));}return super.dispatchKeyEvent(e);}
 @Override protected void onDestroy(){w.removeJavascriptInterface("Studio");w.destroy();super.onDestroy();}
 final class Bridge{
 Radio.Pad selected;int slot;byte[][] orig;int cachedSlot=-1,rgb=-1,bright=-1;long retry;String cacheToken="";
 @JavascriptInterface public void pickScreen(){runOnUiThread(()->ScreenPick.open(StudioActivity.this,color->w.evaluateJavascript("window.pickedColor("+JSONObject.quote(color)+")",null)));}
 @JavascriptInterface public synchronized String request(String msg){JSONObject result=new JSONObject();try{result.put("out",dispatch(new JSONObject(msg)));}catch(Exception ex){try{result.put("error",ex.getMessage()==null?"操作失败":ex.getMessage());}catch(Exception ignored){}}return result.toString();}
 Object dispatch(JSONObject m)throws Exception{
 String op=m.getString("op");if(op.equals("list")){JSONArray a=new JSONArray();for(Radio.Pad p:Radio.list())a.put(new JSONObject().put("id",p.token).put("address",p.address).put("fw",p.firmware));return a;}
 if(op.equals("pair")){try(Radio r=new Radio()){r.request(6,new byte[0]);return true;}}
 String id=m.getString("id");Radio.Pad p=selected;
 if(p==null||!id.equals(p.token)){p=null;for(Radio.Pad item:Radio.list())if(item.token.equals(id))p=item;if(p==null)throw new Exception("手柄已断开，请刷新");}
 try(Radio r=new Radio(p)){ProfileGip g=new ProfileGip(r);
 if(op.equals("live")){String[] words=new String(r.request(4,new byte[0]),StandardCharsets.US_ASCII).trim().split(" +");if(words.length!=10)throw new Exception("配套服务版本不一致");
 JSONArray a=new JSONArray();for(String x:words)a.put(Integer.parseInt(x));int s=a.getInt(9);long now=android.os.SystemClock.elapsedRealtime();
 if(!cacheToken.equals(id)||cachedSlot!=s||(rgb<0 && now>=retry)){cacheToken=id;cachedSlot=s;retry=now+3000;rgb=s==0?0xffffff:-1;bright=-1;
 if(s>=1&&s<=3)try{byte[] d=g.command(new byte[]{2,(byte)(32+(s-1)*2),56});if(d.length==60&&(d[2]&255)==32+(s-1)*2&&d[3]==56){int mode=d[49]&255;rgb=mode==255?0xffffff:mode==0?((d[50]&255)<<16)|((d[51]&255)<<8)|(d[52]&255):-1;bright=d[48]&255;}}catch(Exception ignore){}}
 return a.put(rgb).put(bright);}
 if(op.equals("pulse")){int n=m.getInt("motor");if(n<0||n>3)throw new Exception("马达无效");r.request(5,new byte[]{(byte)n});return true;}
 if(op.equals("read")){int s=m.getInt("slot");byte[][] data=g.readSlot(s);selected=p;slot=s;orig=data;return pack(data);}
 if(selected==null||!id.equals(selected.token)||m.getInt("slot")!=slot||orig==null)throw new Exception("请重新读取目标档位");
 if(op.equals("backup")){byte[][] b=Backup.load(StudioActivity.this,p,slot);if(b==null)throw new Exception("本档暂无备份");return pack(b);}
 if(op.equals("save")){byte[][] next=unpack(m.getJSONArray("pages"));validateEdits(orig,next);if(Arrays.deepEquals(next,orig))return true;
 if(!Arrays.deepEquals(orig,g.readSlot(slot)))throw new Exception("手柄内容已变化，请重新读取");Backup.store(StudioActivity.this,p,slot,orig);byte[][] old=orig;orig=null;cachedSlot=-1;
 g.writeChanged(slot,next,old);if(!Arrays.deepEquals(next,g.readSlot(slot)))throw new Exception("写后校验失败，请重新读档");orig=next;return true;}
 if(op.equals("getName")||op.equals("setName")){String old=name(g);if(op.equals("getName"))return old;
 String n=m.getString("name");if(!old.equals(m.getString("old"))||n.trim().isEmpty()||n.length()>15||n.matches("(?s).*\\p{Cntrl}.*"))throw new Exception("原名变化或新名称无效");
 if(!getSharedPreferences("name-history",MODE_PRIVATE).edit().putString(p.address+"-"+System.currentTimeMillis(),old).commit())throw new Exception("名称备份失败");
 byte[] data=new byte[33];data[0]=4;byte[] str=n.getBytes(StandardCharsets.UTF_16LE);System.arraycopy(str,0,data,1,str.length);g.command(new byte[]{3});g.command(data);if(!n.equals(name(g)))throw new Exception("名称写后校验失败");return n;}
 throw new Exception("未知请求");}}
 String name(ProfileGip g)throws Exception{byte[] d=g.command(new byte[]{5});if(d.length!=34)throw new Exception("名称响应不完整");return new String(d,2,32,StandardCharsets.UTF_16LE).replaceFirst("\\x00+$","");}
 JSONArray pack(byte[][] d){JSONArray a=new JSONArray();for(byte[] page:d){JSONArray b=new JSONArray();for(byte x:page)b.put(x&255);a.put(b);}return a;}
 byte[][] unpack(JSONArray a)throws Exception{if(a.length()!=4)throw new Exception("配置长度无效");byte[][] out=new byte[4][];for(int q=0;q<4;q++){JSONArray b=a.getJSONArray(q);int n=q<2?56:43;if(b.length()!=n)throw new Exception("配置页不完整");out[q]=new byte[n];for(int j=0;j<n;j++){int x=b.getInt(j);if(x<0||x>255)throw new Exception("数值越界");out[q][j]=(byte)x;}}return out;}
 void validateEdits(byte[][] o,byte[][] d)throws Exception{for(int p=0;p<4;p++)for(int i=0;i<d[p].length;i++){if(o[p][i]==d[p][i])continue;int x=d[p][i]&255;boolean ok=p<2?((i>=1&&i<=16&&(x==0||x>=4&&x<=15))||(i>=28&&i<=31&&x<=100)||((i==32||i==34||i==38||i==40)&&o[p][i+1]==0)||(i>=45&&i<=48&&(i!=45||x==0||x==255))):(i>=1&&i<=24);
 if(p<2&&i>=9&&i<=16&&(o[p][0]&1)!=0)for(int j=9;j<=16;j++)if(o[p][j]==0)ok=false;
 if(p>=2&&ok){int k=1+6*((i-1)/6);int[] c=new int[6];for(int j=0;j<6;j++)c[j]=d[p][k+j]&255;ok=0<c[0]&&c[0]<c[2]&&c[2]<c[4]&&c[4]<255&&c[1]<=c[3]&&c[3]<=c[5];}
 if(!ok)throw new Exception("不支持此字段或数值");}}
 }
}
