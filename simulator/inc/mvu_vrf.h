#ifndef MVU_VRF_H
#define MVU_VRF_H

#include <vector>
#include <iostream>
#include <string>
#include <tuple>
#include <assert.h>
#include <math.h>
#include "input.h"
#include "output.h"
#include "register_file.h"
#include "utils.h"
#include "defines.h"

/* 
 * This class implements the MVU vector register file (VRF). This module has the same interface as
 * a conventional register file, but supplies the batch-3 inputs in sequence to be compatible with
 * the Stratix 10 NX DPE. For a conventional DPE, a conventional register file would have been used.
 * Input Ports:
 * - VRF write data (from Loader)
 * - VRF write address (from Loader)
 * - VRF read address (from MVU uOP)
 * - VRF select control signal (from MVU uOP)
 * Output Ports:
 * - VRF read data (to DPEs)
 */
class MVUVRF : public Module {
public:
    // Constructor
    MVUVRF (std::string t_name, unsigned int t_tile_id);
    // Clock function
    void clock();
    // Getters and setters
    Input<std::vector<TYPE>> *getPortVrfWdata();
    Input<unsigned int> *getPortVrfWaddr();
    Output<std::vector<TYPE>> *getPortVrfRdata();
    Input<unsigned int> *getPortVrfRaddr();
    Input<unsigned int> *getPortVrfSel();
    // Destructor
    ~MVUVRF();

private:
    // Module name
    std::string name;
    // Input and Output ports
    Input<std::vector<TYPE>>* vrf_wdata;
    Input<unsigned int>* vrf_waddr;
    Output<std::vector<TYPE>>* vrf_rdata;
    Input<unsigned int>* vrf_raddr;
    Input<unsigned int>* vrf_sel;
    // Internal modules
    std::vector<RegisterFile<std::vector<TYPE>>*> vrfs;
    // Internal channels
    std::vector<Channel<unsigned int>*> vrf_raddr_channel;
    std::vector<Channel<std::vector<TYPE>>*> vrf_rdata_channel;
    std::vector<Channel<unsigned int>*> vrf_waddr_channel;
    std::vector<Channel<std::vector<TYPE>>*> vrf_wdata_channel;
    // Local variables
    unsigned int tile_id;
    unsigned int num_vrfs = LANES / 10;
};

#endif