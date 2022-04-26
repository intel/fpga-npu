#include <iostream>
#include <fstream>
#include <iomanip>
#include <cstdlib>
#include <unistd.h>
#include <limits>
#include <time.h>
#include <termios.h>
#include <ctime>
#include <system_error>
#include <cerrno>
#include <stdexcept>
#include <cstring>
#include <sys/time.h>
#include "intel_fpga_pcie_api.hpp"
#include "dma_test.hpp"
#include <stdio.h>
#include <stdlib.h>

#define DEBUG 1
#define DW_SIZE 4
#define NUM_DW 4096
#define NUM_DESC 32
#define BUF_SIZE NUM_DW*NUM_DESC*DW_SIZE/2 //4096 cache lines 
#define H2D_BUF0_START 0
#define H2D_BUF1_START BUF_SIZE
#define D2H_BUF0_START 2*BUF_SIZE
#define D2H_BUF1_START 3*BUF_SIZE

using namespace std;

static unsigned int welcome_options(void);
static uint16_t sel_dev_menu(void);
static int sel_bar_menu(void);
static void dma_show_perf(bool run_rd, bool run_wr, bool run_simul,
                          unsigned int num_dw, unsigned int num_desc,
                          unsigned int cur_run, double (&rd_perf)[2],
                          double (&wr_perf)[2], double (&simul_perf)[2]);
static void dma_show_config(bool run_rd, bool run_wr, bool run_simul,
                            unsigned int num_dw, unsigned int num_desc);
static void do_npu_test_file(intel_fpga_pcie_dev *dev);
static void add_tags(uint32_t* pos, int line_width, int bank, int addr, int dest, int line_num, int lines_per_itr);

int main(int argc, char **argv)
{
    intel_fpga_pcie_dev *dev;
    unsigned int opt;

    uint16_t bdf = 0;
    int bar = 2;
    std::ios_base::fmtflags f(cout.flags()); // Record initial flags
    
    try {
        opt = welcome_options();

        if (opt == WELCOME_OPT_MANUAL) {
            bdf = sel_dev_menu();
            bar = sel_bar_menu();
        }

        try {
            dev = new intel_fpga_pcie_dev(bdf,bar);
        } catch (const std::exception& ex) {
            cout << "Invalid BDF or BAR!" << endl;
            throw;
        }
        cout << hex << showbase;
        cout << "Opened a handle to BAR " << dev->get_bar();
        cout << " of a device with BDF " << dev->get_dev() << endl;

        do_npu_test_file(dev);

    } catch (std::exception& ex) {
        cout.flags(f); // Restore initial flags
        cout << ex.what() << endl;
        return -1;
    }
    
    cout.flags(f); // Restore initial flags
}

//DMA write - move data from host PC buffer to FPGA internal write RAM
//parameter:
//dev : PCIe device control node, which pass down from main()
//host buffer offset: not physical address, but offset in bytes
//FPGA buffer offset: not physical address, but offset in bytes
//num_dw: DWord numbers for every descriptor
//num_desc: descriptor number
static void dma_write(intel_fpga_pcie_dev *dev, unsigned int rp_offset,
                    unsigned int ep_offset, unsigned int num_dw,
                    unsigned int num_desc)
{
   int result;
   unsigned int i;

   for (i=0; i<num_desc; ++i) {
        result = dev->dma_queue_write(ep_offset + i*num_dw*4, num_dw*4, rp_offset+i*num_dw*4);
        if (result == 0) {
                cout << "Could not queue DMA write! Aborting DMA.." << endl;
                return;
        }
   }
   result = dev->dma_send_write();

#ifdef DMA_PROFILE
   unsigned int wr_period   =std::numeric_limits<unsigned int>::max();
   double  rd_perf[2], wr_perf[2], simul_perf[2];
   unsigned long long payload_bytes;
   unsigned long long cumul_wr_time;
   bool run_wr = 1;

   payload_bytes = (unsigned long long) num_dw*num_desc*4;
   
   cumul_wr_time = 0;

   if (result != 0) {
       wr_period = dev->get_ktimer();
       cumul_wr_time += wr_period;
   }

    wr_perf[0]    = payload_bytes/(wr_period*1000.0);
    wr_perf[1]    = payload_bytes/(cumul_wr_time*1000.0);

    dma_show_config(0, run_wr, 0, num_dw, num_desc);
    dma_show_perf(0, run_wr, 0, num_dw, num_desc, 1,
        rd_perf, wr_perf, simul_perf);

#endif

    if (result == 0) {
        cout << "Stopping DMA run due to error.." << endl;
        return;
    }

}

