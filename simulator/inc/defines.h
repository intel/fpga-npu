#ifndef DEFINES_H_
#define DEFINES_H_

#include <string>
#include <iostream>

// Debug Messages
#define VERBOSE_OP 1
#define VERBOSE_MVU 1
#define VERBOSE_LD_OUT 0

// Architecture Parameters
#define TILES 7
#define DPES 40
#define LANES 40
#define MVU_VRF_DEPTH 512
#define MVU_MRF_DEPTH 1024
#define EVRF_DEPTH 512
#define MFU_VRF0_DEPTH 512
#define MFU_VRF1_DEPTH 512
#define FIFO_DEPTH 512

// Latency Parameters
#define DPE_MULT_LATENCY 2
#define DPE_ADDER_LATENCY 1
#define RF_WRITE_LATENCY 1
#define RF_READ_LATENCY 1
#define MRF_TO_DPE_LATENCY 8
#define VRF_TO_DPE_LATENCY 8
#define MVU_ACCUM_LATENCY 4
#define MVU_REDUCTION_LATENCY (unsigned int)(ceil(log2(TILES))+5)
#define MFU_ACT_LATENCY 3
#define MFU_ADD_LATENCY 3
#define MFU_MUL_LATENCY 3
#define MFU_LATENCY MFU_ACT_LATENCY+MFU_ADD_LATENCY+MFU_MUL_LATENCY
#define LD_WB_LATENCY 5

// Precision
#define TYPE int
#define INPUT_PRECISION 8
#define MASK_TRUNCATE 0x000000FF
#define MASK_SIGN_EXTEND 0xFFFFFF00
#define MASK_SIGN_CHECK 0x00000080

#define LOG(module_name, msg) do { \
std::cout << "[" << module_name << " @ " << cycle_count << "]: " << msg << std::endl; \
} while (0)

#endif
