#pragma once
#include <stdint.h>
#include <stddef.h>
#include "dif/uart.h"   // for uart_write_str / uart_puts / uart_putu32_dec

// ======================================================
// BASE ADDRESSES FOR PERF COUNTERS
// ======================================================
#define PERF_COUNTER_DRAM_BASE   0x03009000u
#define PERF_COUNTER_LLC_BASE    0x0300A000u
#define PERF_COUNTER_CORE_BASE   0x0300B000u

// ======================================================
// OFFSETS (each +4 bytes from the previous)
// ======================================================
#define PERF_OFF_AW_VALID_CNT         0x00u
#define PERF_OFF_AW_READY_CNT         0x04u
#define PERF_OFF_AW_DONE_CNT          0x08u
#define PERF_OFF_AW_BW                0x0Cu
#define PERF_OFF_AW_STALL_CNT         0x10u

#define PERF_OFF_AR_VALID_CNT         0x14u
#define PERF_OFF_AR_READY_CNT         0x18u
#define PERF_OFF_AR_DONE_CNT          0x1Cu
#define PERF_OFF_AR_BW                0x20u
#define PERF_OFF_AR_STALL_CNT         0x24u

#define PERF_OFF_R_VALID_CNT          0x28u
#define PERF_OFF_R_READY_CNT          0x2Cu
#define PERF_OFF_R_DONE_CNT           0x30u
#define PERF_OFF_R_BW                 0x34u
#define PERF_OFF_R_STALL_CNT          0x38u

#define PERF_OFF_W_VALID_CNT          0x3Cu
#define PERF_OFF_W_READY_CNT          0x40u
#define PERF_OFF_W_DONE_CNT           0x44u
#define PERF_OFF_W_BW                 0x48u
#define PERF_OFF_W_STALL_CNT          0x4Cu

#define PERF_OFF_B_VALID_CNT          0x50u
#define PERF_OFF_B_READY_CNT          0x54u
#define PERF_OFF_B_DONE_CNT           0x58u

#define PERF_OFF_BUF_W_STALL_CNT      0x5Cu
#define PERF_OFF_BUF_R_STALL_CNT      0x60u
#define PERF_OFF_NEXT_ID              0x64u
#define PERF_OFF_COMPLETED_ID         0x68u
#define PERF_OFF_BUSY_CNT             0x6Cu


// Reading from the registers
static inline uint64_t perf_read(uintptr_t base, uintptr_t off) {
    volatile uint32_t *addr_low = (volatile uint32_t *)(base + off);
    volatile uint32_t *addr_high = (volatile uint32_t *)(base + off + 4);
    return ((*addr_high) << 32) | (*addr_low);
}

// uART helpers

static inline void uart_putc(char c) {
    uart_write_str(&__base_uart, &c, 1);
}

static void uart_puts(const char *s){
  uart_write_str(&__base_uart, s, __builtin_strlen(s));
  uart_write_flush(&__base_uart);
}
static void uart_puthex32(uint32_t v){
  static const char hexd[16] = "0123456789ABCDEF";
  char b[11]; b[0]='0'; b[1]='x';
  for (int i=0;i<8;i++) b[2+i]=hexd[(v>>(28-4*i))&0xF];
  b[10]='\0'; uart_puts(b);
}
static void uart_putu64_dec(uint64_t v){
  char b[21]; int i=20; b[i--]='\0'; if(!v){ uart_write_str(&__base_uart,"0",1); return; }
  while(v && i>=0){ b[i--]='0'+(v%10); v/=10; }
  uart_write_str(&__base_uart,&b[i+1],20-(i+1));
}

static void uart_putu32_dec(uint32_t v){
  char b[11]; int i=10; b[i--]='\0'; 
  if(!v){ uart_write_str(&__base_uart,"0",1); return; }
  while(v && i>=0){ b[i--]='0'+(v%10); v/=10; }
  uart_write_str(&__base_uart,&b[i+1],10-(i+1));
}

static void uart_put_double(double value) {
    if (value < 0) {
        uart_putc('-');              // your UART single char function
        value = -value;
    }

    // Extract integer part
    uint64_t int_part = (uint64_t)value;

    // Extract fractional part (scaled)
    double frac = value - (double)int_part;
    uint32_t frac_part = (uint32_t)(frac * 1000.0 + 0.5);  // 3 decimal places, rounded

    // Print integer part
    uart_putu64_dec(int_part);      // assumes you already have this helper

    uart_putc('.');

    // Print fractional part with zero-padding (e.g., 0.045 → "045")
    uart_putc('0' + (frac_part / 100) % 10);
    uart_putc('0' + (frac_part / 10) % 10);
    uart_putc('0' + (frac_part / 1) % 10);

  }

// DUMP FUNCTION — prints all 28 counters in order

static inline void perf_dump(uintptr_t base, const char *label) {
    static const char *names[28] = {
        "aw_valid_cnt", "aw_ready_cnt", "aw_done_cnt", "aw_bw", "aw_stall_cnt",
        "ar_valid_cnt", "ar_ready_cnt", "ar_done_cnt", "ar_bw", "ar_stall_cnt",
        "r_valid_cnt",  "r_ready_cnt",  "r_done_cnt",  "r_bw",  "r_stall_cnt",
        "w_valid_cnt",  "w_ready_cnt",  "w_done_cnt",  "w_bw",  "w_stall_cnt",
        "b_valid_cnt",  "b_ready_cnt",  "b_done_cnt",
        //"buf_w_stall",  "buf_r_stall",  "next_id", "completed_id", "busy_cnt"
    };

    uart_puts("\r\n==== PERF COUNTERS [");
    uart_puts(label);
    uart_puts("] ====\r\n");

    for (int i = 0; i < 23; i++) {
        uint32_t val = perf_read(base, i * 4u);

        uart_puts(names[i]);
        uart_puts(": ");
        uart_putu64_dec(val);
        uart_puts("\r\n");
    }

    uart_puts("===========================\r\n");
}
