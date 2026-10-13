#!/usr/bin/env bash
# halocode-probe.sh — 编译并刷入 HaloCode 引脚探测固件
# 用法: ./halocode-probe.sh [--port /dev/cu.usbserial-110] [--idf-dir ~/esp/esp-idf-v6]
set -euo pipefail

PORT=""
IDF_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        -p|--port)   PORT="$2"; shift 2 ;;
        --idf-dir)   IDF_DIR="$2"; shift 2 ;;
        -h|--help)   echo "用法: $0 [--port 串口] [--idf-dir IDF目录]"; exit 0 ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$SCRIPT_DIR/halocode-probe"

for cmd in git python3 cmake ninja; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "缺少依赖: $cmd" >&2; exit 1; }
done

if [ -z "$IDF_DIR" ]; then
    for d in "${IDF_PATH:-}" "$HOME/esp/esp-idf-v6.0.1" "$HOME/esp/esp-idf-v6" "$HOME/esp/esp-idf"; do
        if [ -n "$d" ] && [ -f "$d/export.sh" ]; then IDF_DIR="$d"; break; fi
    done
fi
if [ -z "$IDF_DIR" ]; then
    IDF_DIR="$HOME/esp/esp-idf-v6"
    echo "==> 未找到 ESP-IDF, 正在克隆 v6.0.1 到 $IDF_DIR..."
    git clone --depth 1 --shallow-submodules -b v6.0.1 --recursive https://github.com/espressif/esp-idf.git "$IDF_DIR"
    echo "==> 安装工具链 (esp32, 只需一次)..."
    "$IDF_DIR/install.sh" esp32
fi
# shellcheck disable=SC1091
. "$IDF_DIR/export.sh" >/dev/null 2>&1
command -v idf.py >/dev/null 2>&1 || { echo "idf.py 不可用" >&2; exit 1; }

echo "==> 注意: 刷探测固件会覆盖 HaloCode 原厂 mBlock 固件 (之后可用 mBlock 刷回去)"
echo "==> 编译探测固件..."
(cd "$PROJ" && idf.py -DIDF_TARGET=esp32 build)

if [ -z "$PORT" ]; then
    # shellcheck disable=SC2086,SC2207
    FOUND=($(ls /dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART* /dev/cu.usbmodem* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true))
    if [ "${#FOUND[@]}" -ne 1 ]; then
        echo "找到 ${#FOUND[@]} 个候选串口: ${FOUND[*]:-无}; 请用 --port 指定" >&2
        exit 1
    fi
    PORT="${FOUND[0]}"
fi
echo "==> 刷入 $PORT ..."
(cd "$PROJ" && idf.py -p "$PORT" flash)
echo "==> 刷入完成, 查看串口输出 (Ctrl-] 退出):"
(cd "$PROJ" && idf.py -p "$PORT" monitor)
