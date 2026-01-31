import csv, sys, matplotlib.pyplot as plt

if len(sys.argv) < 3:
    print("Usage: python plot_llc_min.py run.csv <core_MHz>")
    sys.exit(1)

core_hz = float(sys.argv[2]) * 1e6
sizes=[]; cold=[]; hot=[]; copy_gbs=[]

with open(sys.argv[1]) as f:
    r = csv.reader(f)
    header = next(r)  # sizeB,read_cold...,read_hot...,copy_Bpc_x1e6
    for row in r:
        if not row: continue
        sz = int(row[0])
        cold_cyc = float(row[1])
        hot_cyc  = float(row[2])
        bpc = float(row[3]) / 1e6    # bytes per cycle
        sizes.append(sz)
        cold.append(cold_cyc)
        hot.append(hot_cyc)
        copy_gbs.append((bpc * core_hz) / 1e9)

plt.figure()
plt.semilogx(sizes, cold, marker='o', label='Cold (cycles/line)')
plt.semilogx(sizes, hot,  marker='x', label='Hot (cycles/line)')
plt.xlabel('Working set size (bytes, log2)')
plt.ylabel('Cycles per cache line')
plt.title('LLC latency: cold vs hot')
plt.grid(True, which='both', ls=':')
plt.legend()

plt.figure()
plt.semilogx(sizes, copy_gbs, marker='o')
plt.xlabel('Working set size (bytes, log2)')
plt.ylabel('GB/s (copy inside LLC)')
plt.title('LLC streaming throughput')
plt.grid(True, which='both', ls=':')

plt.show()
