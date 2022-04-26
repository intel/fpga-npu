#include "decoder.h"

// Decoder constructor
Decoder::Decoder(std::string t_name) : Module (t_name) {
    // Create input and output ports
    vliw = new Input<npu_instruction> (t_name+"_vliw", this);
    mvu_uOP_port  = new Output<mvu_uOP> (t_name+"_mvu_uOP" , this);
    evrf_uOP_port = new Output<evrf_uOP>(t_name+"_evrf_uOP", this);
    mfu0_uOP_port = new Output<mfu_uOP> (t_name+"_mfu0_uOP", this);
    mfu1_uOP_port = new Output<mfu_uOP> (t_name+"_mfu1_uOP", this);
    ld_uOP_port   = new Output<ld_uOP>  (t_name+"_ld_uOP"  , this);

    // Create internal channels
    mvu_mOP_channel  = new Channel<mvu_mOP> (t_name+"_mvu_mOP", FIFO_DEPTH, 1);
    evrf_mOP_channel = new Channel<evrf_mOP> (t_name+"_evrf_mOP", FIFO_DEPTH, 1);
    mfu0_mOP_channel = new Channel<mfu_mOP> (t_name+"_mfu0_mOP", FIFO_DEPTH, 1);
    mfu1_mOP_channel = new Channel<mfu_mOP> (t_name+"_mfu1_mOP", FIFO_DEPTH, 1);
    ld_mOP_channel   = new Channel<ld_mOP> (t_name+"_ld_mOP", FIFO_DEPTH, 1);

    // InitialiZe local variables
    ld_counter = 0; 
    ld_batch_counter = 0;
    mvu_counter = 0;
    mvu_pipeline_counter = 0;
    mvu_chunk_counter = 0;
    reg_sel_flag = 0;
    remaining_rows = -1;
    acc_size = 0;
    evrf_counter = 0;
    evrf_batch_counter = 0;
    mfu0_counter = 0;
    mfu0_batch_counter = 0;
    mfu1_counter = 0;
    mfu1_batch_counter = 0;
    decoding_mvu = false;
    decoding_evrf = false;
    decoding_mfu0 = false;
    decoding_mfu1 = false;
    decoding_ld = false;
}

