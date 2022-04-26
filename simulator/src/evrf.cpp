#include "evrf.h"

// eVRF Constructor
EVRF::EVRF(std::string t_name) : Module (t_name) {
    // Create Input and Output ports
    evrf_input = new Input<std::vector<TYPE>>(t_name + "_input", this);
    uOP = new Input<evrf_uOP>(t_name + "_uOP", this);
    update_tag = new Input<bool>(t_name + "_update_tag", this);
    evrf_result = new Output<std::vector<TYPE>>(t_name + "_result", this);

    // Create internal modules
    evrf = new RegisterFile<std::vector<TYPE>>(t_name, EVRF_DEPTH);
    evrf_wdata = evrf->getPortWdata();
    evrf_waddr = evrf->getPortWaddr();

    // Create internal channels
    mvu_channel = new Channel<std::vector<TYPE>>(t_name + "_mvu_channel", 
        RF_READ_LATENCY + 1, RF_READ_LATENCY + 1);
    evrf_raddr = new Channel<unsigned int>(t_name + "_evrf_raddr", 1, 0);
    evrf->getPortRaddr()->connectTo(evrf_raddr);
    evrf_rdata = new Channel<std::vector<TYPE>>(t_name + "_evrf_rdata", 1, 0);
    evrf->getPortRdata()->connectTo(evrf_rdata);

    // Initialize local variables
    current_tag = 0;
}

// Clock cycle update function
void EVRF::clock(unsigned int &cycle_count){
    // If uOP is ready to dispatch
    if(!uOP->isChannelEmpty()){
        // Peek ready uOP to decide how to proceed
        evrf_uOP temp = uOP->peekChannel();
        // If ready operation is NOP, read and ignore
		if (temp.op == 0) {
            temp = uOP->readFromChannel();
            LOG(this->getName(), "NOP");

        // If ready operation is flush
        } else if (temp.op == 2 && !evrf_input->isChannelEmpty() && temp.tag <= current_tag) {
            evrf_input->readFromChannel();

        // If ready operation is bypass
        } else if(!temp.src && !mvu_channel->isFull() && !evrf_input->isChannelEmpty() && 
            temp.tag <= current_tag){
            mvu_channel->write(evrf_input->readFromChannel());
            temp = uOP->readFromChannel();
            if(temp.first_flag) {
                LOG(this->getName(), "Issued first uOP " + std::to_string(temp.first_flag));
            }

        // If ready operation is read eVRF
        } else if (temp.src && !evrf_rdata->isFull() && temp.tag <= current_tag) {
            evrf_raddr->write(temp.vrf_addr);
            temp = uOP->readFromChannel();
            if(temp.first_flag) {
                LOG(this->getName(), "Issued first uOP " + std::to_string(temp.first_flag));
            }
        }
    }

    // Write eVRF output when ready
    if(!mvu_channel->isEmpty()){
        evrf_result->writeToChannel(mvu_channel->read());
        LOG(this->getName(), "Produced Output");
    } else if (!evrf_rdata->isEmpty()){
        evrf_result->writeToChannel(evrf_rdata->read());
        LOG(this->getName(), "Produced Output");
    }

    // Update local instruction tag (if required)
    if(!update_tag->isChannelEmpty()){
        update_tag->readFromChannel();
        current_tag++;
    }

    // Clock internal modules
    evrf->clock();
    // Clock internal channels
    evrf_raddr->clock();
    evrf_rdata->clock();
    mvu_channel->clock();
}

// Getter function for name
std::string EVRF::getName() { 
    return name; 
}

// Getter function for eVRF input port
Input<std::vector<TYPE>>* EVRF::getPortInput() { 
    return evrf_input; 
}

// Getter function for uOP input port
Input<evrf_uOP>* EVRF::getPortuOP() { 
    return uOP; 
}

// Getter function for eVRF write data input port
Input<std::vector<TYPE>>* EVRF::getPortEvrfWdata() { 
    return evrf_wdata; 
}

// Getter function for eVRF write address input port
Input<unsigned int>* EVRF::getPortEvrfWaddr() { 
    return evrf_waddr; 
}

// Getter function for update tag inputy port
Input<bool>* EVRF::getPortUpdateTag() { 
    return update_tag; 
}

// Getter function for eVRF output port
Output<std::vector<TYPE>>* EVRF::getPortRes() { 
    return evrf_result; 
}

EVRF::~EVRF() {
    delete evrf_input;
    delete uOP;
    delete update_tag;
    delete evrf_result;
    delete evrf;
    delete mvu_channel;
    delete evrf_raddr;
    delete evrf_rdata;
}