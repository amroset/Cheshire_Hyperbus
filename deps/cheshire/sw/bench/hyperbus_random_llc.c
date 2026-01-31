#include "regs/cheshire.h"
#include "dif/clint.h"
#include "dif/uart.h"
#include "util.h"
#include "perf_counters.h"
#include "axi_llc_regs.h"

#define HYP_DRAM_BASE 0x80000000ULL

#define CLK_MHZ     100            // e.g. 100 MHz if ClkPeriodSys=10ns

#define BUF_BYTES   (256u *256u * 16u) // 1 MiB with 16u

#define CSR_DCACHE 0x7C1u

extern char __bss_end;   // provided by linker script
#define ALIGN_UP(x,a)   (((x) + ((a)-1)) & ~((a)-1))

static inline volatile uint64_t *bench_buf_ptr(void) {
    uintptr_t start = ALIGN_UP((uintptr_t)&__bss_end, 64);   // after program image
    return (volatile uint64_t *)start;
}



// Use 64-bit elements (tune to your datapath)
typedef uint64_t elem_t;

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

// -------------------- Fast PRNG (xorshift64*) --------------------
static inline uint64_t xorshift64star(uint64_t *s)
{
    uint64_t x = *s;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    *s = x;
    return x * 0x2545F4914F6CDD1DULL;
}

static inline size_t random_full_offset(uint64_t *seed)
{
    const size_t elem_mask = (BUF_BYTES / sizeof(elem_t)) - 1; // power-of-two assumption
    uint64_t r = xorshift64star(seed);
    size_t e = (size_t)(r & elem_mask);
    return e * sizeof(elem_t);
}


// ======= Bandwidth kernels =======
static uint64_t read(const volatile elem_t *src, uint64_t *seed, int n_el) {
  volatile elem_t acc = 0;
  full_fence(); uint64_t t0 = rdcycle();
  for (size_t i = 0; i < n_el; i++) {
        size_t off = random_full_offset(seed);
        sink64 += src[off / sizeof(elem_t)];
    }
  full_fence(); uint64_t t1 = rdcycle();
  return t1 - t0;                 
}

static uint64_t write(volatile elem_t *dst, uint64_t *seed, int n_el, elem_t v) {
  full_fence(); uint64_t t0 = rdcycle();
  for (size_t i = 0; i < n_el; i++) {
        size_t off = random_full_offset(seed);
        dst[off / sizeof(elem_t)] = v;
  }
  full_fence(); uint64_t t1 = rdcycle();
  return t1 - t0;
}


