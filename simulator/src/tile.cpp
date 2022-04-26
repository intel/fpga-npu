#include "tile.h"

// MVU Tile Constructor
Tile::Tile(std::string t_name, unsigned int t_tile_id) : Module (t_name) {
    // Create Input and Output ports
    uOP = new Input<mvu_uOP>(t_name + "_uOP", this);

    // Initialize local variables
    tile_id = t_tile_id;
    accum_latency = RF_READ_LATENCY + MRF_TO_DPE_LATENCY 
        + 3 * (1 + LANES/10) + 2 + (unsigned int) (ceil(log2(LANES/10)) * DPE_ADDER_LATENCY) + 4;
    reg_sel_latency = RF_READ_LATENCY + MRF_TO_DPE_LATENCY;

    // Create internal modules & channels
    vrf = new MVUVRF(t_name + "_vrf", t_tile_id);
    vrf_wdata = vrf->getPortVrfWdata();
    vrf_waddr = vrf->getPortVrfWaddr();
    vrf_raddr = new Channel<unsigned int>(t_name + "_vrf_raddr", 1, 0);
    vrf_sel = new Channel<unsigned int>(t_name + "_vrf_sel", 1, 0);
    vrf->getPortVrfRaddr()->connectTo(vrf_raddr);
    vrf->getPortVrfSel()->connectTo(vrf_sel);

    for(unsigned int i = 0; i < DPES; i++){
        // Create channels for accumulation uOP
        Channel<unsigned int>* temp_accum_uOP = new Channel<unsigned int>(t_name + "_accum_uOP" +
            std::to_string(i), accum_latency, accum_latency);
        accum_uOP.push_back(temp_accum_uOP);
        Channel<unsigned int>* temp_accum_size = new Channel<unsigned int>(t_name+ "_accum_size" + 
            std::to_string(i), accum_latency, accum_latency);
        accum_size.push_back(temp_accum_size);

        // Create a DPE and its corresponding MRF
        DPE* d = new DPE(t_name + "_dpe" + std::to_string(i), i, t_tile_id);
		std::string file_name = "register_files/mrf_tile_"+
			std::to_string(t_tile_id)+"_dpe_"+std::to_string(i)+".txt";
        RegisterFile<std::vector<TYPE>> *m = new RegisterFile<std::vector<TYPE>> (t_name + 
            "_mrf" + std::to_string(i), MVU_MRF_DEPTH, &file_name);

        // Create channels for the MRF
        Channel<unsigned int>* temp_mrf_raddr = new Channel<unsigned int>
                (t_name + "_mrf" + std::to_string(i) + "_raddr", 1, 0);
        Channel<unsigned int>* temp_mrf_waddr = new Channel<unsigned int>
                (t_name + "_mrf" + std::to_string(i) + "_waddr", 1, 0);
        Channel<std::vector<TYPE>>* temp_mrf_wdata = new Channel<std::vector<TYPE>>
                (t_name + "_mrf" + std::to_string(i) + "_wdata", 1, 0);
        m->getPortRaddr()->connectTo(temp_mrf_raddr);
        m->getPortWaddr()->connectTo(temp_mrf_waddr);
        m->getPortWdata()->connectTo(temp_mrf_wdata);
        mrf_raddr.push_back(temp_mrf_raddr);
        mrf_waddr.push_back(temp_mrf_waddr);
        mrf_wdata.push_back(temp_mrf_wdata);

        // Create channels to connect each MRF to its corresponding DPE
        Channel<std::vector<TYPE>> *mrf_to_dpe = new Channel<std::vector<TYPE>>
            (t_name + "_mrf" + std::to_string(i) + "_to_dpe" + std::to_string(i), 
            MRF_TO_DPE_LATENCY, MRF_TO_DPE_LATENCY);
        m->getPortRdata()->connectTo(mrf_to_dpe);
        d->getPortVBroadcast()->connectTo(mrf_to_dpe);

        // Create channels to connect the tile VRF to each DPE
        Channel<std::vector<TYPE>>* vrf_to_dpe = new Channel<std::vector<TYPE>> (t_name + 
            "_vrf_to_d" + std::to_string(i), VRF_TO_DPE_LATENCY, VRF_TO_DPE_LATENCY-1);
        vrf->getPortVrfRdata()->connectTo(vrf_to_dpe);
        d->getPortVSeq()->connectTo(vrf_to_dpe);

        Channel<unsigned int>* dpe_reg_sel = new Channel<unsigned int>
            (t_name + "_vrf_to_d" + std::to_string(i), reg_sel_latency, reg_sel_latency);
        d->getPortRegSel()->connectTo(dpe_reg_sel);

        Channel<unsigned int> *dpe_vrf_en = new Channel<unsigned int>
            (t_name + "_vrf_to_d" + std::to_string(i), reg_sel_latency, reg_sel_latency);
        d->getPortVrfEn()->connectTo(dpe_vrf_en);

        // Populate the created modules and channels in the tile data structures
        mrfs.push_back(m);
        dpes.push_back(d);
        vrf_to_dpe_channels.push_back(vrf_to_dpe);
        mrf_to_dpe_channels.push_back(mrf_to_dpe);
        dpe_reg_sel_channels.push_back(dpe_reg_sel);
        dpe_vrf_en_channels.push_back(dpe_vrf_en);

        // Create channels to connect DPEs to the accumulators
        Channel<TYPE> *dpe_result0 = new Channel<TYPE>(t_name + "_dpe0_" + std::to_string(i) + 
            "_to_accum0_" + std::to_string(i), MVU_ACCUM_LATENCY, MVU_ACCUM_LATENCY);
        Channel<TYPE> *dpe_result1 = new Channel<TYPE>(t_name + "_dpe1_" + std::to_string(i) + 
            "_to_accum1_" + std::to_string(i), MVU_ACCUM_LATENCY, MVU_ACCUM_LATENCY);
        Channel<TYPE> *dpe_result2 = new Channel<TYPE>(t_name + "_dpe2_" + std::to_string(i) + 
            "_to_accum2_" + std::to_string(i), MVU_ACCUM_LATENCY, MVU_ACCUM_LATENCY);
        d->getPortDPERes(0)->connectTo(dpe_result0);
        d->getPortDPERes(1)->connectTo(dpe_result1);
        d->getPortDPERes(2)->connectTo(dpe_result2);
        accum0_channels.push_back(dpe_result0);
        accum1_channels.push_back(dpe_result1);
        accum2_channels.push_back(dpe_result2);

        // Create accumulators
        Accumulator* accum = new Accumulator(t_name + "_accum" + std::to_string(i), i);
        accum->getPortuOP()->connectTo(accum_uOP[i]);
        accum->getPortSize()->connectTo(accum_size[i]);
        accum->getPortInput(0)->connectTo(accum0_channels[i]);
        accum->getPortInput(1)->connectTo(accum1_channels[i]);
        accum->getPortInput(2)->connectTo(accum2_channels[i]);
        accums.push_back(accum);

        // Hook up the tile output ports to the DPE output ports
        accum0_results.push_back(accums[i]->getPortRes(0));
        accum1_results.push_back(accums[i]->getPortRes(1));
        accum2_results.push_back(accums[i]->getPortRes(2));
    }
}

