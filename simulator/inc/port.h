#ifndef PORT_H_
#define PORT_H_

#include <string>
#include <iostream>
#include <vector>
#include <cstring>
#include "inst.h"
#include "utils.h"
#include "module.h"
#include "channel.h"

/* 
 * This class implements a module port. This class is not used in the implementation of the 
 * simulator. Both Input and Output port classes inherit from it.
 */
template <class T>
class Port { 
public:
	// Constructor
	Port (std::string t_name, Module *t_module);
	// Getther functions
	std::string getName();
	Module* getModule();
	virtual ~Port() {};

protected:
	// Port name
	std::string name;
	// Module the port belongs to
	Module* module;
};
#endif

