#ifndef UTILS_H
#define UTILS_H

#include <string>
#include <iostream>
#include <vector>
#include <queue>
#include <iomanip>
#include <fstream>
#include <sstream>
#include <assert.h>
#include "defines.h"

/*
 * This header file declares several utility functions used throughout the simulator
 */

// Operator overload for printing a vector
template <typename T>
std::ostream& operator<< (std::ostream& out, const std::vector<T>& v);

// Used for populating vector register file contents from a file
void readVectorFile(std::string &file_name, std::vector<std::vector<TYPE>> &vec_data);

// Used for populating vector FIFO contents from a file
void readVectorFile(std::string &file_name, std::queue<std::vector<TYPE>> &que_data);

// Operator overload for adding two vectors
std::vector<TYPE> operator+ (const std::vector<TYPE> &v1, const std::vector<TYPE> &v2);

// Used for reading simulating golden outputs
template <typename T>
void readGoldenOutput(std::string &file_name, std::vector<T> &vec_data, int v_size);

#endif
