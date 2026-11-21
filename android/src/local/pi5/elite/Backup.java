package local.pi5.elite;

import android.content.Context;
import android.util.AtomicFile;
import java.io.*;
import java.security.*;
import java.util.Arrays;

final class Backup {
    private static final int[] LENGTHS={56,56,43,43};
    private static File file(Context c,Radio.Pad p,int slot,String kind) throws IOException {
        if(slot<1 || slot>3 || !p.address.matches("(?i)([a-f0-9]{2}:){5}[a-f0-9]{2}") || !p.firmware.matches("[0-9.]+")) throw new IOException("手柄标识无效");
        return new File(c.getFilesDir(),p.address.replace(":", "")+"_"+p.firmware+"_"+slot+"_"+kind+".bak");
    }
    private static byte[] hash(byte[] bytes) throws IOException {
        try { return MessageDigest.getInstance("SHA-256").digest(bytes); } catch(NoSuchAlgorithmException e){throw new IOException(e);}
    }
    static byte[][] load(Context c,Radio.Pad p,int slot) throws IOException {
        AtomicFile f=new AtomicFile(file(c,p,slot,"original"));
        byte[] all;
        try { all=f.readFully(); } catch(FileNotFoundException missing) {
            if (!f.getBaseFile().exists() && !new File(f.getBaseFile()+".bak").exists()) return null;
            throw missing;
        }
        if(all.length<32 || all.length>1024) throw new IOException("备份长度异常");
        byte[] data=Arrays.copyOf(all,all.length-32);
        if(!MessageDigest.isEqual(hash(data),Arrays.copyOfRange(all,data.length,all.length))) throw new IOException("备份校验失败");
        DataInputStream in=new DataInputStream(new ByteArrayInputStream(data));
        if(in.readInt()!=0x45504631 || !in.readUTF().equals(p.address) || !in.readUTF().equals(p.firmware) || in.readInt()!=slot) throw new IOException("备份与手柄、固件或档位不匹配");
        byte[][] result=new byte[4][];
        for(int i=0;i<4;i++){result[i]=new byte[LENGTHS[i]];in.readFully(result[i]);}
        if(in.available()!=0) throw new IOException("备份格式不符");
        return result;
    }
    static synchronized void store(Context c,Radio.Pad p,int slot,byte[][] pages) throws IOException {
        ProfilePages.validate(pages);
        ByteArrayOutputStream buf=new ByteArrayOutputStream();
        DataOutputStream out=new DataOutputStream(buf);
        out.writeInt(0x45504631);out.writeUTF(p.address);out.writeUTF(p.firmware);out.writeInt(slot);
        for(byte[] page:pages) out.write(page);
        byte[] data=buf.toByteArray();
        String kind=load(c,p,slot)==null?"original":"latest";
        AtomicFile f=new AtomicFile(file(c,p,slot,kind));
        FileOutputStream stream=f.startWrite();
        try {stream.write(data);stream.write(hash(data));f.finishWrite(stream);} catch(IOException e){f.failWrite(stream);throw e;}
        if(!Arrays.equals(f.readFully(),concat(data,hash(data)))) throw new IOException("备份写入后校验失败");
    }
    private static byte[] concat(byte[] a,byte[] b) {byte[] c=Arrays.copyOf(a,a.length+b.length);System.arraycopy(b,0,c,a.length,b.length);return c;}
}
