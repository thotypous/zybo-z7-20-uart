# based on https://github.com/ucb-bar/fpga-zynq/blob/master/common/Makefrag

verilog_srcs = \
	src/verilog/top.v \
	src/verilog/mkTop.v

proj_name = zynq_serial
project = $(proj_name)/$(proj_name).xpr

all: sdcard/BOOT.BIN

$(project): src/tcl/project.tcl | $(verilog_srcs)
	rm -rf $(proj_name)
	vivado -mode tcl -source src/tcl/project.tcl

project: $(project)

vivado: $(project)
	# Open GUI
	vivado $(project) &

bitstream = $(proj_name)/$(proj_name).runs/impl_1/top.bit
$(bitstream): src/tcl/make_bitstream.tcl $(verilog_srcs) src/constrs/base.xdc | $(project)
	vivado -mode tcl -source src/tcl/make_bitstream.tcl
bitstream: $(bitstream)

sdcard/BOOT.BIN: boot.bif boot/zynq_fsbl.elf boot/u-boot.elf | $(bitstream)
	bootgen -image $< -w -o $@

clean:
	rm -f sdcard/BOOT.BIN
	rm -rf $(proj_name) .Xil
	rm -f *.log *.jou
