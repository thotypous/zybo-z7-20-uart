open_project zynq_serial/zynq_serial.xpr
reset_run synth_1
reset_run impl_1
launch_runs synth_1
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
exit
