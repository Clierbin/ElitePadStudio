package local.pi5.elite;

import java.util.Locale;

/** Raw page layout observed on the Elite Series 2 USB interface, firmware 5.17. */
public final class ProfilePages {
    private static final int[] LENGTHS = {56, 56, 43, 43};
    private static final int PADDLES = 1;
    private static final int COLOR_MODE = 45;
    private static final int RED = 46;
    private static final int GREEN = 47;
    private static final int BLUE = 48;
    private static final int[] TARGETS = {4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0};
    private static final String[] BUTTON_NAMES = {
        "A", "B", "X", "Y", "方向键上", "方向键下", "方向键左", "方向键右",
        "LB", "RB", "左摇杆按下", "右摇杆按下"
    };
    public static final int DEFAULT_COLOR = -1;
    public static final int UNKNOWN_COLOR = -2;

    private ProfilePages() {}

    /** Pages contain bare data in normal/shift mapping, normal/shift curve order. */
    public static void validate(byte[][] pages) {
        if (pages == null || pages.length != LENGTHS.length)
            throw new IllegalArgumentException("档位必须包含四个完整配置页");
        for (int i = 0; i < LENGTHS.length; i++) {
            if (pages[i] == null || pages[i].length != LENGTHS[i])
                throw new IllegalArgumentException("配置页 " + (i + 1) + " 长度不符");
        }
        if (pages[0] == pages[1] || pages[2] == pages[3])
            throw new IllegalArgumentException("普通层与 Shift 层必须独立保存");
    }

    public static byte[][] copy(byte[][] pages) {
        validate(pages);
        byte[][] result = new byte[pages.length][];
        for (int i = 0; i < pages.length; i++) result[i] = pages[i].clone();
        return result;
    }

    /** Apply a verified backup from the same physical pad, firmware and slot.
     * Preserve every other byte from the live read, including stick and trigger settings.
     * Original firmware-specific mappings and differently coloured layers round-trip exactly.
     */
    public static byte[][] restoreEditable(byte[][] live, byte[][] backup) {
        byte[][] result = copy(live);
        validate(backup);
        for (int layer = 0; layer < 2; layer++) {
            System.arraycopy(backup[layer], PADDLES, result[layer], PADDLES, 4);
            System.arraycopy(backup[layer], COLOR_MODE, result[layer], COLOR_MODE, BLUE - COLOR_MODE + 1);
        }
        return result;
    }

    private static byte[] mapping(byte[][] pages, int layer) {
        validate(pages);
        if (layer != 0 && layer != 1) throw new IllegalArgumentException("映射层超出范围");
        return pages[layer];
    }

    private static int offset(int index) {
        if (index < 0 || index >= 4) throw new IllegalArgumentException("拨片编号超出范围");
        return PADDLES + index;
    }

    public static int paddle(byte[][] pages, int layer, int index) {
        return mapping(pages, layer)[offset(index)] & 0xff;
    }

    public static int[] choices() {
        return TARGETS.clone();
    }

    public static String label(int code) {
        if (code == 0) return "未分配";
        if (code == 1) return "Shift 修饰键";
        if (code >= 4 && code <= 15) return BUTTON_NAMES[code - 4];
        return String.format(Locale.ROOT, "原有映射 0x%02X", code);
    }

    private static void requireTarget(int code) {
        if (code != 0 && (code < 4 || code > 15))
            throw new IllegalArgumentException("不支持写入这个拨片映射");
    }

    public static void setPaddle(byte[][] pages, int layer, int index, int code) {
        byte[] data = mapping(pages, layer);
        int at = offset(index);
        if ((data[at] & 0xff) == code) return;  // Keep an existing OEM-specific mapping verbatim.
        requireTarget(code);
        data[at] = (byte) code;
    }

    /** Returns 0xRRGGBB, DEFAULT_COLOR, or UNKNOWN_COLOR for unrecognised stored modes. */
    public static int color(byte[][] pages, int layer) {
        byte[] data = mapping(pages, layer);
        switch (data[COLOR_MODE] & 0xff) {
            case 0xff: return DEFAULT_COLOR;
            case 0: return ((data[RED] & 0xff) << 16) | ((data[GREEN] & 0xff) << 8)
                    | (data[BLUE] & 0xff);
            default: return UNKNOWN_COLOR;
        }
    }

    /** Profile lighting is set for both layers; the adjacent brightness byte stays untouched. */
    public static void setColor(byte[][] pages, int rgb) {
        validate(pages);
        if (rgb < DEFAULT_COLOR || rgb > 0xffffff) throw new IllegalArgumentException("颜色值无效");
        boolean isDefault = rgb == DEFAULT_COLOR;
        int channels = isDefault ? 0 : rgb;
        for (int layer = 0; layer < 2; layer++) {
            byte[] data = pages[layer];
            data[COLOR_MODE] = isDefault ? (byte) 0xff : 0;
            data[RED] = (byte) (channels >>> 16);
            data[GREEN] = (byte) (channels >>> 8);
            data[BLUE] = (byte) channels;
        }
    }

    /** Verify an editor transaction independently against the snapshot read from the controller. */
    public static void validateEdits(byte[][] original, byte[][] edited) {
        validate(original);
        validate(edited);
        boolean changedColor = false;
        for (int page = 0; page < LENGTHS.length; page++) {
            for (int i = 0; i < LENGTHS[page]; i++) {
                if (original[page][i] == edited[page][i]) continue;
                if (page < 2 && i >= PADDLES && i < PADDLES + 4) {
                    requireTarget(edited[page][i] & 0xff);
                } else if (page < 2 && i >= COLOR_MODE && i <= BLUE) {
                    changedColor = true;
                } else {
                    throw new IllegalArgumentException("修改涉及拨片和灯色以外的设置");
                }
            }
        }
        if (changedColor) {
            int rgb = color(edited, 0);
            if (rgb == UNKNOWN_COLOR || rgb != color(edited, 1))
                throw new IllegalArgumentException("两层灯色不匹配或灯色格式未知");
            if (rgb == DEFAULT_COLOR) {
                for (int layer = 0; layer < 2; layer++) {
                    if ((edited[layer][RED] | edited[layer][GREEN] | edited[layer][BLUE]) != 0)
                        throw new IllegalArgumentException("恢复默认灯色时 RGB 值应清零");
                }
            }
        }
    }
}
