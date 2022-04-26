#include "input.h"

// Input Port Constructor
template <class T>
Input<T>::Input(std::string t_name, Module *t_module) : Port<T>(t_name, t_module) { }

// Helper function for connecting an Input port to incoming channel
template <class T>
void Input<T>::connectTo(Channel<T> *t_channel) {
    channel = t_channel;
}

// Helper function for reading from the incoming channel connected to this port
template <class T>
T Input<T>::readFromChannel() {
    return channel->read();
}

// Helper function for peeking the contents of a channel connected to this port
template <class T>
T Input<T>::peekChannel() {
    return channel->peek();
}

// Helper function for checking if the channel connected to this port is empty
template <class T>
bool Input<T>::isChannelEmpty(){
    assert((channel) && "no channel for input");
    return channel->isEmpty();
}

template <class T>
Input<T>::~Input(){ channel = NULL; }

template class Input<TYPE>;	
template class Input<std::vector<TYPE>>;	
template class Input<bool>;	
template class Input<unsigned int>;
template class Input<mvu_uOP>;
template class Input<evrf_uOP>;
template class Input<mfu_uOP>;
template class Input<ld_uOP>;
template class Input<npu_instruction>;