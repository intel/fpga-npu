#ifndef PRIME_ACCUMULATOR_H
#define PRIME_ACCUMULATOR_H

#include <vector>
#include <string>
#include "input.h"
#include "output.h"
#include "inst.h"
#include "defines.h"
#include "utils.h"

/* 
 * This class implements the MVU accumulation of the 3 results computed by the dot product engines
 * based on the Stratix 10 NX tensor block.
 * Input Ports:
 * - 3 data inputs (from inter-tile reduction)
 * - uOP (from decoder)
 * - reconfigurable accumulator size (from decoder)
 * Output Ports:
 * - 3 accumulation results (to MVU output)
 */
class Accumulator : public Module {
public:
    // Constructor
    Accumulator (std::string t_name, unsigned int t_accum_id);
    // Clock function
    void clock();
    // Getter functions
    std::string getName();
    unsigned int getId();
    Input<TYPE> *getPortInput(unsigned int i);
    Input<unsigned int> *getPortuOP();
    Input<unsigned int> *getPortSize();
    Output<TYPE> *getPortRes(unsigned int i);
    // Helper functions
    void reset();
    // Destructor
    ~Accumulator();

private:
    // Module name
    std::string name;
    // Input and Output ports
    Input<TYPE>* input0;
    Input<TYPE>* input1;
    Input<TYPE>* input2;
    Input<unsigned int>* uOP;
    Input<unsigned int>* size;
    Output<TYPE>* result0;
    Output<TYPE>* result1;
    Output<TYPE>* result2;
    // Local variables
    unsigned int accum_id;
    std::vector<TYPE> accum0_values;
    std::vector<TYPE> accum1_values;
    std::vector<TYPE> accum2_values;
	unsigned int channel_full_count;
    unsigned int num_accum_values = 2 * 3 * (LANES/10);
    unsigned int accum_idx;
};

#endif
