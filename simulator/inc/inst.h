#ifndef INST_H
#define INST_H

#include <iostream>

/* 
 * This header file defines the instruction set used by the NPU. Each instruction consists of 5
 * macro operations (mOP) for the 5 main pipeline stages (MVU, eVRF, MFU0, MFU1, Loader). The
 * decoder translates these mOPs into a series of micro operations (uOP) to control the hardware.
 */

struct mvu_uOP{
    unsigned int op = 0;         //Operation = {NOP(0), MVMUL(1)}
    unsigned int vrf_addr = 0;
    unsigned int vrf_en = 0;
    unsigned int mrf_addr = 0;
    unsigned int accum = 0;      //Accumulator control = {ACCUM(0), RESET(1)}
    unsigned int accum_size = 0;
    unsigned int reg_sel = 0;
    unsigned int vrf_sel = 0;
    unsigned int tag = 0;
    unsigned int first_flag = 0;
    unsigned int last_flag = 0;
	void print (unsigned int &cycle_count) { 
		std::cout<<"[MVU uOP @ " << cycle_count << "] \033[33mop: " << op << ", vrf_addr: " << 
            vrf_addr << ", vrf_en: " << vrf_en << ", mrf_addr: " << mrf_addr << ", accum: " << 
            accum << ", accum_size: " << accum_size << ", reg_sel: " << reg_sel << ", vrf_sel: " << 
            vrf_sel << ", tag: " << tag << ", first_flag: " << first_flag << ", last_flag: " << 
            last_flag << "\033[0m" << std::endl;
	}
};

struct mvu_mOP{
    unsigned int op = 0;        //Operation = {NOP(0), MVMUL(1)}
    unsigned int vrf_addr0 = 0;
    unsigned int vrf_addr1 = 0;
    unsigned int vrf_addr2 = 0;
    unsigned int v_size = 0;
    unsigned int mrf_addr = 0;
    unsigned int m_size = 0;
    unsigned int tag = 0;
	void print (unsigned int &cycle_count) { 
		std::cout<<"[MVU mOP @ " << cycle_count << "] \033[31mop: " << op << ", vrf_addr0: " << 
        vrf_addr0 << ", vrf_addr1: " << vrf_addr1 << ", vrf_addr2: " << vrf_addr2 << 
        ", v_size: " << v_size << ", mrf_addr: " << mrf_addr << ", m_size: " << m_size <<
		", tag: " << tag << "\033[0m " << std::endl;
	}

};

struct evrf_uOP{
    unsigned int op = 0;        //Operation = {NOP(0), MOV(1), FLUSH(2)}
    unsigned int src = 0;       //Source = {MVU(0), EVRF(1)}
    unsigned int vrf_addr = 0;
    unsigned int tag = 0;
    unsigned int first_flag = 0;
    unsigned int last_flag = 0;
	void print (unsigned int &cycle_count) { 
		std::cout<<"[evrf uOP @ " << cycle_count << "] \033[036mop: " << op << ", src: " << src <<
			", vrf_addr: " << vrf_addr << ", tag: " << tag << ", first_flag: " << first_flag << 
            ", last_flag: " << last_flag << "\033[0m" << std::endl;
	}
};

struct evrf_mOP{
    unsigned int op = 0;        //Operation = {NOP(0), MOV(1)}
    unsigned int src = 0;       //Source = {MVU(0), EVRF(1)}
    unsigned int vrf_addr0 = 0;
    unsigned int vrf_addr1 = 0;
    unsigned int vrf_addr2 = 0;
    unsigned int v_size = 0;
    unsigned int tag = 0;
    unsigned int batch = 0;
	void print (unsigned int &cycle_count) { 
		std::cout<<"[evrf mOP @ " << cycle_count << "] \033[35mop: " << op << ", src: " << src <<
			", vrf_addr0: " << vrf_addr0 << ", v_size: " << v_size << ", tag: " << tag << 
            ", batch: " << batch << "\033[0m" << std::endl;
	}

};

struct mfu_uOP{
    unsigned int op = 0;            //Operation = {NOP(0), do_something(1)}
    unsigned int act_op = 0;        //Activation = {NOP(0), TANH(1), SIGMOID(2), RELU(3)}
    unsigned int add_op = 0;        //Elementwise Add = {NOP(0), ADD(1), SUBAB(2), SUBBA(3)}
    unsigned int vrf0_addr = 0;
    unsigned int mul_op = 0;        //Elementwise Multiply = {NOP(0), MUL(1)}
    unsigned int vrf1_addr = 0;
    unsigned int tag = 0;
    unsigned int first_flag = 0;
    unsigned int last_flag = 0;
	void print (unsigned int &cycle_count) { 
		std::cout<<"[MFU uOP @ " << cycle_count << "] \033[34mop: " << op << ", act_op: " << 
            act_op << ", add_op: " << add_op << ", mul_op: " << mul_op << ", vrf0_addr: " << 
            vrf0_addr << ", vrf1_addr: " << vrf1_addr << ", tag: " << tag << ", first_flag: " << 
            first_flag << ", last_flag: " << last_flag << "\033[0m " << std::endl;
	}

};

