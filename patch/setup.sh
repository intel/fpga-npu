#!/bin/bash

cd ../DUT_example_design/ip/pcie_ed/pcie_ed_MEM/altera_avalon_onchip_memory2_1920/synth

FILE=pcie_ed_MEM_altera_avalon_onchip_memory2_1920_2xhjmhi.v
if test -f "$FILE"; then
	sed -i "s/\[ 13\: 0\]/\[ 12\: 0\]/g" $FILE
	sed -i "s/16384/8192/g" $FILE
	sed -i "s/14/13/g" $FILE
else
	echo "IP not configured correctly."
	exit 1
fi

# DMA double buffer controller
cd ../../synth
cp ../../../../../patch/pcie_ed_MEM.v ./


# modify npu.vh path name
cd ../../../../../rtl/
cwd=$(pwd)
sed -i "s~/nfs/sc/disks/swuser_work_aboutros/npu_demo/npu-s10-nx/rtl/~$cwd~" npu.vh

# add npu src files to Quartus prj
cd ../DUT_example_design/
for f in ../rtl/*.sv
do
	if [[ $f != "../rtl/altera_syncram.sv" ]] && [[ $f != "../rtl/self_tester_shim.sv" ]] && [[ $f != "../rtl/tester_rom.sv" ]]
	then
		echo "set_global_assignment -name SYSTEMVERILOG_FILE $f" >> pcie_ed.qsf
	fi
done

echo "set_global_assignment -name VERILOG_FILE ../rtl/dma_buffer.v" >> pcie_ed.qsf
echo "set_global_assignment -name VERILOG_INCLUDE_FILE ../rtl/npu.vh" >> pcie_ed.qsf
echo "set_global_assignment -name MIF_FILE ../rtl/tanh.mif" >> pcie_ed.qsf
echo "set_global_assignment -name MIF_FILE ../rtl/sigmoid.mif" >> pcie_ed.qsf
echo "set_global_assignment -name OPTIMIZATION_MODE \"SUPERIOR PERFORMANCE WITH MAXIMUM PLACEMENT EFFORT\"" >> pcie_ed.qsf

# host program
cd ./software
cp ../../patch/kernel/* ./kernel/linux/
cp ../../patch/user/*.hpp ./user/api/
cp ../../patch/user/*.cpp ./user/api/linux/
cp -r ../../patch/npu_test ./user/