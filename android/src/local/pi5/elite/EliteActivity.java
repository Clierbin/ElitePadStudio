package local.pi5.elite;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;

import java.io.IOException;
import java.util.Arrays;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Foreground settings for profiles on individual paired Elite Series 2 controllers. */
public final class EliteActivity extends Activity implements EliteScreen.Actions {
    private static final String TAG = "EliteProfiles";
    private static final int[] COLORS = {
            ProfilePages.DEFAULT_COLOR, 0xff4444, 0xff9d00, 0xffdd00, 0x39d277,
            0x00cee0, 0x247bff, 0x9946ff, 0xff669e, 0xffffff
    };
    private static final String[] COLOR_NAMES = {
            "默认白", "红", "橙", "黄", "绿", "青", "蓝", "紫", "粉", "白"
    };

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private EliteScreen screen;
    private Radio.Pad[] devices = new Radio.Pad[0];
    private int selected = -1;
    private int slot = 1;
    private byte[][] original;
    private byte[][] draft;
    private byte[][] backup;
    private boolean fromBackup;
    private boolean busy;
    private String status = "";

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        screen = new EliteScreen(this, this);
        setContentView(screen.root());
        onRefresh();
    }

    private Radio.Pad pad() {
        return selected >= 0 && selected < devices.length ? devices[selected] : null;
    }

    private static String shortId(Radio.Pad pad) {
        String address = pad.address;
        return address.substring(Math.max(0, address.length() - 8)).toUpperCase(Locale.ROOT);
    }

    private static String displayName(Radio.Pad pad) {
        return "精英二代 · " + shortId(pad);
    }

    private boolean dirty() {
        return draft != null && !Arrays.deepEquals(original, draft);
    }

    private void render() {
        String[] names = new String[devices.length];
        for (int i = 0; i < devices.length; i++) names[i] = displayName(devices[i]);
        String[][] labels = null;
        if (draft != null) {
            labels = new String[2][4];
            for (int l = 0; l < 2; l++) {
                for (int p = 0; p < 4; p++) labels[l][p] = ProfilePages.label(ProfilePages.paddle(draft, l, p));
            }
        }
        screen.show(status, names, selected, slot, labels, dirty(), busy, pad() != null,
                draft != null && backup != null);
        String color = null;
        if (draft != null) {
            int regular = ProfilePages.color(draft, 0), shifted = ProfilePages.color(draft, 1);
            color = regular == shifted ? colorName(regular) : colorName(regular) + " / " + colorName(shifted);
        }
        screen.setColor(color, draft != null && !busy);
    }

    private static String colorName(int rgb) {
        for (int i = 0; i < COLORS.length; i++) if (COLORS[i] == rgb) return COLOR_NAMES[i];
        return rgb == ProfilePages.UNKNOWN_COLOR ? "原有模式"
                : String.format(Locale.ROOT, "#%06X", rgb);
    }

    private void clearSnapshot() {
        original = draft = backup = null;
        fromBackup = false;
    }

    private void discardThen(Runnable next) {
        if (busy) return;
        if (!dirty()) {
            next.run();
            return;
        }
        new AlertDialog.Builder(this).setTitle("放弃本档的草稿？")
                .setMessage("当前修改尚未写入手柄。")
                .setNegativeButton("保留草稿", null)
                .setPositiveButton("放弃并继续", (dialog, which) -> next.run()).show();
    }

    private interface Job<T> { T run() throws Exception; }
    private interface Completion<T> { void accept(T value); }

    private <T> void runJob(String message, Job<T> work, Completion<T> success,
                            Completion<Exception> failure) {
        if (busy) return;
        busy = true;
        status = message;
        render();
        io.execute(() -> {
            try {
                T result = work.run();
                runOnUiThread(() -> {
                    if (isDestroyed() || isFinishing()) return;
                    busy = false;
                    success.accept(result);
                    render();
                });
            } catch (Exception e) {
                Log.w(TAG, message, e);
                runOnUiThread(() -> {
                    if (isDestroyed() || isFinishing()) return;
                    busy = false;
                    failure.accept(e);
                    render();
                });
            }
        });
    }

    private static String error(Exception e) {
        String message = e.getMessage();
        return message != null && !message.trim().isEmpty() ? message : e.getClass().getSimpleName();
    }

    @Override public void onRefresh() {
        discardThen(() -> {
            String oldAddress = pad() == null ? null : pad().address;
            clearSnapshot();
            runJob("正在查找已连接的精英二代…", Radio::list, list -> {
                devices = list;
                selected = devices.length == 0 ? -1 : 0;
                for (int i = 0; i < list.length; i++) {
                    if (list[i].address.equalsIgnoreCase(oldAddress)) selected = i;
                }
                status = pad() == null ? "等待无线手柄连接。" : "请选择档位，然后读取。固件 " + pad().firmware;
            }, e -> {
                devices = new Radio.Pad[0];
                selected = -1;
                status = "无法连接配置服务。" + error(e);
            });
        });
    }

    @Override public void onDevice(int index) {
        if (index < 0 || index >= devices.length || index == selected) return;
        discardThen(() -> {
            selected = index;
            clearSnapshot();
            status = "已选择 " + displayName(pad()) + "。请选择档位，然后读取。";
            render();
        });
    }

    @Override public void onSlot(int number) {
        if (number < 1 || number > 3 || number == slot) return;
        discardThen(() -> {
            slot = number;
            clearSnapshot();
            status = "已选择档位 " + slot + "，请读取手柄。";
            render();
        });
    }

    @Override public void onRead() {
        if (busy || pad() == null) return;
        discardThen(() -> {
            Radio.Pad controller = pad();
            int number = slot;
            clearSnapshot();
            runJob("正在读取档位 " + number + "…", () -> {
                byte[][] pages;
                try (Radio link = new Radio(controller)) {
                    pages = new ProfileGip(link).readSlot(number);
                }
                ProfilePages.validate(pages);
                byte[][] saved = Backup.load(this, controller, number);
                if (saved != null) ProfilePages.validate(saved);
                return new byte[][][]{pages, saved};
            }, result -> {
                original = result[0];
                draft = ProfilePages.copy(original);
                backup = result[1];
                status = "已读取档位 " + number + " · 固件 " + controller.firmware;
            }, e -> status = "读取失败。" + error(e) + " 重新连接后可刷新设备。");
        });
    }

    @Override public void onEdit(int layer, int index) {
        if (busy || draft == null) return;
        int[] codes = ProfilePages.choices();
        int current = ProfilePages.paddle(draft, layer, index);
        String[] names = new String[codes.length];
        int active = -1;
        for (int i = 0; i < codes.length; i++) {
            names[i] = ProfilePages.label(codes[i]);
            if (codes[i] == current) active = i;
        }
        String title = (layer == 0 ? "常规" : "Shift") + "拨片 P" + (index + 1);
        new AlertDialog.Builder(this).setTitle(title)
                .setSingleChoiceItems(names, active, (dialog, item) -> {
                    dialog.dismiss();
                    ProfilePages.setPaddle(draft, layer, index, codes[item]);
                    status = title + " · " + names[item];
                    render();
                }).setNegativeButton("取消", null).show();
    }

    @Override public void onColor() {
        if (busy || draft == null) return;
        int active = -1, regular = ProfilePages.color(draft, 0);
        if (regular == ProfilePages.color(draft, 1)) {
            for (int i = 0; i < COLORS.length; i++) if (COLORS[i] == regular) active = i;
        }
        new AlertDialog.Builder(this).setTitle("选择本档两层的灯色")
                .setSingleChoiceItems(COLOR_NAMES, active, (dialog, item) -> {
                    dialog.dismiss();
                    ProfilePages.setColor(draft, COLORS[item]);
                    status = "档位灯色 · " + COLOR_NAMES[item];
                    render();
                }).setNegativeButton("取消", null).show();
    }

    @Override public void onRestore() {
        if (busy || original == null || backup == null) return;
        new AlertDialog.Builder(this).setTitle("载入本档的原始备份？")
                .setMessage("将首次保存前的拨片和灯色载入草稿。其余设置沿用刚读取的档位。")
                .setNegativeButton("取消", null)
                .setPositiveButton("载入草稿", (dialog, which) -> {
                    draft = ProfilePages.restoreEditable(original, backup);
                    fromBackup = true;
                    status = dirty() ? "备份已载入草稿。确认后可保存到手柄。" : "当前拨片和灯色与备份一致。";
                    render();
                }).show();
    }

    @Override public void onSave() {
        if (busy || !dirty() || pad() == null) return;
        Radio.Pad controller = pad();
        int number = slot;
        new AlertDialog.Builder(this).setTitle("保存到手柄的档位 " + number + "？")
                .setMessage(displayName(controller) + "\n应用会先核对当前档位、保存备份，再写入并读回校验。请让手柄保持开机。")
                .setNegativeButton("取消", null)
                .setPositiveButton("确认写入", (dialog, which) -> save(controller, number)).show();
    }

    private void save(Radio.Pad controller, int number) {
        byte[][] expected = ProfilePages.copy(original);
        byte[][] desired = ProfilePages.copy(draft);
        boolean restore = fromBackup;
        boolean[] startedWrite = {false};
        boolean[] changedElsewhere = {false};
        runJob("正在核对、写入并校验档位 " + number + "…", () -> {
            try (Radio link = new Radio(controller)) {
                ProfileGip protocol = new ProfileGip(link);
                byte[][] current = protocol.readSlot(number);
                if (!Arrays.deepEquals(current, expected)) {
                    changedElsewhere[0] = true;
                    throw new IOException("手柄上的档位已经改变，请重新读取。");
                }
                byte[][] reference = current;
                if (restore) {
                    byte[][] stored = Backup.load(this, controller, number);
                    if (stored == null) throw new IOException("找不到此手柄和档位的原始备份。");
                    reference = ProfilePages.restoreEditable(current, stored);
                }
                ProfilePages.validateEdits(reference, desired);
                Backup.store(this, controller, number, current);
                byte[][] stored = Backup.load(this, controller, number);
                if (stored == null) throw new IOException("无法读取本次写入前保存的备份。");
                ProfilePages.validate(stored);
                startedWrite[0] = true;
                protocol.writeSlot(number, desired);
                byte[][] readback = protocol.readSlot(number);
                if (!Arrays.deepEquals(readback, desired)) throw new IOException("手柄读回数据与草稿不符。");
                return new byte[][][]{readback, stored};
            }
        }, result -> {
            original = result[0];
            draft = ProfilePages.copy(original);
            backup = result[1];
            fromBackup = false;
            status = "档位 " + number + " 已写入，四页内容读回一致。";
        }, e -> {
            if (startedWrite[0] || changedElsewhere[0]) clearSnapshot();
            status = (startedWrite[0] ? "写入结果未确认。请重新读取档位。 " : "尚未写入。") + error(e);
        });
    }

    @Override public void onBackPressed() {
        if (busy) {
            Toast.makeText(this, "正在与手柄通信，请稍候", Toast.LENGTH_SHORT).show();
            return;
        }
        discardThen(this::finish);
    }

    @Override protected void onDestroy() {
        io.shutdown();
        super.onDestroy();
    }
}