//DMA read - move data from FPGA internal read RAM to host PC buffer
//parameter:
//dev : PCIe device control node, which pass down from main()
//host buffer offset: not physical address, but offset in bytes
//FPGA buffer offset: not physical address, but offset in bytes
//num_dw: DWord numbers for every descriptor
//num_desc: descriptor number
static void dma_read(intel_fpga_pcie_dev *dev, unsigned int rp_offset,
                    unsigned int ep_offset, unsigned int num_dw,
                    unsigned int num_desc)
{
   int result;
   unsigned int i;

   for (i=0; i<num_desc; ++i) {
        result = dev->dma_queue_read(ep_offset+i*num_dw*4, num_dw*4, rp_offset+i*num_dw*4);
        if (result == 0) {
                cout << "Could not queue DMA read! Aborting DMA.." << endl;
                return;
        }
   }
   result = dev->dma_send_read();

#ifdef DMA_PROFILE
   unsigned int rd_period   =std::numeric_limits<unsigned int>::max();
   double  rd_perf[2], wr_perf[2], simul_perf[2];
   unsigned long long payload_bytes;
   unsigned long long cumul_rd_time;
   bool run_rd = 1;

   payload_bytes = (unsigned long long) num_dw*num_desc*4;

   cumul_rd_time = 0;

   if (result != 0) {
       rd_period = dev->get_ktimer();
       cumul_rd_time += rd_period;
   }

        rd_perf[0]    = payload_bytes/(rd_period*1000.0);
        rd_perf[1]    = payload_bytes/(cumul_rd_time*1000.0);

        //system("clear");
        dma_show_config( run_rd,0, 0, num_dw, num_desc);
        dma_show_perf(run_rd,0, 0, num_dw, num_desc, 1,
                        rd_perf,wr_perf, simul_perf);
#endif

    if (result == 0) {
        cout << "Stopping DMA run due to error.." << endl;
        return;
    }

}

static void dma_show_config(bool run_rd, bool run_wr, bool run_simul,
                            unsigned int num_dw, unsigned int num_desc)
{
    std::ios_base::fmtflags f(cout.flags()); // Record initial flags
    cout << dec << noshowbase;
    cout << "\n" << SEL_MENU_DELIMS << "\n";
    cout << "Current DMA configurations" << endl;
    cout << "    Run Read  (card->system)  ? " << run_rd << endl;
    cout << "    Run Write (system->card)  ? " << run_wr << endl;
    cout << "    Run Simultaneous          ? " << run_simul << endl;
    cout << "    Number of dwords/desc     : " << num_dw << endl;
    cout << "    Number of descriptors     : " << num_desc << endl;
    cout << "    Total length of transfer  : " << (num_dw*num_desc*4/1024.0) << " KiB";
    cout.flags(f); // Restore initial flags
}

