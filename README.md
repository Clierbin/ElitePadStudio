# ElitePad Studio
树莓派 5 Android TV 和 macOS 上的精英二代板载档位编辑器，使用微软 Xbox Wireless Adapter，修改保存在手柄内。已识别产品 0b00 和固件 5.23.6.0。
## 树莓派使用
打开电视应用「精英手柄配置」，用方向键移动焦点，A/确定打开选项，也支持鼠标。顶部按无线地址选择手柄。开启「跟随手柄」会跟随硬件报告的第 1–3 档；默认档只显示。修改会暂停跟随。写入前按手柄、固件和档位备份并检查原配置，写后读回四页。
- P1–P4、ABXY、方向键、肩键、摇杆按下的两层映射，保留现有 Shift 修饰键。
- 每轴满输入行程、四马达强度、四轴曲线与基于曲线的中心死区、每档 Xbox 键 RGB 灯色、设备蓝牙广播名称。
- 摇杆、按键、扳机百分比、物理拨片、实机档位与保存灯色，按需测试单个马达。橙框是编辑目标，绿色是真实输入。固件未报告的状态显示未知。
- 色值输入、预设色、WebView 颜色选择与本应用画面取色。电视端取色不会录制其他应用。备份存于应用私有目录，清除数据会删除备份。
## 编译及升级现有 r4
Mac 构建机：Android SDK Platform 34、Build Tools 34.0.0、JDK 11、Android NDK r27d、CMake 3.20+。设置 ANDROID_SDK_ROOT、ANDROID_NDK_ROOT。android/build.sh 默认使用用户自己的 ~/.android/debug.keystore 开发签名。首次可使用 Android Studio 创建开发密钥；同包名升级必须沿用同一签名。不要提交私钥。
运行 `bash scripts/build-pi.sh` 得到 dist/xow 与 dist/elite-profiles.apk。单装 APK 不够；需要配套服务。升级脚本面向已经装好 r4、接收器固件、libusb 和 xbox_pi5 init 服务，且支持 adb root 的 Pi 5 Android TV 系统，不是全新系统的一键安装器。
连接自己的树莓派，设置 ANDROID_SERIAL，adb root 并重连。运行 `bash scripts/upgrade-pi.sh`；回退游戏驱动用 `bash scripts/upgrade-pi.sh rollback`。会短暂断开手柄，不清除配对。完成后 adb unroot。回退后游戏输入可用，配置编辑器需要新版服务。pi/ 提供现有冷启动、热插拔和 init 脚本源文件。
## macOS
需要 Xcode Command Line Tools 与系统 Python 3。XBOX_FIRMWARE 指向自行取得的 FW_ACC_00U.bin，运行 `bash scripts/build-mac.sh`。配置时退出 GamepadBridge，完成后再启动。不要分发包含微软固件的本地 .app。
## 目录与测试
android/assets 为电视离线界面；android/src 为 Android 本地通信、备份和配置处理；pi/native 为 ARM64 用户态驱动；macos 为 AppKit 客户端与 Mac 接收器通信。运行 `python3 macos/tests/test_advanced.py` 检查配置页边界和写后校验。tests/readonly_probe.py 可通过 adb forward 到 localabstract:pi5.elite.profiles.v1 对每只在线手柄做双遍只读核对。请不要公开带个人无线地址或序列号的日志。
许可证与上游见 LICENSE、NOTICE.md、licenses/。

无线输入布局回归：`c++ -std=c++17 tests/test_paddles.cpp -o /tmp/test-elite-input && /tmp/test-elite-input`。以下实机结果仅代表本次：树莓派 Android TV / 单只精英二代，应用成功识别并显示实时输入，三个档位的 12 页连续两遍读取完全一致。未为验收写入用户的手柄，未在这一版本重新断电或拔插接收器。
