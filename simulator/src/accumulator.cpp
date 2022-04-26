#include "accumulator.h"

// Reset helper function to set accumulated values to zeros
void Accumulator::reset(){
    accum0_values.erase(accum0_values.begin(), accum0_values.end());
    accum1_values.erase(accum1_values.begin(), accum1_values.end());
    accum2_values.erase(accum2_values.begin(), accum2_values.end());
    for(unsigned int i = 0; i < num_accum_values; i++){
        accum0_values.push_back(0);
        accum1_values.push_back(0);
        accum2_values.push_back(0);
    }
}

// Accumulator Constructor
Accumulator::Accumulator(std::string t_name, unsigned int t_accum_id) : Module (t_name) {
	// Initialize local variables
    accum_id = t_accum_id;
    this->reset();
	channel_full_count = 0;
	accum_idx = 0;
	// Create Input and Output ports
    input0 = new Input<TYPE>(t_name + "_input0", this);
    input1 = new Input<TYPE>(t_name + "_input1", this);
    input2 = new Input<TYPE>(t_name + "_input2", this);
    uOP = new Input<unsigned int>(t_name + "_uOP", this);
    size = new Input<unsigned int>(t_name + "_size", this);
    result0 = new Output<TYPE>(t_name + "_output0", this);
    result1 = new Output<TYPE>(t_name + "_output1", this);
    result2 = new Output<TYPE>(t_name + "_output2", this);
}

// Clock cycle update function
void Accumulator::clock(){
	// If no input data/size or uOP ready, abort
	if (input0->isChannelEmpty() || uOP->isChannelEmpty() || size->isChannelEmpty()) return;
	
	// Peek uOP and size to decide how to proceed
	unsigned int temp_uOP = uOP->peekChannel();
	unsigned int temp_size = size->peekChannel(); 
	
	//Accumlate input values
	TYPE input0_data = input0->readFromChannel();
	TYPE input1_data = input1->readFromChannel();
	TYPE input2_data = input2->readFromChannel();
	temp_uOP = uOP->readFromChannel();
	temp_size = size->readFromChannel(); 
	accum0_values[accum_idx] = accum0_values[accum_idx] + input0_data;
	accum1_values[accum_idx] = accum1_values[accum_idx] + input1_data;
	accum2_values[accum_idx] = accum2_values[accum_idx] + input2_data;

	// Write out the final result & reset the accumulator
	if (temp_uOP)   {
		result0->writeToChannel(accum0_values[accum_idx]);
		result1->writeToChannel(accum1_values[accum_idx]);
		result2->writeToChannel(accum2_values[accum_idx]);
		accum0_values[accum_idx] = 0;
		accum1_values[accum_idx] = 0;
		accum2_values[accum_idx] = 0;
		channel_full_count = 0;
	} 

	// Update accumulator index
	if(accum_idx == temp_size-1)
		accum_idx = 0;
	else
		accum_idx++;
}

// Getter function for name
std::string Accumulator::getName() { 
	return name; 
}

// Getter function for ID
unsigned int Accumulator::getId() { 
	return accum_id; 
}

// Getter function for input ports
Input<TYPE>* Accumulator::getPortInput(unsigned int i) {
    if(i == 0) 
        return input0;
    else if (i == 1)
        return input1;
    else
        return input2; 
}

// Getter function for uOP input port
Input<unsigned int>* Accumulator::getPortuOP() { 
	return uOP; 
}

// Getter function for port size
Input<unsigned int>* Accumulator::getPortSize() { 
	return size; 
}

// Getter function for output ports
Output<TYPE>* Accumulator::getPortRes(unsigned int i) { 
    if(i == 0)
        return result0;
    else if (i == 1)
        return result1;
    else
        return result2; 
}

// Destructor
Accumulator::~Accumulator(){
	delete input0;
	delete input1;
	delete input2;
	delete uOP;
	delete size;
	delete result0;
	delete result1;
	delete result2;
}