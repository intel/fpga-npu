#ifndef OUTPUT_H_
#define OUTPUT_H_

#include <string>
#include <vector> 
#include "defines.h"
#include "inst.h"
#include "port.h"
#include "module.h"
#include "channel.h"

/* 
 * This class implements an output port for a module. Each output port is connected to one or more
 * outgoing channel(s).
 */
template <class T>
class Output : public Port<T>
{
public:
	// Constructor
	Output(std::string t_name, Module *t_module); 
	// Helper functions
	void connectTo(Channel<T> *t_channel);
	void writeToChannel(T t_data);
	bool isChannelFull();
	// Destructor
	~Output();

private:
	std::vector<Channel<T>*> channels;		
};

#endif