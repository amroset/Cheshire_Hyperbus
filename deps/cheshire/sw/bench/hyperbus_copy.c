#include "bench.h"
#include "regs/cheshire.h"
#include "dif/clint.h"
#include "dif/uart.h"
#include "util.h"
#include "perf_counters.h"
#include "axi_llc_regs.h"

#define HYP_DRAM_BASE 0x80000000ULL

#define CLK_MHZ     100            // e.g. 100 MHz if ClkPeriodSys=10ns

#define BUF_BYTES   (256u *256u * 16u) // 1 MiB

#define CSR_DCACHE 0x7C1u

extern char __bss_end;   // provided by linker script
#define ALIGN_UP(x,a)   (((x) + ((a)-1)) & ~((a)-1))

static inline volatile uint64_t *bench_buf_ptr(void) {
    uintptr_t start = ALIGN_UP((uintptr_t)&__bss_end, 64);   // after program image
    return (volatile uint64_t *)start;
}



// Use 64-bit elements (tune to your datapath)

static volatile uint32_t sink32;
static volatile uint64_t sink64;


// --- timing helpers ---
static inline uint64_t rdcycle(void){ uint64_t v; __asm__ volatile("rdcycle %0":"=r"(v)); return v; }
static inline void full_fence(void){ __asm__ volatile("fence rw,rw" ::: "memory"); }

// 32-bit write to IO memory region
static inline void iowrite32(unsigned int value, volatile unsigned int *addr)
{
    *addr = value;
}

static inline void set_reg_32(unsigned int value, void *base, unsigned int off)
{
    iowrite32(value, (volatile unsigned int *) (base + off));
}

// ----- Low-level CSR helpers (Zicsr required) -----
static inline uint64_t csr_read_u64(unsigned csr)
{
  uint64_t v;
  asm volatile ("csrr %0, %1" : "=r"(v) : "i"(csr));
  return v;
}
static inline void csr_write_u64(unsigned csr, uint64_t v)
{
  asm volatile ("csrw %0, %1" :: "i"(csr), "r"(v));
}

// ======= Bandwidth kernels =======
static uint64_t read(const volatile elem_t *src, int n_el, int stride) {
  volatile elem_t acc = 0;
  full_fence(); uint64_t t0 = rdcycle();
  for (int i = 0; i < n_el; i+= stride) acc += src[i];
  full_fence(); uint64_t t1 = rdcycle();
  //sink64 += acc; 
  return t1 - t0;                 
}

static uint64_t write(volatile elem_t *dst, int n_el, elem_t v, int stride) {
  full_fence(); uint64_t t0 = rdcycle();
  for (int i = 0; i < n_el; i+= stride) dst[i] = v;
  full_fence(); uint64_t t1 = rdcycle();
  return t1 - t0;
}

static uint64_t copy(volatile elem_t *dst, const volatile elem_t *src, int n_el) {
  full_fence(); uint64_t t0 = rdcycle();
  for (int i = 0; i < n_el; i++) dst[i] = src[i];
  full_fence(); uint64_t t1 = rdcycle();
  return t1 - t0;
}

// Convenience wrappers for readability ---------------------------------

void bench_copy(int n_el) {
  // UART early

  uart_puts("Boot COPY\r\n");

  volatile uint64_t *buffer = bench_buf_ptr();

  //Software disable LLC
  *reg32(&__base_llc, AXI_LLC_CFG_SPM_LOW_REG_OFFSET) = 0xFFFFFFFF;
  *reg32(&__base_llc, AXI_LLC_CFG_SPM_HIGH_REG_OFFSET) = 0xFFFFFFFF;

  set_reg_32(0x1, &__base_llc, AXI_LLC_COMMIT_CFG_REG_OFFSET);

  //Software disable L1 data cache
  //csr_write_u64(CSR_DCACHE, 0x0);
  // Use the first half as src, second half as dst (avoid overlap effects)

  double bw_write_core_0 = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_W_BW);
  double bw_write_llc_0 = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_W_BW);
  double bw_write_dram_0 = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_W_BW);
  
  double bw_read_core_0 = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_R_BW);
  double bw_read_llc_0 = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_R_BW);
  double bw_read_dram_0 = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_R_BW);

  uint64_t cycles_copy = copy(buffer, buffer + n_el, n_el);

  double bw_write_core = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_W_BW) - bw_write_core_0;
  double bw_write_llc = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_W_BW) - bw_write_llc_0;
  double bw_write_dram = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_W_BW) - bw_write_dram_0;
  
  double bw_read_core = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_R_BW) - bw_read_core_0;
  double bw_read_llc = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_R_BW) - bw_read_llc_0;
  double bw_read_dram = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_R_BW) - bw_read_dram_0;


  //perf_dump(PERF_COUNTER_CORE_BASE, "CORE");

  uart_puts("LLC OFF\n");

  /*uart_puts("COPY_CORE: "); uart_put_double((bw_read_core + bw_write_core) / (cycles_copy)); uart_puts("B/cycle"); uart_puts("\r\n");
  uart_puts("COPY_LLC: "); uart_put_double((bw_read_llc + bw_write_llc) / (cycles_copy)); uart_puts("B/cycle"); uart_puts("\r\n");
  uart_puts("COPY_DRAM: "); uart_put_double((bw_read_dram + bw_write_dram) / (cycles_copy)); uart_puts("B/cycle"); uart_puts("\r\n");*/

  uart_puts("CORE  R/W: ");  uart_put_double(bw_read_core/cycles_copy); uart_puts("///"); uart_put_double(bw_write_core/cycles_copy); uart_puts("\n");
  uart_puts("LLC   R/W: ");  uart_put_double(bw_read_llc/cycles_copy); uart_puts("///");  uart_put_double(bw_write_llc/cycles_copy); uart_puts("\n");
  uart_puts("DRAM  R/W: ");  uart_put_double(bw_read_dram/cycles_copy); uart_puts("///");  uart_put_double(bw_write_dram/cycles_copy); uart_puts("\n");

  uart_puts("Time to copy: "); uart_putu64_dec(cycles_copy * 10); uart_puts("ns"); uart_puts("\r\n");




  //uart_puts("COPY: "); uart_putu64_dec(c_bc); uart_puts("B/cycle"); uart_puts("\r\n");

  uart_puts("Done\r\n");


}

