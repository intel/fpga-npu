#include "dpe.h"

// DPE Constructor
DPE::DPE (std::string t_name, unsigned int t_dpe_id, unsigned int t_tile_id) : Module(t_name) {
	// Create Input and Output ports
	vSeq = new Input<std::vector<TYPE>>(t_name + "_vSeq", this);
	vBroadcast = new Input<std::vector<TYPE>>(t_name + "_vBroadcast", this);
	reg_sel = new Input<unsigned int>(t_name + "_reg_sel", this);
	vrf_en = new Input<unsigned int>(t_name + "_vrf_en", this);
	dpe_res0  = new Output<TYPE>(t_name + "_dpe_res0", this);
	dpe_res1  = new Output<TYPE>(t_name + "_dpe_res1", this);
	dpe_res2  = new Output<TYPE>(t_name + "_dpe_res2", this);
	// Create internal channels
	dpe_result0_channel = new Channel<TYPE>(t_name + "_dpe_result0_channel", dpe_result_latency, 
		dpe_result_latency);
	dpe_result1_channel = new Channel<TYPE>(t_name + "_dpe_result1_channel", dpe_result_latency, 
		dpe_result_latency);
	dpe_result2_channel = new Channel<TYPE>(t_name + "_dpe_result2_channel", dpe_result_latency, 
		dpe_result_latency);
	pingpong0 = new Channel<std::vector<TYPE>>(t_name + "_pingpong0_channel", pingpong_length, 
		pingpong_length);
	pingpong1 = new Channel<std::vector<TYPE>>(t_name + "_pingpong1_channel", pingpong_length, 
		pingpong_length);
	broadcast_delay = new Channel<std::vector<TYPE>>(t_name + "_broadcast_delay_channel", 
		pingpong_length, pingpong_length);
	input_sel_delay = new Channel<unsigned int>(t_name + "_input_sel_delay_channel", 
		pingpong_length, pingpong_length);
	reg_sel_delay = new Channel<unsigned int>(t_name + "_input_reg_delay_channel", 3, 3);
	vrf_en_delay = new Channel<unsigned int>(t_name + "_vrf_en_delay_channel", 3, 3);
	// Initialize local variables
	dpe_id = t_dpe_id;
	tile_id = t_tile_id;
}

// Dot product helper function
TYPE dot_product(std::vector<TYPE> &v1, std::vector<TYPE> &v2){
	TYPE result = 0;
	for(unsigned int i = 0; i < LANES; i++){
		result += (v1[i] * v2[i]);
	}
	return result;
}

