# 0) Simple test
set cheshire_path [exec bender path cheshire]
set BINARY "$cheshire_path/sw/tests/run_benchmarks.dram.elf"
set BOOTMODE 0
set PRELMODE 1


do compile.tcl
vlog -ccflags "-std=c++11" "$cheshire_path/target/sim/src/elfloader.cpp"
vlog -sv +acc +define+FUNCTIONAL "$ROOT/models/s27ks0641/s27ks0641.v"



vsim -t 1ps -voptargs=+acc -suppress vopt-2732 -suppress vopt-2912 -suppress vopt-3009 work.cheshire_hyperbus_tb \
  +BINARY=$BINARY +BOOTMODE=$BOOTMODE +PRELMODE=$PRELMODE \
  -do "run -all" \
  -l run.log
