package local.pi5.elite;

import java.io.IOException;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicInteger;

/** Full GIP frames for the three Elite Series 2 hardware profile slots. */
public final class ProfileGip {
    /**
     * An exclusive session to one physical controller. The link matches command and sequence
     * before delivery, handles transport acknowledgments and rejects a changed controller.
     */
    public interface Link {
        byte[] exchange(byte[] out, int timeoutMs) throws IOException;
        void send(byte[] out) throws IOException;
    }

    private static final int VENDOR = 0x4d;
    private static final int TIMEOUT_MS = 1500;
    private static final int[] PAGE_OFFSETS = {0, 6, 1, 7};
    private static final int[] PAGE_SIZES = {56, 56, 43, 43};
    private static final AtomicInteger SEQUENCE = new AtomicInteger((int) System.nanoTime() & 0xff);
    private final Link link;

    public ProfileGip(Link link) {
        if (link == null) throw new IllegalArgumentException("缺少手柄连接");
        this.link = link;
    }

    /** Normal mapping, Shift mapping, normal curves, Shift curves. No mode changes or commits. */
    public synchronized byte[][] readSlot(int slot) throws IOException {
        int base = pageBase(slot);
        byte[][] pages = new byte[PAGE_SIZES.length][];
        for (int i = 0; i < pages.length; i++) {
            int page = base + PAGE_OFFSETS[i];
            int size = PAGE_SIZES[i];
            byte[] result = command(new byte[]{2, (byte) page, (byte) size});
            if (result.length != size + 4 || (result[2] & 0xff) != page
                    || (result[3] & 0xff) != size) {
                throw new IOException("手柄返回的配置页编号或长度有误，页码 " + hex(page));
            }
            pages[i] = Arrays.copyOfRange(result, 4, result.length);
        }
        return pages;
    }

    /**
     * Caller must check original bytes and back them up before writing. Caller reads the four
     * pages again to verify. A failed transaction may have staged or committed data, so this
     * method never retries a command or issues a commit after a failed page.
     */
    public synchronized void writeSlot(int slot, byte[][] pages) throws IOException {
        writeChanged(slot,pages,null);
    }
    public synchronized void writeChanged(int slot,byte[][] pages,byte[][] old) throws IOException {
        int base = pageBase(slot);
        if (pages == null || pages.length != PAGE_SIZES.length) {
            throw new IOException("写入需要完整的四个原始配置页");
        }
        byte[][] input = new byte[PAGE_SIZES.length][];
        for (int i = 0; i < input.length; i++) {
            if (pages[i] == null || pages[i].length != PAGE_SIZES[i]) {
                throw new IOException("配置页长度不正确，已停止写入");
            }
            input[i] = pages[i].clone();
        }

        // Xbox Accessories captures: extended reports + unlock, four pages, extended + commit.
        // The final POWER command used on USB is unnecessary for reading back stored pages.
        // Do not send it over a live Xbox Wireless connection.
        confirm(new byte[]{7, 0});
        confirm(new byte[]{3});
        for (int i = 0; i < input.length; i++) {
            if(old!=null && Arrays.equals(old[i],input[i]))continue;
            int page = base + PAGE_OFFSETS[i];
            byte[] data = input[i];
            byte[] payload = new byte[3 + data.length];
            payload[0] = 1;
            payload[1] = (byte) page;
            payload[2] = (byte) data.length;
            System.arraycopy(data, 0, payload, 3, data.length);
            byte[] reply = command(payload);
            if (reply.length != 3 || (reply[2] & 0xff) != page) {
                throw new IOException("手柄未确认写入页 " + hex(page));
            }
        }
        confirm(new byte[]{7, 0});
        confirm(new byte[]{3});
    }

    private static int pageBase(int slot) throws IOException {
        if (slot < 1 || slot > 3) throw new IOException("仅支持手柄的第 1、2、3 档");
        return 0x20 + (slot - 1) * 2;
    }

    private void confirm(byte[] payload) throws IOException {
        if (command(payload).length < 2) {
            throw new IOException("手柄没有按预期确认命令 " + hex(payload[0]));
        }
    }

    byte[] command(byte[] payload) throws IOException {
        int sequence = Math.floorMod(SEQUENCE.getAndIncrement(), 255) + 1;
        byte[] frame = new byte[4 + payload.length];
        frame[0] = (byte) VENDOR;
        frame[1] = 0x10;
        frame[2] = (byte) sequence;
        frame[3] = (byte) payload.length;
        System.arraycopy(payload, 0, frame, 4, payload.length);
        byte[] reply = link.exchange(frame, TIMEOUT_MS);
        if (reply == null || reply.length < 6 || (reply[0] & 0xff) != VENDOR
                || (reply[1] & ~0x10) != 0 || reply[2] != frame[2] || reply[4] != payload[0]) {
            throw new IOException("手柄没有返回匹配的配置响应，命令 " + hex(payload[0]));
        }
        int end = 4 + (reply[3] & 0xff);
        // The receiver may round frames up to a 32-bit boundary. Never include USB/RF padding
        // in a configuration page and never fill a short page with zeroes.
        if (end < 6 || (reply.length != end && reply.length != ((end + 3) & ~3))) {
            throw new IOException("手柄配置响应不完整，命令 " + hex(payload[0]));
        }
        if (reply[5] != 0) {
            throw new IOException("手柄拒绝配置命令 " + hex(payload[0])
                    + "，状态 " + hex(reply[5]));
        }
        return Arrays.copyOfRange(reply, 4, end);
    }

    private static String hex(int value) {
        return "0x" + Integer.toHexString(value & 0xff);
    }
}
