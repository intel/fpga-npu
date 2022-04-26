#include "mvu.h"

// MVU Constructor
MVU::MVU(std::string t_name) : Module (t_name) {
    // Create Input and Output ports
    update_tag = new Input<bool>(t_name + "_update_tag", this);
    uOP = new Input<mvu_uOP>(t_name + "_uOP", this);
    mvu_results = new Output<std::vector<TYPE>>(t_name + "_results", this);

    // Create internal modules
    for(unsigned int i = 0; i < TILES; i++){
        Tile* mvu_tile = new Tile(t_name+"_tile"+std::to_string(i), i);
        mvu_tiles.push_back(mvu_tile);
        vrfs_wdata.push_back(mvu_tile->getPortVrfWdata());
        vrfs_waddr.push_back(mvu_tile->getPortVrfWaddr());

        Channel<mvu_uOP>* uOP_channel = new Channel<mvu_uOP>(t_name+"_uOP" + std::to_string(i), 
            1, 0);
        uOP_channels.push_back(uOP_channel);
        mvu_tile->getPortuOP()->connectTo(uOP_channels[i]);

        std::vector<Channel<TYPE>*> temp_tile_results0, temp_tile_results1, temp_tile_results2;
        for(unsigned int j = 0; j < DPES; j++){
            Channel<TYPE> *temp0 = new Channel<TYPE>(t_name + "_tile" + std::to_string(i) + 
                "_result0", 1, 0);
            Channel<TYPE> *temp1 = new Channel<TYPE>(t_name + "_tile" + std::to_string(i) + 
                "_result1", 1, 0);
            Channel<TYPE> *temp2 = new Channel<TYPE>(t_name + "_tile" + std::to_string(i) + 
                "_result2", 1, 0);
            mvu_tile->getPortResults(0, j)->connectTo(temp0);
            mvu_tile->getPortResults(1, j)->connectTo(temp1);
            mvu_tile->getPortResults(2, j)->connectTo(temp2);
            temp_tile_results0.push_back(temp0);
            temp_tile_results1.push_back(temp1);
            temp_tile_results2.push_back(temp2);
        }
        tile_results0.push_back(temp_tile_results0);
        tile_results1.push_back(temp_tile_results1);
        tile_results2.push_back(temp_tile_results2);
    }

    // Create internal channels
    reduction_channel0 = new Channel<std::vector<TYPE>>(t_name + "_reduction0",
            MVU_REDUCTION_LATENCY, MVU_REDUCTION_LATENCY-1);
    reduction_channel1 = new Channel<std::vector<TYPE>>(t_name + "_reduction1",
            MVU_REDUCTION_LATENCY, MVU_REDUCTION_LATENCY-1);
    reduction_channel2 = new Channel<std::vector<TYPE>>(t_name + "_reduction2",
            MVU_REDUCTION_LATENCY, MVU_REDUCTION_LATENCY-1);

    // Initialize local variables
    current_tag = 0;
}