void bench_random_llc(int n_el) {
  // UART early
  uint32_t rtc = *reg32(&__base_regs, CHESHIRE_RTC_FREQ_REG_OFFSET);
  uint64_t core = clint_get_core_freq(rtc, 2500);
  uart_init(&__base_uart, core, __BOOT_BAUDRATE);
  uart_puts("Boot, RANDOM\r\n");

  uint64_t seed_write = 0x1234abcd5678ULL;   // deterministic; vary to reshuffle
  uint64_t seed_read = 0x8765dcba4321ULL;

  //Software enable LLC
  *reg32(&__base_llc, AXI_LLC_CFG_SPM_LOW_REG_OFFSET) = 0x0;
  *reg32(&__base_llc, AXI_LLC_CFG_SPM_HIGH_REG_OFFSET) = 0x0;

  set_reg_32(0x1, &__base_llc, AXI_LLC_COMMIT_CFG_REG_OFFSET);

  //Software disable L1 data cache
  //csr_write_u64(CSR_DCACHE, 0x0);

  volatile uint64_t *buffer = bench_buf_ptr();

  //WRITE

  double bw_write_core_0 = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_W_BW);
  double bw_write_llc_0 = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_W_BW);
  double bw_write_dram_0 = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_W_BW);

  double done_write_core_0 = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_W_DONE_CNT);
  double done_write_llc_0 = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_W_DONE_CNT);
  double done_write_dram_0 = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_W_DONE_CNT);

  uint64_t cycles_w = write(buffer, &seed_write, n_el, 22);

  double bw_write_core = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_W_BW) - bw_write_core_0;
  double bw_write_llc = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_W_BW) - bw_write_llc_0;
  double bw_write_dram = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_W_BW) - bw_write_dram_0;

  double done_write_core = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_W_DONE_CNT) - done_write_core_0;
  double done_write_llc = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_W_DONE_CNT) - done_write_llc_0;
  double done_write_dram = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_W_DONE_CNT) - done_write_dram_0;

  //READ
  
  double bw_read_core_0 = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_R_BW);
  double bw_read_llc_0 = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_R_BW);
  double bw_read_dram_0 = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_R_BW);

  double done_read_core_0 = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_R_DONE_CNT);
  double done_read_llc_0 = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_R_DONE_CNT);
  double done_read_dram_0 = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_R_DONE_CNT);

  uint64_t cycles_r = read(buffer + n_el, &seed_read, n_el);

  double bw_read_core = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_R_BW) - bw_read_core_0;
  double bw_read_llc = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_R_BW) - bw_read_llc_0;
  double bw_read_dram = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_R_BW) - bw_read_dram_0;

  double done_read_core = perf_read(PERF_COUNTER_CORE_BASE, PERF_OFF_R_DONE_CNT) - done_read_core_0;
  double done_read_llc = perf_read(PERF_COUNTER_LLC_BASE, PERF_OFF_R_DONE_CNT) - done_read_llc_0;
  double done_read_dram = perf_read(PERF_COUNTER_DRAM_BASE, PERF_OFF_R_DONE_CNT) - done_read_dram_0;
  

  //perf_dump(PERF_COUNTER_CORE_BASE, "CORE");

  uart_puts("LLC ON\n");

  uart_puts("READ_CORE: "); uart_put_double(bw_read_core  / cycles_r); uart_puts("B/cycle"); uart_puts("\r\n");
  uart_put_double(done_read_core); uart_puts("transactions"); uart_puts("\r\n");

  uart_puts("WRITE_CORE: "); uart_put_double(bw_write_core / cycles_w); uart_puts("B/cycle"); uart_puts("\r\n");
  uart_put_double(done_write_core); uart_puts("transactions"); uart_puts("\r\n");

  uart_puts("READ_LLC: "); uart_put_double(bw_read_llc / cycles_r); uart_puts("B/cycle"); uart_puts("\r\n");
  uart_put_double(done_read_llc); uart_puts("transactions"); uart_puts("\r\n");

  uart_puts("WRITE_LLC: "); uart_put_double(bw_write_llc / cycles_w); uart_puts("B/cycle"); uart_puts("\r\n");
  uart_put_double(done_write_llc); uart_puts("transactions"); uart_puts("\r\n");

  uart_puts("READ_DRAM: "); uart_put_double(bw_read_dram / cycles_r); uart_puts("B/cycle"); uart_puts("\r\n");
  uart_put_double(done_read_dram); uart_puts("transactions"); uart_puts("\r\n");
  
  uart_puts("WRITE_DRAM: "); uart_put_double(bw_write_dram / cycles_w); uart_puts("B/cycle"); uart_puts("\r\n");
  uart_put_double(done_write_dram); uart_puts("transactions"); uart_puts("\r\n");

  uart_puts("Time to read: "); uart_putu64_dec(cycles_r * 10); uart_puts("ns"); uart_puts("\r\n");
  uart_puts("Time to write: "); uart_putu64_dec(cycles_w * 10); uart_puts("ns"); uart_puts("\r\n");
  uart_puts("Total time: "); uart_putu64_dec((cycles_w  + cycles_r) * 10); uart_puts("ns"); uart_puts("\r\n");

  uart_puts("Done\r\n");



  // Quick MMIO sanity (SCRATCH reg)
 /**reg32(&__base_regs, CHESHIRE_SCRATCH_0_REG_OFFSET) = 0x12345678;
  uart_puts("MMIO OK\r\n");*/


  // ---- Single DRAM probe (this is the key) ----
  /*volatile uint32_t *dram32 = (volatile uint32_t *)HYP_DRAM_BASE;

  uart_puts("Store @ "); uart_puthex32((uint32_t)HYP_DRAM_BASE); uart_puts("...\r\n");
  *dram32 = 0xA5A5A5A5;                 // if there is NO responder, core may stall here
  fence_rw_rw();

  uart_puts("Load  @ "); uart_puthex32((uint32_t)HYP_DRAM_BASE); uart_puts("...\r\n");
  uint32_t val = *dram32;               // if access-fault, trap prints mcause/mtval
  fence_rw_rw();

  uart_puts("DRAM OK val="); uart_puthex32(val); uart_puts("\r\n");
  uart_puts("Done\r\n");
  return 0;*/



}

