// llc_min_bench.c — minimal LLC baseline (CSV over UART)
// Plots: (1) cold vs hot cycles/line   (2) copy throughput (bytes/cycle)

#include "regs/cheshire.h"
#include "dif/clint.h"
#include "dif/uart.h"
#include "util.h"
#include <stdint.h>
#include <stddef.h>

// ======= Tunables (keep minimal) =======
#ifndef TARGET_BASE
#define TARGET_BASE 0x10000000UL   // Cached SPM alias. Use 0x80000000UL for DRAM later.
#endif
#ifndef STRIDE
#define STRIDE 64                 // 1 touch per cache line
#endif
#ifndef MIN_SIZE
#define MIN_SIZE 1024      // 1 KiB
#endif
// MAX_SIZE will be clamped to LLC size automatically.

// ======= Tiny timing & UART =======
static inline void mb(void){ __asm__ volatile("fence rw,rw" ::: "memory"); }
static inline uint64_t rdcycle(void){ uint64_t v; __asm__ volatile("rdcycle %0":"=r"(v)); return v; }

static void uart_puts(const char* s){ uart_write_str(&__base_uart, s, __builtin_strlen(s)); }
static void uart_putc(char c){ uart_write_str(&__base_uart, &c, 1); }
static void uart_putu64_dec(uint64_t v){
  char b[21]; int i=20; b[i--]='\0'; if(!v){ uart_write_str(&__base_uart,"0",1); return; }
  while(v && i>=0){ b[i--]='0'+(v%10); v/=10; }
  uart_write_str(&__base_uart,&b[i+1],20-(i+1));
}

// ======= Kernels (minimal) =======

// Cold sweep: one read per line across [base, base+size)
static uint64_t read_cold_cycles(volatile uint8_t* base, uint32_t size){
  mb(); uint64_t t0=rdcycle();
  for(uint32_t i=0;i<size;i+=STRIDE){ volatile uint8_t x = base[i]; (void)x; }
  mb(); return rdcycle()-t0;
}

// Hot sweep: two touches per line back-to-back → forces a genuine hit for the 2nd access
// (This measures hit latency even if total size > L1; second touch will be L1-hit.)
static uint64_t read_two_touches_cycles(volatile uint8_t* base, uint32_t size){
  mb(); uint64_t t0=rdcycle();
  for(uint32_t i=0;i<size;i+=STRIDE){
    volatile uint8_t x = base[i]; (void)x;   // cold
    x = base[i]; (void)x;                    // hot
  }
  mb(); return rdcycle()-t0;
}

// Streaming copy within the same window (non-overlapping halves), 64-bit
static uint64_t copy_cycles(uintptr_t base_addr, uint32_t size){
  // copy size/2 bytes: dst=[base], src=[base+size/2]
  uintptr_t dstA = (base_addr + 63u) & ~63u;
  uintptr_t srcA = ((base_addr + size/2) + 63u) & ~63u;
  volatile uint64_t* dst = (volatile uint64_t*)dstA;
  volatile uint64_t* src = (volatile uint64_t*)srcA;
  uint32_t n64 = (size/2)/8;

  mb(); uint64_t t0=rdcycle();
  for(uint32_t i=0;i<n64;i++) dst[i] = src[i];
  mb(); return rdcycle()-t0;
}

int main(void){
  // UART init
  uint32_t rtc = *reg32(&__base_regs, CHESHIRE_RTC_FREQ_REG_OFFSET);
  uint64_t core = clint_get_core_freq(rtc, 2500);
  uart_init(&__base_uart, core, __BOOT_BAUDRATE);

  // Header
  //uart_puts("sizeB,read_cold_cyc_per_line,read_hot_cyc_per_line,copy_Bpc_x1e6\n");
  uart_puts("sizeB,read_cold_cyc_per_line,read_hot_cyc_per_line\n");

  // Clamp sizes to LLC size so we characterize LLC (not DRAM)
  uint32_t llc_sz = *reg32(&__base_regs, CHESHIRE_LLC_SIZE_REG_OFFSET);
  if (llc_sz < MIN_SIZE) llc_sz = MIN_SIZE;

  //uart_puts("llc_size: ");          uart_putu64_dec(llc_sz); uart_putc('\n');

  volatile uint8_t* base = (volatile uint8_t*)TARGET_BASE;

  // Prefill a bit to avoid X-prop warnings in sim (write 0s over LLC span)
  for (uint32_t i=0;i<(llc_sz/4 & ~7u); i+=8)
    *(volatile uint64_t*)((uintptr_t)base + i) = 0ULL;

  for (uint32_t sz = MIN_SIZE; sz && sz <= llc_sz/4; sz <<= 1){
    // 1) Cold read (miss latency per line)
    uint64_t cyc_cold = read_cold_cycles(base, sz);

    // 2) Two-touch pass (hot hits per line)
    uint64_t cyc_two  = read_two_touches_cycles(base, sz);

    // Derive per-line numbers
    uint64_t lines = sz / STRIDE;
    uint64_t cold_cyc_per_line = lines ? (cyc_cold / lines) : 0;
    // two touches = cold + hot → hot = (two - cold)
    uint64_t hot_cyc_per_line  = lines ? ((cyc_two - cyc_cold) / lines) : 0;

    // 3) Copy throughput inside LLC window (bytes/cycle, scaled *1e6 for easy UART)
    /*uint64_t cyc_copy = copy_cycles((uintptr_t)base, sz);
    uint64_t bytes = sz/2; // we copied half
    uint64_t copy_bpc_x1e6 = cyc_copy ? (bytes * 1000000ULL) / cyc_copy : 0;*/

    // CSV line (decimal for convenience)
    uart_putu64_dec(sz);                 uart_putc(',');
    uart_putu64_dec(cold_cyc_per_line);  uart_putc(',');
    uart_putu64_dec(hot_cyc_per_line);   uart_putc(',');
    //uart_putu64_dec(copy_bpc_x1e6);      uart_putc('\n');
  }

  uart_write_flush(&__base_uart);
  return 0;
}
