#include "util.h"

typedef uint64_t elem_t;

// Each benchmark exposes ONE function
void bench_random(int n_el);
void bench_copy(int n_el);
void bench_sequential(int n_el);
void bench_random_window(int n_el);
void bench_sequential_stride(int n_el);

void bench_random_llc(int n_el);
void bench_copy_llc(int n_el);
void bench_sequential_llc(int n_el);
void bench_random_window_llc(int n_el);
void bench_sequential_stride_llc(int n_el);