static void dma_show_perf(bool run_rd, bool run_wr, bool run_simul,
                          unsigned int num_dw, unsigned int num_desc,
                          unsigned int cur_run, double (&rd_perf)[2],
                          double (&wr_perf)[2], double (&simul_perf)[2])
{
    time_t rawtime;
    std::ios_base::fmtflags f(cout.flags()); // Record initial flags
    time(&rawtime);
    cout << dec << noshowbase << setfill(' ') << internal;
    cout << fixed << setprecision(2);
    cout << "\n\n";
    cout << "Current run #: " << cur_run << endl;
    cout << "Current time : " << ctime(&rawtime) << endl;
    cout << "DMA throughputs, in GB/s (10^9B/s)" << endl;
    if (run_rd) {
        cout << "    Current Read Throughput   : " << setw(5) << rd_perf[0] << endl;
        cout << "    Average Read Throughput   : " << setw(5) << rd_perf[1] << endl;
    }
    if (run_wr) {
        cout << "    Current Write Throughput  : " << setw(5) << wr_perf[0] << endl;
        cout << "    Average Write Throughput  : " << setw(5) << wr_perf[1] << endl;
    }
    if (run_simul) {
        cout << "    Current Simul Throughput  : " << setw(5) << simul_perf[0] << endl;
        cout << "    Average Simul Throughput  : " << setw(5) << simul_perf[1] << endl;
    }
    cout << SEL_MENU_DELIMS << "\n";
    cout.flags(f); // Restore initial flags
}

// Check write buffer ready
inline bool check_wb_ready(int csr, int buf_idx)
{
    if (csr & (1 << buf_idx)) return true;
    else return false;
}

// Check read buffer valid
inline bool check_rb_valid(int csr, int buf_idx)
{
    if (csr & (1 << (buf_idx+16))) return true;
    else return false;
}

// Add tags to each line to direct NPU shim where to steer data
static void add_tags(uint32_t* pos, int line_width, int bank, int addr, int dest, int line_num, int lines_per_itr)
{
    // Set tag value
    uint32_t tag = 0;
    tag += dest;
    tag += (bank << 3);
    tag += (addr << 12);
    if ((dest == 3) || (dest == 4)) {
	    int mod_line_num = line_num % lines_per_itr;
	    if (mod_line_num == lines_per_itr-1) {
		    tag += (1 << 21);
	    }
    }
    *(pos) = tag;
    
    // Pad rest of line with zeros
    for (int b = 1; b < (16-line_width/4); b++) {
        *(pos+b) = 0;
    }
}

