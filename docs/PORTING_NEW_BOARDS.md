# Muse Gadgets 新开发板移植指南

本文档提供如何将任何新的 ESP32 / ESP32-S3 / ESP32-C6 / ESP32-C5 开发板或商业硬件移植到 Muse Gadgets 生态系统中的完整流程。

---

## 1. 移植基本要素

Muse Gadgets 固件运行在 ESP-IDF 之上，一个完整的开发板移植需要明确以下 5 个硬件要素：

1. **主控芯片型号与版本**：
   - ESP32 (经典双核), ESP32-S3, ESP32-C6, ESP32-C5 等。
   - **注意芯片版本（Revision）**：ESP32 rev 0/1 芯片必须在配置中指定 `CONFIG_ESP32_REV_MIN_0=y` 并关闭 Secure Boot V2 RSA 签名检查。
2. **Flash 容量与分区布局**：
   - 4MB / 8MB / 16MB。
   - 4MB 板子建议使用单 Factory App 分区布局（`partitions_<board>.csv`）。
3. **PSRAM 支持**：
   - 有 PSRAM：可开启家庭内网隧道 (`CONFIG_HOMEHUB_TUNNEL=y`)。
   - 无 PSRAM：禁用隧道 (`CONFIG_HOMEHUB_TUNNEL=n`)，以轻量控制通道运行。
4. **状态指示反馈后端 (LED / 屏幕)**：
   - WS2812 地址灯（如 `CONFIG_HOMEHUB_LED_BACKEND_DEVKIT_GPIO27=y`）
   - PWM RGB LED
   - 彩屏 / 墨水屏（ST7789, ST7701, SSD1681 等）
   - I2C 矩阵芯片（如 HaloCode 上的 IS31FL3731）或安全模式 (`CONFIG_HOMEHUB_LED_BACKEND_NONE=y`)
5. **物理按键 (Button)**：
   - 至少需要一个 Active-Low 按键（如 BOOT 按键 GPIO 0），用于：
     - 单击：配对鉴权确认
     - 长按 5 秒：清除 Wi-Fi 与配对信息，恢复出厂设置

---

## 2. 移植步骤

### 步骤 1：创建 Kconfig 覆盖配置 (`devices/sdkconfig.<board>`)
例如为你的开发板创建 `devices/sdkconfig.<myboard>`：
```ini
CONFIG_IDF_TARGET="esp32s3"
CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ_240=y

# 按键与指示灯
CONFIG_HOMEHUB_BUTTON_GPIO=0
CONFIG_HOMEHUB_LED_BACKEND_DEVKIT_GPIO27=y
CONFIG_HOMEHUB_LED_STRIP_GPIO=48

# Flash 与分区
CONFIG_ESPTOOLPY_FLASHMODE_DIO=y
CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions_<myboard>.csv"
```

### 步骤 2：创建分区表 (`partitions_<board>.csv`)
若为 4MB Flash 无 OTA 配置：
```csv
# Name,   Type, SubType, Offset,  Size,   Flags
nvs,      data, nvs,     0x11000, 0x6000,
phy_init, data, phy,     0x19000, 0x1000,
factory,  app,  factory, 0x20000, 0x3E0000,
```

### 步骤 3：在 `flash-muse-gadget.sh` 中注册板子
在脚本的 `case "$BOARD" in` 中添加你的板子定义：
```bash
myboard)
    TARGET=esp32s3; OVERLAYS="devices/sdkconfig.myboard"
    PORTS="/dev/cu.usbmodem* /dev/cu.usbserial-*"
    DESC="My Custom ESP32-S3 Board" ;;
```

---

## 3. 常见排查与避坑指南

1. **Bootloader 报 Chip revision error**：
   - 现象：`Chip revision X is older than minimum required 3`
   - 原因：经典 ESP32 rev 1.0 被强制要求 rev 3.0。
   - 修复：设置 `CONFIG_ESP32_REV_MIN_0=y`，同时设置 `CONFIG_SECURE_SIGNED_APPS_NO_SECURE_BOOT=n`。
2. **未知引脚探测**：
   - 若板载硬件未公开引脚图，可使用 `boards/makeblock-halocode/halocode-probe` 探测固件扫描 GPIO 和 I2C 总线。
