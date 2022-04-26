`include "npu.vh"

module npu # (
    // data width
    parameter EW       = `EW,    // element width
    parameter ACCW     = `ACCW,
    parameter DOTW     = `DOTW,
    // # functional units
    parameter NTILE    = `NTILE, // # mvu tiles
    parameter NDPE     = `NDPE,  // # dpes
    parameter NMFU     = `NMFU,  // # mfus
    parameter NVRF     = `NVRF,  // # vrfs
    parameter NMRF     = `NMRF,  // # mrfs
    // VRF & MRF
    parameter VRFD     = `VRFD,  // VRF depth
    parameter VRFAW    = `VRFAW, // VRF address width
    parameter MRFD     = `MRFD,  // MRF depth
    parameter MRFAW    = `MRFAW, // MRF address width
    parameter MRFIDW   = `MRFIDW,
    // instructions
    parameter NSIZE    = `NSIZE,
    parameter NSIZEW   = `NSIZEW,
    parameter NTAG     = `NTAG,
    parameter NTAGW    = `NTAGW,
    parameter DOT_PER_DSP = `DOT_PER_DSP,
    parameter PRIME_DOTW = `PRIME_DOTW,
    parameter NUM_DSP  = `NUM_DSP,
    parameter NUM_ACCUM= `NUM_ACCUM,
    parameter ACCIDW   = `ACCIDW,
    parameter VRFIDW   = `VRFIDW,
    parameter MIW_MVU  = `MIW_MVU,
    parameter UIW_MVU  = `UIW_MVU,
    parameter MIW_EVRF = `MIW_EVRF,
    parameter UIW_EVRF = `UIW_EVRF,
    parameter MIW_MFU  = `MIW_MFU,
    parameter UIW_MFU  = `UIW_MFU,
    parameter MIW_LD   = `MIW_LD,
    parameter UIW_LD   = `UIW_LD,
    parameter MICW     = `MICW,
    // others
    parameter QDEPTH   = `QDEPTH,  // queue depth
    parameter WB_LMT   = `WB_LMT,  // write-back limit
    parameter WB_LMTW  = `WB_LMTW,
    parameter MULT_LATENCY = `MULT_LATENCY,
    parameter DPE_PIPELINE = `DPE_PIPELINE,
    parameter SIM_FLAG = `SIM_FLAG,
    parameter TILES_THRESHOLD = `TILES_THRESHOLD,
    parameter DPES_THRESHOLD = `DPES_THRESHOLD,
    parameter RTL_DIR = `RTL_DIR,
    parameter TARGET_FPGA = `TARGET_FPGA,
    parameter INPUT_BUFFER_SIZE = `INPUT_BUFFER_SIZE,
    parameter OUTPUT_BUFFER_SIZE = `OUTPUT_BUFFER_SIZE,
    parameter INST_DEPTH = `INST_DEPTH,
    parameter INST_ADDRW = `INST_ADDRW
) (
    // Input Instructions
    input  i_minst_chain_wr_en,
    input  [MICW-1:0] i_minst_chain_wr_din,
    input  [INST_ADDRW-1:0] i_minst_chain_wr_addr,
    // Input Data
    input  i_ld_in_wr_en,
    output o_ld_in_wr_rdy,
    input  [EW*DOTW-1:0] i_ld_in_wr_din,
    output [$clog2(INPUT_BUFFER_SIZE)-1:0] o_ld_in_usedw,
    input  i_ld_in_wr_en1,
    output o_ld_in_wr_rdy1,
    input  [EW*DOTW-1:0] i_ld_in_wr_din1,
    output [$clog2(INPUT_BUFFER_SIZE)-1:0] o_ld_in_usedw1,
    // Output Data
    input  i_ld_out_rd_en,
    output o_ld_out_rd_rdy,
    output [EW*DOTW:0] o_ld_out_rd_dout,
    output [$clog2(OUTPUT_BUFFER_SIZE)-1:0] o_ld_out_usedw,
    input  i_ld_out_rd_en1,
    output o_ld_out_rd_rdy1,
    output [EW*DOTW:0] o_ld_out_rd_dout1,
    output [$clog2(OUTPUT_BUFFER_SIZE)-1:0] o_ld_out_usedw1,
    // MRF Data & Control
    input  [MRFAW-1:0] i_mrf_wr_addr, 
    input  [EW*DOTW-1:0] i_mrf_wr_data, 
    input  [MRFIDW-1:0] i_mrf_wr_en,
    // Top-level Control
    input  [2:0] diag_mode,
    input  i_start,
    input  [INST_ADDRW-1:0] pc_start_offset,
    output o_done,
    // Debug Counters
    output [31:0] o_debug_mvu_ofifo_counter,
    output [31:0] o_debug_ld_ififo_counter,
    output [31:0] o_debug_ld_wbfifo_counter,
    output [31:0] o_debug_ld_instfifo_counter,
    output [31:0] o_debug_ld_ofifo_counter,
    output [31:0] o_result_count,
    // Clock and Reset
    input  clk, 
    input  rst
);
    
	 localparam RESET_ENDPOINTS = 15;
	 localparam RESET_DELAY = 10;
	 
	 wire delayed_rst [0:RESET_ENDPOINTS-1];
	 
	star_interconnect # (
		.END_POINTS(RESET_ENDPOINTS),
		.DATAW(1),
		.LATENCY(RESET_DELAY)
	) rst_distribution (
		.clk(clk),
		.rst(1'b0),
		.i_star_in(rst),
		.o_star_out(delayed_rst)
	);

    wire delayed_start;
    pipeline_interconnect # (
        .DATAW(1),
        .LATENCY(3*RESET_DELAY)
    ) start_delay (
        .clk(clk),
        .rst(rst),
        .i_pipe_in(i_start),
        .o_pipe_out(delayed_start)
    );


   // mvu
    wire                    mvu_minst_rd_en;
    wire                    mvu_minst_rd_rdy;
    wire [MIW_MVU-1:0]      mvu_minst_rd_dout;

    wire                    mvu_minst_wr_en;
    wire                    mvu_minst_wr_rdy;
    wire [MIW_MVU-1:0]      mvu_minst_wr_din;
    wire                    mvu_uinst_rd_en;
    wire                    mvu_uinst_rd_rdy;
    wire [UIW_MVU-1:0]      mvu_uinst_rd_dout;

    wire                    mvu_uinst_wr_en;
    wire                    mvu_uinst_wr_rdy;
    wire [VRFAW-1:0]        mvu_uinst_vrf_addr;
    wire [VRFIDW-1:0]       mvu_uinst_vrf_id;
    wire                    mvu_uinst_reg_sel; 
    wire [MRFAW-1:0]        mvu_uinst_mrf_addr;
    wire [NTAGW-1:0]        mvu_uinst_tag;
    wire [1:0]              mvu_uinst_acc_op;
    wire [4:0]              mvu_uinst_acc_size;
    wire                    mvu_uinst_vrf_en;

    // evrf
    wire                    evrf_minst_rd_en;
    wire                    evrf_minst_rd_rdy;
    wire [MIW_EVRF-1:0]     evrf_minst_rd_dout;

    wire                    evrf_minst_wr_en;
    wire                    evrf_minst_wr_rdy;
    wire [MIW_EVRF-1:0]     evrf_minst_wr_din;
    wire                    evrf_uinst_rd_en;
    wire                    evrf_uinst_rd_rdy;
    wire [UIW_EVRF-1:0]     evrf_uinst_rd_dout;

    wire                    evrf_uinst_wr_en;
    wire                    evrf_uinst_wr_rdy;
    wire [VRFAW-1:0]        evrf_uinst_vrf_addr; 
    wire [1:0]              evrf_uinst_src_sel;
    wire [NTAGW-1:0]        evrf_uinst_tag;

    // mfu0
    wire                    mfu0_minst_rd_en;
    wire                    mfu0_minst_rd_rdy;
    wire [MIW_MFU-1:0]      mfu0_minst_rd_dout;

    wire                    mfu0_minst_wr_en;
    wire                    mfu0_minst_wr_rdy;
    wire [MIW_MFU-1:0]      mfu0_minst_wr_din;
    wire                    mfu0_uinst_rd_en;
    wire                    mfu0_uinst_rd_rdy;
    wire [UIW_MFU-1:0]      mfu0_uinst_rd_dout;

    wire                    mfu0_uinst_wr_en;
    wire                    mfu0_uinst_wr_rdy;
    wire [VRFAW-1:0]        mfu0_uinst_vrf0_addr; 
    wire [VRFAW-1:0]        mfu0_uinst_vrf1_addr;
    wire [5:0]              mfu0_uinst_func_op;
    wire [NTAGW-1:0]        mfu0_uinst_tag;

    // mfu1
    wire                    mfu1_minst_rd_en;
    wire                    mfu1_minst_rd_rdy;
    wire [MIW_MFU-1:0]      mfu1_minst_rd_dout;

    wire                    mfu1_minst_wr_en;
    wire                    mfu1_minst_wr_rdy;
    wire [MIW_MFU-1:0]      mfu1_minst_wr_din;
    wire                    mfu1_uinst_rd_en;
    wire                    mfu1_uinst_rd_rdy;
    wire [UIW_MFU-1:0]      mfu1_uinst_rd_dout;

    wire                    mfu1_uinst_wr_en;
    wire                    mfu1_uinst_wr_rdy;
    wire [VRFAW-1:0]        mfu1_uinst_vrf0_addr; 
    wire [VRFAW-1:0]        mfu1_uinst_vrf1_addr;
    wire [5:0]              mfu1_uinst_func_op;
    wire [NTAGW-1:0]        mfu1_uinst_tag;

    // ld
    wire                    ld_minst_rd_en;
    wire                    ld_minst_rd_rdy;
    wire [MIW_LD-1:0]       ld_minst_rd_dout;

    wire                    ld_minst_wr_en;
    wire                    ld_minst_wr_rdy;
    wire [MIW_LD-1:0]       ld_minst_wr_din;
    wire                    ld_uinst_rd_en;
    wire                    ld_uinst_rd_rdy;
    wire [UIW_LD-1:0]       ld_uinst_rd_dout;

    wire                    ld_uinst_wr_en;
    wire                    ld_uinst_wr_rdy;
    wire [2*NVRF-1:0]       ld_uinst_vrf_id; 
    wire [VRFAW-1:0]        ld_uinst_vrf0_addr;
    wire [VRFAW-1:0]        ld_uinst_vrf1_addr;
    wire                    ld_uinst_src_sel;
    wire                    ld_uinst_last;
    wire                    ld_uinst_interrupt;
    wire                    ld_uinst_report_to_host;
	 
	 wire start_from_ld;

    top_sched #(
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .MIW_MVU(MIW_MVU), .MIW_EVRF(MIW_EVRF), 
        .MIW_MFU(MIW_MFU), .MIW_LD(MIW_LD), .MICW(MICW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    ) top_sched (
        // input - macro instruction chain
        .i_minst_chain_wr_en    (i_minst_chain_wr_en),
        .i_minst_chain_wr_addr  (i_minst_chain_wr_addr),
        .i_minst_chain_wr_din   (i_minst_chain_wr_din),
        // output - MVU macro instruction
        .i_mvu_minst_rd_en      (mvu_minst_rd_en     ),
        .o_mvu_minst_rd_rdy     (mvu_minst_rd_rdy    ),
        .o_mvu_minst_rd_dout    (mvu_minst_rd_dout   ),
        // output - ext VRF macro instruction
        .i_evrf_minst_rd_en     (evrf_minst_rd_en    ),
        .o_evrf_minst_rd_rdy    (evrf_minst_rd_rdy   ),
        .o_evrf_minst_rd_dout   (evrf_minst_rd_dout  ),
        // output - MFU0 macro instruction
        .i_mfu0_minst_rd_en     (mfu0_minst_rd_en    ),
        .o_mfu0_minst_rd_rdy    (mfu0_minst_rd_rdy   ),
        .o_mfu0_minst_rd_dout   (mfu0_minst_rd_dout  ),
        // output - MFU1 macro instruction
        .i_mfu1_minst_rd_en     (mfu1_minst_rd_en    ),
        .o_mfu1_minst_rd_rdy    (mfu1_minst_rd_rdy   ),
        .o_mfu1_minst_rd_dout   (mfu1_minst_rd_dout  ),
        // output - LD macro instruction
        .i_ld_minst_rd_en       (ld_minst_rd_en      ),
        .o_ld_minst_rd_rdy      (ld_minst_rd_rdy     ),
        .o_ld_minst_rd_dout     (ld_minst_rd_dout    ),
        // start
        .i_start                (delayed_start),
	    //.i_start(start_from_ld),
        .pc_start_offset        (pc_start_offset),
        // clk & rst
        .clk (clk), 
        .rst (delayed_rst[0])
    );

    mvu_sched #(
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .MIW_MVU(MIW_MVU), .MIW_EVRF(MIW_EVRF), 
        .MIW_MFU(MIW_MFU), .MIW_LD(MIW_LD), .MICW(MICW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    ) mvu_sched (
        // input - MVU macro instruction
        .i_mvu_minst_wr_en      (mvu_minst_wr_en     ),
        .o_mvu_minst_wr_rdy     (mvu_minst_wr_rdy    ),
        .i_mvu_minst_wr_din     (mvu_minst_wr_din    ),
        // output - MVU micro instruction
        .i_mvu_uinst_rd_en      (mvu_uinst_rd_en     ),
        .o_mvu_uinst_rd_rdy     (mvu_uinst_rd_rdy    ),
        .o_mvu_uinst_rd_dout    (mvu_uinst_rd_dout   ),
        // clk & rst
        .clk (clk), .rst (delayed_rst[1]));

    evrf_sched #(
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .MIW_MVU(MIW_MVU), .MIW_EVRF(MIW_EVRF), 
        .MIW_MFU(MIW_MFU), .MIW_LD(MIW_LD), .MICW(MICW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    ) evrf_sched (
        // input - evrf macro instruction
        .i_evrf_minst_wr_en      (evrf_minst_wr_en   ),
        .o_evrf_minst_wr_rdy     (evrf_minst_wr_rdy  ),
        .i_evrf_minst_wr_din     (evrf_minst_wr_din  ),
        // output - evrf micro instruction
        .i_evrf_uinst_rd_en      (evrf_uinst_rd_en   ),
        .o_evrf_uinst_rd_rdy     (evrf_uinst_rd_rdy  ),
        .o_evrf_uinst_rd_dout    (evrf_uinst_rd_dout ),
        // clk & rst
        .clk (clk), .rst (delayed_rst[2]));

    mfu_sched #(
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .MIW_MVU(MIW_MVU), .MIW_EVRF(MIW_EVRF), 
        .MIW_MFU(MIW_MFU), .MIW_LD(MIW_LD), .MICW(MICW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    ) mfu0_sched (
        // input - mfu macro instruction
        .i_mfu_minst_wr_en      (mfu0_minst_wr_en    ),
        .o_mfu_minst_wr_rdy     (mfu0_minst_wr_rdy   ),
        .i_mfu_minst_wr_din     (mfu0_minst_wr_din   ),
        // output - mfu micro instruction
        .i_mfu_uinst_rd_en      (mfu0_uinst_rd_en    ),
        .o_mfu_uinst_rd_rdy     (mfu0_uinst_rd_rdy   ),
        .o_mfu_uinst_rd_dout    (mfu0_uinst_rd_dout  ),
        // clk & rst
        .clk (clk), .rst (delayed_rst[3]));

    mfu_sched #(
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .MIW_MVU(MIW_MVU), .MIW_EVRF(MIW_EVRF), 
        .MIW_MFU(MIW_MFU), .MIW_LD(MIW_LD), .MICW(MICW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    ) mfu1_sched (
        // input - mfu macro instruction
        .i_mfu_minst_wr_en      (mfu1_minst_wr_en    ),
        .o_mfu_minst_wr_rdy     (mfu1_minst_wr_rdy   ),
        .i_mfu_minst_wr_din     (mfu1_minst_wr_din   ),
        // output - mfu micro instruction
        .i_mfu_uinst_rd_en      (mfu1_uinst_rd_en    ),
        .o_mfu_uinst_rd_rdy     (mfu1_uinst_rd_rdy   ),
        .o_mfu_uinst_rd_dout    (mfu1_uinst_rd_dout  ),
        // clk & rst
        .clk (clk), .rst (delayed_rst[4]));

    ld_sched #(
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .MIW_MVU(MIW_MVU), .MIW_EVRF(MIW_EVRF), 
        .MIW_MFU(MIW_MFU), .MIW_LD(MIW_LD), .MICW(MICW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    ) ld_sched (
        // input - ld macro instruction
        .i_ld_minst_wr_en      (ld_minst_wr_en       ),
        .o_ld_minst_wr_rdy     (ld_minst_wr_rdy      ),
        .i_ld_minst_wr_din     (ld_minst_wr_din      ),
        // output - ld micro instruction
        .i_ld_uinst_rd_en      (ld_uinst_rd_en       ),
        .o_ld_uinst_rd_rdy     (ld_uinst_rd_rdy      ),
        .o_ld_uinst_rd_dout    (ld_uinst_rd_dout     ),
        // clk & rst
        .clk (clk), .rst (delayed_rst[5]));

    // control path
    // top - MVU
    assign mvu_minst_rd_en = (mvu_minst_rd_rdy && mvu_minst_wr_rdy);
    assign mvu_minst_wr_en = (mvu_minst_rd_rdy && mvu_minst_wr_rdy);
    assign mvu_minst_wr_din = mvu_minst_rd_dout;
    // top - ext VRF
    assign evrf_minst_rd_en = (evrf_minst_rd_rdy && evrf_minst_wr_rdy);
    assign evrf_minst_wr_en = (evrf_minst_rd_rdy && evrf_minst_wr_rdy);
    assign evrf_minst_wr_din = evrf_minst_rd_dout;
    // top - MFU0
    assign mfu0_minst_rd_en = (mfu0_minst_rd_rdy && mfu0_minst_wr_rdy);
    assign mfu0_minst_wr_en = (mfu0_minst_rd_rdy && mfu0_minst_wr_rdy);
    assign mfu0_minst_wr_din = mfu0_minst_rd_dout;
    // top - MFU1
    assign mfu1_minst_rd_en = (mfu1_minst_rd_rdy && mfu1_minst_wr_rdy);
    assign mfu1_minst_wr_en = (mfu1_minst_rd_rdy && mfu1_minst_wr_rdy);
    assign mfu1_minst_wr_din = mfu1_minst_rd_dout;
    // top - LD
    assign ld_minst_rd_en = (ld_minst_rd_rdy && ld_minst_wr_rdy);
    assign ld_minst_wr_en = (ld_minst_rd_rdy && ld_minst_wr_rdy);
    assign ld_minst_wr_din = ld_minst_rd_dout;

    // MVU
    assign mvu_uinst_rd_en = (mvu_uinst_rd_rdy && mvu_uinst_wr_rdy);
    assign mvu_uinst_wr_en = (mvu_uinst_rd_rdy && mvu_uinst_wr_rdy);
    assign {mvu_uinst_vrf_addr, mvu_uinst_vrf_id, mvu_uinst_reg_sel, mvu_uinst_mrf_addr,
            mvu_uinst_tag, mvu_uinst_acc_op, mvu_uinst_acc_size, mvu_uinst_vrf_en} = mvu_uinst_rd_dout;
    // ext VRF
    assign evrf_uinst_rd_en = (evrf_uinst_rd_rdy && evrf_uinst_wr_rdy);
    assign evrf_uinst_wr_en = (evrf_uinst_rd_rdy && evrf_uinst_wr_rdy);
    assign {evrf_uinst_vrf_addr, evrf_uinst_src_sel, evrf_uinst_tag} = evrf_uinst_rd_dout;
    // MFU0
    assign mfu0_uinst_rd_en = (mfu0_uinst_rd_rdy && mfu0_uinst_wr_rdy);
    assign mfu0_uinst_wr_en = (mfu0_uinst_rd_rdy && mfu0_uinst_wr_rdy);
    assign {mfu0_uinst_vrf0_addr, mfu0_uinst_vrf1_addr,
            mfu0_uinst_tag, mfu0_uinst_func_op} = mfu0_uinst_rd_dout;
    // MFU1
    assign mfu1_uinst_rd_en = (mfu1_uinst_rd_rdy && mfu1_uinst_wr_rdy);
    assign mfu1_uinst_wr_en = (mfu1_uinst_rd_rdy && mfu1_uinst_wr_rdy);
    assign {mfu1_uinst_vrf0_addr, mfu1_uinst_vrf1_addr,
            mfu1_uinst_tag, mfu1_uinst_func_op} = mfu1_uinst_rd_dout;
    // LD
    assign ld_uinst_rd_en = (ld_uinst_rd_rdy && ld_uinst_wr_rdy);
    assign ld_uinst_wr_en = (ld_uinst_rd_rdy && ld_uinst_wr_rdy);
    assign {ld_uinst_vrf_id, ld_uinst_vrf0_addr, ld_uinst_vrf1_addr,
            ld_uinst_src_sel, ld_uinst_last, ld_uinst_interrupt, ld_uinst_report_to_host} = ld_uinst_rd_dout;


    // pipeline datapath
    // vrf wr ctrl 
    wire                 vrf_wr_en [0:NTILE+2];
    wire [2*NVRF-1:0]    vrf_wr_id [0:NTILE+2];
    wire [VRFAW-1:0]     vrf0_wr_addr [0:NTILE+2];
    wire [VRFAW-1:0]     vrf1_wr_addr [0:NTILE+2];
    wire [ACCW*DOTW-1:0] vrf_wr_data  [0:NTILE+2];

    wire                 vrf_wr_en1 [0:NTILE+2];
    wire [2*NVRF-1:0]    vrf_wr_id1 [0:NTILE+2];
    wire [VRFAW-1:0]     vrf0_wr_addr1 [0:NTILE+2];
    wire [VRFAW-1:0]     vrf1_wr_addr1 [0:NTILE+2];
    wire [ACCW*DOTW-1:0] vrf_wr_data1  [0:NTILE+2];

    // ld
    wire                 ld_data_wr_en;
    wire                 ld_data_wr_rdy;
    wire [ACCW*DOTW-1:0] ld_data_wr_din;
    wire                 ld_ofifo_wr_ok;

    wire                 ld_data_wr_en1;
    wire                 ld_data_wr_rdy1;
    wire [ACCW*DOTW-1:0] ld_data_wr_din1;
    wire                 ld_ofifo_wr_ok1;

    // mvu
    wire [DOTW-1:0]      mvu_data_rd_en;
    wire [DOTW-1:0]      mvu_data_rd_rdy;
    wire [ACCW*NDPE-1:0] mvu_data_rd_dout;

    wire [DOTW-1:0]      mvu_data_rd_en1;
    wire [DOTW-1:0]      mvu_data_rd_rdy1;
    wire [ACCW*NDPE-1:0] mvu_data_rd_dout1;

    // evrf
    wire [DOTW-1:0]      evrf_data_wr_en;
    wire [DOTW-1:0]      evrf_data_wr_rdy;
    wire [ACCW*NDPE-1:0] evrf_data_wr_din;

    wire [DOTW-1:0]      evrf_data_wr_en1;
    wire [DOTW-1:0]      evrf_data_wr_rdy1;
    wire [ACCW*NDPE-1:0] evrf_data_wr_din1;

    // evrf
    wire [DOTW-1:0]      evrf_data_rd_en;
    wire [DOTW-1:0]      evrf_data_rd_rdy;
    wire [ACCW*DOTW-1:0] evrf_data_rd_dout;

    wire [DOTW-1:0]      evrf_data_rd_en1;
    wire [DOTW-1:0]      evrf_data_rd_rdy1;
    wire [ACCW*DOTW-1:0] evrf_data_rd_dout1;

    // mfu0
    wire [DOTW-1:0]      mfu0_data_wr_en;
    wire [DOTW-1:0]      mfu0_data_wr_rdy;
    wire [ACCW*DOTW-1:0] mfu0_data_wr_din;

    wire [DOTW-1:0]      mfu0_data_wr_en1;
    wire [DOTW-1:0]      mfu0_data_wr_rdy1;
    wire [ACCW*DOTW-1:0] mfu0_data_wr_din1;

    // mfu0
    wire [DOTW-1:0]      mfu0_data_rd_en;
    wire [DOTW-1:0]      mfu0_data_rd_rdy;
    wire [ACCW*DOTW-1:0] mfu0_data_rd_dout;

    wire [DOTW-1:0]      mfu0_data_rd_en1;
    wire [DOTW-1:0]      mfu0_data_rd_rdy1;
    wire [ACCW*DOTW-1:0] mfu0_data_rd_dout1;

    // mfu1
    wire [DOTW-1:0]      mfu1_data_wr_en;
    wire [DOTW-1:0]      mfu1_data_wr_rdy;
    wire [ACCW*DOTW-1:0] mfu1_data_wr_din;

    wire [DOTW-1:0]      mfu1_data_wr_en1;
    wire [DOTW-1:0]      mfu1_data_wr_rdy1;
    wire [ACCW*DOTW-1:0] mfu1_data_wr_din1;

    // mfu1
    wire [DOTW-1:0]      mfu1_data_rd_en;
    wire [DOTW-1:0]      mfu1_data_rd_rdy;
    wire [ACCW*DOTW-1:0] mfu1_data_rd_dout;

    wire [DOTW-1:0]      mfu1_data_rd_en1;
    wire [DOTW-1:0]      mfu1_data_rd_rdy1;
    wire [ACCW*DOTW-1:0] mfu1_data_rd_dout1;

    wire                 tag_update_en [0:NTILE+2];
    wire                 tag_update_en1 [0:NTILE+2];
    
    wire done0, done1;

    //diagnostic signals
    wire         mvu_diag_wr_en;
    wire [ACCW*NDPE-1:0] mvu_diag_wr_din;
    wire         mfu0_diag_wr_en;
    wire [ACCW*DOTW-1:0] mfu0_diag_wr_din;
    wire         mfu1_diag_wr_en;
    wire [ACCW*DOTW-1:0] mfu1_diag_wr_din;



    mvu #(
        .IW(UIW_MVU),
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW),
        .TILES_THRESHOLD(TILES_THRESHOLD), .DPES_THRESHOLD(DPES_THRESHOLD), .TARGET_FPGA(TARGET_FPGA)
    )
    mvu (
        // mrf write
        .i_mrf_wr_addr   (i_mrf_wr_addr), 
        .i_mrf_wr_data   (i_mrf_wr_data), 
        .i_mrf_wr_en     (i_mrf_wr_en),
        // vrf write
        .i_vrf0_wr_addr  (vrf0_wr_addr[0:NTILE-1]      ), 
        .i_vrf1_wr_addr  (vrf1_wr_addr[0:NTILE-1]      ), 
        .i_vrf_wr_data   (vrf_wr_data [0:NTILE-1]      ), 
        .i_vrf_wr_en     (vrf_wr_en   [0:NTILE-1]      ),
        .i_vrf_wr_id     (vrf_wr_id   [0:NTILE-1]      ),

        .i_vrf0_wr_addr1  (vrf0_wr_addr1[0:NTILE-1]      ), 
        .i_vrf1_wr_addr1  (vrf1_wr_addr1[0:NTILE-1]      ), 
        .i_vrf_wr_data1   (vrf_wr_data1 [0:NTILE-1]      ), 
        .i_vrf_wr_en1     (vrf_wr_en1   [0:NTILE-1]      ),
        .i_vrf_wr_id1     (vrf_wr_id1   [0:NTILE-1]      ),

        // instruction
        .i_inst_wr_en    (mvu_uinst_wr_en   ),
        .o_inst_wr_rdy   (mvu_uinst_wr_rdy  ),
        .i_vrf_rd_addr   (mvu_uinst_vrf_addr),
        .i_vrf_rd_id     (mvu_uinst_vrf_id),
        .i_reg_sel       (mvu_uinst_reg_sel),
        .i_mrf_rd_addr   (mvu_uinst_mrf_addr),
        .i_acc_op        (mvu_uinst_acc_op  ),
        .i_tag           (mvu_uinst_tag     ),
        .i_acc_size      (mvu_uinst_acc_size),
        .i_vrf_en        (mvu_uinst_vrf_en),
        // pipeline datapath
        .i_data_rd_en    (mvu_data_rd_en    ),
        .o_data_rd_rdy   (mvu_data_rd_rdy   ),
        .o_data_rd_dout  (mvu_data_rd_dout  ),

        .i_data_rd_en1    (mvu_data_rd_en1    ),
        .o_data_rd_rdy1   (mvu_data_rd_rdy1   ),
        .o_data_rd_dout1  (mvu_data_rd_dout1  ),
        // from ld
        .i_tag_update_en (tag_update_en [0:NTILE-1]    ),
        // clk & rst
        .clk (clk), 
        .rst (delayed_rst[6])
    );

    localparam EVRF_VRF0_ID = NTILE;
    evrf
    #(
        .VRF0_ID(EVRF_VRF0_ID), .IW(UIW_EVRF),
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    )
    evrf (
        // vrf write
        .i_vrf0_wr_addr (vrf0_wr_addr[NTILE+2]       ), 
        .i_vrf1_wr_addr (vrf1_wr_addr[NTILE+2]       ), 
        .i_vrf_wr_data  (vrf_wr_data[NTILE+2]        ), 
        .i_vrf_wr_en    (vrf_wr_en [NTILE+2]         ),
        .i_vrf_wr_id    (vrf_wr_id [NTILE+2]         ),
        // pipeline datapath (in)
        .i_data_wr_en   (evrf_data_wr_en    ),
        .o_data_wr_rdy  (evrf_data_wr_rdy   ),
        .i_data_wr_din  (evrf_data_wr_din   ),
        // pipeline datapath (out)
        .i_data_rd_en   (evrf_data_rd_en    ),
        .o_data_rd_rdy  (evrf_data_rd_rdy   ),
        .o_data_rd_dout (evrf_data_rd_dout  ),       
        // instruction
        .i_inst_wr_en   (evrf_uinst_wr_en   ),
        .o_inst_wr_rdy  (evrf_uinst_wr_rdy  ),
        .i_vrf_rd_addr  (evrf_uinst_vrf_addr),
        .i_src_sel      (evrf_uinst_src_sel ),
        .i_tag          (evrf_uinst_tag     ),
        // from ld
        .i_tag_update_en (tag_update_en [NTILE+2]    ),
        // clk & rst
        .clk(clk), .rst(delayed_rst[7]));

    evrf
    #(
        .VRF0_ID(EVRF_VRF0_ID), .IW(UIW_EVRF),
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    )
    evrf1 (
        // vrf write
        .i_vrf0_wr_addr (vrf0_wr_addr1[NTILE+2]       ), 
        .i_vrf1_wr_addr (vrf1_wr_addr1[NTILE+2]       ), 
        .i_vrf_wr_data  (vrf_wr_data1[NTILE+2]        ), 
        .i_vrf_wr_en    (vrf_wr_en1 [NTILE+2]         ),
        .i_vrf_wr_id    (vrf_wr_id1 [NTILE+2]         ),
        // pipeline datapath (in)
        .i_data_wr_en   (evrf_data_wr_en1    ),
        .o_data_wr_rdy  (evrf_data_wr_rdy1   ),
        .i_data_wr_din  (evrf_data_wr_din1   ),
        // pipeline datapath (out)
        .i_data_rd_en   (evrf_data_rd_en1    ),
        .o_data_rd_rdy  (evrf_data_rd_rdy1   ),
        .o_data_rd_dout (evrf_data_rd_dout1  ),       
        // instruction
        .i_inst_wr_en   (evrf_uinst_wr_en   ),
        //.o_inst_wr_rdy  (evrf_uinst_wr_rdy  ),
        .i_vrf_rd_addr  (evrf_uinst_vrf_addr),
        .i_src_sel      (evrf_uinst_src_sel ),
        .i_tag          (evrf_uinst_tag     ),
        // from ld
        .i_tag_update_en (tag_update_en1 [NTILE+2]    ),
        // clk & rst
        .clk(clk), .rst(delayed_rst[8]));

    localparam MFU0_VRF0_ID = NTILE+1;
    localparam MFU0_VRF1_ID = NTILE+2;
    mfu
    #(
        .MFU_ID("mfu0"), .VRF0_ID(MFU0_VRF0_ID), .VRF1_ID(MFU0_VRF1_ID), .IW(UIW_MFU),
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW), .RTL_DIR(RTL_DIR)
    )
    mfu0 (
        // vrf write
        .i_vrf0_wr_addr (vrf0_wr_addr [NTILE]       ), 
        .i_vrf1_wr_addr (vrf1_wr_addr [NTILE]       ), 
        .i_vrf_wr_data  (vrf_wr_data [NTILE]        ), 
        .i_vrf_wr_en    (vrf_wr_en [NTILE]         ),
        .i_vrf_wr_id    (vrf_wr_id [NTILE]         ),
        // pipeline datapath (in)
        .i_data_wr_en   (mfu0_data_wr_en     ),
        .o_data_wr_rdy  (mfu0_data_wr_rdy    ),
        .i_data_wr_din  (mfu0_data_wr_din    ),
        // pipeline datapath (out)
        .i_data_rd_en   (mfu0_data_rd_en     ),
        .o_data_rd_rdy  (mfu0_data_rd_rdy    ),
        .o_data_rd_dout (mfu0_data_rd_dout   ),       
        // instruction
        .i_inst_wr_en   (mfu0_uinst_wr_en    ),
        .o_inst_wr_rdy  (mfu0_uinst_wr_rdy   ),
        .i_vrf0_rd_addr (mfu0_uinst_vrf0_addr),
        .i_vrf1_rd_addr (mfu0_uinst_vrf1_addr),
        .i_func_op      (mfu0_uinst_func_op  ),
        .i_tag          (mfu0_uinst_tag      ),
        // from ld
        .i_tag_update_en (tag_update_en [NTILE]     ),
        // clk & rst
        .clk(clk), .rst(delayed_rst[9]));

    mfu
    #(
        .MFU_ID("mfu0"), .VRF0_ID(MFU0_VRF0_ID), .VRF1_ID(MFU0_VRF1_ID), .IW(UIW_MFU),
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW), .RTL_DIR(RTL_DIR)
    )
    mfu0_1 (
        // vrf write
        .i_vrf0_wr_addr (vrf0_wr_addr1 [NTILE]       ), 
        .i_vrf1_wr_addr (vrf1_wr_addr1 [NTILE]       ), 
        .i_vrf_wr_data  (vrf_wr_data1 [NTILE]        ), 
        .i_vrf_wr_en    (vrf_wr_en1 [NTILE]         ),
        .i_vrf_wr_id    (vrf_wr_id1 [NTILE]         ),
        // pipeline datapath (in)
        .i_data_wr_en   (mfu0_data_wr_en1     ),
        .o_data_wr_rdy  (mfu0_data_wr_rdy1    ),
        .i_data_wr_din  (mfu0_data_wr_din1    ),
        // pipeline datapath (out)
        .i_data_rd_en   (mfu0_data_rd_en1     ),
        .o_data_rd_rdy  (mfu0_data_rd_rdy1    ),
        .o_data_rd_dout (mfu0_data_rd_dout1   ),       
        // instruction
        .i_inst_wr_en   (mfu0_uinst_wr_en    ),
        //.o_inst_wr_rdy  (mfu0_uinst_wr_rdy   ),
        .i_vrf0_rd_addr (mfu0_uinst_vrf0_addr),
        .i_vrf1_rd_addr (mfu0_uinst_vrf1_addr),
        .i_func_op      (mfu0_uinst_func_op  ),
        .i_tag          (mfu0_uinst_tag      ),
        // from ld
        .i_tag_update_en (tag_update_en1 [NTILE]     ),
        // clk & rst
        .clk(clk), .rst(delayed_rst[10]));

    localparam MFU1_VRF0_ID = NTILE+3;
    localparam MFU1_VRF1_ID = NTILE+4;
    mfu
    #(
        .MFU_ID("mfu1"), .VRF0_ID(MFU1_VRF0_ID), .VRF1_ID(MFU1_VRF1_ID), .IW(UIW_MFU),
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW), .RTL_DIR(RTL_DIR)
    )
    mfu1 (
        // vrf write
        .i_vrf0_wr_addr (vrf0_wr_addr [NTILE+1]       ), 
        .i_vrf1_wr_addr (vrf1_wr_addr [NTILE+1]       ), 
        .i_vrf_wr_data  (vrf_wr_data [NTILE+1]        ), 
        .i_vrf_wr_en    (vrf_wr_en [NTILE+1]          ),
        .i_vrf_wr_id    (vrf_wr_id [NTILE+1]          ),
        // pipeline datapath (in)
        .i_data_wr_en   (mfu1_data_wr_en     ),
        .o_data_wr_rdy  (mfu1_data_wr_rdy    ),
        .i_data_wr_din  (mfu1_data_wr_din    ),
        // pipeline datapath (out)
        .i_data_rd_en   (mfu1_data_rd_en     ),
        .o_data_rd_rdy  (mfu1_data_rd_rdy    ),
        .o_data_rd_dout (mfu1_data_rd_dout   ),       
        // instruction
        .i_inst_wr_en   (mfu1_uinst_wr_en    ),
        .o_inst_wr_rdy  (mfu1_uinst_wr_rdy   ),
        .i_vrf0_rd_addr (mfu1_uinst_vrf0_addr),
        .i_vrf1_rd_addr (mfu1_uinst_vrf1_addr),
        .i_func_op      (mfu1_uinst_func_op  ),
        .i_tag          (mfu1_uinst_tag      ),
        // from ld
        .i_tag_update_en (tag_update_en [NTILE+1]     ),
        // clk & rst
        .clk(clk), .rst(delayed_rst[11]));

    mfu
    #(
        .MFU_ID("mfu1"), .VRF0_ID(MFU1_VRF0_ID), .VRF1_ID(MFU1_VRF1_ID), .IW(UIW_MFU),
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW), .RTL_DIR(RTL_DIR)
    )
    mfu1_1 (
        // vrf write
        .i_vrf0_wr_addr (vrf0_wr_addr1 [NTILE+1]       ), 
        .i_vrf1_wr_addr (vrf1_wr_addr1 [NTILE+1]       ), 
        .i_vrf_wr_data  (vrf_wr_data1 [NTILE+1]        ), 
        .i_vrf_wr_en    (vrf_wr_en1 [NTILE+1]          ),
        .i_vrf_wr_id    (vrf_wr_id1 [NTILE+1]          ),
        // pipeline datapath (in)
        .i_data_wr_en   (mfu1_data_wr_en1     ),
        .o_data_wr_rdy  (mfu1_data_wr_rdy1    ),
        .i_data_wr_din  (mfu1_data_wr_din1    ),
        // pipeline datapath (out)
        .i_data_rd_en   (mfu1_data_rd_en1     ),
        .o_data_rd_rdy  (mfu1_data_rd_rdy1    ),
        .o_data_rd_dout (mfu1_data_rd_dout1   ),       
        // instruction
        .i_inst_wr_en   (mfu1_uinst_wr_en    ),
        //.o_inst_wr_rdy  (mfu1_uinst_wr_rdy   ),
        .i_vrf0_rd_addr (mfu1_uinst_vrf0_addr),
        .i_vrf1_rd_addr (mfu1_uinst_vrf1_addr),
        .i_func_op      (mfu1_uinst_func_op  ),
        .i_tag          (mfu1_uinst_tag      ),
        // from ld
        .i_tag_update_en (tag_update_en1 [NTILE+1]     ),
        // clk & rst
        .clk(clk), .rst(delayed_rst[12]));


    loader #(
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    )
    ld (
        // vrf write
        .o_vrf_wr_en     (vrf_wr_en         ),
        .o_vrf_wr_id     (vrf_wr_id         ),
        .o_vrf0_wr_addr  (vrf0_wr_addr      ),
        .o_vrf1_wr_addr  (vrf1_wr_addr      ),
        .o_vrf_wr_data   (vrf_wr_data       ),
        // input datapath
        .i_in_wr_en      (i_ld_in_wr_en     ),
        .o_in_wr_rdy     (o_ld_in_wr_rdy    ),
        .i_in_wr_din     (i_ld_in_wr_din    ),
        // pipeline datapath
        .i_data_wr_en    (ld_data_wr_en     ),
        .o_data_wr_rdy   (ld_data_wr_rdy    ),
        .i_data_wr_din   (ld_data_wr_din    ),
        .i_data_rd_en    (i_ld_out_rd_en    ),
        .o_data_rd_rdy   (o_ld_out_rd_rdy   ),
        .o_data_rd_dout  (o_ld_out_rd_dout  ),
        .o_data_usedw    (o_ld_out_usedw    ),
        // instruction
        .i_inst_wr_en    (ld_uinst_wr_en    ),
        .o_inst_wr_rdy   (ld_uinst_wr_rdy   ),
        .i_vrf_wr_id     (ld_uinst_vrf_id   ),
        .i_vrf0_wr_addr  (ld_uinst_vrf0_addr),
        .i_vrf1_wr_addr  (ld_uinst_vrf1_addr),
        .i_vrf_wr_src    (ld_uinst_src_sel  ),
        .i_vrf_wr_last   (ld_uinst_last     ),
        .i_interrupt     (ld_uinst_interrupt),
        .i_report_to_host(ld_uinst_report_to_host),
        // from ld
        .o_tag_update_en (tag_update_en     ),
        // debug counters
        .o_debug_ld_ififo_counter   (o_debug_ld_ififo_counter),
        .o_debug_ld_wbfifo_counter  (o_debug_ld_wbfifo_counter),
        .o_debug_ld_instfifo_counter(o_debug_ld_instfifo_counter),
        .o_debug_ld_ofifo_counter   (o_debug_ld_ofifo_counter),
        .o_result_count (o_result_count),
        // o_done
        //.o_done          (done0            ),
		  .o_start(start_from_ld),
        //diagnostic signals
        .diag_mode    (diag_mode),
        .o_data_wr_ok     (ld_ofifo_wr_ok),

        .i_mvu_data_wr_en  (mvu_diag_wr_en),
        .i_mvu_data    (mvu_diag_wr_din),
        .i_mfu0_data_wr_en (mfu0_diag_wr_en),
        .i_mfu0_data       (mfu0_diag_wr_din),
        .i_mfu1_data_wr_en (mfu1_diag_wr_en),
        .i_mfu1_data       (mfu1_diag_wr_din),
        // clk & rst
        .clk(clk), .rst(rst));

    loader #(
        .EW(EW), .ACCW(ACCW), .DOTW(DOTW),
        .VRFD(VRFD), .VRFAW(VRFAW), .MRFD(MRFD), .MRFAW(MRFAW),
        .NTILE(NTILE), .NDPE(NDPE), .NMFU(NMFU), .NVRF(NVRF), .NMRF(NMRF),
        //.DW(DW), .ACC_DW(ACC_DW),
        .NSIZE(NSIZE), .NSIZEW(NSIZEW), .NTAG(NTAG), .NTAGW(NTAGW),
        .QDEPTH(QDEPTH), .WB_LMT(WB_LMT), .WB_LMTW(WB_LMTW)
    ) ld1 (
        // vrf write
        .o_vrf_wr_en     (vrf_wr_en1         ),
        .o_vrf_wr_id     (vrf_wr_id1         ),
        .o_vrf0_wr_addr  (vrf0_wr_addr1      ),
        .o_vrf1_wr_addr  (vrf1_wr_addr1      ),
        .o_vrf_wr_data   (vrf_wr_data1       ),
        // input datapath
        .i_in_wr_en      (i_ld_in_wr_en1     ),
        .o_in_wr_rdy     (o_ld_in_wr_rdy1    ),
        .i_in_wr_din     (i_ld_in_wr_din1    ),
        // pipeline datapath
        .i_data_wr_en    (ld_data_wr_en1     ),
        .o_data_wr_rdy   (ld_data_wr_rdy1    ),
        .i_data_wr_din   (ld_data_wr_din1    ),
        .i_data_rd_en    (i_ld_out_rd_en1    ),
        .o_data_rd_rdy   (o_ld_out_rd_rdy1   ),
        .o_data_rd_dout  (o_ld_out_rd_dout1  ),    
        // instruction
        .i_inst_wr_en    (ld_uinst_wr_en    ),
        //.o_inst_wr_rdy   (ld_uinst_wr_rdy   ),
        .i_vrf_wr_id     (ld_uinst_vrf_id   ),
        .i_vrf0_wr_addr  (ld_uinst_vrf0_addr),
        .i_vrf1_wr_addr  (ld_uinst_vrf1_addr),
        .i_vrf_wr_src    (ld_uinst_src_sel  ),
        .i_vrf_wr_last   (ld_uinst_last     ),
        .i_interrupt     (ld_uinst_interrupt),
        .i_report_to_host(ld_uinst_report_to_host),
        // from ld
        .o_tag_update_en (tag_update_en1     ),
        //.o_done          (done1            ),
        // clk & rst
        .clk(clk), .rst(rst));

    // mvu - evrf
    genvar s;
    generate 
        for (s = 0; s < DOTW; s = s + 1) begin: gen_signals
            assign mvu_data_rd_en[s]  = mvu_data_rd_rdy[s]  && evrf_data_wr_rdy[s];
            assign evrf_data_wr_en[s] = mvu_data_rd_rdy[s]  && evrf_data_wr_rdy[s];
            assign evrf_data_rd_en[s] = evrf_data_rd_rdy[s] && mfu0_data_wr_rdy[s];
            assign mfu0_data_wr_en[s] = evrf_data_rd_rdy[s] && mfu0_data_wr_rdy[s];
            assign mfu0_data_rd_en[s] = mfu0_data_rd_rdy[s] && mfu1_data_wr_rdy[s];
            assign mfu1_data_wr_en[s] = mfu0_data_rd_rdy[s] && mfu1_data_wr_rdy[s];
            assign mfu1_data_rd_en[s] = mfu1_data_rd_rdy[s] && ld_data_wr_rdy;

            assign mvu_data_rd_en1[s]  = mvu_data_rd_rdy1[s]  && evrf_data_wr_rdy1[s];
            assign evrf_data_wr_en1[s] = mvu_data_rd_rdy1[s]  && evrf_data_wr_rdy1[s];
            assign evrf_data_rd_en1[s] = evrf_data_rd_rdy1[s] && mfu0_data_wr_rdy1[s];
            assign mfu0_data_wr_en1[s] = evrf_data_rd_rdy1[s] && mfu0_data_wr_rdy1[s];
            assign mfu0_data_rd_en1[s] = mfu0_data_rd_rdy1[s] && mfu1_data_wr_rdy1[s];
            assign mfu1_data_wr_en1[s] = mfu0_data_rd_rdy1[s] && mfu1_data_wr_rdy1[s];
            assign mfu1_data_rd_en1[s] = mfu1_data_rd_rdy1[s] && ld_data_wr_rdy1;
        end
    endgenerate
    assign evrf_data_wr_din = mvu_data_rd_dout;
    assign mfu0_data_wr_din = evrf_data_rd_dout;
    assign mfu1_data_wr_din = mfu0_data_rd_dout;
    assign ld_data_wr_en = (mfu1_data_rd_rdy[0] && ld_data_wr_rdy);
    assign ld_data_wr_din = mfu1_data_rd_dout;

    assign evrf_data_wr_din1 = mvu_data_rd_dout1;
    assign mfu0_data_wr_din1 = evrf_data_rd_dout1;
    assign mfu1_data_wr_din1 = mfu0_data_rd_dout1;
    assign ld_data_wr_en1 = (mfu1_data_rd_rdy1[0] && ld_data_wr_rdy1);
    assign ld_data_wr_din1 = mfu1_data_rd_dout1;

    assign mvu_diag_wr_en = (mvu_data_rd_rdy && evrf_data_wr_rdy && ld_ofifo_wr_ok );
    assign mvu_diag_wr_din =  mvu_data_rd_dout;
    assign mfu0_diag_wr_en = (mfu0_data_rd_rdy && mfu1_data_wr_rdy && ld_ofifo_wr_ok );
    assign mfu0_diag_wr_din = mfu0_data_rd_dout;
    assign mfu1_diag_wr_en = (mfu1_data_rd_rdy && ld_data_wr_rdy && ld_ofifo_wr_ok );
    assign mfu1_diag_wr_din = mfu1_data_rd_dout;

endmodule
