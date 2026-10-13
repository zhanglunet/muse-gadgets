#!/usr/bin/env bash
# flash-muse-gadget.sh — 一键编译并刷写 Muse Gadgets ESP32 固件
#
# 对应上游仓库: https://github.com/facebookincubator/muse-gadget-sdk (esp32/)
# 做法: 装 ESP-IDF v6.0.1 -> 把 SDK token 烘进固件(CONFIG_GADGET_SDK_TOKEN)
#       -> 按板子编译 -> esptool 刷机。token 只从环境变量或交互输入读取,
#       脚本内任何地方都不会打印完整 token。
#
# 用法:
#   ./flash-muse-gadget.sh [--board devkit] [--port /dev/cu.usbmodem1101]
#                          [--build-only] [--flash-only] [--monitor]
#                          [--idf-dir ~/esp/esp-idf-v6] [--repo-dir ~/muse-gadget-sdk]
#
#   MUSE_SDK_TOKEN 环境变量可预先设置; 未设置时会安全地交互式索取(不回显)。
set -euo pipefail

BOARD="devkit"
PORT=""
BUILD_ONLY=0
FLASH_ONLY=0
DO_MONITOR=0
IDF_DIR=""
REPO_DIR="${HOME}/muse-gadget-sdk"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORCE=0

usage() {
    sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    echo
    echo "支持的板子:"
    echo "  devkit                  ESP32-C5 DevKitC-1 (默认, 状态灯+按键)"
    echo "  espressif-s3-devkitc-1  ESP32-S3-DevKitC-1 v1.1 (N8R8)"
    echo "  c6-nopsram              ESP32-C6 devkit (无 PSRAM)"
    echo "  ideaspark               ideaspark ESP32 + 1.9寸 ST7789 屏"
    echo "  waveshare-c6-lcd-147    Waveshare ESP32-C6-LCD-1.47"
    echo "  waveshare-s3-epaper-154 Waveshare ESP32-S3 1.54寸墨水屏 V2"
    echo "  sensecap-indicator      Seeed SenseCAP Indicator (4寸屏)"
    echo "  reterminal-e1001        Seeed reTerminal E1001 (7.5寸墨水屏)"
    echo "  reterminal-e1002        Seeed reTerminal E1002 (7.3寸彩色墨水屏)"
    echo "  home-assistant-voice    Home Assistant Voice Preview Edition"
    echo "  seeed-respeaker-lite    Seeed reSpeaker Lite + XIAO ESP32-S3 (实验)"
    echo "  halocode                Makeblock HaloCode (社区移植, 实验)"
    echo "  m5stickc-plus         M5StickC Plus v1.x (社区移植, 实验)"
    echo
    echo "halocode 需要先跑 ./halocode-probe.sh 探测引脚, 再 export"
    echo "HALOCODE_BUTTON_GPIO / HALOCODE_LED_GPIO 后构建。"
    echo
    echo "带完整 UI 的板子(AMOLED 触屏等)请按仓库 AGENTS.md 用 tools/muse/board.sh 手动构建。"
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -b|--board)    BOARD="$2"; shift 2 ;;
        -p|--port)     PORT="$2"; shift 2 ;;
        --build-only)  BUILD_ONLY=1; shift ;;
        --flash-only)  FLASH_ONLY=1; shift ;;
        --monitor)     DO_MONITOR=1; shift ;;
        --idf-dir)     IDF_DIR="$2"; shift 2 ;;
        --repo-dir)    REPO_DIR="$2"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        -h|--help)     usage 0 ;;
        *) echo "未知参数: $1" >&2; usage 2 ;;
    esac
done

