#include "loader.h"

// Loader constructor
LD::LD(std::string t_name) : Module (t_name) {
	// Create Input and Output ports
    uOP = new Input<ld_uOP>(t_name + "_uOP", this);
    ld_input = new Input<std::vector<TYPE>>(t_name + "_input", this);
    for(unsigned int i = 0; i < TILES; i++){
        Output<std::vector<TYPE>>* mvu_vrf_wdata = new Output<std::vector<TYPE>>(t_name +
        	"_mvu_vrf" + std::to_string(i) + "_wdata", this);
        Output<unsigned int>* mvu_vrf_waddr = new Output<unsigned int>(t_name + "_mvu_vrf" +
        	std::to_string(i) + "_waddr", this);
        mvu_vrfs_wdata.push_back(mvu_vrf_wdata);
        mvu_vrfs_waddr.push_back(mvu_vrf_waddr);
    }
    evrf_wdata = new Output<std::vector<TYPE>>(t_name + "_evrf_wdata", this);
    evrf_waddr = new Output<unsigned int>(t_name + "_evrf_waddr", this);
    mfu0_vrf0_wdata = new Output<std::vector<TYPE>>(t_name + "_mfu0_vrf0_wdata", this);
    mfu0_vrf0_waddr = new Output<unsigned int>(t_name + "_mfu0_vrf0_waddr", this);
    mfu0_vrf1_wdata = new Output<std::vector<TYPE>>(t_name + "_mfu0_vrf1_wdata", this);
    mfu0_vrf1_waddr = new Output<unsigned int>(t_name + "_mfu0_vrf1_waddr", this);
    mfu1_vrf0_wdata = new Output<std::vector<TYPE>>(t_name + "_mfu1_vrf0_wdata", this);
    mfu1_vrf0_waddr = new Output<unsigned int>(t_name + "_mfu1_vrf0_waddr", this);
    mfu1_vrf1_wdata = new Output<std::vector<TYPE>>(t_name + "_mfu1_vrf1_wdata", this);
    mfu1_vrf1_waddr = new Output<unsigned int>(t_name + "_mfu1_vrf1_waddr", this);
    update_tag_mvu  = new Output<bool>(t_name + "_update_mvu", this);
    update_tag_evrf = new Output<bool>(t_name + "_update_evrf", this);
    update_tag_mfu0 = new Output<bool>(t_name + "_update_mfu0", this);
    update_tag_mfu1 = new Output<bool>(t_name + "_update_mfu1", this);
    ld_output = new Output<std::vector<TYPE>>(t_name + "_output", this);

    // Load input FIFO with initial inputs to the NPU
	std::string file_name = "register_files/vrf_file.txt"; 
	readVectorFile(file_name, input_fifo);
	std::cout << "Initial size of input FIFO: " << input_fifo.size() << std:: endl;
}

