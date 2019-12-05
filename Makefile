SHELL:=/bin/bash

BSC_FLAGS= -aggressive-conditions -keep-fires -show-schedule -check-assert +RTS -K1G -RTS -steps-max-intervals 10000000

.PHONY: all clean Top
all: Top

define compileProc
$(1): $(1).bsv
	mkdir -p build_dir/$(1)
	bsc $(BSC_FLAGS) -bdir build_dir/$(1) -info-dir build_dir/$(1) -vdir vivado/src/verilog -verilog -u -g mkTop $(1).bsv
	make -C vivado
	@echo "Now copy the files from vivado/sdcard/ to an SD card"
endef

$(eval $(call compileProc,Top))


clean:
	rm -rf *.v *.ba *.cxx *.o *.h *.so *.sched synthDir testout
	rm -rf test_out
	rm -rf build_dir
	rm -rf Top

superclean: clean
	make -C sw clean
	make -C vivado clean
