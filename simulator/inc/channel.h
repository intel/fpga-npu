#ifndef CHANNEL_H_
#define CHANNEL_H_

#include <string>
#include <queue>
#include <tuple>
#include <assert.h>
#include <iostream>
#include "defines.h"
#include "inst.h"

/* 
 * This class implements a communication channel. Each channel has a capacity and latency
 * parameters. By setting these two parameters, a channel can be used to model:
 * - wire: capacity 1 and latency 0
 * - register: capacity 1 and latency 1
 * - pipeline: capacity N and latency N
 * - FIFO: capacity N and latency 1
 */
template <class T>
class Channel { 
public:
    // Constructor
    Channel (std::string t_name, unsigned int t_size, unsigned int t_latency);
    // Clock function
    void clock();
    // Helper functions
    void write(T t_value);
    T read();
    T peek();
    T at(unsigned int idx);
    bool isEmpty();
    bool isFull();
    // Getter functions
    std::string getName();
    unsigned int getSize();

private:
    // Module name
    std::string name;
    // Local variables
    std::queue<std::tuple<T, unsigned int>> buffer;
    unsigned int size;
    unsigned int latency;
};
#endif