// Clock cycle update function
void LD::clock(unsigned int &cycle_count){
	// If no uOPs ready, abort
	if(uOP->isChannelEmpty()) return;

	// Peek ready uOP to decide how to proceed
	ld_uOP temp = uOP->peekChannel();
	// If ready operation is NOP, read and ignore
	if (temp.op == 0) {
		uOP->readFromChannel();
		LOG(this->getName(), "NOP");

	// If source is set to the MFU input
	} else if(!temp.src && !ld_input->isChannelEmpty() && (temp.op == 1)){
		temp = uOP->readFromChannel();
		// If first uOP, log starting cycle
		if(temp.first_flag && (temp.dst0_id == 0 || temp.dst0_id >= TILES)){
			LOG(this->getName(), "Issued first uOP " + std::to_string(temp.first_flag));
		}
		// If last uOP, log ending cycle and issue tag update flags to all modules
		if(temp.last_flag){
			LOG(this->getName(), "Produced Output");
			update_tag_mvu->writeToChannel(true);
			update_tag_evrf->writeToChannel(true);
			update_tag_mfu0->writeToChannel(true);
			update_tag_mfu1->writeToChannel(true);
		}
		// Write to output FIFO (if required)
		std::vector<TYPE> temp_res = ld_input->peekChannel();
		if(temp.wr_to_output && !ld_output->isChannelFull()){
			ld_output->writeToChannel(temp_res);
		}
		// Output for first destination
		if(temp.dst0_valid && temp.dst0_id < TILES){
			std::vector<TYPE> mvu_temp_res(temp_res.size());
			for(unsigned int i = 0; i < temp_res.size(); i++){
				mvu_temp_res[i] = temp_res[i] & MASK_TRUNCATE;
				if(mvu_temp_res[i] & MASK_SIGN_CHECK){
					mvu_temp_res[i] = mvu_temp_res[i] | MASK_SIGN_EXTEND;
				}
			}
			mvu_vrfs_wdata[temp.dst0_id]->writeToChannel(mvu_temp_res);
			mvu_vrfs_waddr[temp.dst0_id]->writeToChannel(temp.dst0_addr);
			#if(VERBOSE_LD_OUT)
			std::cout << "LD OUTPUT: " << temp_res << std::endl;
			#endif
		} else if (temp.dst0_valid && (temp.dst0_id == TILES)){
			evrf_wdata->writeToChannel(temp_res);
			evrf_waddr->writeToChannel(temp.dst0_addr);
		} else if (temp.dst0_valid && (temp.dst0_id == TILES+1)){
			mfu0_vrf0_wdata->writeToChannel(temp_res);
			mfu0_vrf0_waddr->writeToChannel(temp.dst0_addr);
		} else if (temp.dst0_valid && (temp.dst0_id == TILES+2)){
			mfu0_vrf1_wdata->writeToChannel(temp_res);
			mfu0_vrf1_waddr->writeToChannel(temp.dst0_addr);
		} else if (temp.dst0_valid && (temp.dst0_id == TILES+3)){
			mfu1_vrf0_wdata->writeToChannel(temp_res);
			mfu1_vrf0_waddr->writeToChannel(temp.dst0_addr);
		} else if (temp.dst0_valid && (temp.dst0_id == TILES+4)){
			mfu1_vrf1_wdata->writeToChannel(temp_res);
			mfu1_vrf1_waddr->writeToChannel(temp.dst0_addr);
		}
		// Output for second destination
		if(temp.dst1_valid && temp.dst1_id < TILES){
			mvu_vrfs_wdata[temp.dst1_id]->writeToChannel(temp_res);
			mvu_vrfs_waddr[temp.dst1_id]->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES)){
			evrf_wdata->writeToChannel(temp_res);
			evrf_waddr->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES+1)){
			mfu0_vrf0_wdata->writeToChannel(temp_res);
			mfu0_vrf0_waddr->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES+2)){
			mfu0_vrf1_wdata->writeToChannel(temp_res);
			mfu0_vrf1_waddr->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES+3)){
			mfu1_vrf0_wdata->writeToChannel(temp_res);
			mfu1_vrf0_waddr->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES+4)){
			mfu1_vrf1_wdata->writeToChannel(temp_res);
			mfu1_vrf1_waddr->writeToChannel(temp.dst1_addr);
		}
		// Read out Loader input
        ld_input->readFromChannel();

    // If source is set to the input FIFO
	} else if(temp.src && !input_fifo.empty() && (temp.op == 1)){
		temp = uOP->readFromChannel();
		// If first uOP, log starting cycle
		if(temp.first_flag && (temp.dst0_id == 0 || temp.dst0_id >= TILES)){
			LOG(this->getName(), "Issued first uOP " + std::to_string(temp.first_flag));
		}
		// If last uOP, log ending cycle and issue tag update flags to all modules
		if(temp.last_flag){
			LOG(this->getName(), "Produced Output");
			update_tag_mvu->writeToChannel(true);
			update_tag_evrf->writeToChannel(true);
			update_tag_mfu0->writeToChannel(true);
			update_tag_mfu1->writeToChannel(true);
		}
		// Write to output FIFO (if required)
		std::vector<TYPE> temp_res = input_fifo.front();
		if(temp.wr_to_output && !ld_output->isChannelFull()){
			ld_output->writeToChannel(temp_res);
		}
		// Output for first destination
        if(temp.dst0_valid && temp.dst0_id < TILES){
			mvu_vrfs_wdata[temp.dst0_id]->writeToChannel(temp_res);
			mvu_vrfs_waddr[temp.dst0_id]->writeToChannel(temp.dst0_addr);
			#if(VERBOSE_LD_OUT)
			std::cout << "LD OUTPUT: " << input_fifo.front() << std::endl;
			#endif
		} else if (temp.dst0_valid && (temp.dst0_id == TILES)){
			evrf_wdata->writeToChannel(temp_res);
			evrf_waddr->writeToChannel(temp.dst0_addr);
		} else if (temp.dst0_valid && (temp.dst0_id == TILES+1)){
			mfu0_vrf0_wdata->writeToChannel(temp_res);
			mfu0_vrf0_waddr->writeToChannel(temp.dst0_addr);
		} else if (temp.dst0_valid && (temp.dst0_id == TILES+2)){
			mfu0_vrf1_wdata->writeToChannel(temp_res);
			mfu0_vrf1_waddr->writeToChannel(temp.dst0_addr);
		} else if (temp.dst0_valid && (temp.dst0_id == TILES+3)){
			mfu1_vrf0_wdata->writeToChannel(temp_res);
			mfu1_vrf0_waddr->writeToChannel(temp.dst0_addr);
		} else if (temp.dst0_valid && (temp.dst0_id == TILES+4)){
			mfu1_vrf1_wdata->writeToChannel(temp_res);
			mfu1_vrf1_waddr->writeToChannel(temp.dst0_addr);
		}
		// Output for second destination
		if(temp.dst1_valid && temp.dst1_id < TILES){
			mvu_vrfs_wdata[temp.dst1_id]->writeToChannel(temp_res);
			mvu_vrfs_waddr[temp.dst1_id]->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES)){
			evrf_wdata->writeToChannel(temp_res);
			evrf_waddr->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES+1)){
			mfu0_vrf0_wdata->writeToChannel(temp_res);
			mfu0_vrf0_waddr->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES+2)){
			mfu0_vrf1_wdata->writeToChannel(temp_res);
			mfu0_vrf1_waddr->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES+3)){
			mfu1_vrf0_wdata->writeToChannel(temp_res);
			mfu1_vrf0_waddr->writeToChannel(temp.dst1_addr);
		} else if (temp.dst1_valid && (temp.dst1_id == TILES+4)){
			mfu1_vrf1_wdata->writeToChannel(temp_res);
			mfu1_vrf1_waddr->writeToChannel(temp.dst1_addr);
		}
		// Read out NPU input
        input_fifo.pop();

    // Flush operation
    } else if (temp.op == 2 && !ld_input->isChannelEmpty()) {
        temp = uOP->readFromChannel();
        ld_input->readFromChannel();
        if(temp.last_flag){
			LOG(this->getName(), "Produced Output");
			update_tag_mvu->writeToChannel(true);
			update_tag_evrf->writeToChannel(true);
			update_tag_mfu0->writeToChannel(true);
			update_tag_mfu1->writeToChannel(true);
		}

    // Catching wrong load operations
    } else if(temp.src && input_fifo.empty() && temp.op){
        std::cerr << "No input available in the NPU input FIFO" << std::endl;
        exit(0);
    }
}

