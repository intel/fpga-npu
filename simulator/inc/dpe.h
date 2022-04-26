#ifndef DPE_H_
#define DPE_H_

#include <string>
#include <vector>
#include <tuple>
#include <math.h>
#include <iostream>
#include <assert.h>
#include "module.h"
#include "input.h"
#include "output.h"
#include "defines.h"
#include "utils.h"

/* 
 * This class implements the MVU dot product engine (DPE) based on the Stratix 10 NX tensor blocks.
 * Each DPE implements a batch-3 dot product operation (i.e. 1 shared vector multiplied by 3 other
 * input vectors).
 * Input Ports:
 * - shared input vector (vBroadcast)
 * - sequentially loaded input vectors (vSeq)
 * - control signals (reg_sel, vrf_en)
 * Output Ports:
 * - 3 dot product results (dpe_res0, dpe_res1, dpe_res2)
 */
class DPE : public Module { 
public:
	// Constructor
	DPE (std::string t_name, unsigned int t_dpe_id, unsigned int t_tile_id);
	// Clock function
	void clock();
	// Getter functions
	std::string getName();
	Input<std::vector<TYPE>> *getPortVSeq();
	Input<std::vector<TYPE>> *getPortVBroadcast();
	Input<unsigned int> *getPortRegSel();
	Input<unsigned int> *getPortVrfEn();
	Output<TYPE> *getPortDPERes(unsigned int i);
	// Destructor
	~DPE();

private:
	// Module name
	std::string name;
	// Input and Output ports
	Input<std::vector<TYPE>>* vSeq;
	Input<std::vector<TYPE>>* vBroadcast;
	Input<unsigned int>* reg_sel;
	Input<unsigned int>* vrf_en;
	Output<TYPE>* dpe_res0;
	Output<TYPE>* dpe_res1;
	Output<TYPE>* dpe_res2;
	// Internal channels'
	Channel<TYPE>* dpe_result0_channel;
	Channel<TYPE>* dpe_result1_channel;
	Channel<TYPE>* dpe_result2_channel;
	Channel<std::vector<TYPE>>* pingpong0;
	Channel<std::vector<TYPE>>* pingpong1;
	Channel<std::vector<TYPE>>* broadcast_delay;
	Channel<unsigned int>* input_sel_delay;
	Channel<unsigned int>* reg_sel_delay;
	Channel<unsigned int>* vrf_en_delay;
	// Local variables
	unsigned int dpe_id;
	unsigned int tile_id;
	// Local latency variables
	unsigned int num_prime_dsps = (unsigned int) ceil(1.0 * LANES / 10.0);
	unsigned int dpe_result_latency = (unsigned int) 2 + (ceil(log2(num_prime_dsps)) * 
		DPE_ADDER_LATENCY);
	unsigned int pingpong_length = 3 * (1 + num_prime_dsps);
	int accum_val = 0;
};

#endif
		
