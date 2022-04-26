#include "output.h"

// Output Port Constructor
template <class T>
Output<T>::Output(std::string t_name, Module *t_module): Port<T>(t_name, t_module) { }

// Helper function for connecting an output port to an outgoing channel
template <class T> 
void Output<T>::connectTo(Channel<T> *t_channel) { 
	channels.push_back(t_channel);
}

// Helper function for writing to all the channels connected to this output port
template <class T>
void Output<T>::writeToChannel(T t_data) {
    for(unsigned int i = 0; i < channels.size(); i++){
        channels[i]->write(t_data);
    }
}

// Helper function for checking if the channel connected to this port is full
template <class T>
bool Output<T>::isChannelFull() {
    bool full = false;
    for(unsigned int i = 0; i < channels.size(); i++){
        full = full || channels[i]->isFull();
    }
    return full;
}

template <class T>
Output<T>::~Output(){ 
	for (unsigned int i = 0; i < channels.size(); i++){
		channels[i] = NULL;
	} 
}

template class Output<TYPE>;
template class Output<std::vector<TYPE>>;
template class Output<bool>;
template class Output<unsigned int>;
template class Output<mvu_uOP>;
template class Output<evrf_uOP>;
template class Output<mfu_uOP>;
template class Output<ld_uOP>;
