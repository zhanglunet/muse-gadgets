#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "driver/i2c_master.h"

#define IS31_ADDR 0x74
#define I2C_SDA_GPIO 19
#define I2C_SCL_GPIO 18

static i2c_master_dev_handle_t is31_dev = NULL;

static esp_err_t is31_write_reg(uint8_t reg, uint8_t val)
{
    uint8_t buf[2] = { reg, val };
    return i2c_master_transmit(is31_dev, buf, 2, 50);
}

static void is31_set_all_leds(uint8_t r, uint8_t g, uint8_t b)
{
    if (!is31_dev) return;
    // Select function page
    is31_write_reg(0xFD, 0x0B);
    is31_write_reg(0x0A, 0x01); // normal operation
    is31_write_reg(0x00, 0x00);
    is31_write_reg(0x01, 0x00);

    // Select Frame 0
    is31_write_reg(0xFD, 0x00);
    for (uint8_t reg = 0x00; reg <= 0x11; reg++) {
        is31_write_reg(reg, 0xFF);
    }

    const uint8_t r_regs[] = { 0x29, 0x28, 0x27, 0x26, 0x25, 0x24, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11 };
    const uint8_t g_regs[] = { 0x35, 0x34, 0x33, 0x32, 0x31, 0x30, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d };
    const uint8_t b_regs[] = { 0x41, 0x40, 0x3F, 0x3E, 0x3D, 0x3C, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05 };

    for (int i = 0; i < 12; i++) {
        is31_write_reg(r_regs[i], r);
        is31_write_reg(g_regs[i], g);
        is31_write_reg(b_regs[i], b);
    }
}

static void init_is31fl(void)
{
    i2c_master_bus_config_t bus_cfg = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = I2C_SDA_GPIO,
        .scl_io_num = I2C_SCL_GPIO,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    i2c_master_bus_handle_t bus_handle;
    if (i2c_new_master_bus(&bus_cfg, &bus_handle) != ESP_OK) return;

    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = IS31_ADDR,
        .scl_speed_hz = 400000,
    };
    if (i2c_master_bus_add_device(bus_handle, &dev_cfg, &is31_dev) == ESP_OK) {
        printf("[+] IS31FL 驱动就绪! 点亮蓝色状态灯!\n");
        is31_set_all_leds(0, 0, 100); // 蓝色
    }
}

static const int candidate_gpios[] = {
    0, 2, 4, 5, 12, 13, 14, 15, 16, 17, 21, 22, 23, 25, 26, 27, 32, 33,
    34, 35, 36, 37, 38, 39
};
#define N_PINS (sizeof(candidate_gpios) / sizeof(candidate_gpios[0]))

void app_main(void)
{
    printf("\n\n================================================\n");
    printf(" HaloCode 按键即时捕获程序 (SDA=19, SCL=18)\n");
    printf("================================================\n\n");

    init_is31fl();

    for (size_t i = 0; i < N_PINS; i++) {
        int g = candidate_gpios[i];
        if (g == I2C_SDA_GPIO || g == I2C_SCL_GPIO) continue;
        gpio_reset_pin(g);
        gpio_set_direction(g, GPIO_MODE_INPUT);
        if (g < 34) {
            gpio_set_pull_mode(g, GPIO_PULLUP_ONLY);
        }
    }

    vTaskDelay(pdMS_TO_TICKS(50));
    int base[40];
    for (size_t i = 0; i < N_PINS; i++) {
        int g = candidate_gpios[i];
        base[g] = gpio_get_level(g);
    }

    printf("[READY] 监听已就绪! 请按下中间按键:\n");

    int count = 0;
    while (1) {
        count++;
        bool any_change = false;
        for (size_t i = 0; i < N_PINS; i++) {
            int g = candidate_gpios[i];
            if (g == I2C_SDA_GPIO || g == I2C_SCL_GPIO) continue;
            int lvl = gpio_get_level(g);
            if (lvl != base[g]) {
                printf("\n[★★★ 按键变化! GPIO %d: %d -> %d ★★★]\n", g, base[g], lvl);
                base[g] = lvl; // update baseline
                any_change = true;
            }
        }
        if (any_change) {
            is31_set_all_leds(0, 150, 0); // 变绿
        }

        if (count % 4 == 0) {
            printf("[%ds] ", count / 4);
            for (size_t i = 0; i < N_PINS; i++) {
                int g = candidate_gpios[i];
                if (g == I2C_SDA_GPIO || g == I2C_SCL_GPIO) continue;
                printf("%d=%d ", g, gpio_get_level(g));
            }
            printf("\n");
        }
        vTaskDelay(pdMS_TO_TICKS(250));
    }
}

