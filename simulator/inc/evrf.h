#ifndef EVRF_H
#define EVRF_H

#include <vector>
#include <string>
#include "input.h"
#include "output.h"
#include "register_file.h"
#include "inst.h"
#include "defines.h"

/* 
 * This class implements the external VRF (eVRF) module which is used to skip the MVU if an
 * instruction chain does not have an MVU operation.
 * Input Ports:
 * - eVRF input (from previous block in pipeline -- MVU)
 * - eVRF uOP (from decoder)
 * - eVRF write data (from Loader)
 * - eVRF write address (from Loader)
 * - update tag (from Loader)
 * Output Ports:
 * - eVRF output (to next block in pipeline -- MFU0)
 */
class EVRF : public Module {
public:
    // Constructor
    EVRF (std::string t_name);
    // Clock function
    void clock(unsigned int &cycle_count);
    // Getter functions
    std::string getName();
    Input<std::vector<TYPE>>* getPortInput();
    Input<evrf_uOP>* getPortuOP();
    Input<std::vector<TYPE>>* getPortEvrfWdata();
    Input<unsigned int>* getPortEvrfWaddr();
    Input<bool>* getPortUpdateTag();
    Output<std::vector<TYPE>>* getPortRes();
    // Destructor
    ~EVRF();

private:
    // Module name
    std::string name;
    // Input and Output ports
    Input<std::vector<TYPE>>* evrf_input;
    Input<evrf_uOP>* uOP;
    Input<std::vector<TYPE>>* evrf_wdata;
    Input<unsigned int>* evrf_waddr;
    Input<bool>* update_tag;
    Output<std::vector<TYPE>>* evrf_result;
    // Internal modules
    RegisterFile<std::vector<TYPE>>* evrf;
    // Internal channels
    Channel<std::vector<TYPE>>* mvu_channel;
    Channel<unsigned int>* evrf_raddr;
    Channel<std::vector<TYPE>>* evrf_rdata;
    // Local variables
    unsigned int current_tag;
};

#endif