struct mfu_mOP{
    unsigned int op = 0;            //Operation = {NOP(0), EN(1)}
    unsigned int v_size = 0;
    unsigned int act_op = 0;        //Activation = {NOP(0), TANH(1), SIGMOID(2), RELU(3)}
    unsigned int add_op = 0;        //Elementwise Add = {NOP(0), ADD(1), SUBAB(2), SUBBA(3)}
    unsigned int vrf0_addr0 = 0;
    unsigned int vrf0_addr1 = 0;
    unsigned int vrf0_addr2 = 0;
    unsigned int mul_op = 0;        //Elementwise Multiply = {NOP(0), MUL(1)}
    unsigned int vrf1_addr0 = 0;
    unsigned int vrf1_addr1 = 0;
    unsigned int vrf1_addr2 = 0;
    unsigned int tag = 0;
    unsigned int batch = 0;
	void print (unsigned int &cycle_count) { 
		std::cout<<"[MFU mOP @ " << cycle_count << "] \033[32mop: "<< op << ", act_op: " << 
            act_op << ", add_op: " << add_op << ", mul_op: " << mul_op << ", v_size: " << v_size <<
			", vrf0_addr0: " << vrf0_addr0 << ", vrf0_addr1: " << vrf0_addr1 << ", vrf0_addr2: " <<
            vrf0_addr2 << ", vrf1_addr0: " << vrf1_addr0 << ", vrf1_addr1: " << vrf1_addr1 << 
            ", vrf1_addr2: " << vrf1_addr2 << ", tag: " << tag << ", batch: " << batch << 
            "\033[0m " << std::endl;
	}
};

struct ld_uOP{
    unsigned int op = 0;       //Operation = {NOP(0), STORE(1), FLUSH(2)}
    unsigned int src = 0;      //Source = {MFU(0), Input(1)}
    bool dst0_valid = 0;
    unsigned int dst0_id = 0;  //Dest = {Tiles, EVRF, MFU0_VRF0, MFU0_VRF1, MFU1_VRF0, MFU1_VRF1}
    unsigned int dst0_addr = 0;
    bool dst1_valid = 0;
    unsigned int dst1_id = 0;
    unsigned int dst1_addr = 0;
    bool wr_to_output = 0;
    unsigned int first_flag = 0;
    unsigned int last_flag = 0;
	void print (unsigned int &cycle_count) { 
		std::cout<<"[ld uOP @ " << cycle_count << "] \033[33m op: "<< op << ", src: " << src <<
			", dst0_valid: " << dst0_valid << ", dst0_id: " << dst0_id << ", dst0_addr: " << 
            dst0_addr << ", dst1_valid: " << dst1_valid << ", dst1_id: " << dst1_id << 
            ", dst1_addr: " << dst1_addr << ", oflag: " << wr_to_output << ", first_flag: " << 
            first_flag << ", last_flag: " << last_flag << "\033[0m" <<std::endl;
	}

};

struct ld_mOP{
    unsigned int op = 0;
    unsigned int src = 0;
    unsigned int v_size = 0;
    unsigned int m_size = 0;
    bool dst0_valid = 0;
    unsigned int dst0_id = 0;
    unsigned int dst0_addr0 = 0;
    unsigned int dst0_addr1 = 0;
    unsigned int dst0_addr2 = 0;
    bool dst1_valid = 0;
    unsigned int dst1_id = 0;
    unsigned int dst1_addr0 = 0;
    unsigned int dst1_addr1 = 0;
    unsigned int dst1_addr2 = 0;
    bool wr_to_output = 0;
    unsigned int batch = 0;
	void print (unsigned int &cycle_count) { 
		std::cout<<"[ld mOP @ " << cycle_count << "]\033[31m op: " << op<<", src: " << src <<
            ", v_size: " << v_size << ", dst0_valid: " << dst0_valid << ", dst0_id: " << dst0_id << 
            ", dst0_addr0: " << dst0_addr0 << ", dst0_addr1: " << dst0_addr1 << ", dst0_addr2: " << 
            dst0_addr2 << ", dst1_valid: " << dst1_valid << ", dst1_id: " << dst1_id << 
            ", dst1_addr0: " << dst1_addr0 << ", dst1_addr1: " << dst1_addr1 << ", dst1_addr2: " << 
            dst1_addr2 << ", oflag: " << wr_to_output << ", batch: " << batch << "\033[0m" <<
            std::endl;
	}
};

struct npu_instruction{
    mvu_mOP  mvu_inst;
    evrf_mOP evrf_inst;
    mfu_mOP  mfu0_inst;
    mfu_mOP  mfu1_inst;
    ld_mOP   ld_inst;
	unsigned int chain_num;
};

#endif