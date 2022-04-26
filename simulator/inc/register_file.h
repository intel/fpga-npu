#ifndef REGISTER_FILE_H_
#define REGISTER_FILE_H_

#include <string>
#include <vector>
#include <tuple>
#include <iostream>
#include <assert.h>
#include <type_traits>
#include "module.h"
#include "input.h"
#include "output.h"
#include "channel.h"
#include "utils.h"
#include "defines.h"

/* 
 * This class implements a simple dual-port register file (1 read and 1 write ports) that is used 
 * in different modules of the NPU.
 * Input Ports:
 * - VRF write data
 * - VRF write address
 * - VRF read address
 * Output Ports:
 * - VRF read data
 */
template<class T>
class RegisterFile : public Module { 
public:
	// Constructor
	RegisterFile(std::string t_name, unsigned int t_depth, std::string *t_file_name = nullptr);
	// Clock function
	void clock();
	// Getter functions
	Input<unsigned int>* getPortRaddr();
	Output<T>* getPortRdata();
	Input<unsigned int>* getPortWaddr();
	Input<T>* getPortWdata();
	// Helper functions
	void write();
	void read();
	void print();
	// Destructor
	~RegisterFile();

private:
	// Input and Output ports
	Input<unsigned int>* raddr;
	Output<T>* rdata;
	Input<unsigned int>* waddr;
	Input<T>* wdata;
	// Local variables
	std::vector<T> register_file;
	unsigned int depth;
	std::queue<std::tuple<unsigned int, unsigned int>> read_pipeline;
	unsigned int reads_in_flight;
	std::queue<std::tuple<unsigned int, T, unsigned int>> write_pipeline;
	unsigned int writes_in_flight;
};

#endif
		