// Clock cycle update function
void Tile::clock(){
    // If uOP is ready to dispatch
    if(!uOP->isChannelEmpty()) {
        // Peek ready uOP to decide how to proceed
        mvu_uOP micro_op = uOP->peekChannel();
        // If operation is valid and involved channels are clear
        if (!accum_uOP[0]->isFull() && !accum_size[0]->isFull() && !vrf_raddr->isFull() && 
            !mrf_raddr[0]->isFull() && micro_op.op == 1) {
            // Read out uOP and dispatch it
            micro_op = uOP->readFromChannel();
            vrf_raddr->write(micro_op.vrf_addr);
            vrf_sel->write(micro_op.vrf_sel);
            for (unsigned int i = 0; i < DPES; i++) {
                dpe_reg_sel_channels[i]->write(micro_op.reg_sel);
                dpe_vrf_en_channels[i]->write(micro_op.vrf_en);
                mrf_raddr[i]->write(micro_op.mrf_addr);
                accum_uOP[i]->write(micro_op.accum);
                accum_size[i]->write(micro_op.accum_size);
            }
        }
    }

    // Clock internal modules
    vrf->clock();
    for(unsigned int i = 0; i < DPES; i++){
        mrfs[i]->clock();
        dpes[i]->clock();
        accums[i]->clock();
    }

    // Clock internal channels
    vrf_raddr->clock();
    vrf_sel->clock();
    for(unsigned int i = 0; i < DPES; i++) {
        accum_uOP[i]->clock();
        accum_size[i]->clock();
        mrf_raddr[i]->clock();
        mrf_waddr[i]->clock();
        mrf_wdata[i]->clock();
        mrf_to_dpe_channels[i]->clock();
        vrf_to_dpe_channels[i]->clock();
        dpe_reg_sel_channels[i]->clock();
        dpe_vrf_en_channels[i]->clock();
        accum0_channels[i]->clock();
        accum1_channels[i]->clock();
        accum2_channels[i]->clock();
    }
}

// Getter function for VRF write data input port
Input<std::vector<TYPE>>* Tile::getPortVrfWdata() { 
    return vrf_wdata; 
}

// Getter function for VRF write address input port
Input<unsigned int>* Tile::getPortVrfWaddr() { 
    return vrf_waddr; 
}

// Getter function for uOP input port
Input<mvu_uOP>* Tile::getPortuOP() { 
    return uOP; 
}

// Getter function for Tile output port
Output<TYPE>* Tile::getPortResults(unsigned int accum, unsigned int idx) { 
    if(accum == 0)
        return accum0_results[idx]; 
    else if (accum == 1)
        return accum1_results[idx]; 
    else 
        return accum2_results[idx]; 
}

Tile::~Tile() {
    delete uOP;
    delete vrf_raddr;
    delete vrf_sel;
    delete vrf;
    for(unsigned int i = 0; i < DPES; i++) {
        delete mrfs[i];
        delete dpes[i];
        delete accums[i];
        delete dpe_reg_sel_channels[i];
        delete dpe_vrf_en_channels[i];
        delete accum_uOP[i];
        delete accum_size[i];
        delete accum0_channels[i];
        delete accum1_channels[i];
        delete accum2_channels[i];
    }
}