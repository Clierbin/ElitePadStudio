# 来源与许可

项目自有代码按 GPL-2.0-only 提供；各上游文件保留原有作者声明和许可证。

xow 的上游是 medusalix/xow，提交 d335d6024f8380f52767a7de67727d9b2f867871。作者和逐文件声明保存在 pi/native/vendor/xow。本项目从针对树莓派的 r4 改动继续开发。xow 采用 GPL-2.0-or-later。本次新增的无线配置接口以相同条款提供。
https://github.com/medusalix/xow/tree/d335d6024f8380f52767a7de67727d9b2f867871

libusb 来源于 libusb/libusb，提交 15a7ebb4d426c5ce196684347d2b7cafad862626（v1.0.29），动态链接。版权与 LGPL-2.1-or-later 许可位于 pi/native/vendor/libusb/AUTHORS 和 COPYING。
https://github.com/libusb/libusb/tree/15a7ebb4d426c5ce196684347d2b7cafad862626

精英二代板载页布局、配置事务和测试样本参考 lemonxah/xbelite2 的协议文档和 USB 抓包，提交 89ae1c5ed1dd20a56e3e9eb02830aac304ff53a7。上游以 GPL-2.0-only 提供。随包的 Android 配置应用源码按 GPL-2.0-only 提供。GPL 正文见licenses/。
https://github.com/lemonxah/xbelite2/tree/89ae1c5ed1dd20a56e3e9eb02830aac304ff53a7

设备继续使用此前树莓派已安装的微软官方接收器固件。固件归微软所有。

Mac 接收器基于 aberguecio/xow-mac（aacc2f35235579c96aad74dc1099889eb17271cf），GPL-2.0-or-later：https://github.com/aberguecio/xow-mac 。不同固件的输入布局参考 https://github.com/libsdl-org/SDL 的 SDL_hidapi_xboxone.c 文档。微软接收器固件和个人配置不随源码发布。本项目非官方。
