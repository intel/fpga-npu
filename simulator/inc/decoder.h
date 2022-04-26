#ifndef DECODER_H
#define DECODER_H

#include <vector>
#include <string>
#include <iostream>
#include "input.h"
#include "output.h"
#include "channel.h"
#include "inst.h"
#include "defines.h"
#include "utils.h"

/* 
 * This class implements the NPU instruction decoders that translate an NPU VLIW instruction 
 * (5 chained mOPs) into a sequence of uOPs for each of the 5 NPU pipeline stages.
 * Input Ports: 
 * - VLIW NPU instructions (from NPU top-level module)
 * Output Ports:
 * - MVU uOP (to NPU datapath)
 * - eVRF uOP (to NPU datapath)
 * - MFU0 uOP (to NPU datapath)
 * - MFU1 uOP (to NPU datapath)
 * - Loader uOP (to NPU datapath)
 */
class Decoder : public Module {
public:
    // Constructor
    Decoder (std::string t_name);
    // Clock function
    void clock(unsigned int &cycle_count);
    // Getter functions
    std::string getName();
    Input<npu_instruction>* getPortInputVLIW();
    Output<mvu_uOP>* getPortMVUuOP();
    Output<evrf_uOP>* getPortEVRFuOP();
    Output<mfu_uOP>* getPortMFU0uOP();
    Output<mfu_uOP>* getPortMFU1uOP();
    Output<ld_uOP>* getPortLDuOP();
    // Destructor
    ~Decoder();

private:
    // Module name
    std::string name;
    // Input and Output ports
    Input<npu_instruction>* vliw;
    Output<mvu_uOP>*  mvu_uOP_port;
    Output<evrf_uOP>* evrf_uOP_port;
    Output<mfu_uOP>*  mfu0_uOP_port;
    Output<mfu_uOP>*  mfu1_uOP_port;
    Output<ld_uOP>*   ld_uOP_port;
    // Internal channels
    Channel<mvu_mOP>*  mvu_mOP_channel;
    Channel<evrf_mOP>* evrf_mOP_channel;
    Channel<mfu_mOP>*  mfu0_mOP_channel;
    Channel<mfu_mOP>*  mfu1_mOP_channel;
    Channel<ld_mOP>*   ld_mOP_channel;
    // Local variables for decoding logic
    unsigned int mvu_counter;
    unsigned int mvu_pipeline_counter;
    unsigned int mvu_chunk_counter;
    unsigned int reg_sel_flag;
    int remaining_rows;
    unsigned int acc_size;
    unsigned int evrf_counter;
    unsigned int evrf_batch_counter;
    unsigned int mfu0_counter;
    unsigned int mfu0_batch_counter;
    unsigned int mfu1_counter;
    unsigned int mfu1_batch_counter;
    unsigned int ld_counter;
    unsigned int ld_batch_counter;
    bool decoding_mvu;
    bool decoding_evrf;
    bool decoding_mfu0;
    bool decoding_mfu1;
    bool decoding_ld;
    npu_instruction inst;
    mvu_uOP u1; evrf_uOP u2; mfu_uOP u3; mfu_uOP u4; ld_uOP u5;
    mvu_mOP m1; evrf_mOP m2; mfu_mOP m3; mfu_mOP m4; ld_mOP m5;
    unsigned int row_count; unsigned int col_count;
    unsigned int tile_id; unsigned int pue_id;
    unsigned int x_size; unsigned int y_size; unsigned int chunks_per_tile;
};

#endif
