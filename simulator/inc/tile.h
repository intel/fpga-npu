#ifndef TILE_H
#define TILE_H

#include <vector>
#include <string>
#include "input.h"
#include "output.h"
#include "dpe.h"
#include "mvu_vrf.h"
#include "register_file.h"
#include "accumulator.h"
#include "inst.h"
#include "defines.h"

/* 
 * This class implements the matrix-vector multiplication unit (MVU) tile.
 * Input Ports:
 * - VRFs write data (from Loader)
 * - VRFs write address (from Loader)
 * - MVU uOP (from decoder)
 * Output Ports:
 * - MVU tile output 0 (to MVU reduction)
 * - MVU tile output 1 (to MVU reduction)
 * - MVU tile output 2 (to MVU reduction)
 */
class Tile : public Module {
public:
    // Constructor
    Tile (std::string t_name, unsigned int t_tile_id);
    // Clock function
    void clock();
    // Getter functions
    Input<std::vector<TYPE>> *getPortVrfWdata();
    Input<unsigned int> *getPortVrfWaddr();
    Input<mvu_uOP> *getPortuOP();
    Output<TYPE> *getPortResults(unsigned int accum, unsigned int idx);
    // Destructor
    ~Tile();

private:
    // Module name
    std::string name;
    // Input and Output ports
    Input<std::vector<TYPE>>* vrf_wdata;
    Input<unsigned int>* vrf_waddr;
    Input<mvu_uOP>* uOP;
    std::vector<Output<TYPE>*> accum0_results;
    std::vector<Output<TYPE>*> accum1_results;
    std::vector<Output<TYPE>*> accum2_results;
    // Internal modules
    MVUVRF* vrf;
    std::vector<RegisterFile<std::vector<TYPE>>*> mrfs;
    std::vector<DPE*> dpes;
    std::vector<Accumulator*> accums;
    // Internal channels
    Channel<unsigned int>* vrf_raddr;
    Channel<unsigned int>* vrf_sel;
    std::vector<Channel<unsigned int>*> mrf_raddr;
    std::vector<Channel<std::vector<TYPE>>*> mrf_rdata;
    std::vector<Channel<unsigned int>*> mrf_waddr;
    std::vector<Channel<std::vector<TYPE>>*> mrf_wdata;
    std::vector<Channel<std::vector<TYPE>>*> vrf_to_dpe_channels;
    std::vector<Channel<std::vector<TYPE>>*> mrf_to_dpe_channels;
    std::vector<Channel<unsigned int>*> dpe_reg_sel_channels;
    std::vector<Channel<unsigned int>*> dpe_vrf_en_channels;
    std::vector<Channel<unsigned int>*> accum_uOP;
    std::vector<Channel<unsigned int>*> accum_size;
    std::vector<Channel<TYPE>*> accum0_channels;
    std::vector<Channel<TYPE>*> accum1_channels;
    std::vector<Channel<TYPE>*> accum2_channels;
    // Local variables
    unsigned int tile_id;
    unsigned int accum_latency;
    unsigned int reg_sel_latency;
};

#endif