# ---- 板子配置表(与上游 tools/board.sh 保持一致) ----
case "$BOARD" in
    devkit)
        TARGET=esp32c5; OVERLAYS=""; PORTS="/dev/cu.usbmodem* /dev/ttyACM*"
        DESC="ESP32-C5 DevKitC-1" ;;
    c6-nopsram)
        TARGET=esp32c6; OVERLAYS="devices/sdkconfig.c6-nopsram"; PORTS="/dev/cu.usbmodem* /dev/ttyACM*"
        DESC="ESP32-C6 devkit (无 PSRAM)" ;;
    espressif-s3-devkitc-1)
        TARGET=esp32s3; OVERLAYS="devices/sdkconfig.espressif-s3-devkitc-1"; PORTS="/dev/cu.usbmodem* /dev/ttyACM*"
        DESC="ESP32-S3-DevKitC-1 v1.1" ;;
    ideaspark)
        TARGET=esp32; OVERLAYS="devices/sdkconfig.ideaspark"; PORTS="/dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/ttyUSB*"
        DESC="ideaspark ESP32 + 1.9寸屏" ;;
    waveshare-c6-lcd-147)
        TARGET=esp32c6; OVERLAYS="devices/sdkconfig.waveshare-c6-lcd-147"; PORTS="/dev/cu.usbmodem* /dev/ttyACM*"
        DESC="Waveshare ESP32-C6-LCD-1.47" ;;
    waveshare-s3-epaper-154)
        TARGET=esp32s3; OVERLAYS="devices/sdkconfig.waveshare-s3-epaper-154"; PORTS="/dev/cu.usbmodem* /dev/ttyACM*"
        DESC="Waveshare ESP32-S3 1.54寸墨水屏 V2" ;;
    sensecap-indicator)
        TARGET=esp32s3; OVERLAYS="devices/sdkconfig.sensecap-indicator"; PORTS="/dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/ttyUSB*"
        DESC="Seeed SenseCAP Indicator" ;;
    reterminal-e1001)
        TARGET=esp32s3; OVERLAYS="devices/sdkconfig.reterminal-e1001"; PORTS="/dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/ttyUSB*"
        DESC="Seeed reTerminal E1001" ;;
    reterminal-e1002)
        TARGET=esp32s3; OVERLAYS="devices/sdkconfig.reterminal-e1002"; PORTS="/dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/ttyUSB*"
        DESC="Seeed reTerminal E1002" ;;
    home-assistant-voice)
        TARGET=esp32s3; OVERLAYS="devices/sdkconfig.home-assistant-voice"; PORTS="/dev/cu.usbmodem* /dev/ttyACM*"
        DESC="Home Assistant Voice Preview Edition" ;;
    seeed-respeaker-lite)
        TARGET=esp32s3; OVERLAYS="devices/sdkconfig.seeed-respeaker-lite"; PORTS="/dev/cu.usbmodem* /dev/ttyACM*"
        DESC="Seeed reSpeaker Lite (实验)" ;;
    halocode)
        TARGET=esp32; OVERLAYS="devices/sdkconfig.halocode"
        PORTS="/dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART* /dev/cu.usbmodem* /dev/ttyUSB* /dev/ttyACM*"
        DESC="Makeblock HaloCode (社区移植, 实验)" ;;
    m5stickc-plus)
        TARGET=esp32; OVERLAYS="devices/sdkconfig.m5stickc-plus"
        PORTS="/dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART* /dev/cu.usbmodem* /dev/ttyUSB* /dev/ttyACM*"
        DESC="M5StickC Plus v1.x (社区移植, 实验)" ;;
    *) echo "不支持的板子: $BOARD" >&2; usage 2 ;;
esac

# HaloCode 配置: 默认按键为 GPIO 35 (板载中间按键)
if [ "$BOARD" = halocode ]; then
    HALOCODE_BUTTON_GPIO="${HALOCODE_BUTTON_GPIO:-35}"
fi


OS="$(uname -s)"
[ "$OS" = "Darwin" ] || [ "$OS" = "Linux" ] || { echo "只支持 macOS / Linux, 当前: $OS" >&2; exit 1; }

echo "==> 目标板子: $DESC ($BOARD, $TARGET)"

# ---- 1. 基础依赖 ----
for cmd in git python3 cmake ninja; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "缺少依赖: $cmd" >&2
        if [ "$OS" = "Darwin" ]; then
            echo "请先运行: brew install cmake ninja dfu-util python3" >&2
        else
            echo "请按 https://docs.espressif.com/projects/esp-idf/en/v6.0.1/esp32c5/get-started/linux-macos-setup.html 安装编译依赖" >&2
        fi
        exit 1
    }
done

