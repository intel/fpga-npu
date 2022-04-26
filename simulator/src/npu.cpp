#include "npu.h"

// NPU constructor
NPU::NPU(std::string t_name) : Module(t_name) {
    // Create channels for the micro-OPs to connect between datapath and instruction decoders
    mvu_uOP_channel  = new Channel<mvu_uOP>(t_name+"_mvu_uOP", FIFO_DEPTH, 1);
    evrf_uOP_channel = new Channel<evrf_uOP>(t_name+"_evrf_uOP", FIFO_DEPTH, 1);
    mfu0_uOP_channel = new Channel<mfu_uOP>(t_name+"_mfu0_uOP", FIFO_DEPTH, 1);
    mfu1_uOP_channel = new Channel<mfu_uOP>(t_name+"_mfu1_uOP", FIFO_DEPTH, 1);
    ld_uOP_channel   = new Channel<ld_uOP>(t_name+"_ld_uOP", FIFO_DEPTH, 1);

    // Create NPU datapath and connect input uOP ports to channels
    npu_datapath = new Datapath(t_name);
    npu_datapath->getPortMVUuOP()->connectTo(mvu_uOP_channel);
    npu_datapath->getPortEVRFuOP()->connectTo(evrf_uOP_channel);
    npu_datapath->getPortMFU0uOP()->connectTo(mfu0_uOP_channel);
    npu_datapath->getPortMFU1uOP()->connectTo(mfu1_uOP_channel);
    npu_datapath->getPortLDuOP()->connectTo(ld_uOP_channel);

    // Create NPU instruction decoder and connect output uOP ports to channels
    npu_decoders = new Decoder(t_name+"_decoder");
    npu_decoders->getPortMVUuOP()->connectTo(mvu_uOP_channel);
    npu_decoders->getPortEVRFuOP()->connectTo(evrf_uOP_channel);
    npu_decoders->getPortMFU0uOP()->connectTo(mfu0_uOP_channel);
    npu_decoders->getPortMFU1uOP()->connectTo(mfu1_uOP_channel);
    npu_decoders->getPortLDuOP()->connectTo(ld_uOP_channel);

    // Connect NPU input and output ports
    npu_inst = npu_decoders->getPortInputVLIW();
    npu_output = npu_datapath->getPortOutput();
}

// Clock cycle update function
void NPU::clock(unsigned int &cycle_count) {
    npu_datapath->clock(cycle_count);
    npu_decoders->clock(cycle_count);

    mvu_uOP_channel->clock();
    evrf_uOP_channel->clock();
    mfu0_uOP_channel->clock();
    mfu1_uOP_channel->clock();
    ld_uOP_channel->clock();
}

// Getter function for name
std::string NPU::getName() { 
    return name; 
}

// Getter function for instruction port
Input<npu_instruction>* NPU::getPortInst() { 
    return npu_inst; 
}

// Getter function for output port
Output<std::vector<TYPE>>* NPU::getPortOutput() { 
    return npu_output; 
}

NPU::~NPU(){
    delete npu_datapath;
    delete npu_decoders;
    delete mvu_uOP_channel;
    delete evrf_uOP_channel;
    delete mfu0_uOP_channel;
    delete mfu1_uOP_channel;
    delete ld_uOP_channel;
}