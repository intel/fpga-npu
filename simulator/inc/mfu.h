#ifndef MFU_H
#define MFU_H

#include <vector>
#include <string>
#include <math.h>
#include <assert.h>

#include "input.h"
#include "output.h"
#include "register_file.h"
#include "inst.h"
#include "defines.h"
#include "utils.h"

/* 
 * This class implements the Multi-Function Unit (MFU) which performs vector element-wise 
 * operations: activations {tanh, sigmoid, relu}, addition {add, sub_ab, sub_ba, max}, and
 * multiplication {mult}.
 * Input Ports:
 * - MFU input (from previous block in pipeline -- eVRF for MFU0 or MFU0 for MFU1)
 * - MFU uOP (from decoder)
 * - VRF0 write data (from Loader)
 * - VRF0 write address (from Loader)
 * - VRF1 write data (from Loader)
 * - VRF1 write address (from Loader)
 * - Tag update (from Loader)
 * Output Ports:
 * - MFU output (to next block in pipeline -- MFU1 for MFU0 or Loader for MFU1)
 */
class MFU : public Module {
public:
    // Constructor
    MFU (std::string t_name);
    // Clock function
    void clock(unsigned int &cycle_count);
    // Getter functions
    std::string getName();
    Input<std::vector<TYPE>>* getPortInput();
    Input<mfu_uOP>* getPortuOP();
    Output<std::vector<TYPE>>* getPortRes();
    Input<std::vector<TYPE>>* getPortVrf0Wdata();
    Input<std::vector<TYPE>>* getPortVrf1Wdata();
    Input<unsigned int>* getPortVrf0Waddr();
    Input<unsigned int>* getPortVrf1Waddr();
    Input<bool>* getPortUpdateTag();
    // Destructor
    ~MFU();

private:
    // Module name
    std::string name;
    // Input and Output port
    Input<std::vector<TYPE>>* mfu_input;
    Input<mfu_uOP>* uOP;
    Input<std::vector<TYPE>>* vrf0_wdata;
    Input<unsigned int>* vrf0_waddr;
    Input<std::vector<TYPE>>* vrf1_wdata;
    Input<unsigned int>* vrf1_waddr;
    Input<bool>* update_tag;
    Output<std::vector<TYPE>>* mfu_result;
    // Internal modules
    RegisterFile<std::vector<TYPE>> *vrf0;
    RegisterFile<std::vector<TYPE>> *vrf1;
    // Internal channels
    Channel<std::vector<TYPE>>* mfu_channel;
    Channel<std::vector<TYPE>>* vrf0_rdata_channel;
    Channel<unsigned int>* vrf0_raddr_channel;
    Channel<std::vector<TYPE>>* vrf1_rdata_channel;
    Channel<unsigned int>* vrf1_raddr_channel;
    Channel<mfu_uOP>* uOP_channel;
    Channel<std::vector<TYPE>>* act_out_channel;
    Channel<std::vector<TYPE>>* add_out_channel;
    Channel<mfu_uOP>* uOP_pipeline;
    // Local variables
    unsigned int current_tag;
};

#endif