# ---- 2. ESP-IDF v6.0.1 ----
if [ -z "$IDF_DIR" ]; then
    for d in "${IDF_PATH:-}" "$HOME/esp/esp-idf-v6.0.1" "$HOME/esp/esp-idf-v6" "$HOME/esp/esp-idf"; do
        if [ -n "$d" ] && [ -f "$d/export.sh" ]; then IDF_DIR="$d"; break; fi
    done
fi
if [ -z "$IDF_DIR" ]; then
    IDF_DIR="$HOME/esp/esp-idf-v6"
    echo "==> 未找到 ESP-IDF, 正在克隆 v6.0.1 到 $IDF_DIR (约 1GB, 需要几分钟)..."
    git clone -b v6.0.1 --recursive https://github.com/espressif/esp-idf.git "$IDF_DIR"
    echo "==> 安装工具链 (esp32c5,esp32s3,esp32c6,esp32, 约 10-20 分钟, 只需一次)..."
    "$IDF_DIR/install.sh" esp32c5,esp32s3,esp32c6,esp32
fi
# shellcheck disable=SC1091
. "$IDF_DIR/export.sh" >/dev/null 2>&1
command -v idf.py >/dev/null 2>&1 || { echo "idf.py 不可用, ESP-IDF 环境异常: $IDF_DIR" >&2; exit 1; }
IDF_VER="$(idf.py --version 2>/dev/null || true)"
echo "==> ESP-IDF: $IDF_VER"
case "$IDF_VER" in
    *v6.0.1*) ;;
    *) echo "警告: 官方只支持 v6.0.1, 当前为 $IDF_VER" >&2
       [ "$FORCE" = 1 ] || { echo "用 --force 可强行继续 (可能编译失败)" >&2; exit 1; } ;;
esac

# ---- 3. 仓库 ----
if [ ! -d "$REPO_DIR/esp32" ]; then
    echo "==> 克隆 muse-gadget-sdk 到 $REPO_DIR ..."
    git clone --depth 1 https://github.com/facebookincubator/muse-gadget-sdk "$REPO_DIR"
fi
# m5stickc-plus 的 C 语言移植补丁基于 2026-10-12 的上游快照: 钉住已验证的
# commit, 保证补丁能干净应用 (其他板子不受影响, 仍用最新上游)。
if [ "$BOARD" = m5stickc-plus ]; then
    PIN_COMMIT="812c46f9fe42b69d916613a9dc702cbac5ff7b54"
    if [ "$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)" != "$PIN_COMMIT" ]; then
        echo "==> m5stickc-plus 移植补丁需要上游快照 $PIN_COMMIT, 正在切换..."
        git -C "$REPO_DIR" fetch --depth 1 origin "$PIN_COMMIT" \
            && git -C "$REPO_DIR" checkout "$PIN_COMMIT" \
            || { echo "错误: 无法切换到 $PIN_COMMIT" >&2; exit 1; }
    fi
fi
PROJ="$REPO_DIR/esp32"
BUILD_DIR="$PROJ/build-$BOARD"
echo "==> 源码: $PROJ"

