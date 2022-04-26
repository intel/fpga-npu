# Extremely simple makefile.

all:
	g++ -Wno-sign-compare -Wno-unused -std=c++0x -Wall -I ../api -I ../api/linux ../api/linux/intel_fpga_pcie_api_linux.cpp real_npu_test.cpp -o real_npu_test
clean:
	rm -f ./real_npu_test
