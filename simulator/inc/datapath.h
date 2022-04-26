#ifndef DATAPATH_H
#define DATAPATH_H

#include <vector>
#include <string>

#include "input.h"
#include "output.h"
#include "mvu.h"
#include "mfu.h"
#include "evrf.h"
#include "loader.h"
#include "inst.h"
#include "defines.h"

/* 
 * This class implements the NPU datapath. It consists of 5 main pipeline stages (MVU, eVRF, MFU0,
 * MFU1, and Loader).
 * Input Ports:
 * - MVU uOP (from NPU decoders)
 * - eVRF uOP (from NPU decoders)
 * - MFU0 uOP (from NPU decoders)
 * - MFU1 uOP (from NPU decoders)
 * - Loader uOP (from NPU decoders)
 * Output Ports:
 * - Final NPU output (to tester)
 */
class Datapath : public Module {
public:
    // Constructor
    Datapath (std::string t_name);
    // Clock function
    void clock(unsigned int &cycle_count);
    // Getter functions
    Input<mvu_uOP>* getPortMVUuOP();
    Input<evrf_uOP>* getPortEVRFuOP();
    Input<mfu_uOP>* getPortMFU0uOP();
    Input<mfu_uOP>* getPortMFU1uOP();
    Input<ld_uOP>* getPortLDuOP();
    Output<std::vector<TYPE>>* getPortOutput();
    // Destructor
    ~Datapath();

private:
    // Module name
    std::string name;
    // Input and Output ports
    Input<mvu_uOP>*  mvu_uOP_port;
    Input<evrf_uOP>* evrf_uOP_port;
    Input<mfu_uOP>*  mfu0_uOP_port;
    Input<mfu_uOP>*  mfu1_uOP_port;
    Input<ld_uOP>*   ld_uOP_port;
    Output<std::vector<TYPE>>* datapath_output;
    // Internal modules
    MVU* mvu;
    EVRF* evrf;
    MFU* mfu0;
    MFU* mfu1;
    LD* ld;
    // Internal channels
    Channel<std::vector<TYPE>>* mvu_to_evrf_channel;
    Channel<std::vector<TYPE>>* evrf_to_mfu0_channel;
    Channel<std::vector<TYPE>>* mfu0_to_mfu1_channel;
    Channel<std::vector<TYPE>>* mfu1_to_ld_channel;
    // Loader to MVU channels
    std::vector<Channel<std::vector<TYPE>>*> ld_to_mvu_wdata_channels;
    std::vector<Channel<unsigned int>*> ld_to_mvu_waddr_channels;
    Channel<bool>* ld_to_mvu_update_channel;
    // Loader to eVRF Channels
    Channel<std::vector<TYPE>>* ld_to_evrf_wdata_channel;
    Channel<unsigned int>* ld_to_evrf_waddr_channel;
    Channel<bool>* ld_to_evrf_update_channel;
    // Loader to MRF0 Channels
    Channel<std::vector<TYPE>>* ld_to_mfu0_vrf0_wdata_channel;
    Channel<std::vector<TYPE>>* ld_to_mfu0_vrf1_wdata_channel;
    Channel<unsigned int>* ld_to_mfu0_vrf0_waddr_channel;
    Channel<unsigned int>* ld_to_mfu0_vrf1_waddr_channel;
    Channel<bool>* ld_to_mfu0_update_channel;
    // Loader to MRF1 Channels
    Channel<std::vector<TYPE>>* ld_to_mfu1_vrf0_wdata_channel;
    Channel<std::vector<TYPE>>* ld_to_mfu1_vrf1_wdata_channel;
    Channel<unsigned int>* ld_to_mfu1_vrf0_waddr_channel;
    Channel<unsigned int>* ld_to_mfu1_vrf1_waddr_channel;
    Channel<bool>* ld_to_mfu1_update_channel;
};

#endif
