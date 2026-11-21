package local.pi5.elite;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import java.io.Closeable;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;

final class Radio implements ProfileGip.Link, Closeable {
    static final class Pad {
        final String address, firmware, token;
        Pad(String[] words) {
            address = words[0]; token = address + " " + words[1]; firmware = words[2];
        }
    }
    private final LocalSocket socket = new LocalSocket();
    private DataInputStream in;
    private DataOutputStream out;
    Radio() throws IOException {
        try {
            socket.connect(new LocalSocketAddress("pi5.elite.profiles.v1", LocalSocketAddress.Namespace.ABSTRACT));
            if (socket.getPeerCredentials().getUid() != 0) throw new IOException("配置服务身份不符");
            socket.setSoTimeout(4500);
            in = new DataInputStream(socket.getInputStream());
            out = new DataOutputStream(socket.getOutputStream());
        } catch (IOException e) { socket.close(); throw new IOException("无线配置服务未连接，请检查接收器和配套服务",e); }
    }
    Radio(Pad pad) throws IOException {
        this();
        try { request(2,pad.token.getBytes(StandardCharsets.US_ASCII)); }
        catch(IOException e) { close(); throw e; }
    }
    static Pad[] list() throws IOException {
        ArrayList<Pad> devices = new ArrayList<>();
        try (Radio session = new Radio()) {
            String list = new String(session.request(1,new byte[0]),StandardCharsets.UTF_8).trim();
            if (!list.isEmpty()) for (String line : list.split("\n")) {
                String[] words=line.trim().split("\\s+");
                if (words.length!=3 || !words[0].matches("(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}") || !words[1].matches("[0-9]+") || !words[2].matches("[0-9.]+")) throw new IOException("无线服务返回了未知的手柄标识");
                devices.add(new Pad(words));
            }
        }
        return devices.toArray(new Pad[0]);
    }
    byte[] request(int op,byte[] data) throws IOException {
        out.writeByte(op); out.writeShort(data.length); out.write(data); out.flush();
        int status=in.readUnsignedByte(), len=in.readUnsignedShort();
        if (len>2048) throw new IOException("无线服务返回数据过长");
        byte[] reply = new byte[len]; in.readFully(reply);
        if (status!=0) throw new IOException("无线服务："+new String(reply,StandardCharsets.UTF_8));
        return reply;
    }
    public byte[] exchange(byte[] frame,int timeoutMs) throws IOException { return request(3,frame); }
    public void send(byte[] frame) throws IOException { throw new IOException("无线写入需要手柄明确应答"); }
    public void close() throws IOException { socket.close(); }
}
