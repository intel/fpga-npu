#!/bin/bash

cd ../simulator
make &> make_log
./npu_sim &> perf_sim_log
make clean &> make_clean_log