// Clock cycle update function
void DPE::clock() {
	std::vector<TYPE> temp_vSeq, temp_vBroadcast;
	TYPE dpe_result0, dpe_result1, dpe_result2;
	// Write output results when ready
	if(!dpe_result0_channel->isEmpty() && !dpe_res0->isChannelFull()){
		dpe_res0->writeToChannel(dpe_result0_channel->read());
		dpe_res1->writeToChannel(dpe_result1_channel->read());
		dpe_res2->writeToChannel(dpe_result2_channel->read());
	}
	// Prepare operands
	if(!broadcast_delay->isEmpty() && !dpe_result0_channel->isFull()){
		std::vector<TYPE> v0, v1, v2, temp, vb;
		unsigned int input_sel = input_sel_delay->read();
		if(input_sel == 0){
			for(unsigned int i = 0; i < (LANES/10 * 3); i++){
				temp = pingpong0->at(i);
				if(i % 3 == 0){			
					v0.insert(v0.end(), temp.begin(), temp.end());
				} else if (i % 3 == 1) {
					v1.insert(v1.end(), temp.begin(), temp.end());
				} else {
					v2.insert(v2.end(), temp.begin(), temp.end());
				}
			}
		} else {
			for(unsigned int i = 0; i < (LANES/10 * 3); i++){
				temp = pingpong1->at(i);
				if(i % 3 == 0){			
					v0.insert(v0.end(), temp.begin(), temp.end());
				} else if (i % 3 == 1) {
					v1.insert(v1.end(), temp.begin(), temp.end());
				} else {
					v2.insert(v2.end(), temp.begin(), temp.end());
				}
			}
		}
		vb = broadcast_delay->read();
		// Perform computation
		dpe_result0 = dot_product(vb, v0);
		dpe_result1 = dot_product(vb, v1);
		dpe_result2 = dot_product(vb, v2);
		// Write dot product results to delay channels
		dpe_result0_channel->write(dpe_result0);
		dpe_result1_channel->write(dpe_result1);
		dpe_result2_channel->write(dpe_result2);
	}

    // Accept new inputs
    if(!vSeq->isChannelEmpty() && !vBroadcast->isChannelEmpty() 
    	&& !reg_sel->isChannelEmpty() && !broadcast_delay->isFull()) {
        
        temp_vSeq = vSeq->readFromChannel();
        temp_vBroadcast = vBroadcast->readFromChannel();
        unsigned int temp_reg_sel = reg_sel->readFromChannel();
        unsigned int temp_vrf_en = vrf_en->readFromChannel();
        unsigned int delayed_reg_sel;
        unsigned int delayed_vrf_en;
        if(!reg_sel_delay->isEmpty()){
        	delayed_reg_sel = reg_sel_delay->read();
        	delayed_vrf_en = vrf_en_delay->read();
        } else {
        	delayed_reg_sel = temp_reg_sel;
        	delayed_vrf_en = temp_vrf_en;
        }

        if(!pingpong0->isEmpty() && delayed_reg_sel == 0 && (delayed_vrf_en == 1))
        	pingpong0->read();
        if(!pingpong1->isEmpty() && delayed_reg_sel == 1 && (delayed_vrf_en == 1))
        	pingpong1->read();

        if((temp_reg_sel == 0) && (temp_vrf_en == 1)){
        	pingpong0->write(temp_vSeq);
        } else if ((temp_reg_sel == 1) && (temp_vrf_en == 1)){
        	pingpong1->write(temp_vSeq);
        }

        if(((temp_reg_sel == 0) && (temp_vrf_en == 1)) || (delayed_reg_sel == 0 && 
        	delayed_vrf_en == 1))
        		pingpong0->clock();

       	if(((temp_reg_sel == 1) && (temp_vrf_en == 1)) || (delayed_reg_sel == 1 && 
       		delayed_vrf_en == 1))
       			pingpong1->clock();

        broadcast_delay->write(temp_vBroadcast);
        input_sel_delay->write(temp_reg_sel);   
        reg_sel_delay->write(temp_reg_sel);
        vrf_en_delay->write(temp_vrf_en);
    } else if(!reg_sel_delay->isEmpty()){
    	unsigned int delayed_reg_sel = reg_sel_delay->read();
    	unsigned int delayed_vrf_en = vrf_en_delay->read();

        if(!pingpong0->isEmpty() && delayed_reg_sel == 0 && delayed_vrf_en == 1)
        	pingpong0->read();
        if(!pingpong1->isEmpty() && delayed_reg_sel == 1 && delayed_vrf_en == 1)
        	pingpong1->read();

        if(delayed_reg_sel == 0 && delayed_vrf_en == 1)
        	pingpong0->clock();

       	if(delayed_reg_sel == 1 && delayed_vrf_en == 1)
       		pingpong1->clock();
    }

    // Clock internal channels
    broadcast_delay->clock();
    input_sel_delay->clock();
    reg_sel_delay->clock();
    vrf_en_delay->clock();
    dpe_result0_channel->clock();
    dpe_result1_channel->clock();
    dpe_result2_channel->clock();
}

// Getter function for name
std::string DPE::getName() { 
	return name; 
}

// Getter function for sequentially loaded input port
Input<std::vector<TYPE>>* DPE::getPortVSeq()  { 
	return vSeq; 
}

// Getter function for broadcast input port
Input<std::vector<TYPE>>* DPE::getPortVBroadcast()  { 
	return vBroadcast; 
}

// Getter function for register select input port
Input<unsigned int>* DPE::getPortRegSel() { 
	return reg_sel; 
}

// Getter function for VRF enable input port
Input<unsigned int>* DPE::getPortVrfEn() { 
	return vrf_en; 
}

// Getter function for DPE output ports
Output<TYPE>* DPE::getPortDPERes(unsigned int i) { 
	if(i == 0)
		return dpe_res0; 
	else if (i == 1)
		return dpe_res1;
	else
		return dpe_res2;
}

DPE::~DPE() {
	delete vSeq;
	delete vBroadcast;
	delete reg_sel;
	delete vrf_en;
	delete dpe_res0;
	delete dpe_res1;
	delete dpe_res2;
	delete dpe_result0_channel;
	delete dpe_result1_channel;
	delete dpe_result2_channel;
	delete pingpong0;
	delete pingpong1;
	delete broadcast_delay;
	delete input_sel_delay;
	delete reg_sel_delay;
	delete vrf_en_delay;
}