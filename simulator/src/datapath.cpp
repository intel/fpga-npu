#include "datapath.h"

// Datapath constructor
Datapath::Datapath(std::string t_name) : Module (t_name) {
    // Create MVU
    mvu = new MVU(t_name+"_mvu");
    mvu_uOP_port = mvu->getPortuOP();
    mvu_to_evrf_channel = new Channel<std::vector<TYPE>>(t_name+"_mvu_to_evrf", FIFO_DEPTH, 1);
    mvu->getPortRes()->connectTo(mvu_to_evrf_channel);

    // Create EVRF
    evrf = new EVRF(t_name+"_evrf");
    evrf_uOP_port = evrf->getPortuOP();
    evrf->getPortInput()->connectTo(mvu_to_evrf_channel);
    evrf_to_mfu0_channel = new Channel<std::vector<TYPE>>(t_name+"_evrf_to_mfu0", FIFO_DEPTH, 1);
    evrf->getPortRes()->connectTo(evrf_to_mfu0_channel);

    // Create MFU0
    mfu0 = new MFU(t_name+"_mfu0");
    mfu0_uOP_port = mfu0->getPortuOP();
    mfu0->getPortInput()->connectTo(evrf_to_mfu0_channel);
    mfu0_to_mfu1_channel = new Channel<std::vector<TYPE>>(t_name+"_mfu0_to_mfu1", FIFO_DEPTH, 1);
    mfu0->getPortRes()->connectTo(mfu0_to_mfu1_channel);

    // Create MFU1
    mfu1 = new MFU(t_name+"_mfu1");
    mfu1_uOP_port = mfu1->getPortuOP();
    mfu1->getPortInput()->connectTo(mfu0_to_mfu1_channel);
    mfu1_to_ld_channel = new Channel<std::vector<TYPE>>(t_name+"_mfu1_to_ld", FIFO_DEPTH, 1);
    mfu1->getPortRes()->connectTo(mfu1_to_ld_channel);

    // Create Loader
    ld = new LD(t_name+"_ld");
    ld_uOP_port = ld->getPortuOP();
    ld->getPortInput()->connectTo(mfu1_to_ld_channel);
    datapath_output = ld->getPortOutput();

    // Connect Loader to MVU
    for(unsigned int i = 0; i < TILES; i++){
        Channel<std::vector<TYPE>> *ld_to_mvu_wdata = new Channel<std::vector<TYPE>>(t_name +
            "_wdata_ld_to_tile" + std::to_string(i), FIFO_DEPTH, LD_WB_LATENCY);
        Channel<unsigned int> *ld_to_mvu_waddr = new Channel<unsigned int>(t_name +
            "_waddr_ld_to_tile" + std::to_string(i), FIFO_DEPTH, LD_WB_LATENCY);
        mvu->getPortVrfWdata(i)->connectTo(ld_to_mvu_wdata);
        mvu->getPortVrfWaddr(i)->connectTo(ld_to_mvu_waddr);
        ld->getPortMVUWdata(i)->connectTo(ld_to_mvu_wdata);
        ld->getPortMVUWaddr(i)->connectTo(ld_to_mvu_waddr);
        ld_to_mvu_wdata_channels.push_back(ld_to_mvu_wdata);
        ld_to_mvu_waddr_channels.push_back(ld_to_mvu_waddr);
    }
    ld_to_mvu_update_channel = new Channel<bool>(t_name + "_update_ld_to_mvu", FIFO_DEPTH, 
        LD_WB_LATENCY + 2);
    ld->getPortUpdateMVU()->connectTo(ld_to_mvu_update_channel);
    mvu->getPortUpdateTag()->connectTo(ld_to_mvu_update_channel);

    // Connect Loader to eVRF
    ld_to_evrf_wdata_channel = new Channel<std::vector<TYPE>>(t_name + "_wdata_ld_to_evrf", 
        FIFO_DEPTH, LD_WB_LATENCY);
    evrf->getPortEvrfWdata()->connectTo(ld_to_evrf_wdata_channel);
    ld->getPortEvrfWdata()->connectTo(ld_to_evrf_wdata_channel);
    ld_to_evrf_waddr_channel = new Channel<unsigned int>(t_name + "_waddr_ld_to_evrf", 
        FIFO_DEPTH, LD_WB_LATENCY);
    evrf->getPortEvrfWaddr()->connectTo(ld_to_evrf_waddr_channel);
    ld->getPortEvrfWaddr()->connectTo(ld_to_evrf_waddr_channel);
    ld_to_evrf_update_channel = new Channel<bool>(t_name + "_update_ld_to_evrf", FIFO_DEPTH, 
        LD_WB_LATENCY + 2);
    evrf->getPortUpdateTag()->connectTo(ld_to_evrf_update_channel);
    ld->getPortUpdateEvrf()->connectTo(ld_to_evrf_update_channel);

    // Connect Loader to MFU0
    ld_to_mfu0_vrf0_wdata_channel = new Channel<std::vector<TYPE>>(t_name+"_wdata_ld_to_mfu0_vrf0",
        LD_WB_LATENCY, LD_WB_LATENCY);
    mfu0->getPortVrf0Wdata()->connectTo(ld_to_mfu0_vrf0_wdata_channel);
    ld->getPortMFU0Vrf0Wdata()->connectTo(ld_to_mfu0_vrf0_wdata_channel);
    ld_to_mfu0_vrf1_wdata_channel = new Channel<std::vector<TYPE>>(t_name+"_wdata_ld_to_mfu0_vrf1",
        FIFO_DEPTH, LD_WB_LATENCY);
    mfu0->getPortVrf1Wdata()->connectTo(ld_to_mfu0_vrf1_wdata_channel);
    ld->getPortMFU0Vrf1Wdata()->connectTo(ld_to_mfu0_vrf1_wdata_channel);
    ld_to_mfu0_vrf0_waddr_channel = new Channel<unsigned int>(t_name+"_waddr_ld_to_mfu0_vrf0",
        FIFO_DEPTH, LD_WB_LATENCY);
    mfu0->getPortVrf0Waddr()->connectTo(ld_to_mfu0_vrf0_waddr_channel);
    ld->getPortMFU0Vrf0Waddr()->connectTo(ld_to_mfu0_vrf0_waddr_channel);
    ld_to_mfu0_vrf1_waddr_channel = new Channel<unsigned int>(t_name+"_waddr_ld_to_mfu0_vrf1",
        FIFO_DEPTH, LD_WB_LATENCY);
    mfu0->getPortVrf1Waddr()->connectTo(ld_to_mfu0_vrf1_waddr_channel);
    ld->getPortMFU0Vrf1Waddr()->connectTo(ld_to_mfu0_vrf1_waddr_channel);
    ld_to_mfu0_update_channel = new Channel<bool>(t_name+"_update_ld_to_mfu0", 
        FIFO_DEPTH, LD_WB_LATENCY + 2);
    mfu0->getPortUpdateTag()->connectTo(ld_to_mfu0_update_channel);
    ld->getPortUpdateMFU0()->connectTo(ld_to_mfu0_update_channel);

    // Connect Loader to MFU1
    ld_to_mfu1_vrf0_wdata_channel = new Channel<std::vector<TYPE>>(t_name+"_wdata_ld_to_mfu1_vrf0",
        FIFO_DEPTH, LD_WB_LATENCY);
    mfu1->getPortVrf0Wdata()->connectTo(ld_to_mfu1_vrf0_wdata_channel);
    ld->getPortMFU1Vrf0Wdata()->connectTo(ld_to_mfu1_vrf0_wdata_channel);
    ld_to_mfu1_vrf1_wdata_channel = new Channel<std::vector<TYPE>>(t_name+"_wdata_ld_to_mfu1_vrf1",
        FIFO_DEPTH, LD_WB_LATENCY);
    mfu1->getPortVrf1Wdata()->connectTo(ld_to_mfu1_vrf1_wdata_channel);
    ld->getPortMFU1Vrf1Wdata()->connectTo(ld_to_mfu1_vrf1_wdata_channel);
    ld_to_mfu1_vrf0_waddr_channel = new Channel<unsigned int>(t_name+"_waddr_ld_to_mfu1_vrf0",
        FIFO_DEPTH, LD_WB_LATENCY);
    mfu1->getPortVrf0Waddr()->connectTo(ld_to_mfu1_vrf0_waddr_channel);
    ld->getPortMFU1Vrf0Waddr()->connectTo(ld_to_mfu1_vrf0_waddr_channel);
    ld_to_mfu1_vrf1_waddr_channel = new Channel<unsigned int>(t_name+"_waddr_ld_to_mfu1_vrf1",
        FIFO_DEPTH, LD_WB_LATENCY);
    mfu1->getPortVrf1Waddr()->connectTo(ld_to_mfu1_vrf1_waddr_channel);
    ld->getPortMFU1Vrf1Waddr()->connectTo(ld_to_mfu1_vrf1_waddr_channel);
    ld_to_mfu1_update_channel = new Channel<bool>(t_name+"_update_ld_to_mfu1", 
        FIFO_DEPTH, LD_WB_LATENCY + 2);
    mfu1->getPortUpdateTag()->connectTo(ld_to_mfu1_update_channel);
    ld->getPortUpdateMFU1()->connectTo(ld_to_mfu1_update_channel);
}