// main NPU routine
// Total DMA buffer size up to 1MB
// We use low 512KB for DMA write and high 512KB for DMA read
// We further split each 512KB buffer to two 256KB buffers.
// To send/recieve, we alternate between two 256KB buffers to maximize throughput
static void do_npu_test_file(intel_fpga_pcie_dev *dev)
{
    FILE * database;
    uint32_t* instruction;
    uint32_t* input_data;
    uint32_t* mrfs;
    uint32_t* output_data;
    uint32_t* golden_data;
    int bank_num, bank_depth, bank_width;
    int b, i, j, k;

    int result;
    void *mmap_addr;
    uint32_t *kdata;

    // Obtain kernel memory.
    // malloc double size buffer, first half for data write into FPGA, second half is for read back data
    result = dev->set_kmem_size(2*NUM_DESC*NUM_DW*4); 
    if (result != 1) {
        cout << "Could not get kernel memory!" << endl;
        return;
    }

    //For buffer is malloc in Kernel mode, so we need to mmap it to user mode for use, we will use that
    //kdata (address) to access Kernel buffer in this test application 
    mmap_addr = dev->kmem_mmap(2*NUM_DESC*NUM_DW*4, 0);
    if (mmap_addr == MAP_FAILED) {
        cout << "Could not get mmap kernel memory!" << endl;
        return;
    }
    kdata = reinterpret_cast<uint32_t *>(mmap_addr);

    printf("Allocate Kernel memory succesully!\n");

    //---------------------------------------------------------
    // read mrfs.dat to a buffer
    //---------------------------------------------------------

    database = fopen("mrfs.dat", "r");
    ofstream mrf_data_file;
    mrf_data_file.open("mrf_data_host");

    if (NULL == database)
    {
        perror("can't open mrfs.dat");
        return;
    }

    // read mrfs metadata
    fscanf(database, "%d %d %d", &bank_num, &bank_depth, &bank_width);

    // read mrfs data
    int mrfs_size = ((bank_num*bank_depth+1+4095)/4096)*4096*16;
    mrfs = (uint32_t*) malloc(mrfs_size*sizeof(uint32_t));
    printf("Filling %d MRFs with %d elements x %d words\n", bank_num, bank_width, bank_depth);
    printf("MRF buffer size = %d Bytes\n", mrfs_size * 4);

    // Add header line
    uint64_t header_data = 0;
    header_data += 5;
    header_data += ((bank_num * bank_depth + 1) << 3);
    *(mrfs) = header_data & 0xFFFFFFFF;
    *(mrfs+1) = (header_data >> 32) & 0xFFFFFFFF;
    for (b = 2; b < 16; b++) {
        *(mrfs+b) = 0;
    }

    // Add MRF content
    for (i = 0; i < bank_num; i++) {
        for (j = 0; j < bank_depth; j++) {
            // Construct data for one cache line
            uint32_t* line_pos;
            for (k = 0; k < bank_width/4; k++) {
                int tmp0, tmp1, tmp2, tmp3;
                fscanf(database, "%d %d %d %d", &tmp0, &tmp1, &tmp2, &tmp3);
                line_pos = mrfs + 16 + (j*bank_num+i)*16 + k + (16-bank_width/4);
                *line_pos = ((tmp0 & 0xFF) + ((tmp1 & 0xFF) << 8) + ((tmp2 & 0xFF) << 16) + ((tmp3 & 0xFF) << 24));
            }
            add_tags(line_pos-15, bank_width, i, j, 1, bank_num*bank_depth, bank_num*bank_depth);
        }
    }
    for (i = (bank_num*bank_depth+1)*16; i < mrfs_size; i++) mrfs[i] = 0; // padding zeros

#ifdef DEBUG
    uint32_t ctmp;//, count;
    for (int l = 0; l < bank_num*bank_depth+1; l++){
        for (int e = 15; e >= 0; e--){
            for (int b = 0; b < 32; b++) {
                ctmp = (uint32_t) mrfs[l*16 + e];
                ctmp = (ctmp >> (31-b)) & 1;
                if(ctmp){
                    mrf_data_file << "1";
                } else {
                    mrf_data_file << "0";
                }
            }
        }
        mrf_data_file << "\n";
    }
#endif
    mrf_data_file.close();
    fclose(database);
    printf("Finished parsing MRF file!\n");

    //---------------------------------------------------------
    //read instructions.dat to a buffer
    //---------------------------------------------------------
    
    database = fopen("instructions.dat", "r");

    if (NULL == database)
    {
         perror("can't open instructions.dat");
        return;
    }

    // read instructions metadata
    int num_instr;
    fscanf(database, "%d %d", &num_instr, &bank_width);
    ofstream inst_data_file;
    inst_data_file.open("inst_data_host");

    // read instruction data
    int inst_buf_size = ((num_instr+1+4095)/4096)*4096*16;
    instruction = (uint32_t*) malloc(inst_buf_size*sizeof(uint32_t));
    printf("Filling instruction memory with %d elements x %d words\n", bank_width, num_instr);
    printf("Instruction buffer size = %d Bytes\n", inst_buf_size * 4);

    // Add header line
    header_data = 0;
    header_data += 5;
    header_data += ((num_instr + 1) << 3);
    *(instruction) = header_data & 0xFFFFFFFF;
    *(instruction+1) = (header_data >> 32) & 0xFFFFFFFF;
    for (b = 2; b < 16; b++) {
        *(instruction+b) = 0;
    }

    // Add Inst content
    for (i = 0; i < num_instr; i++) {
        uint32_t* line_pos;
        for (j = 0; j < bank_width/4; j++) {
            int tmp0, tmp1, tmp2, tmp3;
            fscanf(database, "%d %d %d %d", &tmp0, &tmp1, &tmp2, &tmp3);
            line_pos = instruction + 16 + i*16 + j + (16-bank_width/4);
            *line_pos = ((tmp0 & 0xFF) + ((tmp1 & 0xFF) << 8) + ((tmp2 & 0xFF) << 16) + ((tmp3 & 0xFF) << 24));
        }
        add_tags(line_pos-15, bank_width, 0, i, 2, num_instr, num_instr);
    }
    for (i = (num_instr+1)*16; i < inst_buf_size; i++) instruction[i] = 0; // padding zeros

#ifdef DEBUG
    for (int l = 0; l < num_instr+1; l++){
        for (int e = 15; e >= 0; e--){
            for (int b = 0; b < 32; b++) {
                ctmp = (uint32_t) instruction[l*16 + e];
                ctmp = (ctmp >> (31-b)) & 1;
                if(ctmp){
                    inst_data_file << "1";
                } else {
                    inst_data_file << "0";
                }
            }
        }
        inst_data_file << "\n";
    }
#endif
    inst_data_file.close();
    fclose(database);
    printf("Finished parsing Instructions file!\n");

    //-------------------------------------------------
    //read inputs.dat then send out input data to FPGA
    //------------------------------------------------
    int num_inputs, input_width, num_outputs, output_width, lines_per_iteration;
    database = fopen("inputs.dat", "r");

    ofstream input_data_file;
    input_data_file.open("input_data_host");

    if (NULL == database)
    {
         perror("can't open inputs.dat");
        return;
    }

    // read inputs metadata
    fscanf(database, "%d %d %d %d %d", &num_inputs, &input_width, &num_outputs, &output_width, &lines_per_iteration);

    int input_buf_size = ((num_inputs+2+4095)/4096)*4096*16;
    printf("Filling input memory with %d elements x %d words\n", input_width, num_inputs);
    printf("Input buffer size = %d Bytes\n", input_buf_size * 4);

    // read input data
    input_data = (uint32_t*) malloc(input_buf_size*sizeof(uint32_t));

    // Add header lines
    header_data = 0;
    header_data += 5;
    header_data += ((num_inputs + 2) << 3);
    *(input_data) = header_data & 0xFFFFFFFF;
    *(input_data+1) = (header_data >> 32) & 0xFFFFFFFF;
    for (b = 2; b < 16; b++) {
        *(input_data+b) = 0;
    }

    header_data = 0;
    header_data += 6;
    header_data += ((num_outputs) << 3);
    *(input_data+16) = header_data & 0xFFFFFFFF;
    *(input_data+17) = (header_data >> 32) & 0xFFFFFFFF;
    for (b = 2; b < 16; b++) {
        *(input_data+16+b) = 0;
    }

    // Add input content
    for (i = 0; i < num_inputs; i++) {
        uint32_t* line_pos;
        // Construct data for one cache line
        for (j = 0; j < input_width/4; j++) {
            int tmp0, tmp1, tmp2, tmp3;
            fscanf(database, "%d %d %d %d", &tmp0, &tmp1, &tmp2, &tmp3);
            line_pos = input_data + 32 + i*16 + j + (16-input_width/4);
            *line_pos = ((tmp0 & 0xFF) + ((tmp1 & 0xFF) << 8) + ((tmp2 & 0xFF) << 16) + ((tmp3 & 0xFF) << 24));
        }
        add_tags(line_pos-15, input_width, 0, 0, 3+(i%2), i, lines_per_iteration);
    }
    //cout << "padding " << (input_buf_size - num_inputs*64)/1024 << " KB zeros" << endl;
    for (i = (num_inputs+2)*16; i < input_buf_size; i++) input_data[i] = 0; // padding zeros

#ifdef DEBUG
    for (int l = 0; l < num_inputs+2; l++){
        for (int e = 15; e >= 0; e--){
            for (int b = 0; b < 32; b++) {
                ctmp = (uint32_t) input_data[l*16 + e];
                ctmp = (ctmp >> (31-b)) & 1;
                if(ctmp){
                    input_data_file << "1";
                } else {
                    input_data_file << "0";
                }
            }
        }
        input_data_file << "\n";
    }
#endif

    input_data_file.close();
    fclose(database);
    printf("Finished parsing Inputs file!\n");
    
    //-----------------------------------------------------------------------
    //read outputs.dat then read data from FPGA to compare with golden data
    //-----------------------------------------------------------------------
    database = fopen("outputs.dat", "r");
    ofstream golden_data_file;
    golden_data_file.open("golden_data_host");

    if (NULL == database)
    {
        perror("can't open outputs.dat");
        return;
    }

    int output_buf_size = ((num_outputs+4095)/4096)*4096*16;

    //read output data
    golden_data = (uint32_t*) malloc(output_buf_size*sizeof(uint32_t));
    for (i = 0; i < num_outputs; i++) {
        // Construct data for one cache line
        for (j = 0; j < output_width/4; j++) {
            int tmp0, tmp1, tmp2, tmp3;
            fscanf(database, "%d %d %d %d", &tmp0, &tmp1, &tmp2, &tmp3);
            uint32_t *line_pos = golden_data + i*16 + j;
            *line_pos = ((tmp0 & 0xFF) + ((tmp1 & 0xFF) << 8) + ((tmp2 & 0xFF) << 16) + ((tmp3 & 0xFF) << 24));
        }
        for (j = output_width/4; j < 16; j++) {
            uint32_t *line_pos = golden_data + i*16 + j;
            *line_pos = 0;
        }
    }
    for (i = num_outputs*16; i < output_buf_size; i++) golden_data[i] = 0; // padding zeros

#ifdef DEBUG
    for (int l = 0; l < num_outputs; l++){
        for (int e = output_width/4-1; e >= 0; e--){
            for (int b = 0; b < 32; b++) {
                ctmp = (uint32_t) golden_data[l*16 + e];
                ctmp = (ctmp >> (31-b)) & 1;
                if(ctmp){
                    golden_data_file << "1";
                }else{
                    golden_data_file << "0";
                }
            }
        }
        golden_data_file << "\n";
    }
#endif

    golden_data_file.close();
    fclose(database);
    printf("Finished parsing Golden Outputs file!\n");

    //-----------------------------------------------------------------------
    //reset NPU
    //-----------------------------------------------------------------------
    dma_write(dev, H2D_BUF0_START, NPU_SOFT_RST, 32, 1);
    // FILE *logfile = fopen("npu_log.txt", "r+");
    // int wr_buf_idx, rd_buf_idx;
    // fscanf(logfile, "%d %d", &wr_buf_idx, &rd_buf_idx);

    // rewind(logfile);
    // printf("wr buf idx: %d, rd buf idx: %d\n", wr_buf_idx, rd_buf_idx);
    // fclose(logfile);

    //-----------------------------------------------------------------------
    //send mrfs
    //-----------------------------------------------------------------------
    // each buffer has 4096 cache lines
    int wr_pos = 0;
    int wr_buf_idx = 0;
    int rd_buf_idx = 0;
    int buf_status;
    while (wr_pos < mrfs_size) {
        // poll buf status
        dma_read(dev, D2H_BUF0_START, POLL_RAM_STATUS, 32, 1);
        buf_status = *(kdata+D2H_BUF0_START/DW_SIZE);
        //printf("Polling write buffer %d ... Status: %x\n", wr_buf_idx, buf_status);
        if (check_wb_ready(buf_status, wr_buf_idx) == 1) {
            // send data to buf if buf is ready
            int kmem_wr_offset = (wr_buf_idx) ? H2D_BUF1_START : H2D_BUF0_START;
            int fpga_buf_offset = (wr_buf_idx) ? BUF_SIZE : 0;
            uint32_t* kmem_wr_pos = kdata + kmem_wr_offset/DW_SIZE;
            // copy 4096 lines of data from mrfs host buffer to DMA send buffer
            memcpy(kmem_wr_pos, &mrfs[wr_pos], BUF_SIZE);
            // issue DMA write
            dma_write(dev,kmem_wr_offset,fpga_buf_offset,NUM_DW,NUM_DESC/2);
            wr_pos += BUF_SIZE/4;
            //printf("Wrote to buffer %d\n", wr_buf_idx);
            // switch to the other buffer
            wr_buf_idx = wr_buf_idx ^ 1;
        }
    }
    printf("Finished sending MRFs\n");

    //-----------------------------------------------------------------------
    //send instructions
    //-----------------------------------------------------------------------
    struct timeval start, end;
    wr_pos = 0;
    while (wr_pos < inst_buf_size) {
        // poll buf status
        dma_read(dev,D2H_BUF0_START,POLL_RAM_STATUS,32,1);
        buf_status = *(kdata+D2H_BUF0_START/DW_SIZE);
        //printf("Polling write buffer %d ... Status: %x\n", wr_buf_idx, buf_status);
        if (check_wb_ready(buf_status, wr_buf_idx) == 1) {
            // send data to buf if buf is ready
            int kmem_wr_offset = (wr_buf_idx) ? H2D_BUF1_START : H2D_BUF0_START;
            int fpga_buf_offset = (wr_buf_idx) ? BUF_SIZE : 0;
            uint32_t* kmem_wr_pos = kdata + kmem_wr_offset/DW_SIZE;
            // copy 4096 lines from instruction host buffer to DMA send buffer
            memcpy(kmem_wr_pos, &instruction[wr_pos], BUF_SIZE);
            // issue dma write
            dma_write(dev,kmem_wr_offset,fpga_buf_offset,NUM_DW,NUM_DESC/2);
            wr_pos += BUF_SIZE/4;
            //printf("Wrote to buffer %d\n", wr_buf_idx);
            wr_buf_idx = wr_buf_idx ^ 1;
        }
    }
    printf("Finished sending instructions\n");

    //-----------------------------------------------------------------------
    //send inputs/receive outputs
    //-----------------------------------------------------------------------
    wr_pos = 0;
    int rd_pos = 0; // output_buf pointer
    output_data = (uint32_t*) malloc(output_buf_size*sizeof(uint32_t));

    gettimeofday(&start, 0);
    while((wr_pos < input_buf_size) || (rd_pos < output_buf_size)) {
        dma_read(dev,D2H_BUF0_START,POLL_RAM_STATUS,32,1);
        buf_status = *(kdata+D2H_BUF0_START/DW_SIZE);
        //printf("Polling buffer, Status: %x\n", buf_status);
        // read output buf
        if (check_rb_valid(buf_status, rd_buf_idx) && (rd_pos < output_buf_size)) {
            int kmem_rd_offset = (rd_buf_idx) ? D2H_BUF1_START : D2H_BUF0_START;
            int fpga_buf_offset = (rd_buf_idx) ? BUF_SIZE : 0;
            uint32_t* kmem_rd_pos = kdata + kmem_rd_offset/DW_SIZE;
            // issue DMA read
            dma_read(dev,kmem_rd_offset,fpga_buf_offset,NUM_DW,NUM_DESC/2);
            // copy data from DMA recieve buffer to output buffer
            memcpy(&output_data[rd_pos], kmem_rd_pos, BUF_SIZE);
            rd_pos += BUF_SIZE/4;
            rd_buf_idx = rd_buf_idx ^ 1;
        }
        // write input buf
        if (check_wb_ready(buf_status, wr_buf_idx) && (wr_pos < input_buf_size)) {
            int kmem_wr_offset = (wr_buf_idx) ? H2D_BUF1_START : H2D_BUF0_START;
            int fpga_buf_offset = (wr_buf_idx) ? BUF_SIZE : 0;
            uint32_t* kmem_wr_pos = kdata + kmem_wr_offset/DW_SIZE;
            // copy data from input data buffer to DMA send buffer
            memcpy(kmem_wr_pos, &input_data[wr_pos], BUF_SIZE);
            // issue DMA write
            dma_write(dev,kmem_wr_offset,fpga_buf_offset,NUM_DW,NUM_DESC/2);
            wr_pos += BUF_SIZE/4;
            wr_buf_idx = wr_buf_idx ^ 1;
        }
    }
    gettimeofday(&end, 0);
    long seconds = end.tv_sec - start.tv_sec;
    long useconds = end.tv_usec - start.tv_usec;
    double elapsed = seconds*1000 + useconds*1e-3;
    printf("Latency is %f ms\n", elapsed);

    printf("Finished sending all inputs and receiving all results!\n");

    // fprintf(logfile, "%d %d\n", wr_buf_idx, rd_buf_idx);

    //-----------------------------------------------------------------------
    //compare results
    //-----------------------------------------------------------------------
    int num_err = 0;

#ifdef DEBUG
    ofstream output_data_file;
    output_data_file.open("output_data_host");
    
    for (i = 0; i < num_outputs; i++) {
        for (int j = 0; j < output_width / 4; j++) {
            uint32_t element = output_data[(i*16)+j];
            output_data_file << (element & 0xFF) << " " << ((element >> 8) & 0xFF) << " ";
            output_data_file << ((element >> 16) & 0xFF) << " " << ((element >> 24) & 0xFF) << " ";
        }
        output_data_file << "\n";
    }
#endif

    for (i = 0; i < num_outputs; i++) {
        for (int j = 0; j < output_width / 4; j++) {
           if(golden_data[(i*16)+j] != output_data[(i*16)+j]) {
               printf("%d: Golden output = %d\n", (i*output_width)+j, golden_data[(i*16)+j]);
               printf("%d: FPGA output   = %d\n", (i*output_width)+j, output_data[(i*16)+j]);
               printf("-------------------------------\n");
               num_err++;
               //if (num_err > 100) break;
           }
        }
    }
    if (num_err == 0)
        printf("TEST PASSED!\n");
    else 
        printf("TEST FAILED! %d OUTPUT(S) ARE MISMATCHING!\n", num_err * 4 / output_width);

}

