#include "channel.h"

// Channel constructor
template <class T>
Channel<T>::Channel(std::string t_name, unsigned int t_size, unsigned int t_latency){
	name = t_name;
	size = t_size;
	latency = t_latency;
}

// Helper function to write to a channel
template <class T>
void Channel<T>::write(T t_value){
	if (this->isFull()) 
		std::cerr << "Channel "<< name <<" buffer size "<<
		  buffer.size() << " out of " << size << std::endl;
	assert((!this->isFull()) && "Writing to a full channel");
	buffer.push(std::make_tuple(t_value, latency));
}

// Helper function to read from a channel
template <class T>
T Channel<T>::read(){
	assert((!buffer.empty() || (std::get<1>(buffer.front()) == 0)) && "Reading from empty channel");
	T temp = std::get<0>(buffer.front());
	buffer.pop();
	return temp;
};

// Helper function to peek a channel (look at the next element in the channel)
template <class T>
T Channel<T>::peek(){
    assert((!buffer.empty() || (std::get<1>(buffer.front()) == 0)) && "Peeking an empty channel");
    T temp = std::get<0>(buffer.front());
    return temp;
};

// Helper function to get the element at a specific location in the channel
template <class T>
T Channel<T>::at(unsigned int idx){
    assert((buffer.size() > idx) && "Channel size is less that accessed index");
    unsigned int i = 0;
    T temp;
    std::tuple<T, unsigned int> temp_tuple;
    for(unsigned int itr = 0; itr < buffer.size(); itr++){
    	temp_tuple = buffer.front();
    	buffer.pop();
    	if(i == idx)
    		temp = std::get<0>(temp_tuple);
    	buffer.push(temp_tuple);
    	i++;
    }
    return temp;
};

// Helper function to check if channel is empty
template <class T>
bool Channel<T>::isEmpty(){
	return buffer.empty() || (std::get<1>(buffer.front()) != 0);
}

// Helper function to check if channel is full
template <class T>
bool Channel<T>::isFull(){
	return !(buffer.size() <= size);
}

// Clock cycle update function
template <class T>
void Channel<T>::clock(){
    if(!buffer.empty()){
        for(unsigned int i = 0; i < buffer.size(); i++){
            std::tuple<T, unsigned int> temp = buffer.front();
            buffer.pop();
            if(std::get<1>(temp) > 0){
                std::get<1>(temp)--;
            }
            buffer.push(temp);
        }
    }
}

// Getter function for name
template <class T>
std::string Channel<T>::getName () { 
    return name; 
}

// Getter function for size
template <class T>
unsigned int Channel<T>::getSize() { 
    return buffer.size(); 
}

template class Channel<TYPE>;
template class Channel<std::vector<TYPE>>;
template class Channel<bool>;
template class Channel<unsigned int>;
template class Channel<mvu_uOP>;
template class Channel<evrf_uOP>;
template class Channel<mfu_uOP>;
template class Channel<ld_uOP>;
template class Channel<npu_instruction>;
template class Channel<mvu_mOP>;
template class Channel<evrf_mOP>;
template class Channel<mfu_mOP>;
template class Channel<ld_mOP>;