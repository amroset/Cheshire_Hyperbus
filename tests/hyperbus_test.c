#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define HYP_DRAM_BASE 0x80000000UL   // your HyperBus-mapped DRAM base
#define BUFSZ (256 * 1024)

static inline uint64_t rdcycle(void){
  uint64_t v;
  __asm__ volatile ("rdcycle %0" : "=r"(v));
  return v;
}
static inline void fence_rw_rw(void){ __asm__ volatile("fence rw,rw" ::: "memory"); }

uint8_t *const dram = (uint8_t*)HYP_DRAM_BASE;
uint8_t buf_write[BUFSZ];
uint8_t buf_read[BUFSZ];

int main(void) {
  // fill buffer with a known pattern
  for (size_t i = 0; i < BUFSZ; i++) buf_write[i] = (uint8_t)(i & 0xFF);

  // Write to DRAM
  fence_rw_rw();
  uint64_t t0 = rdcycle();
  for (size_t i = 0; i < BUFSZ; i++) dram[i] = buf_write[i];
  fence_rw_rw();
  uint64_t t1 = rdcycle();
  printf("Write: %lu bytes in %lu cycles (%.3f B/cyc)\n",
         (unsigned long)BUFSZ, (unsigned long)(t1 - t0),
         (double)BUFSZ / (double)(t1 - t0));

  // Read back from DRAM into a separate buffer
  fence_rw_rw();
  t0 = rdcycle();
  for (size_t i = 0; i < BUFSZ; i++) buf_read[i] = dram[i];
  fence_rw_rw();
  t1 = rdcycle();
  printf("Read: %lu bytes in %lu cycles (%.3f B/cyc)\n",
         (unsigned long)BUFSZ, (unsigned long)(t1 - t0),
         (double)BUFSZ / (double)(t1 - t0));

  // Verify
  if (memcmp(buf_write, buf_read, BUFSZ) != 0) {
    // find first mismatch
    for (size_t i = 0; i < BUFSZ; i++) {
      if (buf_write[i] != buf_read[i]) {
        printf("FAIL: mismatch at 0x%08zx: wrote 0x%02x read 0x%02x\n",
               i, (unsigned)buf_write[i], (unsigned)buf_read[i]);
        break;
      }
    }
    return 1;
  }

  printf("PASS: DRAM read/write verification successful\n");
  return 0;
}
