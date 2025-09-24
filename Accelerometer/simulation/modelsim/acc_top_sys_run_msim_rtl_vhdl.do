transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+D:/VHDL_2/acc_top_sys/db {D:/VHDL_2/acc_top_sys/db/pll_altpll.v}
vcom -2008 -work work {D:/VHDL_2/acc_top_sys/data_interface.vhd}
vcom -2008 -work work {D:/VHDL_2/acc_top_sys/metastability.vhd}
vcom -2008 -work work {D:/VHDL_2/acc_top_sys/Accel_Display.vhd}
vcom -2008 -work work {D:/VHDL_2/acc_top_sys/VGA_Sync.vhd}
vcom -2008 -work work {D:/VHDL_2/acc_top_sys/VGA_KOMPONENT.vhd}
vcom -2008 -work work {D:/VHDL_2/acc_top_sys/DPRAM.vhd}
vcom -2008 -work work {D:/VHDL_2/acc_top_sys/spi_master.vhd}
vcom -2008 -work work {D:/VHDL_2/acc_top_sys/accelerometer_adxl345.vhd}
vcom -2008 -work work {D:/VHDL_2/acc_top_sys/acc_top_sys.vhd}
vcom -2008 -work work {D:/VHDL_2/pll.vhd}

vcom -2008 -work work {D:/VHDL_2/acc_top_sys/simulation/modelsim/acc_top_sys.vht}

vsim -t 1ps -L altera -L lpm -L sgate -L altera_mf -L altera_lnsim -L fiftyfivenm -L rtl_work -L work -voptargs="+acc"  acc_top_sys_vhd_tst

add wave *

add wave -position insertpoint  \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_data_interface/data_x_y_z \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_data_interface/z_valid \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_data_interface/y_valid \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_data_interface/x_valid


add wave -position insertpoint  \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/rx_data \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/busy \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/div \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/sclk \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/count \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/state \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/tx_data \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/start \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/cpol \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_spi_master/scaler


add wave -position insertpoint  \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/acc_start \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/spi_tx_data \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/acceleration_x \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/acceleration_y \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/param_data \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/param_addr \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/param \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/count \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/state \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/spi_ena \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/spi_rx_data \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/dv \
sim:/acc_top_sys_vhd_tst/i1/b2v_inst_accelerometer_adxl345/spi_busy

view structure
view signals
run -all
