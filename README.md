# Muse Gadgets 多硬件开发板固件与移植生态 (Muse Gadgets Multi-Board Ecosystem)

一套面向 **Muse Gadgets** 的全开源硬件移植、探测与一键刷机工具链。支持官方开发板、商业智能硬件、以及各类经典/新型 ESP32 与 RISC-V 社区板子。

---

## 🌟 支持的硬件与开发板列表

| 板子代号 (`--board`) | 硬件型号与平台 | 特性 / 状态反馈后端 | 移植状态 |
| :--- | :--- | :--- | :--- |
| `devkit` | ESP32-C5 DevKitC-1 (Wi-Fi 6, RISC-V) | GPIO27 单珠 WS2812 地址灯 + GPIO28 按键 | **官方默认推荐** |
| `espressif-s3-devkitc-1` | ESP32-S3-DevKitC-1 v1.1 (N8R8) | 状态灯 + BOOT 按键 | 官方支持 |
| `c6-nopsram` | ESP32-C6 DevKit (无 PSRAM) | 状态灯 + BOOT 按键 | 官方支持 |
| `ideaspark` | ideaspark ESP32 + 1.9 寸 ST7789 彩屏 | 170x320 屏幕状态边缘条与动画 | 官方支持 |
| `waveshare-c6-lcd-147` | Waveshare ESP32-C6-LCD-1.47 | 1.47 寸彩色屏幕状态条 | 官方支持 |
| `waveshare-s3-epaper-154`| Waveshare ESP32-S3 1.54 寸墨水屏 V2 | 墨水屏状态刷新 | 官方支持 |
| `sensecap-indicator` | Seeed SenseCAP Indicator | 4.0 寸 ST7701 触控屏 | 官方支持 |
| `reterminal-e1001` | Seeed reTerminal E1001 | 7.5 寸黑白红三色墨水屏 | 官方支持 |
| `reterminal-e1002` | Seeed reTerminal E1002 | 7.3 寸彩色墨水屏 (Spectra 6) | 官方支持 |
| `home-assistant-voice` | Home Assistant Voice Preview Edition | 12 颗 WS2812 环形灯 + 按键 | 官方支持 |
| `seeed-respeaker-lite` | Seeed reSpeaker Lite + XIAO ESP32-S3 | 环形灯 + 麦克风阵列 (实验) | 官方支持 |
| `halocode` | **Makeblock HaloCode（光环板）** | **12 颗 RGB 矩阵 (IS31FL3731) + 中间物理按键** | **社区逆向移植（已验证）** |
| `m5stickc-plus` | **M5Stack M5StickC Plus v1.x** | **1.14 寸 ST7789 彩屏 + AXP192 + Button A** | **社区移植（源码补丁）** |

---

## 🚀 快速上手 (使用说明)

### 你要做的只有三件事：

1. **领取 SDK Token**：
   - 前往 [gadgets.muse.ai](https://gadgets.muse.ai) > Account > **SDK tokens** 领取以 `mgst_` 开头的 Token。
   - 请阅读 [Gadget SDK Terms](https://gadgets.muse.ai/sdk-terms)。*请勿将 Token 提交至公开仓库或贴入公开聊天。*
2. **连接开发板**：
   - 使用支持数据传输的 USB 数据线将板子连接至电脑（Mac / Linux 均支持）。
3. **一键编译与刷机**：
   ```bash
   chmod +x flash-muse-gadget.sh
   ./flash-muse-gadget.sh --board <板子代号>
   ```
   *例如为光环板刷机：*
   ```bash
   ./flash-muse-gadget.sh --board halocode
   ```
   脚本会自动提示安全输入 Token（输入不回显），也可预先执行：
   ```bash
   export MUSE_SDK_TOKEN=mgst_...
   ```

---

## 🔍 社区移植专题

### 1. Makeblock HaloCode（光环板）
- **硬件逆向报告**：详见 [`boards/makeblock-halocode/HARDWARE.md`](boards/makeblock-halocode/HARDWARE.md)。
- **硬件突破**：
  - 彻底推翻坊间假定 WS2812 协议的误区，证实 12 颗 RGB 灯由 **ISSI IS31FL3731（I2C 地址 `0x74`，SDA=GPIO 19, SCL=GPIO 18）** 矩阵芯片驱动。
  - 适配 **ESP32 revision v1.0**，绕过上游对 rev 3.0+ 的硬性依赖与 Secure Boot RSA 硬件限制。
  - 板载中间物理按键绑定至 GPIO 0。
- **探测工具**：`boards/makeblock-halocode/halocode-probe/` 提供了可用于实时扫描 GPIO 和 I2C 外设的探测固件。

### 2. M5Stack M5StickC Plus v1.x
- **移植细节**：详见 [`boards/m5stack-m5stickc-plus/README.md`](boards/m5stack-m5stickc-plus/README.md)。
- 通过应用 `m5stickc-plus.patch` 拓展了 ST7789 驱动，支持 135x240 显示状态并适配 AXP192 电源芯片。

---

## 🛠️ 添加更多新开发板

欢迎社区贡献新的开发板适配！请查阅详细移植手册：
👉 [**新开发板移植指南 (docs/PORTING_NEW_BOARDS.md)**](docs/PORTING_NEW_BOARDS.md)

---

## 📱 配对与使用

1. 固件刷写完成后，设备进入配对广播状态（若配备灯光则为橙色呼吸，屏幕版则显示配对画面）。
2. 在手机打开 **Muse App**：进入 **设置 > 设备 > 开启开发者模式**，点击右上角 `+` 添加设备，找到 `MuseGadget-XXXXXX`。
3. 当提示确认时，按一下板子上的物理按键（如 BOOT 键）完成本人操作确认。
4. 连接成功后即可开始与 Muse 协同体验！
   - 长按物理按键 **5 秒**：解除配对并清除 Wi-Fi，恢复初始设置。