// Getter function for name
std::string LD::getName() { 
	return name; 
}

// Getter function for uOP input port
Input<ld_uOP>* LD::getPortuOP() { 
	return uOP; 
}

// Getter function for Loader input port
Input<std::vector<TYPE>>* LD::getPortInput() { 
	return ld_input; 
}

// Getter function for MVU write data output port
Output<std::vector<TYPE>>* LD::getPortMVUWdata(unsigned int idx) { 
	return mvu_vrfs_wdata[idx]; 
}

// Getter function for MVU write address output port
Output<unsigned int>* LD::getPortMVUWaddr(unsigned int idx) { 
	return mvu_vrfs_waddr[idx]; 
}

// Getter function for eVRF write data output port
Output<std::vector<TYPE>>* LD::getPortEvrfWdata() { 
	return evrf_wdata; 
}

// Getter function for eVRF write address output port
Output<unsigned int>* LD::getPortEvrfWaddr() { 
	return evrf_waddr; 
}

// Getter function for MFU0 VRF0 write data output port
Output<std::vector<TYPE>>* LD::getPortMFU0Vrf0Wdata() { 
	return mfu0_vrf0_wdata; 
}

// Getter function for MFU0 VRF0 write address output port
Output<unsigned int>* LD::getPortMFU0Vrf0Waddr() { 
	return mfu0_vrf0_waddr; 
}