// Clock cycle update function
void Datapath::clock(unsigned int &cycle_count){
    // Clock internal modules
    mvu->clock(cycle_count);
    evrf->clock(cycle_count);
    mfu0->clock(cycle_count);
    mfu1->clock(cycle_count);
    ld->clock(cycle_count);
    // Clock Internal channels
    mvu_to_evrf_channel->clock();
    evrf_to_mfu0_channel->clock();
    mfu0_to_mfu1_channel->clock();
    mfu1_to_ld_channel->clock();
    for(unsigned int i = 0; i < TILES; i ++){
        ld_to_mvu_wdata_channels[i]->clock();
        ld_to_mvu_waddr_channels[i]->clock();
    }
    ld_to_mvu_update_channel->clock();
    ld_to_evrf_wdata_channel->clock();
    ld_to_evrf_waddr_channel->clock();
    ld_to_evrf_update_channel->clock();
    ld_to_mfu0_vrf0_wdata_channel->clock();
    ld_to_mfu0_vrf1_wdata_channel->clock();
    ld_to_mfu0_vrf0_waddr_channel->clock();
    ld_to_mfu0_vrf1_waddr_channel->clock();
    ld_to_mfu0_update_channel->clock();
    ld_to_mfu1_vrf0_wdata_channel->clock();
    ld_to_mfu1_vrf1_wdata_channel->clock();
    ld_to_mfu1_vrf0_waddr_channel->clock();
    ld_to_mfu1_vrf1_waddr_channel->clock();
    ld_to_mfu1_update_channel->clock();
}

