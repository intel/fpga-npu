#include "register_file.h"

// Helper function for initializing vector register files
void init_rf(std::vector<std::vector<TYPE>> &rf, unsigned int depth){
    for (unsigned int i = rf.size(); i < depth; i++) {
        std::vector <TYPE> zeros;
        for (int j = 0; j < LANES; j++) {
            zeros.push_back(0);
        }
        rf.push_back(zeros);
    }
}

// Register File Constructor
template <class T>
RegisterFile<T>::RegisterFile (std::string t_name, unsigned int t_depth, 
	std::string *t_file_name): Module(t_name) { 
		// Create Input and Output ports
		raddr = new Input<unsigned int> (t_name + "_raddr", this);
		rdata = new Output<T> (t_name + "_rdata", this);
		waddr = new Input<unsigned int> (t_name + "_waddr", this);
		wdata = new Input<T> (t_name + "_wdata", this);
		// Initialize local variables
		depth = t_depth;
		reads_in_flight = 0;
		writes_in_flight = 0;
		// Initialize register file contents
		if (t_file_name)
		    readVectorFile(*t_file_name, register_file);
		init_rf(register_file, t_depth);
}

// Helper function for read operation
template <class T>
void RegisterFile<T>::read(){
	// Advance the pipeline if there is any data in it
	if(read_pipeline.size() > 0){
	    bool retire = false;
		for (unsigned int i = 0; i < reads_in_flight; i++){
			std::tuple<unsigned int, unsigned int> temp = read_pipeline.front();
			if((std::get<1>(temp) == 0) && (!rdata->isChannelFull())){
				read_pipeline.pop();
				assert(std::get<0>(temp) < depth && "Read address out of bound");
				rdata->writeToChannel(register_file[std::get<0>(temp)]);
				retire = true;
			} else if (reads_in_flight <= RF_READ_LATENCY) {
				read_pipeline.pop();
				if(std::get<1>(temp) > 0){
				    std::get<1>(temp)--;
				}
				read_pipeline.push(temp);
			}
		}
		reads_in_flight = (retire)? reads_in_flight-1: reads_in_flight;
	}

	// Read in new address if the pipeline is not stalled (i.e. reads in flight
	// less than the pipeline depth/latency)
	if(!raddr->isChannelEmpty() && reads_in_flight <= RF_READ_LATENCY){
		unsigned int temp_raddr = raddr->readFromChannel();
		read_pipeline.push(std::make_tuple(temp_raddr, RF_READ_LATENCY-1));
		reads_in_flight++;
	}
}

// Helper function for write operation
template <class T>
void RegisterFile<T>::write(){
	// Advance the pipeline if there is any data in it
	if(write_pipeline.size() > 0){
	    bool retire = false;
		for (unsigned int i = 0; i < writes_in_flight; i++){
			std::tuple<unsigned int, T, unsigned int> temp = write_pipeline.front();
			if((std::get<2>(temp) == 0)){
				write_pipeline.pop();
				assert(std::get<0>(temp) < depth && "Write address out of bound");
				register_file[std::get<0>(temp)] = std::get<1>(temp);
				retire = true;
			} else if (writes_in_flight <= RF_WRITE_LATENCY) {
				write_pipeline.pop();
				if(std::get<2>(temp) > 0) {
					std::get<2>(temp)--;
				}
				write_pipeline.push(temp);
			}
		}
		writes_in_flight = (retire)? writes_in_flight-1: writes_in_flight;
	}

	// Read in new address and data if the pipeline is not stalled (i.e. reads 
	// in flight less than the pipeline depth/latency)
	if((!waddr->isChannelEmpty()) && (!wdata->isChannelEmpty()) && 
		(writes_in_flight <= RF_WRITE_LATENCY)){
		unsigned int temp_waddr = waddr->readFromChannel();
		T temp_wdata = wdata->readFromChannel();
		write_pipeline.push(std::make_tuple(temp_waddr, temp_wdata, RF_WRITE_LATENCY-1));
		writes_in_flight++;
	}
}

// Clock cycle update function
template <class T>
void RegisterFile<T>::clock() {
	this->write();
	this->read();
}

// Helper function for printing out the contents of a register file (used for debugging)
template <class T>
void RegisterFile<T>::print() { 
	std::cout<<"Register file elements: ";
	for (unsigned int i = 0; i < depth; i++)
		std::cout<< register_file.at(i) << ", ";
	std::cout << std::endl;
}

// Getter function for read address input port
template <class T>
Input<unsigned int>* RegisterFile<T>::getPortRaddr() { 
	return raddr; 
}

// Getter function for read data output port
template <class T>
Output<T>* RegisterFile<T>::getPortRdata() { 
	return rdata; 
}

// Getter function for write address input port
template <class T>
Input<unsigned int>* RegisterFile<T>::getPortWaddr() { 
	return waddr; 
}

// Getter function for write data input port
template <class T>
Input<T>* RegisterFile<T>::getPortWdata() { 
	return wdata; 
}

template <class T>
RegisterFile<T>::~RegisterFile() {
	delete raddr;
	delete rdata;
	delete waddr;
	delete wdata;
}

template class RegisterFile<std::vector<TYPE>>;