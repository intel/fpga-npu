#ifndef MVU_H
#define MVU_H

#include <vector>
#include <string>
#include "input.h"
#include "output.h"
#include "tile.h"
#include "inst.h"
#include "utils.h"
#include "defines.h"

/* 
 * This class implements the matrix-vector multiplication unit (MVU).
 * Input Ports:
 * - VRFs write data (from Loader)
 * - VRFs write address (from Loader)
 * - MVU uOP (from decoder)
 * - update tag (from Loader)
 * Output Ports:
 * - MVU output (to next block in pipeline -- eVRF)
 */
class MVU : public Module {
public:
    // Constructor
    MVU (std::string t_name);
    // Clock function
    void clock(unsigned int &cycle_count);
    // Getter functions
    std::string getName();
    Input<std::vector<TYPE>>* getPortVrfWdata(unsigned int idx);
    Input<unsigned int>* getPortVrfWaddr(unsigned int idx);
    Input<mvu_uOP>* getPortuOP();
    Input<bool>* getPortUpdateTag();
    Output<std::vector<TYPE>>* getPortRes();
    // Destructor
    ~MVU();

private:
    // Module name
    std::string name;
    // Input and Output ports
    std::vector<Input<std::vector<TYPE>>*> vrfs_wdata;
    std::vector<Input<unsigned int>*> vrfs_waddr;
    Input<mvu_uOP>* uOP;
    Input<bool>* update_tag;
    Output<std::vector<TYPE>>* mvu_results;
    // Internal modules
    std::vector<Tile*> mvu_tiles;
    // Internal channels
    std::vector<Channel<mvu_uOP>*> uOP_channels;
    std::vector<std::vector<Channel<TYPE>*>> tile_results0;
    std::vector<std::vector<Channel<TYPE>*>> tile_results1;
    std::vector<std::vector<Channel<TYPE>*>> tile_results2;
    Channel<std::vector<TYPE>>* reduction_channel0;
    Channel<std::vector<TYPE>>* reduction_channel1;
    Channel<std::vector<TYPE>>* reduction_channel2;
    // Local variables
    unsigned int current_tag;
};

#endif
