package local.pi5.elite;
import android.app.*;import android.graphics.*;import android.os.*;import android.view.*;
/** Pick a pixel from this activity without capturing another app or requesting screen-recording permission. */
final class ScreenPick {
 interface Listener{void result(String rgb);}
 static void open(Activity a,Listener listener){
 View root=a.getWindow().getDecorView();int w=root.getWidth(),h=root.getHeight();if(w<1||h<1)return;
 float scale=Math.min(1f,1280f/w);Bitmap bitmap=Bitmap.createBitmap(Math.round(w*scale),Math.round(h*scale),Bitmap.Config.ARGB_8888);
 PixelCopy.request(a.getWindow(),bitmap,code->{if(code!=PixelCopy.SUCCESS||a.isFinishing()||a.isDestroyed()){bitmap.recycle();return;}
 Dialog dialog=new Dialog(a,android.R.style.Theme_Material_NoActionBar_Fullscreen);
 View picker=new View(a){
 final Paint paint=new Paint(3);int x=bitmap.getWidth()/2,y=bitmap.getHeight()/2;
 void choose(){int color=bitmap.getPixel(x,y);dialog.dismiss();listener.result(String.format(java.util.Locale.US,"%06x",color&0xffffff));}
 protected void onDraw(Canvas c){c.drawBitmap(bitmap,null,new Rect(0,0,getWidth(),getHeight()),null);float cx=x*(float)getWidth()/bitmap.getWidth(),cy=y*(float)getHeight()/bitmap.getHeight();
 paint.setStyle(Paint.Style.STROKE);paint.setColor(0xff000000);paint.setStrokeWidth(5);c.drawCircle(cx,cy,10,paint);paint.setColor(-1);paint.setStrokeWidth(2);c.drawCircle(cx,cy,10,paint);paint.setStyle(Paint.Style.FILL);paint.setColor(0xdd152326);c.drawRect(0,0,getWidth(),48,paint);paint.setTextSize(21);paint.setColor(-1);c.drawText(String.format(java.util.Locale.US,"方向键移动 · 确定取色 · 返回取消     #%06X",bitmap.getPixel(x,y)&0xffffff),16,32,paint);}
 public boolean onTouchEvent(MotionEvent e){x=Math.max(0,Math.min(bitmap.getWidth()-1,(int)(e.getX()*bitmap.getWidth()/getWidth())));y=Math.max(0,Math.min(bitmap.getHeight()-1,(int)(e.getY()*bitmap.getHeight()/getHeight())));invalidate();if(e.getAction()==MotionEvent.ACTION_UP)choose();return true;}
 public boolean onKeyDown(int k,KeyEvent e){int d=e.getRepeatCount()>3?12:1;switch(k){case 21:x-=d;break;case 22:x+=d;break;case 19:y-=d;break;case 20:y+=d;break;case 23:case 66:case 96:choose();return true;default:return super.onKeyDown(k,e);}x=Math.max(0,Math.min(bitmap.getWidth()-1,x));y=Math.max(0,Math.min(bitmap.getHeight()-1,y));invalidate();return true;}
 };
 dialog.setContentView(picker);picker.setFocusableInTouchMode(true);dialog.show();picker.requestFocus();
 },new Handler(Looper.getMainLooper()));}
}
