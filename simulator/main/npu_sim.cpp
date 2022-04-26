#include <iostream>
#include <fstream>
#include <vector>
#include <math.h>
#include <cstdlib>
#include <chrono>
#include "../inc/defines.h"
#include "../inc/utils.h"
#include "../inc/channel.h"
#include "../inc/input.h"
#include "../inc/output.h"
#include "../inc/port.h"
#include "../inc/dpe.h"
#include "../inc/mvu_vrf.h"
#include "../inc/register_file.h"
#include "../inc/tile.h"
#include "../inc/mvu.h"
#include "../inc/evrf.h"
#include "../inc/mfu.h"
#include "../inc/datapath.h"
#include "../inc/npu.h"

using namespace std;

void print_vector(vector<TYPE> v){
	cout << "[";
	for(unsigned int i = 0; i < v.size()-1; i++){
		cout << v[i] << ", ";
	}
	cout << v[v.size()-1] << "]" << endl;
}

void read_npu_instructions(unsigned int &cycle_count, Channel<npu_instruction> *inst_q, NPU *npu){
	string file_name = "./register_files/instructions.txt";
	ifstream in(file_name);
	if(!in) assert(0 && "Cannot Open File!");
	string line;
	unsigned int line_num = 0;
	npu_instruction vliw;
	unsigned int temp;
	while(getline(in, line)){
		stringstream line_stream(line);
		// Read MVU Instruction
		if(line_num == 0){
			// Read MVU instruction
			line_stream >> temp;
			vliw.mvu_inst.op = temp;
			line_stream >> temp; 
			vliw.mvu_inst.vrf_addr0 = temp;
			line_stream >> temp; 
			vliw.mvu_inst.vrf_addr1 = temp;
			line_stream >> temp; 
			vliw.mvu_inst.vrf_addr2 = temp;
			line_stream >> temp; 
			vliw.mvu_inst.v_size = temp;
			line_stream >> temp;
			vliw.mvu_inst.mrf_addr = temp;
			line_stream >> temp; 
			vliw.mvu_inst.m_size = temp;
			line_stream >> temp;
			vliw.mvu_inst.tag = temp;
			vliw.mvu_inst.print(cycle_count);
		} else if (line_num == 1){
			// Read eVRF Instruction
			line_stream >> temp;
			vliw.evrf_inst.op = temp;
			line_stream >> temp; 
			vliw.evrf_inst.src = temp;
			line_stream >> temp;
			vliw.evrf_inst.vrf_addr0 = temp;
			line_stream >> temp;
			vliw.evrf_inst.vrf_addr1 = temp;
			line_stream >> temp;
			vliw.evrf_inst.vrf_addr2 = temp;
			line_stream >> temp; 
			vliw.evrf_inst.v_size = temp;
			line_stream >> temp; 
			vliw.evrf_inst.batch = temp;
			line_stream >> temp; 
			vliw.evrf_inst.tag = temp;
			vliw.evrf_inst.print(cycle_count);
		} else if (line_num == 2){
			// Read MFU0 Instruction
			line_stream >> temp;
			vliw.mfu0_inst.op = temp;
			line_stream >> temp; 
			vliw.mfu0_inst.v_size = temp; 
			line_stream >> temp;
			vliw.mfu0_inst.act_op = temp;
			line_stream >> temp; 
			vliw.mfu0_inst.add_op = temp;
			line_stream >> temp;
			vliw.mfu0_inst.vrf0_addr0 = temp;
			line_stream >> temp;
			vliw.mfu0_inst.vrf0_addr1 = temp;
			line_stream >> temp;
			vliw.mfu0_inst.vrf0_addr2 = temp;
			line_stream >> temp; 
			vliw.mfu0_inst.mul_op = temp;
			line_stream >> temp;
			vliw.mfu0_inst.vrf1_addr0 = temp;
			line_stream >> temp;
			vliw.mfu0_inst.vrf1_addr1 = temp;
			line_stream >> temp;
			vliw.mfu0_inst.vrf1_addr2 = temp;
			line_stream >> temp; 
			vliw.mfu0_inst.batch = temp;
			line_stream >> temp; 
			vliw.mfu0_inst.tag = temp;
			vliw.mfu0_inst.print(cycle_count);
		} else if (line_num == 3){
			// Read MFU1 Instruction
			line_stream >> temp;
			vliw.mfu1_inst.op = temp;
			line_stream >> temp;
			vliw.mfu1_inst.v_size = temp;
			line_stream >> temp;  
			vliw.mfu1_inst.act_op = temp;
			line_stream >> temp; 
			vliw.mfu1_inst.add_op = temp;
			line_stream >> temp;
			vliw.mfu1_inst.vrf0_addr0 = temp;
			line_stream >> temp;
			vliw.mfu1_inst.vrf0_addr1 = temp;
			line_stream >> temp;
			vliw.mfu1_inst.vrf0_addr2 = temp; 
 			line_stream >> temp;
			vliw.mfu1_inst.mul_op = temp;
			line_stream >> temp;
			vliw.mfu1_inst.vrf1_addr0 = temp;
			line_stream >> temp;
			vliw.mfu1_inst.vrf1_addr1 = temp;
			line_stream >> temp;
			vliw.mfu1_inst.vrf1_addr2 = temp;
			line_stream >> temp; 
			vliw.mfu1_inst.batch = temp;
			line_stream >> temp; 
			vliw.mfu1_inst.tag = temp;
			vliw.mfu1_inst.print(cycle_count);
		} else if (line_num == 4){
			// Read Loader Instruction
			line_stream >> temp;
			vliw.ld_inst.op = temp;
			line_stream >> temp; 
			vliw.ld_inst.src = temp;
			line_stream >> temp; 
			vliw.ld_inst.v_size = temp;
			line_stream >> temp;
			vliw.ld_inst.dst0_valid = temp;
			line_stream >> temp; 
			vliw.ld_inst.dst0_id = temp;
			line_stream >> temp; 
			vliw.ld_inst.dst0_addr0 = temp;
			line_stream >> temp; 
			vliw.ld_inst.dst0_addr1 = temp;
			line_stream >> temp; 
			vliw.ld_inst.dst0_addr2 = temp;
			line_stream >> temp;
			vliw.ld_inst.dst1_valid = temp;
			line_stream >> temp; 
			vliw.ld_inst.dst1_id = temp;
			line_stream >> temp; 
			vliw.ld_inst.dst1_addr0 = temp;
			line_stream >> temp; 
			vliw.ld_inst.dst1_addr1 = temp;
			line_stream >> temp; 
			vliw.ld_inst.dst1_addr2 = temp;
			line_stream >> temp;
			vliw.ld_inst.batch = temp;
			line_stream >> temp;
			vliw.ld_inst.wr_to_output = temp;
			vliw.ld_inst.print(cycle_count);
		}

		if(line_num == 4){
			inst_q->write(vliw);
			npu->clock(cycle_count);
			cycle_count++;
			line_num = 0;
		} else {
			line_num++;
		}
	}
}