# ---- HaloCode 社区移植: 生成 overlay + 4MB 分区表 ----
setup_halocode() {
    local btn="${HALOCODE_BUTTON_GPIO:-35}"
    cat > "$PROJ/devices/sdkconfig.halocode" <<TEMPLATE
# Makeblock HaloCode — community port.
# Classic ESP32, 4 MB flash, programmable button.
# Load last, after sdkconfig.defaults.
CONFIG_IDF_TARGET="esp32"
CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ_240=y

# Status LED: disabled (board uses IS31FL373x I2C matrix, not WS2812).
CONFIG_HOMEHUB_LED_BACKEND_NONE=y

# Button, active low with internal pull-up (pairing confirm / 5s factory reset).
CONFIG_HOMEHUB_BUTTON_GPIO=$btn

# HaloCode uses ESP32-D0WDQ6 revision 1.0 (allow rev 0/1 chips).
CONFIG_ESP32_REV_MIN_0=y
CONFIG_ESP32_REV_MIN_3=n
CONFIG_ESP32_REV_MIN_FULL=0

# Disable Secure Boot V2 RSA signing (requires ESP32 rev 3+).
CONFIG_SECURE_SIGNED_APPS_NO_SECURE_BOOT=n
CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES=n
CONFIG_SECURE_SIGNED_ON_UPDATE_NO_SECURE_BOOT=n

# 4 MB flash, DIO mode; custom partition table (single app slot, no OTA).
CONFIG_ESPTOOLPY_FLASHMODE_DIO=y
CONFIG_ESPTOOLPY_FLASHFREQ_80M=y
CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y
CONFIG_ESPTOOLPY_FLASHSIZE="4MB"
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions_halocode.csv"

# PSRAM unconfirmed on this board: same no-PSRAM block as ideaspark.
CONFIG_SPIRAM=n
CONFIG_MBEDTLS_INTERNAL_MEM_ALLOC=y
CONFIG_MBEDTLS_EXTERNAL_MEM_ALLOC=n
CONFIG_MBEDTLS_SSL_OUT_CONTENT_LEN=4096
CONFIG_BTDM_CTRL_MODE_BLE_ONLY=y
CONFIG_BTDM_CTRL_MODE_BR_EDR_ONLY=n
CONFIG_BTDM_CTRL_MODE_BTDM=n
CONFIG_ESP_WIFI_STATIC_RX_BUFFER_NUM=8
CONFIG_ESP_WIFI_RX_BA_WIN=16
CONFIG_ESP_WIFI_TX_BA_WIN=16
CONFIG_ESP_WIFI_DYNAMIC_TX_BUFFER_NUM=16
CONFIG_LWIP_IRAM_OPTIMIZATION=n
CONFIG_LWIP_EXTRA_IRAM_OPTIMIZATION=n
CONFIG_ESP_WIFI_IRAM_OPT=n
CONFIG_ESP_WIFI_RX_IRAM_OPT=n
CONFIG_HOMEHUB_TUNNEL=n
TEMPLATE
    cat > "$PROJ/partitions_halocode.csv" <<'CSV'
# Makeblock HaloCode: 4 MB flash layout. Single factory app slot, no OTA —
# reflash over USB to update. Table lives at 0x10000 (sdkconfig.defaults).
nvs,      data, nvs,     0x11000, 0x6000,
phy_init, data, phy,     0x19000, 0x1000,
factory,  app,  factory, 0x20000, 0x3E0000,
CSV
    echo "==> 已生成 devices/sdkconfig.halocode (按键 GPIO=$btn)"
}
if [ "$BOARD" = halocode ]; then setup_halocode; fi