// Getter function for MVU uOP port
Input<mvu_uOP>* Datapath::getPortMVUuOP() { 
    return mvu_uOP_port; 
}

// Getter function for eVRF uOP port
Input<evrf_uOP>* Datapath::getPortEVRFuOP() { 
    return evrf_uOP_port; 
}

// Getter function for MFU0 uOP port
Input<mfu_uOP>* Datapath::getPortMFU0uOP() { 
    return mfu0_uOP_port; 
}

// Getter function for MFU1 uOP port
Input<mfu_uOP>* Datapath::getPortMFU1uOP() { 
    return mfu1_uOP_port; 
}

// Getter function for Loader uOP port
Input<ld_uOP>* Datapath::getPortLDuOP() { 
    return ld_uOP_port; 
}

// Getter function for datapath output port
Output<std::vector<TYPE>>* Datapath::getPortOutput() { 
    return datapath_output; 
}

Datapath::~Datapath() {
    delete mvu; 
    delete evrf; 
    delete mfu0; 
    delete mfu1; 
    delete ld;
    delete mvu_to_evrf_channel;
    delete evrf_to_mfu0_channel;
    delete mfu0_to_mfu1_channel;
    delete mfu1_to_ld_channel;
    for (unsigned int i = 0; i < ld_to_mvu_wdata_channels.size(); i++){
        delete ld_to_mvu_wdata_channels[i];
        delete ld_to_mvu_waddr_channels[i];
    }
    delete ld_to_mvu_update_channel;
    delete ld_to_evrf_wdata_channel;
    delete ld_to_evrf_waddr_channel;
    delete ld_to_evrf_update_channel;
    delete ld_to_mfu0_vrf0_wdata_channel;
    delete ld_to_mfu0_vrf1_wdata_channel;
    delete ld_to_mfu0_vrf0_waddr_channel;
    delete ld_to_mfu0_vrf1_waddr_channel;
    delete ld_to_mfu0_update_channel;
    delete ld_to_mfu1_vrf0_wdata_channel;
    delete ld_to_mfu1_vrf1_wdata_channel;
    delete ld_to_mfu1_vrf0_waddr_channel;
    delete ld_to_mfu1_vrf1_waddr_channel;
    delete ld_to_mfu1_update_channel;
}