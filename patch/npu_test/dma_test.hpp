#ifndef DMA_TEST_HPP
#define DMA_TEST_HPP

const int version_major = 2;
const int version_minor = 0;

#define NPU_PRINT

#define WELCOME_OPT_AUTO        0
#define WELCOME_OPT_MANUAL      1
#define WELCOME_OPT_MAXNR       1

#define NPU_INPUT   0x4000
#define NPU_INPUT_1 0x4100
#define NPU_RAM1    0x4040
#define NPU_RAM2    0x4140
#define NPU_IN_FIFO 0x4080
#define NPU_START   0x4240 

#define NPU_DONE    0x4040
#define NPU_OUT_DEQ 0x40c0  
#define NPU_OUT_FIFO_0 0x4000
#define NPU_OUT_FIFO_1 0x4100
#define NPU_OUT_FIFO_2 0x4200
#define NPU_OUT_FIFO_3 0x4300
#define NPU_OUT_FIFO_4 0x4400

#define POLL_RAM_STATUS 0x80100
#define NPU_SOFT_RST    0x80200

#define SEL_MENU_DELIMS "*********************************************************"
#define FILL_ZERO 0
#define FILL_RAND 1
#define FILL_INCR 2

#endif /* DMA_TEST_HPP */