# ---- M5StickC Plus v1.x 社区移植: 应用 C 补丁 + 生成 overlay + 4MB 分区表 ----
setup_m5stickc_plus() {
    local patch="$SCRIPT_DIR/m5stickc-plus.patch"
    if [ ! -f "$patch" ]; then
        echo "错误: 找不到移植补丁 $patch" >&2
        echo "请确认 m5stickc-plus.patch 和本脚本在同一目录。" >&2
        exit 1
    fi
    if grep -q "HOMEHUB_LED_BACKEND_M5STICKC_PLUS_ST7789" "$PROJ/main/Kconfig.projbuild"; then
        echo "==> 移植补丁已应用, 跳过"
    else
        echo "==> 应用 M5StickC Plus v1.x 移植补丁..."
        git -C "$REPO_DIR" apply --check "$patch" || {
            echo "错误: 补丁无法应用 (上游源码可能已变化)" >&2
            echo "可以删掉 $REPO_DIR 后重跑 (脚本会钉住已验证的上游快照)。" >&2
            exit 1
        }
        git -C "$REPO_DIR" apply "$patch" && echo "==> 补丁已应用"
    fi
    cat > "$PROJ/devices/sdkconfig.m5stickc-plus" <<'TEMPLATE'
# M5StickC Plus (v1.x) — community port (experimental).
# Classic ESP32 (ESP32-PICO-D4), 4 MB flash, 1.14 inch 135x240 ST7789 display,
# AXP192 PMIC, CH522 USB-UART bridge. Load last, after sdkconfig.defaults.
#
# Display pins and AXP192 backlight follow M5GFX's Panel_M5StickCPlus /
# Light_M5StickC and M5Unified; see m5stickc-plus.patch for the
# HOMEHUB_LED_BACKEND_M5STICKC_PLUS_ST7789 backend in main/led_status.c.
CONFIG_IDF_TARGET="esp32"
CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ_240=y

# Status screen: 1.14 inch ST7789, edge status bars + animation (no full UI).
CONFIG_HOMEHUB_LED_BACKEND_M5STICKC_PLUS_ST7789=y
# Advertise as <prefix>-Disp-XXXXXX to tell this board apart from real devices.
CONFIG_HOMEHUB_BLE_NAME_SUFFIX="-Disp"
# Button A, active low.
CONFIG_HOMEHUB_BUTTON_GPIO=37

# Signed apps on classic ESP32 need chip revision 3.0+.
CONFIG_ESP32_REV_MIN_3=y

# 4 MB flash, DIO mode; custom partition table (single app slot, no OTA).
CONFIG_ESPTOOLPY_FLASHMODE_DIO=y
CONFIG_ESPTOOLPY_FLASHFREQ_80M=y
CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y
CONFIG_ESPTOOLPY_FLASHSIZE="4MB"
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions_m5stickc_plus.csv"

# No PSRAM on the PICO-D4. Same no-PSRAM block as ideaspark.
# (No home-network tunnel; control session only.)
CONFIG_SPIRAM=n
CONFIG_MBEDTLS_INTERNAL_MEM_ALLOC=y
CONFIG_MBEDTLS_EXTERNAL_MEM_ALLOC=n
CONFIG_MBEDTLS_SSL_OUT_CONTENT_LEN=4096
CONFIG_BTDM_CTRL_MODE_BLE_ONLY=y
CONFIG_BTDM_CTRL_MODE_BR_EDR_ONLY=n
CONFIG_BTDM_CTRL_MODE_BTDM=n
CONFIG_ESP_WIFI_STATIC_RX_BUFFER_NUM=8
CONFIG_ESP_WIFI_RX_BA_WIN=16
CONFIG_ESP_WIFI_TX_BA_WIN=16
CONFIG_ESP_WIFI_DYNAMIC_TX_BUFFER_NUM=16
CONFIG_LWIP_IRAM_OPTIMIZATION=n
CONFIG_LWIP_EXTRA_IRAM_OPTIMIZATION=n
CONFIG_ESP_WIFI_IRAM_OPT=n
CONFIG_ESP_WIFI_RX_IRAM_OPT=n
CONFIG_HOMEHUB_TUNNEL=n
TEMPLATE
    cat > "$PROJ/partitions_m5stickc_plus.csv" <<'CSV'
# M5StickC Plus (v1.x): 4 MB flash layout. Single factory app slot, no OTA —
# reflash over USB to update. Table lives at 0x10000 (sdkconfig.defaults).
nvs,      data, nvs,     0x11000, 0x6000,
phy_init, data, phy,     0x19000, 0x1000,
factory,  app,  factory, 0x20000, 0x3E0000,
CSV
    echo "==> 已生成 devices/sdkconfig.m5stickc-plus + partitions_m5stickc_plus.csv"
}
if [ "$BOARD" = m5stickc-plus ]; then setup_m5stickc_plus; fi

# ---- 4. SDK token (绝不打印完整值) ----
if [ -z "${MUSE_SDK_TOKEN:-}" ]; then
    echo "==> 需要 Muse Gadgets SDK token"
    echo "    去 gadgets.muse.ai > Account > SDK tokens 领取 (以 mgst_ 开头)"
    echo "    先看一眼 Gadget SDK Terms: https://gadgets.muse.ai/sdk-terms"
    read -rsp "    粘贴 token (输入不回显): " MUSE_SDK_TOKEN; echo
fi
[ -n "${MUSE_SDK_TOKEN:-}" ] || { echo "token 不能为空" >&2; exit 1; }
case "$MUSE_SDK_TOKEN" in
    mgst_*) ;;
    *) echo "警告: token 不是 mgst_ 开头, 可能领错了地方。仍要继续吗? [y/N]" >&2
       read -r yn; [ "$yn" = "y" ] || exit 1 ;;
esac
TOKEN_HEAD="${MUSE_SDK_TOKEN:0:8}"
TOKEN_TAIL="$(printf '%s' "$MUSE_SDK_TOKEN" | tail -c 4)"
echo "==> token 已就绪: ${TOKEN_HEAD}…${TOKEN_TAIL} (只显示头尾)"

