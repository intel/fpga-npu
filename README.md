# The Neural Processing Unit (NPU)

## Introduction
The Neural Processing Unit (NPU) is an FPGA soft processor (i.e., overlay) architecture for low latency, low batch AI inference. It adopts the "persistent AI" approach, in which all model weights are kept persistent in the on-chip SRAM memory of one or more network-connected FPGAs to eliminate the expensive off-chip memory accesses. The NPU is a domain-specific software-programmable processor. Therefore, once the NPU bitstream is compiled and deployed on an FPGA, users can rapidly program it to run different AI workloads using a high-level domain-specific language or a deep learning framework (e.g. TensorFlow Keras) purely in software. This approach enables AI application developers to use FPGAs for AI inference acceleration without the need for FPGA design expertise or suffering from the long runtime of FPGA CAD tools.

## License
Copyright 2022 Intel Corporation

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Citation
If you use the NPU code in this repo for your research, please cite the following paper:
* A. Boutros, E. Nurvitadhi, R. Ma, S. Gribok, Z. Zhao, J. Hoe, V. Betz, and M. Langhammer. "Beyond Peak Performance: Comparing the Real Performance of AI-Optimized FPGAs and GPUs". In the IEEE International Conference on Field-Programmable Technology (FPT), 2020.

You can use the following BibTex entry:
```plaintext
@article{npu_s10_nx,
  title={{Beyond Peak Performance: Comparing the Real Performance of AI-Optimized FPGAs and GPUs}},
  author={Boutros, Andrew and others},
  booktitle={IEEE International Conference on Field-Programmable Technology (ICFPT)},
  year={2020}
}
```
