#include "mvu_vrf.h"

// MVU VRF Constructor
MVUVRF::MVUVRF (std::string t_name, unsigned int t_tile_id) : Module(t_name) {
	// Create Input and Output ports
	vrf_wdata = new Input<std::vector<TYPE>>(t_name + "_vrf_wdata", this);
    vrf_waddr = new Input<unsigned int>(t_name + "_vrf_waddr", this);
    vrf_rdata = new Output<std::vector<TYPE>>(t_name + "_vrf_rdata", this);
    vrf_raddr = new Input<unsigned int>(t_name + "_vrf_raddr", this);
    vrf_sel = new Input<unsigned int>(t_name + "_vrf_sel", this);
	// Create internal modules and channels
    for(unsigned int i = 0; i < num_vrfs; i++){
    	RegisterFile<std::vector<TYPE>>* ivrf = new RegisterFile<std::vector<TYPE>>(t_name + 
    		"_vrf_" + std::to_string(i), MVU_VRF_DEPTH);
    	Channel<unsigned int>* ivrf_raddr = new Channel<unsigned int>(t_name + "_vrf_raddr_" + 
    		std::to_string(i), 1, 0);
    	Channel<std::vector<TYPE>>* ivrf_rdata = new Channel<std::vector<TYPE>>(t_name + 
    		"_vrf_rdata_" + std::to_string(i), 1, 0);
    	Channel<unsigned int>* ivrf_waddr = new Channel<unsigned int>(t_name + "_vrf_waddr_" + 
    		std::to_string(i), 1, 0);
    	Channel<std::vector<TYPE>>* ivrf_wdata = new Channel<std::vector<TYPE>>(t_name + 
    		"_vrf_wdata_" + std::to_string(i), 1, 0);
    	ivrf->getPortRaddr()->connectTo(ivrf_raddr);
    	ivrf->getPortRdata()->connectTo(ivrf_rdata);
    	ivrf->getPortWaddr()->connectTo(ivrf_waddr);
    	ivrf->getPortWdata()->connectTo(ivrf_wdata);
    	vrfs.push_back(ivrf);
    	vrf_raddr_channel.push_back(ivrf_raddr);
    	vrf_rdata_channel.push_back(ivrf_rdata);
    	vrf_waddr_channel.push_back(ivrf_waddr);
    	vrf_wdata_channel.push_back(ivrf_wdata);
    }
	// Initialize local variables
	tile_id = t_tile_id; 
}

// Clock cycle update function
void MVUVRF::clock() {
	// Parallel write to all VRFs
	if(!vrf_wdata->isChannelEmpty() && !vrf_waddr->isChannelEmpty()){
		std::vector<TYPE> wdata = vrf_wdata->readFromChannel();
		unsigned int waddr = vrf_waddr->readFromChannel();
		for(unsigned int i = 0; i < num_vrfs; i++){
			vrf_waddr_channel[i]->write(waddr);
			std::vector<TYPE> vrf_wdata;
			vrf_wdata.insert(vrf_wdata.end(), wdata.begin()+(i*10), wdata.begin()+(i*10)+10);
			assert(vrf_wdata.size() == 10);
			vrf_wdata_channel[i]->write(vrf_wdata);
		}
	}

	// Read from a single VRF
	if(!vrf_sel->isChannelEmpty() && !vrf_raddr->isChannelEmpty()){
		unsigned int temp_vrf_sel = vrf_sel->readFromChannel();
		unsigned int temp_vrf_raddr = vrf_raddr->readFromChannel();
		vrf_raddr_channel[temp_vrf_sel]->write(temp_vrf_raddr);
	}

	// Write output to ports & clock all internal VRFs and channels
	for(unsigned int i = 0; i < num_vrfs; i++){
		if(!vrf_rdata_channel[i]->isEmpty() && !vrf_rdata->isChannelFull())
			vrf_rdata->writeToChannel(vrf_rdata_channel[i]->read());
		vrfs[i]->clock();
		vrf_raddr_channel[i]->clock();
		vrf_rdata_channel[i]->clock();
		vrf_waddr_channel[i]->clock();
		vrf_wdata_channel[i]->clock();
	}
}

// Getter function for VRF write data input port
Input<std::vector<TYPE>>* MVUVRF::getPortVrfWdata() { 
	return vrf_wdata; 
}

// Getter function for VRF write address input port
Input<unsigned int>* MVUVRF::getPortVrfWaddr() { 
	return vrf_waddr; 
}

// Getter function for VRF read data output port
Output<std::vector<TYPE>>* MVUVRF::getPortVrfRdata() { 
	return vrf_rdata; 
}

// Getter function for VRF read address input port
Input<unsigned int>* MVUVRF::getPortVrfRaddr() { 
	return vrf_raddr; 
}

// Getter funtion for VRF select input port
Input<unsigned int>* MVUVRF::getPortVrfSel() { 
	return vrf_sel; 
}	

MVUVRF::~MVUVRF() {
	delete vrf_wdata;
	delete vrf_waddr;
	delete vrf_rdata;
	delete vrf_raddr;
	delete vrf_sel;
	for (unsigned int i = 0; i < vrfs.size(); i++) {
		delete vrfs[i];
		delete vrf_raddr_channel[i];
		delete vrf_rdata_channel[i];
		delete vrf_waddr_channel[i];
		delete vrf_wdata_channel[i];
	}
}