# token 烘焙: 写成一份临时的 Kconfig defaults 覆盖层, 随构建结束自动删除
TOKEN_DEFAULTS="$(mktemp -t muse-gadget-token.XXXXXX)"
trap 'rm -f "$TOKEN_DEFAULTS"' EXIT
ESCAPED_TOKEN="$(printf '%s' "$MUSE_SDK_TOKEN" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf 'CONFIG_GADGET_SDK_TOKEN="%s"\n' "$ESCAPED_TOKEN" > "$TOKEN_DEFAULTS"
chmod 600 "$TOKEN_DEFAULTS"
# 立刻忘掉明文变量, 后续只用文件
MUSE_SDK_TOKEN=""

DEFAULTS="sdkconfig.defaults"
[ -n "$OVERLAYS" ] && DEFAULTS="$DEFAULTS;$OVERLAYS"
DEFAULTS="$DEFAULTS;$TOKEN_DEFAULTS"

idf_build() { # $1... = idf.py action
    ( cd "$PROJ" && idf.py -B "$BUILD_DIR" \
        -DIDF_TARGET="$TARGET" \
        -DSDKCONFIG="$BUILD_DIR/sdkconfig" \
        -DSDKCONFIG_DEFAULTS="$DEFAULTS" "$@" )
}

# ---- 5. 编译 ----
if [ "$FLASH_ONLY" = 0 ]; then
    echo "==> 开始编译 ($BOARD), 首次编译约 5-15 分钟..."
    idf_build build
    BIN="$BUILD_DIR/muse-gadget.bin"
    [ -f "$BIN" ] || { echo "编译产物未生成: $BIN" >&2; exit 1; }
    echo "==> 编译成功: $BIN ($(du -h "$BIN" | cut -f1))"
fi

# ---- 6. 刷机 ----
if [ "$BUILD_ONLY" = 0 ]; then
    if [ -z "$PORT" ]; then
        # shellcheck disable=SC2086,SC2207
        FOUND=($(ls $PORTS 2>/dev/null || true))
        if [ "${#FOUND[@]}" -ne 1 ]; then
            echo "找到 ${#FOUND[@]} 个候选串口: ${FOUND[*]:-无}" >&2
            echo "请插上开发板(只插一块), 或用 --port 指定, 例如:" >&2
            [ "$OS" = "Darwin" ] && echo "  ls /dev/cu.usb*" >&2 || echo "  ls /dev/ttyACM* /dev/ttyUSB*" >&2
            exit 1
        fi
        PORT="${FOUND[0]}"
    fi
    [ -e "$PORT" ] || { echo "串口不存在: $PORT" >&2; exit 1; }
    echo "==> 刷机到 $PORT ..."
    echo "    (若连不上: 按住 BOOT, 点一下 RESET, 松开 BOOT 后重试)"
    idf_build -p "$PORT" flash
    echo "==> 刷机完成。重刷会保留配对和 Wi-Fi; 想彻底重来可用:"
    echo "    idf.py -B $BUILD_DIR -p $PORT erase-flash"
    if [ "$DO_MONITOR" = 1 ]; then
        echo "==> 查看串口日志 (Ctrl-] 退出)..."
        idf_build -p "$PORT" monitor
    fi
fi

cat <<'EOF'

================ 配对 =================
1. 刷完后状态灯应为橙色呼吸 = 等待配对。
2. 手机打开 Muse App: 设置 > 设备 > 打开开发者模式,
   再点右上角 + 添加设备, 找到 MuseGadget-XXXXXX。
3. 灯变蓝色呼吸时, 按一下板子上的 BOOT 键确认是本人操作。
4. 灯变绿 = 已连接, 可以开始用了。

灯语: 橙呼吸=待配对 / 蓝呼吸=按按键确认 / 蓝=连网中 /
      绿=已连接 / 黄闪=重连中 / 紫=未配对 / 红闪=出错看日志
按住按键 5 秒 = 解除配对、清除 Wi-Fi, 重新来过。

安全提示: token 已烘进固件。若板子丢失或 token 泄露,
去 gadgets.muse.ai 吊销旧 token、领新的, 重新跑一遍本脚本即可。
========================================
EOF
echo "完成。"
