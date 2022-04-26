#include "port.h"

// Port Constructor
template <class T> 
Port<T>::Port (std::string t_name, Module *t_module) { 
	name = t_name;
	module = t_module;
}

// Getter function for name
template <class T> 
std::string Port<T>::getName() { 
	return name; 
}

// Getter function for port module
template <class T> 
Module* Port<T>::getModule() { 
	return module; 
}

template class Port<TYPE>;
template class Port<std::vector<TYPE>>;
template class Port<bool>;
template class Port<unsigned int>;
template class Port<mvu_uOP>;
template class Port<evrf_uOP>;
template class Port<mfu_uOP>;
template class Port<ld_uOP>;
template class Port<npu_instruction>;