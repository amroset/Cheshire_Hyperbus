# Watch the exact nets used by VIP and DUT
add wave sim:/cheshire_hyperbus_tb/fix/vip/jtag_tck
add wave sim:/cheshire_hyperbus_tb/fix/vip/jtag_tms
add wave sim:/cheshire_hyperbus_tb/fix/vip/jtag_tdi
add wave sim:/cheshire_hyperbus_tb/fix/vip/jtag_trst_n
add wave sim:/cheshire_hyperbus_tb/fix/vip/jtag_tdo


add wave sim:/cheshire_hyperbus_tb/fix/i_dut/jtag_tck_i
add wave sim:/cheshire_hyperbus_tb/fix/i_dut/jtag_tms_i
add wave sim:/cheshire_hyperbus_tb/fix/i_dut/jtag_tdi_i
add wave sim:/cheshire_hyperbus_tb/fix/i_dut/jtag_trst_ni
add wave sim:/cheshire_hyperbus_tb/fix/i_dut/jtag_tdo_o

add wave -position insertpoint  \
sim:/cheshire_hyperbus_tb/fix/i_dut/i_cheshire_soc/i_dbg_dmi_jtag/tck_i
add wave -position insertpoint  \
sim:/cheshire_hyperbus_tb/fix/i_dut/i_cheshire_soc/i_dbg_dmi_jtag/tms_i
add wave -position insertpoint  \
sim:/cheshire_hyperbus_tb/fix/i_dut/i_cheshire_soc/i_dbg_dmi_jtag/trst_ni
add wave -position insertpoint  \
sim:/cheshire_hyperbus_tb/fix/i_dut/i_cheshire_soc/i_dbg_dmi_jtag/td_i
add wave -position insertpoint  \
sim:/cheshire_hyperbus_tb/fix/i_dut/i_cheshire_soc/i_dbg_dmi_jtag/td_o
add wave -position insertpoint  \
sim:/cheshire_hyperbus_tb/fix/i_dut/i_cheshire_soc/i_dbg_dmi_jtag/tdo_oe_o
