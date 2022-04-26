#include "mfu.h"

// Hyperbolic tangent activation function
void mfu_tanh(std::vector<TYPE> &v){
    for(unsigned i = 0; i < v.size(); i++){
        //v[i] = tanh(v[i]);
        v[i] = v[i]; //TODO: FIX WHENEVER TANH IS ADDED
    }
}

// Sigmoid activation function
void mfu_sigmoid(std::vector<TYPE> &v){
    for(unsigned i = 0; i < v.size(); i++){
        //v[i] = 1 / (1 + exp(-v[i]));
        v[i] = v[i]; //TODO: FIX WHENEVER SIGMOID IS ADDED
    }
}

// Rectified linear unit activation function
void mfu_relu(std::vector<TYPE> &v){
    for(unsigned i = 0; i < v.size(); i++){
        //v[i] = (v[i] > 0)? v[i]: 0;
        v[i] = v[i]; //TODO: FIX WHENEVER RELU IS ADDED
    }
}

// Element-wise addition
void mfu_add(std::vector<TYPE> &v1, std::vector<TYPE> &v2){
    assert((v1.size() == v2.size()) && "The two vectors have different lengths");
    for(unsigned i = 0; i < v1.size(); i++){
        v1[i] = v1[i] + v2[i];
    }
}

// Element-wise subtraction
void mfu_sub_ab(std::vector<TYPE> &v1, std::vector<TYPE> &v2){
    assert((v1.size() == v2.size()) && "The two vectors have different lengths");
    for(unsigned i = 0; i < v1.size(); i++){
        v1[i] = v1[i] - v2[i];
    }
}

// Swapped element-wise subtraction
void mfu_sub_ba(std::vector<TYPE> &v1, std::vector<TYPE> &v2){
    assert((v1.size() == v2.size()) && "The two vectors have different lengths");
    for(unsigned i = 0; i < v1.size(); i++){
        v1[i] = v2[i] - v1[i];
    }
}

// Element-wise multiplication
void mfu_mult(std::vector<TYPE> &v1, std::vector<TYPE> &v2){
    assert((v1.size() == v2.size()) && "The two vectors have different lengths");
    for(unsigned i = 0; i < v1.size(); i++){
        v1[i] = v1[i] * v2[i];
    }
}

// MFU constructor
MFU::MFU(std::string t_name) : Module (t_name) {
    // Create Input and Output ports
    mfu_input = new Input<std::vector<TYPE>>(t_name + "_input", this);
    uOP = new Input<mfu_uOP>(t_name + "_uOP", this);
    update_tag = new Input<bool>(t_name + "_update_tag", this);
    mfu_result = new Output<std::vector<TYPE>>(t_name + "_result", this);

    // Create internal modules
    vrf0 = new RegisterFile<std::vector<TYPE>>(t_name + "_vrf0", MFU_VRF0_DEPTH);
    vrf0_wdata = vrf0->getPortWdata();
    vrf0_waddr = vrf0->getPortWaddr();
    vrf1 = new RegisterFile<std::vector<TYPE>>(t_name + "_vrf1", MFU_VRF1_DEPTH);
    vrf1_wdata = vrf1->getPortWdata();
    vrf1_waddr = vrf1->getPortWaddr();

    // Create internal channels
    mfu_channel = new Channel<std::vector<TYPE>>(t_name + "_channel", MFU_LATENCY, MFU_LATENCY);
    vrf0_rdata_channel = new Channel<std::vector<TYPE>>(t_name + "_vrf0_rdata", 1, 0);
    vrf0->getPortRdata()->connectTo(vrf0_rdata_channel);
    vrf0_raddr_channel = new Channel<unsigned int>(t_name + "_vrf0_raddr", 1, 0);
    vrf0->getPortRaddr()->connectTo(vrf0_raddr_channel);
    vrf1_rdata_channel = new Channel<std::vector<TYPE>>(t_name + "_vrf1_rdata", 1, 0);
    vrf1->getPortRdata()->connectTo(vrf1_rdata_channel);
    vrf1_raddr_channel = new Channel<unsigned int>(t_name + "_vrf1_raddr", 1, 0);
    vrf1->getPortRaddr()->connectTo(vrf1_raddr_channel);
    uOP_channel = new Channel<mfu_uOP>(t_name + "_uOP_channel", RF_READ_LATENCY + 1, 
        RF_READ_LATENCY + 1);
    act_out_channel = new Channel<std::vector<TYPE>>(t_name + "_act_out", FIFO_DEPTH, 0);
    add_out_channel = new Channel<std::vector<TYPE>>(t_name + "_add_out", FIFO_DEPTH, 0);
    uOP_pipeline = new Channel<mfu_uOP>(t_name + "_uOP_pipeline", MFU_LATENCY, MFU_LATENCY);

    // Initialize local variables
    current_tag = 0;
}

