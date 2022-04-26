#ifndef LOADER_H
#define LOADER_H

#include <vector>
#include <queue>
#include <string>
#include "input.h"
#include "output.h"
#include "inst.h"
#include "utils.h"
#include "defines.h"

/* 
 * This class implements the loader module which writes the datapath results back to one of the
 * NPU architectural states (VRFs).
 * Input Ports:
 * - Loader input (from previous block in pipeline -- MFU1)
 * - Loader uOP (from decoder)
 * Output Ports:
 * - MVU VRFs write data (to MVU)
 * - MVU VRFs write address (to MVU)
 * - MVU tag update (to MVU)
 * - eVRF write data (to eVRF)
 * - eVRF write address (to eVRF)
 * - eVRF tag update (to eVRF)
 * - MFU0 VRF0 write data (to MFU0)
 * - MFU0 VRF0 write address (to MFU0)
 * - MFU0 VRF1 write data (to MFU0)
 * - MFU0 VRF1 write address (to MFU0)
 * - MFU0 tag update (to MFU0)
 * - MFU1 VRF0 write data (to MFU1)
 * - MFU1 VRF0 write address (to MFU1)
 * - MFU1 VRF1 write data (to MFU1)
 * - MFU1 VRF1 write address (to MFU1)
 * - MFU1 tag update (to MFU1)
 * - Loader output port (to tester)
 */
class LD : public Module {
public:
    // Constructor
    LD (std::string t_name);
    // Clock function
    void clock(unsigned int &cycle_count);
    // Getter functions
    std::string getName();
    Input<ld_uOP>* getPortuOP();
    Input<std::vector<TYPE>>* getPortInput();
    Output<std::vector<TYPE>>* getPortMVUWdata(unsigned int idx);
    Output<unsigned int>* getPortMVUWaddr(unsigned int idx);
    Output<std::vector<TYPE>>* getPortEvrfWdata();
    Output<unsigned int>* getPortEvrfWaddr();
    Output<std::vector<TYPE>>* getPortMFU0Vrf0Wdata();
    Output<unsigned int>* getPortMFU0Vrf0Waddr();
    Output<std::vector<TYPE>>* getPortMFU0Vrf1Wdata();
    Output<unsigned int>* getPortMFU0Vrf1Waddr();
    Output<std::vector<TYPE>>* getPortMFU1Vrf0Wdata();
    Output<unsigned int>* getPortMFU1Vrf0Waddr();
    Output<std::vector<TYPE>>* getPortMFU1Vrf1Wdata();
    Output<unsigned int>* getPortMFU1Vrf1Waddr();
    Output<bool>* getPortUpdateMVU();
    Output<bool>* getPortUpdateEvrf();
    Output<bool>* getPortUpdateMFU0();
    Output<bool>* getPortUpdateMFU1();
    Output<std::vector<TYPE>>* getPortOutput();
    // Destructor
    ~LD();

private:
    // Module name
    std::string name;
    // Input and Output ports
    Input<ld_uOP>* uOP;
    Input<std::vector<TYPE>>* ld_input;
    std::vector<Output<std::vector<TYPE>>*> mvu_vrfs_wdata;
    std::vector<Output<unsigned int>*> mvu_vrfs_waddr;
    Output<std::vector<TYPE>>* evrf_wdata;
    Output<unsigned int>* evrf_waddr;
    Output<std::vector<TYPE>>* mfu0_vrf0_wdata;
    Output<unsigned int>* mfu0_vrf0_waddr;
    Output<std::vector<TYPE>>* mfu0_vrf1_wdata;
    Output<unsigned int>* mfu0_vrf1_waddr;
    Output<std::vector<TYPE>>* mfu1_vrf0_wdata;
    Output<unsigned int>* mfu1_vrf0_waddr;
    Output<std::vector<TYPE>>* mfu1_vrf1_wdata;
    Output<unsigned int>* mfu1_vrf1_waddr;
    Output<bool> *update_tag_mvu;
    Output<bool> *update_tag_evrf;
    Output<bool> *update_tag_mfu0;
    Output<bool> *update_tag_mfu1;
    Output<std::vector<TYPE>>* ld_output;
    // Local variables
    std::queue<std::vector<TYPE>> input_fifo;
};

#endif