// Clock cycle update function
void MVU::clock(unsigned int &cycle_count){
    // If uOP is ready to dispatch
    if(!uOP->isChannelEmpty()) {
        // Peek ready uOP to decide how to proceed
        mvu_uOP temp = uOP->peekChannel();

        // If ready operation is NOP, read and ignore
		if (temp.op == 0) {
            temp = uOP->readFromChannel();
            LOG(this->getName(), "NOP");

        // If ready operation is not NOP, read and dispatch
        } else if (!uOP->isChannelEmpty() && temp.tag <= current_tag && 
            !uOP_channels[0]->isFull()) {
            temp = uOP->readFromChannel();
            if(temp.first_flag){
                LOG(this->getName(), "Issued first uOP " + std::to_string(temp.first_flag/3));
            }
            for (unsigned int i = 0; i < TILES; i++) {
                uOP_channels[i]->write(temp);
            }
        }
    }

    // Perform reduction of corresponding DPEs from different tiles
    if((!tile_results0[0][0]->isEmpty()) && (!reduction_channel0->isFull())){
        std::vector<TYPE> partial_results0(DPES);
        std::vector<TYPE> partial_results1(DPES);
        std::vector<TYPE> partial_results2(DPES);
        for(unsigned int i = 0; i < TILES; i++){
            for(unsigned int j = 0; j < DPES; j++){
                partial_results0[j] += tile_results0[i][j]->read();
                partial_results1[j] += tile_results1[i][j]->read();
                partial_results2[j] += tile_results2[i][j]->read();
            }
        }
        reduction_channel0->write(partial_results0);
        reduction_channel1->write(partial_results1);
        reduction_channel2->write(partial_results2);
    }

    // Write MVU output when ready
    if((!reduction_channel0->isEmpty()) && (!mvu_results->isChannelFull())){
        // Read reduction result
        std::vector<TYPE> mvu_res_vec0 = reduction_channel0->read();
        std::vector<TYPE> mvu_res_vec1 = reduction_channel1->read();
        std::vector<TYPE> mvu_res_vec2 = reduction_channel2->read();
        // Reshape it from vectors of length DPES to vectors of length LANES (Asymmetric FIFO)
        for(unsigned int i = 0; i < (DPES/LANES); i++){
            std::vector<TYPE> mvu_res_part0, mvu_res_part1, mvu_res_part2;
            for(unsigned int j = 0; j < LANES; j++){
                mvu_res_part0.push_back(mvu_res_vec0[0]);
                mvu_res_part1.push_back(mvu_res_vec1[0]);
                mvu_res_part2.push_back(mvu_res_vec2[0]);
                mvu_res_vec0.erase(mvu_res_vec0.begin());
                mvu_res_vec1.erase(mvu_res_vec1.begin());
                mvu_res_vec2.erase(mvu_res_vec2.begin());
            }
            mvu_results->writeToChannel(mvu_res_part0);
            mvu_results->writeToChannel(mvu_res_part1);
            mvu_results->writeToChannel(mvu_res_part2);
            LOG(this->getName(), "Produced Output");
			#if(VERBOSE_MVU)
	            std::cout << "MVU OUTPUT0: " << mvu_res_part0 << std::endl;
                std::cout << "MVU OUTPUT1: " << mvu_res_part1 << std::endl;
                std::cout << "MVU OUTPUT2: " << mvu_res_part2 << std::endl;
			#endif
        }
    }

    // Update local instruction tag (if required)
    if(!update_tag->isChannelEmpty()){
        update_tag->readFromChannel();
        current_tag++;
    }

    // Clock internal modules
    for(unsigned int i = 0; i < TILES; i++){
        mvu_tiles[i]->clock();
    }
    // Clock internal channels
    for(unsigned int i = 0; i < TILES; i++){
        uOP_channels[i]->clock();
    }
    reduction_channel0->clock();
    reduction_channel1->clock();
    reduction_channel2->clock();
}

// Getter function for name
std::string MVU::getName() { 
    return name; 
}

// Getter function for VRF write data input port
Input<std::vector<TYPE>>* MVU::getPortVrfWdata(unsigned int idx) { 
    return vrfs_wdata[idx]; 
}

// Getter function for VRF write address input port
Input<unsigned int>* MVU::getPortVrfWaddr(unsigned int idx) { 
    return vrfs_waddr[idx]; 
}

// Getter function for uOP input port
Input<mvu_uOP>* MVU::getPortuOP() { 
    return uOP; 
}

// Getter function for update tag input port
Input<bool>* MVU::getPortUpdateTag() { 
    return update_tag; 
}

// Getter function for MVU output port
Output<std::vector<TYPE>>* MVU::getPortRes() { 
    return mvu_results; 
}

MVU::~MVU() {
    delete uOP;
    delete update_tag;
    delete mvu_results;
    for (unsigned int i = 0; i < TILES; i++) {
        delete mvu_tiles[i];
        delete uOP_channels[i];
        for (unsigned int j = 0; j < DPES; j++) {
            delete tile_results0[i][j];
            delete tile_results1[i][j];
            delete tile_results2[i][j];
        }   
    }
    delete reduction_channel0;
    delete reduction_channel1;
    delete reduction_channel2;
}