// Clock cycle update function
void MFU::clock(unsigned int &cycle_count){
    // If a uOP is ready to dispatch
    if(!uOP->isChannelEmpty()){
        mfu_uOP temp = uOP->peekChannel();
        // If operation is NOP, read and ignore
		if (temp.op == 0) {
			temp = uOP->readFromChannel();	
            LOG(this->getName(), "NOP");
        // If valid operation and its tag is less than current tag
        } else if(!uOP_channel->isFull() && temp.tag <= current_tag){
            temp = uOP->readFromChannel();

            if((temp.add_op == 1) || (temp.add_op == 2) || (temp.add_op == 3)){
                vrf0_raddr_channel->write(temp.vrf0_addr);
            }

            if((temp.mul_op == 1) || (temp.mul_op == 3)){
                vrf1_raddr_channel->write(temp.vrf1_addr);
            }
            uOP_channel->write(temp);
        }
    }

    if(!mfu_channel->isFull() && !mfu_input->isChannelEmpty() && !uOP_channel->isEmpty()){
        // Peek uOP to decide how to proceed
        mfu_uOP temp = uOP_channel->peek();
        
        // If any of the possible operations needs to be executed
        if ( temp.act_op || 
            (temp.add_op && !vrf0_rdata_channel->isEmpty()) ||
            (temp.mul_op && !vrf1_rdata_channel->isEmpty())) {

            temp = uOP_channel->read();
            if (temp.first_flag) {
                LOG(this->getName(), "Issued first uOP " + std::to_string(temp.first_flag));
            }

            std::vector<TYPE> res = mfu_input->readFromChannel();

            // Activation Unit
            if (temp.act_op == 1) {
                mfu_tanh(res);
            } else if (temp.act_op == 2) {
                mfu_sigmoid(res);
            } else if (temp.act_op == 3) {
                mfu_relu(res);
            }

            // Addition Unit
            if (temp.add_op == 1) {
                std::vector<TYPE> vrf_rdata = vrf0_rdata_channel->read();
                mfu_add(res, vrf_rdata);
            } else if (temp.add_op == 2) {
                std::vector<TYPE> vrf_rdata = vrf0_rdata_channel->read();
                mfu_sub_ab(res, vrf_rdata);
            } else if (temp.add_op == 3) {
                std::vector<TYPE> vrf_rdata = vrf0_rdata_channel->read();
                mfu_sub_ba(res, vrf_rdata);
            }

            // Multiplication Unit
            if (temp.mul_op == 1) {
                std::vector<TYPE> vrf_rdata = vrf1_rdata_channel->read();
                mfu_mult(res, vrf_rdata);
            }

            // Insert the result into the delay queue
            mfu_channel->write(res);
            uOP_pipeline->write(temp);

        // If it is just a bypass 
        } else {
            temp = uOP_channel->read();
            if (temp.first_flag) {
                LOG(this->getName(), "Issued first uOP " + std::to_string(temp.first_flag));
            }

            std::vector<TYPE> res = mfu_input->readFromChannel();
            mfu_channel->write(res);
            uOP_pipeline->write(temp);
        }
        
    }

    // Output a result if ready
    if(!mfu_channel->isEmpty() && !uOP_pipeline->isEmpty()){
        mfu_result->writeToChannel(mfu_channel->read());
        LOG(this->getName(), "Produced Output");
        uOP_pipeline->read();
    }

    // Update local instruction tag
    if(!update_tag->isChannelEmpty()){
        update_tag->readFromChannel();
        current_tag++;
    }

    // Clock internal modules
    vrf0->clock();
    vrf1->clock();
    // Clock internal channels
    vrf0_raddr_channel->clock();
    vrf0_rdata_channel->clock();
    vrf1_raddr_channel->clock();
    vrf1_rdata_channel->clock();
    mfu_channel->clock();
    uOP_pipeline->clock();
    uOP_channel->clock();
}

// Getter function for name
std::string MFU::getName() { 
    return name; 
}

// Getter function for MFU input port
Input<std::vector<TYPE>>* MFU::getPortInput() { 
    return mfu_input; 
}

// Getter function for uOP input port
Input<mfu_uOP>* MFU::getPortuOP() { 
    return uOP; 
}

// Getter function for VRF0 write data input port
Input<std::vector<TYPE>>* MFU::getPortVrf0Wdata() { 
    return vrf0_wdata; 
}

// Getter function for VRF1 write data input port
Input<std::vector<TYPE>>* MFU::getPortVrf1Wdata() { 
    return vrf1_wdata; 
}

// Getter function for VRF0 write address input port
Input<unsigned int>* MFU::getPortVrf0Waddr() { 
    return vrf0_waddr; 
}

// Getter function for VRF1 write address input port
Input<unsigned int>* MFU::getPortVrf1Waddr() { 
    return vrf1_waddr; 
}

// Getter function for tag update input port
Input<bool>* MFU::getPortUpdateTag() { 
    return update_tag; 
}

// Getter function for MFU output port
Output<std::vector<TYPE>>* MFU::getPortRes() { 
    return mfu_result; 
}

MFU::~MFU() {
    delete mfu_input;
    delete uOP;
    delete update_tag;
    delete mfu_result;
    delete vrf0;
    delete vrf1;
    delete mfu_channel;
    delete vrf0_rdata_channel;
    delete vrf0_raddr_channel;
    delete vrf1_rdata_channel;
    delete vrf1_raddr_channel;
    delete uOP_channel;
    delete act_out_channel;
    delete add_out_channel;
    delete uOP_pipeline;
}