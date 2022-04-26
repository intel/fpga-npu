#ifndef NPU_H
#define NPU_H

#include <vector>
#include "input.h"
#include "output.h"
#include "datapath.h"
#include "decoder.h"
#include "inst.h"
#include "defines.h"

/* 
 * This class implements the NPU top-level module consisting of datapath and instruction decoders.
 * Input Ports: 
 * - VLIW NPU instructions (from tester)
 * Output Ports:
 * - NPU final outputs (to tester) 
 */
class NPU : public Module {
public:
    // Constructor
    NPU (std::string t_name);
    // Clock function
    void clock(unsigned int &cycle_count);
    // Getter functions
    std::string getName();
    Input<npu_instruction>* getPortInst();
    Output<std::vector<TYPE>>* getPortOutput();
    // Destructor
    ~NPU();

private:
    // Module name
    std::string name;
    // Input and Output ports
    Input<npu_instruction>* npu_inst;
    Output<std::vector<TYPE>>* npu_output;
    // Internal modules
    Datapath* npu_datapath;
    Decoder* npu_decoders;
    // Internal channels
    Channel<mvu_uOP>* mvu_uOP_channel;
    Channel<evrf_uOP>* evrf_uOP_channel;
    Channel<mfu_uOP>* mfu0_uOP_channel;
    Channel<mfu_uOP>* mfu1_uOP_channel;
    Channel<ld_uOP>* ld_uOP_channel;
};

#endif
