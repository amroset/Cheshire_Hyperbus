#include "../bench/bench.h"
#define BUF_BYTES   (256u *256u * 16u) // 1 MiB with 16u

#define STACK_SIZE (2 * 1024 * 1024)  // 2 MiB stack (enough for 1 MiB buffer)


static void uart_puts(const char *s){
  uart_write_str(&__base_uart, s, __builtin_strlen(s));
  uart_write_flush(&__base_uart);
}

static inline void full_fence(void){ __asm__ volatile("fence rw,rw" ::: "memory"); }

int main(void)
{   
    uint32_t rtc = *reg32(&__base_regs, CHESHIRE_RTC_FREQ_REG_OFFSET);
    uint64_t core = clint_get_core_freq(rtc, 2500);
    uart_init(&__base_uart, core, __BOOT_BAUDRATE);

    uart_puts("Running all benchmarks\r\n");

    int n_el = (BUF_BYTES / sizeof(elem_t)) / 2;

    //full_fence();

    //bench_copy(n_el);    
    //full_fence();
    //bench_copy_llc(n_el);
    //full_fence();

    //bench_sequential(n_el);
    //full_fence();
    //bench_sequential_llc(n_el);
    //full_fence();

    bench_random(n_el);
    //full_fence();
    //bench_random_llc(n_el);
    //full_fence();
     
    //bench_sequential_stride(n_el);
    //full_fence();
    //bench_sequential_stride_llc(n_el);
    //full_fence();
    
    //I put it last because this deacitvates L1 cache for now
    //bench_random_window(n_el);
    //full_fence();
    //bench_random_window_llc(n_el);
    //full_fence();


    uart_puts("All benchmarks done\r\n");
    return 0;
}
