#ifndef INPUT_H_
#define INPUT_H_

#include <string>
#include <vector>
#include <assert.h>
#include "port.h"
#include "module.h"
#include "defines.h"
#include "inst.h"
#include "channel.h"

/* 
 * This class implements an input port for a module. Each input port is connected to a channel.
 */
template <class T>
class Input : public Port<T> 
{
public: 
	// Constructor
	Input(std::string t_name, Module *t_module);
	// Helper functions
	void connectTo(Channel<T> *t_channel);
	T readFromChannel();
	T peekChannel();
	bool isChannelEmpty();
	// Destructor
	~Input();

private:
	Channel<T>* channel;
};

#endif