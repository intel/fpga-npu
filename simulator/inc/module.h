#ifndef MODULE_H_
#define MODULE_H_

#include <string>

/*
 * This header file defines the module abstract class. Any other module in the simulated
 * architecture inherits this class and has to implement the clock() function
 */
class Module {
public:
	// Constructor
	Module(std::string t_name)	{ name = t_name; }
	virtual ~Module() {}
	//Getter functions
	std::string getName() { return name; }
	// Defines what happens in this module every clock cycle (analogous to always block) 
	virtual void clock() { }
	
private:
	// Module name
	std::string name;
};

#endif 