// Clock cycle update function
void Decoder::clock(unsigned int &cycle_count){
    /*************************************** VLIW Dispatch ****************************************/

    // If a new VLIW is ready dispatch to low level decoders
    if(!mvu_mOP_channel->isFull() && !evrf_mOP_channel->isFull() && !mfu0_mOP_channel->isFull() && 
       !mfu1_mOP_channel->isFull() && !ld_mOP_channel->isFull() && !vliw->isChannelEmpty()){
        // Read VLIW instruction
        inst = vliw->readFromChannel();
        // Write mOPs to internal channels
        mvu_mOP_channel->write(inst.mvu_inst);
        evrf_mOP_channel->write(inst.evrf_inst);
        mfu0_mOP_channel->write(inst.mfu0_inst);
        mfu1_mOP_channel->write(inst.mfu1_inst);
        ld_mOP_channel->write(inst.ld_inst);
    }

    /**********************************************************************************************/

    /*************************************** mOPs Dispatch ****************************************/

    // Dispatch MVU mOP for decoding
    if(!mvu_mOP_channel->isEmpty() && !decoding_mvu && !mvu_uOP_port->isChannelFull()){
        m1 = mvu_mOP_channel->read();
        if (m1.op != 0) {
            #if(VERBOSE_OP)
            m1.print(cycle_count);
            #endif
        } else {
            u1.op = m1.op;
            mvu_uOP_port->writeToChannel(u1);
        }
        decoding_mvu  = (m1.op != 0);
    }

    // Dispatch eVRF mOP for decoding
    if(!evrf_mOP_channel->isEmpty() && !decoding_evrf && !evrf_uOP_port->isChannelFull()){
        m2 = evrf_mOP_channel->read();
        if (m2.op != 0) {
            #if(VERBOSE_OP)
            m2.print( cycle_count);
            #endif
        } else {
            u2.op = m2.op;
            evrf_uOP_port->writeToChannel(u2);
        }
        decoding_evrf = (m2.op != 0);
    }

    // Dispatch MFU0 mOP for decoding
    if(!mfu0_mOP_channel->isEmpty() && !decoding_mfu0 && !mfu0_uOP_port->isChannelFull()){
        m3 = mfu0_mOP_channel->read();
        if (m3.op != 0) {
            #if(VERBOSE_OP==1)
            m3.print( cycle_count);
            #endif
        } else {
            u3.op = m3.op;
            mfu0_uOP_port->writeToChannel(u3);
        }
        decoding_mfu0 = (m3.op != 0);
    }

    // Dispatch MFU1 mOP for decoding
    if(!mfu1_mOP_channel->isEmpty() && !decoding_mfu1 && !mfu1_uOP_port->isChannelFull()){
        m4 = mfu1_mOP_channel->read();
        if (m4.op != 0) {
            #if(VERBOSE_OP==1)
            m4.print( cycle_count);
            #endif
        } else {
            u4.op = m4.op;
            mfu1_uOP_port->writeToChannel(u4);
        }
        decoding_mfu1 = (m4.op != 0);
    }

    // Dispatch Loader mOP for decoding
    if(!ld_mOP_channel->isEmpty() && !decoding_ld && !ld_uOP_port->isChannelFull()){
        m5 = ld_mOP_channel->read();
        x_size = m5.v_size;
        y_size = m5.m_size;
        chunks_per_tile = m5.v_size/TILES;
        if (m5.op != 0) {
            #if(VERBOSE_OP==1)
            m5.print( cycle_count);
            #endif
        } else {
            u5.op = m5.op;
            ld_uOP_port->writeToChannel(u5);
        }
        decoding_ld = (m5.op != 0);
    }

    /**********************************************************************************************/

    /*************************************** Decoding Logic ***************************************/

    // [1] MVU Decoding
    if(decoding_mvu && !mvu_uOP_port->isChannelFull()){
        if(remaining_rows == -1){
            remaining_rows = m1.m_size / m1.v_size;
        }
        acc_size = (remaining_rows > (2*3*LANES/10)-1)? (3*LANES/10): remaining_rows;
        u1.op = m1.op;
        if(mvu_pipeline_counter < (3*LANES/10)) {
            u1.vrf_en = 1;
        } else {
            u1.vrf_en = 0;
        }
        u1.accum_size = acc_size;

        // VRF Address Logic
        if(mvu_pipeline_counter < (3*LANES/10)){
            if(mvu_pipeline_counter % 3 == 0){
                u1.vrf_addr = m1.vrf_addr0 + (mvu_counter % m1.v_size);
            } else if(mvu_pipeline_counter % 3 == 1) {
                u1.vrf_addr = m1.vrf_addr1 + (mvu_counter % m1.v_size);
            } else {
                u1.vrf_addr = m1.vrf_addr2 + (mvu_counter % m1.v_size);
            }
            u1.vrf_sel = mvu_pipeline_counter / 3;
        } else {
            u1.vrf_addr = 0;
            u1.vrf_sel = 0;
        }
        u1.reg_sel = reg_sel_flag;

        // MRF Address Logic
        u1.mrf_addr = m1.mrf_addr + (mvu_chunk_counter * 3 * (LANES/10) * m1.v_size)
            + (mvu_pipeline_counter * m1.v_size) + mvu_counter;

        u1.accum = (((mvu_counter + 1) % m1.v_size) == 0);
        u1.tag = m1.tag;
        u1.first_flag = (mvu_counter == 0 && mvu_chunk_counter == 0
            && mvu_pipeline_counter == 0)? 
            ((m1.op == 3)? (m1.m_size)*DPES*TILES: m1.m_size/m1.v_size*3):0;
        u1.last_flag = (u1.mrf_addr == (m1.mrf_addr + m1.m_size - 1));

        // Write uOP to output port
        mvu_uOP_port->writeToChannel(u1);
        #if(VERBOSE_OP)
        u1.print(cycle_count);
        #endif

        // Update local variables
        if(u1.mrf_addr < m1.mrf_addr + m1.m_size - 1){
            if (mvu_pipeline_counter < acc_size-1){
                mvu_pipeline_counter++;
            } else {
                reg_sel_flag = (reg_sel_flag == 0)? 1: 0;
                mvu_pipeline_counter = 0;
                
                if(mvu_counter < m1.v_size-1){
                    mvu_counter++;                            
                } else {
                    mvu_counter = 0;
                    remaining_rows = (remaining_rows > (2*3*LANES/10)-1)? 
                        remaining_rows-(3*LANES/10): remaining_rows;
                    mvu_chunk_counter++;
                }
            }
        } else {
            mvu_pipeline_counter = 0;
            mvu_counter = 0;
            mvu_chunk_counter = 0;
            reg_sel_flag = (reg_sel_flag == 0)? 1: 0;
            remaining_rows = -1;
            decoding_mvu = false;
        }
    }

    // [2] eVRF Decoding
    if(decoding_evrf && !evrf_uOP_port->isChannelFull()){
        // Decide whether to use MVU output or flush it
        if(evrf_batch_counter < m2.batch) {
            u2.op = m2.op;
        } else {
            u2.op = 2;
        }
        // Set uOP source (MVU or eVRF)
        u2.src = m2.src;
        // Set uOP VRF address
        if(evrf_batch_counter % 3 == 0)
            u2.vrf_addr = m2.vrf_addr0 + evrf_counter;
        else if(evrf_batch_counter % 3 == 1)
            u2.vrf_addr = m2.vrf_addr1 + evrf_counter;
        else
            u2.vrf_addr = m2.vrf_addr2 + evrf_counter;
        // Set uOP tag, first flag and last flag
        unsigned int limit = (m2.src)? m2.batch: 3;
        u2.tag = m2.tag;
        u2.first_flag = (evrf_counter == 0 && evrf_batch_counter == 0)?
            m2.v_size * m2.batch: 0;
        u2.last_flag = (evrf_counter == (m2.v_size-1) &&
            evrf_batch_counter == limit-1);

        // Write uOP to output port
        evrf_uOP_port->writeToChannel(u2);
        #if(VERBOSE_OP)
        u2.print(cycle_count);
        #endif

        // Update local variables
        if(evrf_batch_counter == m2.batch-1){
            evrf_batch_counter = 0;
            evrf_counter++;
            if(evrf_counter == m2.v_size){
                evrf_counter = 0;
                decoding_evrf = false;
            }
        } else {
            evrf_batch_counter++;
        }  
    }

    // [3] MFU0 Decoding
    if(decoding_mfu0 && !mfu0_uOP_port->isChannelFull()){
        u3.op = m3.op;
        // Set uOP Activation operation
        u3.act_op = m3.act_op;
        // Set uOP Add operation and operand address
        u3.add_op = m3.add_op;
        if(mfu0_batch_counter == 0)
            u3.vrf0_addr = m3.vrf0_addr0 + mfu0_counter;
        else if (mfu0_batch_counter == 1)
            u3.vrf0_addr = m3.vrf0_addr1 + mfu0_counter;
        else
            u3.vrf0_addr = m3.vrf0_addr2 + mfu0_counter;
        // Set uOP Multiply operation and operand address
        u3.mul_op = m3.mul_op;
        if(mfu0_batch_counter == 0)
            u3.vrf1_addr = m3.vrf1_addr0 + mfu0_counter;
        else if (mfu0_batch_counter == 1)
            u3.vrf1_addr = m3.vrf1_addr1 + mfu0_counter;
        else
            u3.vrf1_addr = m3.vrf1_addr2 + mfu0_counter;
        // Set uOP tag, first flag and last flag
        u3.tag = m3.tag;
        u3.first_flag = (mfu0_counter == 0 && mfu0_batch_counter == 0)? m3.v_size * m3.batch: 0;
        u3.last_flag = (mfu0_counter == (m3.v_size-1) && mfu0_batch_counter == (m3.batch-1));

        // Write uOP to output port
        mfu0_uOP_port->writeToChannel(u3);
        #if(VERBOSE_OP)
        u3.print(cycle_count);
        #endif

        // Update local variables
        if(mfu0_batch_counter == m3.batch-1){
            mfu0_batch_counter = 0;
            mfu0_counter++;
            if(mfu0_counter == m3.v_size){
                mfu0_counter = 0;
                decoding_mfu0 = false;
            }
        } else {
            mfu0_batch_counter++;
        }
    }

    // [4] MFU1 Decoding
    if (decoding_mfu1 && !mfu1_uOP_port->isChannelFull()) {
        u4.op = m4.op;
        // Set uOP Activation operation
        u4.act_op = m4.act_op;
        // Set uOP Add operation and operand address
        u4.add_op = m4.add_op;
        if(mfu1_batch_counter == 0)
            u4.vrf0_addr = m4.vrf0_addr0 + mfu1_counter;
        else if (mfu1_batch_counter == 1)
            u4.vrf0_addr = m4.vrf0_addr1 + mfu1_counter;
        else
            u4.vrf0_addr = m4.vrf0_addr2 + mfu1_counter;
        // Set uOP Multiply operation and operand address
        u4.mul_op = m4.mul_op;
        if(mfu1_batch_counter == 0)
            u4.vrf1_addr = m4.vrf1_addr0 + mfu1_counter;
        else if (mfu1_batch_counter == 1)
            u4.vrf1_addr = m4.vrf1_addr1 + mfu1_counter;
        else
            u4.vrf1_addr = m4.vrf1_addr2 + mfu1_counter;
        // Set uOP tag, first flag and last flag
        u4.tag = m4.tag;
        u4.first_flag = (mfu1_counter == 0 && mfu1_batch_counter == 0)? m4.v_size * m4.batch: 0;
        u4.last_flag = (mfu0_counter == (m4.v_size-1) && mfu0_batch_counter == (m4.batch-1));

        // Write uOP to output port
        mfu1_uOP_port->writeToChannel(u4);
        #if(VERBOSE_OP)
        u4.print(cycle_count);
        #endif

        // Update local variables
        if(mfu1_batch_counter == m4.batch-1){
            mfu1_batch_counter = 0;
            mfu1_counter++;
            if(mfu1_counter == m4.v_size){
                mfu1_counter = 0;
                decoding_mfu1 = false;
            }
        } else {
            mfu1_batch_counter++;
        }
    }


    if(decoding_ld && !ld_uOP_port->isChannelFull()){
        // Set uOP operation and source
        u5.op = m5.op;
        u5.src = m5.src;
        // Set uOP first destination
        u5.dst0_valid = m5.dst0_valid;
        u5.dst0_id = m5.dst0_id;
        if(ld_batch_counter == 0)
            u5.dst0_addr = m5.dst0_addr0 + ld_counter;
        else if(ld_batch_counter == 1)
            u5.dst0_addr = m5.dst0_addr1 + ld_counter;
        else
            u5.dst0_addr = m5.dst0_addr2 + ld_counter;
        // Set uOP second destination
        u5.dst1_valid = m5.dst1_valid;
        u5.dst1_id = m5.dst1_id;
        if(ld_batch_counter == 0)
            u5.dst1_addr = m5.dst1_addr0 + ld_counter;
        else if(ld_batch_counter == 1)
            u5.dst1_addr = m5.dst1_addr1 + ld_counter;
        else
            u5.dst1_addr = m5.dst1_addr2 + ld_counter;
        // Set uOP flags (write to output FIFO, first, last)
        u5.wr_to_output = m5.wr_to_output;
        u5.first_flag = (ld_counter == 0 && ld_batch_counter == 0)? m5.v_size * m5.batch: 0;
        u5.last_flag = (ld_counter == (m5.v_size - 1) && ld_batch_counter == (m5.batch - 1));

        // Write uOP to output port
        ld_uOP_port->writeToChannel(u5);
        #if(VERBOSE_OP)
        u5.print(cycle_count);
        #endif

        // Update local variables
        if(ld_batch_counter == m5.batch-1){
            ld_batch_counter = 0;
            ld_counter++;
            if(ld_counter == m5.v_size){
                ld_counter = 0;
                decoding_ld = false;
            }
        } else {
            ld_batch_counter++;
        }
    }

    /**********************************************************************************************/

    // Clock the internal channels
    mvu_mOP_channel->clock();
    evrf_mOP_channel->clock();
    mfu0_mOP_channel->clock();
    mfu1_mOP_channel->clock();
    ld_mOP_channel->clock();
}