static unsigned int welcome_options(void)
{
    unsigned int option;
    bool cin_fail;

    cout << dec;
    cin >> dec;

    do {
        cout << "\n" << SEL_MENU_DELIMS << "\n";
        cout << "Intel FPGA PCIe Link Test\n";
        cout << "Version "<< version_major << "." << version_minor << "\n";
        cout << WELCOME_OPT_AUTO   << ": Automatically select a device\n";
        cout << WELCOME_OPT_MANUAL << ": Manually select a device\n";
        cout << SEL_MENU_DELIMS << endl;

        cout << "> " << flush;
        cin >> option;
        cin_fail = cin.fail();
        cin.clear();
        cin.ignore(numeric_limits<streamsize>::max(), '\n');

        if (cin_fail || (option > WELCOME_OPT_MAXNR)) {
            cout << "Invalid option" << endl;
        }
    } while (cin_fail || (option > WELCOME_OPT_MAXNR));

    return option;
}

static uint16_t sel_dev_menu(void)
{
    unsigned int bus, dev, function;
    uint16_t bdf;
    std::ios_base::fmtflags f(cout.flags()); // Record initial flags

    cout << hex;
    cin >> hex;

    cout << "Enter bus number, in hex:\n";
    cout << "> " << flush;
    cin >> bus;

    cout << "Enter device number, in hex:\n";
    cout << "> " << flush;
    cin >> dev;

    cout << "Enter function number, in hex:\n";
    cout << "> " << flush;
    cin >> function;
    cin.clear();
    cin.ignore(numeric_limits<streamsize>::max(), '\n');

    bus &= 0xFF;
    dev &= 0x1F;
    function &= 0x7;
    bdf  = bus << 8;
    bdf |= dev << 3;
    bdf |= function;

    cout << "BDF is " << showbase << bdf << "\n";
    cout << "B:D.F, in hex, is " << noshowbase << bus << ":" << dev << "." << function << endl;
    cout.flags(f); // Restore initial flags
    return bdf;
}

static int sel_bar_menu(void)
{
    int bar;
    cout << "Enter BAR number (-1 for none):\n";
    cout << "> " << flush;
    cin >> dec >> bar;
    cin.clear();
    cin.ignore(numeric_limits<streamsize>::max(), '\n');

    return bar;
}
