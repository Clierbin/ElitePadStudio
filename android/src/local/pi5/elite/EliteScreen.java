package local.pi5.elite;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Android TV UI. All receiver access and persistent edits are owned by the Activity. */
final class EliteScreen {
    interface Actions {
        void onDevice(int index);
        void onSlot(int slot);
        void onRead();
        void onEdit(int layer, int index);
        void onSave();
        void onRestore();
        default void onColor() {}
        void onRefresh();
    }

    private static final int INK = 0xff101c20;
    private static final int PANEL = 0xff23373c;
    private static final int EDGE = 0xff496266;
    private static final int TEXT = 0xffedf7f4;
    private static final int SOFT = 0xffb9ceca;
    private static final int MINT = 0xffa5f0cf;
    private static final int DIM = 0xff849897;

    private final Activity activity;
    private final Actions actions;
    private final ScrollView scroll;
    private final LinearLayout body;
    private final LinearLayout editor;
    private final TextView status;
    private final TextView dirtyNotice;
    private final TextView wiring;
    private final Button device;
    private final Button slotButton;
    private final Button refresh;
    private final Button read;
    private final Button save;
    private final Button restore;
    private final Button color;
    private final Button[][] paddles = new Button[2][4];
    private String[] deviceLabels = new String[0];
    private int selectedDevice = -1;
    private int slot = 1;
    private Button lastFocus;

    EliteScreen(Activity activity, Actions actions) {
        this.activity = activity;
        this.actions = actions;
        scroll = new ScrollView(activity);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(INK);
        body = column();
        body.setPadding(dp(36), dp(22), dp(36), dp(22));
        scroll.addView(body);

        LinearLayout heading = row();
        body.addView(heading);
        TextView title = label("精英手柄配置", 30, TEXT);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        title.setAccessibilityHeading(true);
        heading.addView(title, weighted(1));
        dirtyNotice = label("有未保存的修改", 16, MINT);
        heading.addView(dirtyNotice);
        status = label("", 17, SOFT);
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        body.addView(status, stacked(5));

        LinearLayout selectors = row();
        body.addView(selectors, stacked(14));
        device = control("选择手柄", v -> chooseDevice());
        device.setSingleLine(true);
        device.setEllipsize(TextUtils.TruncateAt.END);
        slotButton = control("档位 1", v -> chooseSlot());
        refresh = control("刷新设备", v -> actions.onRefresh());
        addButton(selectors, device, 2.8f, 0, 44);
        addButton(selectors, slotButton, 1.1f, 10, 44);
        addButton(selectors, refresh, 1.1f, 10, 44);

        wiring = label("按手柄正面的 Xbox 键开机，等指示灯常亮后选择「刷新设备」。", 18, TEXT);
        wiring.setPadding(dp(18), dp(22), dp(18), dp(22));
        wiring.setBackground(shape(PANEL, EDGE));
        body.addView(wiring, stacked(16));

        editor = column();
        body.addView(editor, stacked(0));
        for (int layer = 0; layer < paddles.length; layer++) {
            String name = layer == 0 ? "常规拨片" : "Shift 拨片";
            TextView sectionTitle = label(name, 17, SOFT);
            sectionTitle.setAccessibilityHeading(true);
            editor.addView(sectionTitle, stacked(12));
            LinearLayout line = row();
            editor.addView(line, stacked(4));
            for (int index = 0; index < paddles[layer].length; index++) {
                final int l = layer;
                final int i = index;
                Button button = control("", v -> actions.onEdit(l, i));
                button.setMaxLines(2);
                button.setTextSize(17);
                button.setEllipsize(TextUtils.TruncateAt.END);
                paddles[layer][index] = button;
                addButton(line, button, 1, index == 0 ? 0 : 9, 60);
            }
        }
        color = control("档位灯色", v -> actions.onColor());
        editor.addView(color, stacked(8));
        color.setMinimumHeight(dp(40));
        color.setVisibility(View.GONE);

        LinearLayout operations = row();
        body.addView(operations, stacked(18));
        read = control("读取档位", v -> actions.onRead());
        save = control("保存到手柄", v -> actions.onSave());
        restore = control("恢复备份", v -> actions.onRestore());
        addButton(operations, read, 1, 0, 46);
        addButton(operations, save, 1, 10, 46);
        addButton(operations, restore, 1, 10, 46);
    }

    View root() {
        return scroll;
    }