// Getter function for name
std::string Decoder::getName() { 
    return name; 
}

// Getter function for input VLIW port
Input<npu_instruction>* Decoder::getPortInputVLIW() { 
    return vliw; 
}

// Getter function for output MVU uOP port
Output<mvu_uOP>* Decoder::getPortMVUuOP() {
    return mvu_uOP_port; 
}

// Getter function for output eVRF uOP port
Output<evrf_uOP>* Decoder::getPortEVRFuOP() { 
    return evrf_uOP_port; 
}

// Getter function for output MFU0 uOP port
Output<mfu_uOP>* Decoder::getPortMFU0uOP() { 
    return mfu0_uOP_port; 
}

// Getter function for output MFU1 uOP port
Output<mfu_uOP>* Decoder::getPortMFU1uOP() { 
    return mfu1_uOP_port; 
}

// Getter function for output Loader uOP port
Output<ld_uOP>* Decoder::getPortLDuOP() { 
    return ld_uOP_port; 
}

Decoder::~Decoder() {
    delete vliw;
    delete mvu_uOP_port;
    delete evrf_uOP_port;
    delete mfu0_uOP_port;
    delete mfu1_uOP_port;
    delete ld_uOP_port;
    delete mvu_mOP_channel;
    delete evrf_mOP_channel;
    delete mfu0_mOP_channel;
    delete mfu1_mOP_channel;
    delete ld_mOP_channel;
}