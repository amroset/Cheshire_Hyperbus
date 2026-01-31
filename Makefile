BENDER ?= bender

CHS_ROOT  := $(shell $(BENDER) path cheshire)
HYP_ROOT  := $(shell $(BENDER) path hyperbus)

include $(CHS_ROOT)/cheshire.mk

all: deps sim-scripts chs-sw-all chs-sim-all

deps:
	$(BENDER) checkout

sim-scripts:
	@echo "Generating compile.tcl with Bender..."
	$(BENDER) script vsim -t rtl -t cva6 -t cv64a6_imafdchsclic_sv39_wb -t sim -t test > vsim/compile.tcl
	@echo "Appending HyperRAM model compile..."
	@echo "vlog -incr -sv +acc +define+FUNCTIONAL \"\$$ROOT/models/s27ks0641/s27ks0641.v\"" >> vsim/compile.tcl
	@echo "Done."

clean:
	rm -f vsim/compile.tcl transcript vsim.wlf