// Getter function for MFU0 VRF1 write data output port
Output<std::vector<TYPE>>* LD::getPortMFU0Vrf1Wdata() { 
	return mfu0_vrf1_wdata; 
}

// Getter function for MFU0 VRF1 write address output port
Output<unsigned int>* LD::getPortMFU0Vrf1Waddr() { 
	return mfu0_vrf1_waddr; 
}

// Getter function for MFU1 VRF0 write data output port
Output<std::vector<TYPE>>* LD::getPortMFU1Vrf0Wdata() { 
	return mfu1_vrf0_wdata; 
}

// Getter function for MFU1 VRF0 write address output port
Output<unsigned int>* LD::getPortMFU1Vrf0Waddr() { 
	return mfu1_vrf0_waddr; 
}

// Getter function for MFU1 VRF1 write data output port
Output<std::vector<TYPE>>* LD::getPortMFU1Vrf1Wdata() { 
	return mfu1_vrf1_wdata; 
}

// Getter function for MFU1 VRF1 write address output port
Output<unsigned int>* LD::getPortMFU1Vrf1Waddr() { 
	return mfu1_vrf1_waddr; 
}

// Getter function for MVU tag update output port
Output<bool>* LD::getPortUpdateMVU() { 
	return update_tag_mvu;  
}

// Getter function for eVRF tag update output port
Output<bool>* LD::getPortUpdateEvrf() { 
	return update_tag_evrf; 
}

// Getter function for MFU0 tag update output port
Output<bool>* LD::getPortUpdateMFU0() { 
	return update_tag_mfu0; 
}

// Getter function for MFU1 tag update output port
Output<bool>* LD::getPortUpdateMFU1() { 
	return update_tag_mfu1; 
}

// Getter function for Loader output port
Output<std::vector<TYPE>>* LD::getPortOutput() { 
	return ld_output; 
}

// Destructor
LD::~LD() {
	delete uOP;
    delete ld_input;
    for (unsigned int i = 0; i < mvu_vrfs_wdata.size(); i++) {
    	delete mvu_vrfs_wdata[i];
    	delete mvu_vrfs_waddr[i];
    }
    delete evrf_wdata;
	delete evrf_waddr;
    delete mfu0_vrf0_wdata;
    delete mfu0_vrf0_waddr;
    delete mfu0_vrf1_wdata;
    delete mfu0_vrf1_waddr;
    delete mfu1_vrf0_wdata;
    delete mfu1_vrf0_waddr;
    delete mfu1_vrf1_wdata;
    delete mfu1_vrf1_waddr;
    delete update_tag_mvu;
    delete update_tag_evrf;
    delete update_tag_mfu0;
    delete update_tag_mfu1;
    delete ld_output;
}