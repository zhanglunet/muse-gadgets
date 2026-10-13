# M5Stack M5StickC Plus v1.x 社区移植说明

## 硬件规格
- **主控**: ESP32-PICO-D4 (双核 Xtensa LX6 240MHz, 4MB Flash, 无 PSRAM)
- **屏幕**: 1.14 寸 ST7789v2 彩屏 (135x240 分辨率)
- **电源管理**: AXP192 (I2C 控制)
- **按键**:
  - Button A (正面大按键): GPIO 37 (Active-Low)
  - Button B (侧面按键): GPIO 39
- **RGB LED**: 红灯 GPIO 10 (Active-Low)

## 移植补丁与范围
- 补丁文件：`m5stickc-plus.patch`
- 显示后端：`HOMEHUB_LED_BACKEND_M5STICKC_PLUS_ST7789`（在屏幕上显示状态栏与配对动画，蓝牙名后缀 `-Disp`）
- 按键：默认绑定 Button A (GPIO 37)，用于配对确认与长按 5 秒重置。