void simulate_compiler_code(unsigned int& cycle_count){
	auto start = std::chrono::high_resolution_clock::now();
	NPU *npu = new NPU("NPU");
	
	// Connect Instruction channel
	Channel<npu_instruction> *tester_vliw = new Channel<npu_instruction> (npu->getName()+"_vliw", FIFO_DEPTH, 0);
	npu->getPortInst()->connectTo(tester_vliw);
	// Connect Output channel
	// Need to set the size so that output could be buffered while we are entering instructions in for multiple timesteps
	Channel<vector<TYPE>> *tester_npu_output = new Channel<vector<TYPE>>(npu->getName()+"_output", FIFO_DEPTH, 0);
	npu->getPortOutput()->connectTo(tester_npu_output);
	
	// Write instructions
	cout << "Performance simulation starting" << endl;	
	vector<vector<TYPE>> golden_results;
	string golden_out_file = "./register_files/py_output.txt";
	readVectorFile(golden_out_file, golden_results);
	unsigned int num_outputs = golden_results.size();

	vector<vector<TYPE>> npu_results;
	read_npu_instructions(cycle_count, tester_vliw, npu);
	
	// Wait until all outputs are received
	while(npu_results.size() < num_outputs){
		npu->clock(cycle_count);
		cycle_count++;
			
		if(!tester_npu_output->isEmpty()){
            vector<TYPE> result = tester_npu_output->read();
            npu_results.push_back(result);
		}
		std::cout << "Got " << npu_results.size() << 
			" out of " << num_outputs << std::endl;
    }
	
	auto end = std::chrono::high_resolution_clock::now();
	auto duration = std::chrono::duration_cast<std::chrono::seconds>(end - start);

    for(unsigned int t = 0; t < 100; t++){
    	npu->clock(cycle_count);
    	cycle_count++;
    }
    cycle_count -= 100;
	
	// Simulation Report
	ofstream sim_done;
  	sim_done.open ("./sim_done");
	cout << "************************************************" << endl;
	cout << "Total Simulation Time = " << cycle_count << " cycle(s)" << endl;
	cout << "************************************************" << endl;
	bool flag = true;
	for(unsigned int i = 0; i < num_outputs; i++){
    	for(unsigned int j = 0; j < golden_results[0].size(); j++){
        	if(npu_results[i][j] != golden_results[i][j]){
				flag = false;
			}
		}
	}

	if(flag){
		cout << "Outputs match!" << endl;
		sim_done << "PASS" << endl;
		sim_done << cycle_count << endl; 
		sim_done << duration.count() << endl;
	} else {
		cout << "Outputs don't match!" << endl;
		sim_done << "FAILED" << endl;
		for(unsigned int i = 0; i < num_outputs; i++){
			cout << "NPU: ";
			print_vector(npu_results[i]);
			cout << "REF: ";
			print_vector(golden_results[i]);
			cout << "------------" << endl;
		}
		sim_done << duration.count() << endl;
	}
	sim_done.close();

	delete npu;
	delete tester_vliw;
	delete tester_npu_output;
}

int main() {
	unsigned int cycle_count = 0;
	simulate_compiler_code(cycle_count);
	return 0;
}
