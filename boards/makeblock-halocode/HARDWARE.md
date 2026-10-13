# Makeblock HaloCode（光环板）硬件逆向与适配手册

本文档记录了对 Makeblock HaloCode（光环板）ESP32 硬件进行固件逆向工程、总线探测与 Muse Gadgets SDK 适配的全部技术细节与引脚/寄存器定义。

---

## 1. 核心硬件规格

| 模块 / 特性 | 硬件规格 | 备注 |
| :--- | :--- | :--- |
| **主控芯片** | ESP32-D0WDQ6 (Revision v1.0, 晶振 40MHz) | 双核 Xtensa 240MHz，**注意不是 rev 3.0** |
| **Flash** | 4 MB SPI Flash (DIO 模式, 80MHz) | 分区布局：单 App 槽无 OTA |
| **PSRAM** | 无板载 PSRAM | 控制通道可用，禁用本地内网隧道 |
| **USB 转串口** | WCH CH340 (`/dev/cu.usbserial-120`) | 波特率 115200 / 460800 |
| **按键** | 单个中央物理按键（多功能键） | Active-Low，连接 **GPIO 0**（兼作 BOOT） |
| **板载灯环** | **12 颗独立 RGB LED** | **非 WS2812**，由 ISSI **IS31FL3731** I2C 矩阵芯片驱动 |
| **I2C 总线** | **SDA = GPIO 19**, **SCL = GPIO 18** | 400kHz Fast Mode |
| **板载传感器** | 6 轴加速度计/陀螺仪 (LSM6DS3 @ `0x69`) | 磁力计/外设 (`0x10`) |
| **触摸引脚** | 4 个触摸环 (Touch0..3) | 边缘焊盘环 |

---

## 2. 关键逆向工程突破：LED 驱动架构

### 2.1 为什么 WS2812 驱动无效
许多开源社区尝试将 HaloCode 当作传统单总线 WS2812（Neopixel）驱动，导致所有测试脚位均无法点亮任何灯光。通过对 Makeblock 官方 MicroPython 原厂固件（`firefly`）进行二进制反汇编（`mb_led_matrix` 函数位于 `0x40143080`），证实板载 12 颗 RGB 灯珠实际由 **ISSI IS31FL3731（或兼容 IS31FL373x）** I2C 矩阵 PWM 控制芯片驱动。

### 2.2 I2C 总线探测结果
通过在 HaloCode 上运行 live I2C 扫描探测器，在总线上捕获到三个外设：
- **`0x74` (116)**: IS31FL3731 矩阵 LED 驱动器
- **`0x69` (105)**: LSM6DS3 6 轴运动传感器
- **`0x10` (16)**: 磁力计 / 扩展传感器

### 2.3 IS31FL3731 驱动协议与寄存器映射
- **总线管脚**：
  - `SDA`: **GPIO 19**
  - `SCL`: **GPIO 18**
- **命令页寄存器 (`0xFD`)**：
  - 写入 `0x0B`：进入 Function Registers 模式（功能寄存器页）
  - 写入 `0x00`：进入 Frame 0（帧 0 显示页）
- **初始化时序**：
  1. 选功能页：`WriteReg(0xFD, 0x0B)`
  2. 关断/准备模式：`WriteReg(0x0A, 0x00)`
  3. 配置帧显示：`WriteReg(0x01, 0x00)`（显示 Frame 0）
  4. 选 Frame 0：`WriteReg(0xFD, 0x00)`
  5. 开启所有通道 LED 使能位：`WriteReg(0x00..0x11, 0xFF)`
  6. 写入 12 颗 RGB PWM 占空比寄存器（寄存器偏移见下）
  7. 唤醒正常运行：切回功能页 `0xFD = 0x0B`，写入 `0x0A = 0x01`

#### 12 颗 LED 寄存器表（从反汇编提取）：
- **Red 通道**：`0x29, 0x28, 0x27, 0x26, 0x25, 0x24, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11`
- **Green 通道**：`0x35, 0x34, 0x33, 0x32, 0x31, 0x30, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D`
- **Blue 通道**：`0x41, 0x40, 0x3F, 0x3E, 0x3D, 0x3C, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05`

---

## 3. 上游 Muse Gadget SDK 移植要点

### 3.1 芯片版本支持（解决 Rev 3.0+ 崩溃）
上游 SDK 默认配置假设经典 ESP32 使用芯片版本 3.0+（`CONFIG_ESP32_REV_MIN_3=y`）。在 HaloCode（ESP32 v1.0）上启动会直接触发 Bootloader  panic：
```
eFuse check failed: Chip revision 1 is older than minimum required 3
```
**解决方案**：
在 `sdkconfig.halocode` 中覆盖如下参数：
```ini
CONFIG_ESP32_REV_MIN_0=y
CONFIG_ESP32_REV_MIN_3=n
CONFIG_ESP32_REV_MIN_FULL=0
```

### 3.2 关闭 Secure Boot V2 RSA 签名检查
ESP32 Secure Boot V2（RSA 方案）在硬件级别仅支持 ESP32 rev 3.0+。在 rev 1.0 芯片上必须禁用该构建选项：
```ini
CONFIG_SECURE_SIGNED_APPS_NO_SECURE_BOOT=n
CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES=n
CONFIG_SECURE_SIGNED_ON_UPDATE_NO_SECURE_BOOT=n
```

### 3.3 4MB 空间分区表 (`partitions_halocode.csv`)
单 Factory App 分区，留足 3.875MB 空间容纳带 TLS 与蓝牙协议栈的固件：
```csv
# Name,   Type, SubType, Offset,  Size,   Flags
nvs,      data, nvs,     0x11000, 0x6000,
phy_init, data, phy,     0x19000, 0x1000,
factory,  app,  factory, 0x20000, 0x3E0000,
```

### 3.4 状态指示灯与按键
- 按键配置：`CONFIG_HOMEHUB_BUTTON_GPIO=0`
- 状态后端：`CONFIG_HOMEHUB_LED_BACKEND_NONE=y`（或调用 IS31FL I2C 接口驱动）