    void show(String message, String[] labels, int currentDevice, int currentSlot,
              String[][] paddleLabels, boolean dirty, boolean busy, boolean ready, boolean canRestore) {
        Button previousFocus = lastFocus;
        deviceLabels = labels == null ? new String[0] : labels.clone();
        selectedDevice = currentDevice;
        slot = currentSlot;
        boolean selected = selectedDevice >= 0 && selectedDevice < deviceLabels.length;
        boolean available = selected && ready;
        boolean loaded = selected && paddleLabels != null && paddleLabels.length == 2
                && paddleLabels[0] != null && paddleLabels[0].length == 4
                && paddleLabels[1] != null && paddleLabels[1].length == 4;
        String feedback = message == null ? "" : message.trim();
        status.setText(feedback);
        status.setVisibility(feedback.isEmpty() ? View.GONE : View.VISIBLE);
        dirtyNotice.setVisibility(dirty ? View.VISIBLE : View.GONE);
        device.setText(selected ? deviceLabels[selectedDevice] : "选择无线手柄");
        device.setContentDescription(selected ? "选择手柄，当前为 " + deviceLabels[selectedDevice] : "选择无线手柄");
        device.setEnabled(deviceLabels.length > 0 && !busy);
        slotButton.setText("档位 " + currentSlot);
        slotButton.setContentDescription("选择档位，当前为档位 " + currentSlot);
        slotButton.setEnabled(selected && !busy);
        refresh.setEnabled(!busy);
        wiring.setVisibility(deviceLabels.length == 0 ? View.VISIBLE : View.GONE);
        editor.setVisibility(loaded ? View.VISIBLE : View.GONE);
        if (loaded) {
            for (int l = 0; l < paddles.length; l++) {
                for (int i = 0; i < paddles[l].length; i++) {
                    String mapping = paddleLabels[l][i];
                    String paddle = "P" + (i + 1);
                    paddles[l][i].setText(paddle + "\n" + mapping);
                    paddles[l][i].setContentDescription((l == 0 ? "常规 " : "Shift ")
                            + paddle + "，当前映射 " + mapping);
                    paddles[l][i].setEnabled(!busy && available);
                }
            }
        }
        read.setEnabled(available && !busy);
        save.setEnabled(available && loaded && dirty && !busy);
        restore.setEnabled(available && canRestore && !busy);
        if (busy) {
            lastFocus = previousFocus;
        } else if (scroll.findFocus() == null || scroll.findFocus() == scroll) {
            Button target = previousFocus;
            if (target == null || !target.isEnabled() || !target.isShown()) {
                target = available ? read : refresh;
            }
            target.requestFocus();
        }
    }

    void setColor(String description, boolean enabled) {
        color.setVisibility(description == null ? View.GONE : View.VISIBLE);
        if (description != null) color.setText("档位灯色  ·  " + description);
        color.setEnabled(enabled);
    }

    private void chooseDevice() {
        final String[] choices = deviceLabels.clone();
        new AlertDialog.Builder(activity)
                .setTitle("选择无线手柄")
                .setSingleChoiceItems(choices, selectedDevice, (dialog, item) -> {
                    dialog.dismiss();
                    if (item != selectedDevice) actions.onDevice(item);
                }).setNegativeButton("取消", null).show();
    }

    private void chooseSlot() {
        String[] names = {"档位 1", "档位 2", "档位 3"};
        new AlertDialog.Builder(activity)
                .setTitle("选择手柄档位")
                .setSingleChoiceItems(names, slot - 1, (dialog, item) -> {
                    dialog.dismiss();
                    if (item + 1 != slot) actions.onSlot(item + 1);
                }).setNegativeButton("取消", null).show();
    }

    private Button control(String caption, View.OnClickListener listener) {
        Button button = new Button(activity);
        button.setAllCaps(false);
        button.setMinHeight(0);
        button.setMinimumHeight(0);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setText(caption);
        button.setTextSize(17);
        button.setPadding(dp(6), 0, dp(6), 0);
        button.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        button.setGravity(Gravity.CENTER);
        button.setStateListAnimator(null);
        int[] disabled = {-android.R.attr.state_enabled};
        int[] focused = {android.R.attr.state_focused};
        int[] pressed = {android.R.attr.state_pressed};
        int[] normal = {};
        int[][] states = {disabled, pressed, focused, normal};
        button.setTextColor(new ColorStateList(states, new int[]{DIM, INK, INK, TEXT}));
        StateListDrawable surfaces = new StateListDrawable();
        surfaces.addState(disabled, shape(0xff1c292d, 0xff293b3d));
        surfaces.addState(pressed, shape(0xff7fc8a9, TEXT));
        surfaces.addState(focused, shape(MINT, TEXT));
        surfaces.addState(normal, shape(PANEL, EDGE));
        button.setBackgroundTintList(null);
        button.setBackground(surfaces);
        button.setOnFocusChangeListener((v, hasFocus) -> {
            if (hasFocus) lastFocus = button;
        });
        button.setOnClickListener(listener);
        return button;
    }

    private GradientDrawable shape(int fill, int border) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(fill);
        drawable.setCornerRadius(dp(9));
        drawable.setStroke(dp(1), border);
        return drawable;
    }

    private TextView label(String text, int size, int color) {
        TextView view = new TextView(activity);
        view.setText(text);
        view.setTextSize(size);
        view.setTextColor(color);
        return view;
    }

    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(activity);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private LinearLayout row() {
        LinearLayout layout = new LinearLayout(activity);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        layout.setGravity(Gravity.CENTER_VERTICAL);
        return layout;
    }

    private LinearLayout.LayoutParams stacked(int topMargin) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.topMargin = dp(topMargin);
        return params;
    }

    private LinearLayout.LayoutParams weighted(float weight) {
        return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, weight);
    }

    private void addButton(LinearLayout line, Button button, float weight, int gap, int height) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(height), weight);
        params.leftMargin = dp(gap);
        line.addView(button, params);
    }

    private int dp(int value) {
        return Math.round(activity.getResources().getDisplayMetrics().density * value);
    }
}
