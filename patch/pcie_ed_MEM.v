`timescale 1 ps / 1 ps

`include "../rtl/npu.vh"

module pcie_ed_MEM # (
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
    parameter OUTPUT_BUFFER_SIZE = `OUTPUT_BUFFER_SIZE,
    parameter INST_DEPTH = `INST_DEPTH,
    parameter INST_ADDRW = `INST_ADDRW  
)(
  //AVMM interface to DMA read buffer (i.e. FPGA to host)
  input  wire [13:0]  address,
  output wire [511:0] readdata,
  input  wire         clken,      // can be ignored
  input  wire         chipselect,  // can be ignored
  input  wire         write,       // can be ignored
  input  wire [511:0] writedata,   // can be ignored
  input  wire [63:0]  byteenable,  // can be ignored 
  //AVMM interface to DMA write buffer (i.e. host to FPGA)
  input  wire [13:0]  address2,
    output wire [511:0] readdata2,
  input  wire         clken2,   // can be ignored
  input  wire         chipselect2, // can be ignored  
  input  wire         write2, 
  input  wire [511:0] writedata2,
  input  wire [63:0]  byteenable2,
  //clk & reset signals
  input  wire         clk,
  input  wire         reset,
  input  wire         reset_req
);

// Local parameters
localparam DMA_ADDR_OFFFSET = 14'h400;   // Constant offset for DMA read/write addresses
localparam DMA_POLL_REG = 14'h2004;     // Address for DMA status register
localparam DMA_SOFT_RST = 14'h2008;
localparam BUF0_START = 14'h0, BUF0_END = 14'hfff, BUF1_START = 14'h1000, BUF1_END = 14'h1fff; // Boundaries of double buffer

// Dummy signals that can be ignored 
wire [511:0] dummy_writedata;
wire [63:0] dummy_byteenable;
wire dummy_write, dummy_clken, dummy_clken2, dummy_chipselect, dummy_chipselect2;
assign readdata2 = 512'd0;
assign dummy_writedata = writedata;
assign dummy_byteenable = byteenable;
assign dummy_write = write;
assign dummy_clken = clken; 
assign dummy_clken2 = clken2; 
assign dummy_chipselect = chipselect; 
assign dummy_chipselect2 = chipselect2;

// Soft Reset
reg soft_rst;
reg [15:0] debug_counter_wr; /* synthesis keep */
reg [15:0] debug_counter_rd; /* synthesis keep */

//Chipselect delay
reg chipselect_flop1;
reg chipselect_flop2;

// Double buffer controller signals
wire [1:0] dma_write_buffer_last; // NPU last read
wire [1:0] dma_read_buffer_last;  // NPU last write
reg [1:0] dma_write_buffer_valid; // NPU can read
reg [1:0] dma_write_buffer_ready; // CPU can overwrite
reg [1:0] dma_read_buffer_valid;  // CPU can read
reg [1:0] dma_read_buffer_ready;  // NPU can overwrite
wire dma_write_buffer_ren;

//DMA status register
reg [511:0] dma_status;
reg [511:0] r_dma_status;

// DMA Input to NPU shim interface signals
wire [13:0] dma_write_buffer_waddr;
assign dma_write_buffer_waddr = address2 - DMA_ADDR_OFFFSET; 
wire [12:0] dma_write_buffer_raddr;
wire [511:0] dma_write_buffer_rdata;

// DMA write buffer (inputs)
dma_buffer # (
  .WIDTH  (512),
  .DEPTH  (8192)
) dma_write_buffer (
  .clk    (clk),
  .ren    (1'b1),
  .raddr  (dma_write_buffer_raddr),
  .rdata  (dma_write_buffer_rdata),
  .wen    (write2 && chipselect2 && clken2),
  .waddr  (dma_write_buffer_waddr[12:0]),
  .wben   (byteenable2),
  .wdata  (writedata2)
);

// NPU shim to DMA output interface signals
wire [13:0] dma_read_buffer_raddr;
reg [13:0] r_dma_read_buffer_raddr, rr_dma_read_buffer_raddr;
assign dma_read_buffer_raddr = address - DMA_ADDR_OFFFSET;
wire dma_read_buffer_wen;
wire [12:0] dma_read_buffer_waddr;
wire [63:0] dma_read_buffer_wben;
wire [511:0] dma_read_buffer_wdata;
wire [511:0] dma_read_buffer_rdata;

// DMA read buffer (outputs)
dma_buffer # (
  .WIDTH  (512),
  .DEPTH  (8192)
) dma_read_buffer (
  .clk    (clk),
  .ren    (clken),
  .raddr  (dma_read_buffer_raddr[12:0]),
  .rdata  (dma_read_buffer_rdata),
  .wen    (dma_read_buffer_wen),
  .waddr  (dma_read_buffer_waddr),
  .wben   (dma_read_buffer_wben),
  .wdata  (dma_read_buffer_wdata)
);


always @(posedge clk) begin
  if (soft_rst) begin
    dma_write_buffer_valid <= 2'b00;
    dma_write_buffer_ready <= 2'b11;
  end else begin
    if (dma_write_buffer_waddr == BUF0_END && write2 && chipselect2 && clken2 && dma_write_buffer_ready[0]) begin
      dma_write_buffer_valid[0] <= 1'b1;
      dma_write_buffer_ready[0] <= 1'b0;
    end else if (dma_write_buffer_last[0] && /*dma_write_buffer_ren &&*/ dma_write_buffer_valid[0]) begin
    //end else if (dma_write_buffer_raddr == BUF0_END && dma_write_buffer_ren && dma_write_buffer_valid[0]) begin
      dma_write_buffer_valid[0] <= 1'b0;
      dma_write_buffer_ready[0] <= 1'b1;
    end

    if (dma_write_buffer_waddr == BUF1_END && write2 && chipselect2 && clken2 && dma_write_buffer_ready[1]) begin
      dma_write_buffer_valid[1] <= 1'b1;
      dma_write_buffer_ready[1] <= 1'b0;
    end else if (dma_write_buffer_last[1] && /*dma_write_buffer_ren &&*/ dma_write_buffer_valid[1]) begin
    //end else if (dma_write_buffer_raddr == BUF1_END && dma_write_buffer_ren && dma_write_buffer_valid[1]) begin
      dma_write_buffer_valid[1] <= 1'b0;
      dma_write_buffer_ready[1] <= 1'b1;
    end
  end
end

always @(posedge clk) begin
  if (soft_rst) begin
    debug_counter_wr <= 'd0;
  end else begin
    if ((dma_write_buffer_last[0] && dma_write_buffer_valid[0]) || (dma_write_buffer_last[1] && dma_write_buffer_valid[1])) begin
      debug_counter_wr <= debug_counter_wr + 16'd1;
    end
  end
end

always @(posedge clk) begin
  if(soft_rst) begin
    dma_read_buffer_valid <= 2'b00;
    dma_read_buffer_ready <= 2'b11;
  end else begin
    if (dma_read_buffer_last[0] /*&& dma_read_buffer_wen*/ && dma_read_buffer_ready[0]) begin
    //if (dma_read_buffer_waddr == BUF0_END && dma_read_buffer_wen && dma_read_buffer_ready[0]) begin
      dma_read_buffer_valid[0] <= 1'b1;
      dma_read_buffer_ready[0] <= 1'b0;
    end else if (dma_read_buffer_raddr == BUF0_END && clken && chipselect && dma_read_buffer_valid[0]) begin
      dma_read_buffer_valid[0] <= 1'b0;
      dma_read_buffer_ready[0] <= 1'b1;
    end
    
    if (dma_read_buffer_last[1] && /*dma_read_buffer_wen &&*/ dma_read_buffer_ready[1]) begin
    //if (dma_read_buffer_waddr == BUF1_END && dma_read_buffer_wen && dma_read_buffer_ready[1]) begin
      dma_read_buffer_valid[1] <= 1'b1;
      dma_read_buffer_ready[1] <= 1'b0;
    end else if (dma_read_buffer_raddr == BUF1_END && clken && chipselect && dma_read_buffer_valid[1]) begin
      dma_read_buffer_valid[1] <= 1'b0;
      dma_read_buffer_ready[1] <= 1'b1;
    end
  end
end

always @ (posedge clk) begin
  if (soft_rst) begin
    debug_counter_rd <= 'd0;
  end else begin
    if ((dma_read_buffer_last[0] && dma_read_buffer_ready[0]) || (dma_read_buffer_last[1] && dma_read_buffer_ready[1])) begin
      debug_counter_rd <= debug_counter_rd + 16'd1;
    end
  end
end

always @ (posedge clk) begin
  if (soft_rst) begin
    dma_status <= 512'd0;
    r_dma_status <= 512'd0;
    r_dma_read_buffer_raddr <= 14'd0;
    rr_dma_read_buffer_raddr <= 14'd0;
    chipselect_flop1 <= 'b0;
    chipselect_flop2 <= 'b0;
  end else begin
    if (dma_read_buffer_raddr == DMA_POLL_REG & chipselect) begin
      dma_status <= {{14'b0, dma_read_buffer_ready}, {14'b0, dma_write_buffer_valid}, {14'b0, dma_read_buffer_valid}, {14'b0, dma_write_buffer_ready}};
    end
    r_dma_status <= dma_status;
    r_dma_read_buffer_raddr <= dma_read_buffer_raddr;
    rr_dma_read_buffer_raddr <= r_dma_read_buffer_raddr;
    chipselect_flop1 <= chipselect;
    chipselect_flop2 <= chipselect_flop1;
  end
end

always @(posedge clk or posedge reset) begin
  if (reset) begin
    soft_rst <= 'b1;
  end else begin
    if (dma_write_buffer_waddr == DMA_SOFT_RST && write2 && chipselect2 && clken2) begin
      soft_rst <= 'b1;
    end else begin
      soft_rst <= 'b0;
    end
  end
end

assign readdata = (rr_dma_read_buffer_raddr == DMA_POLL_REG ) & chipselect_flop2 ? r_dma_status : dma_read_buffer_rdata;

wire inst_wen;
wire [INST_ADDRW-1:0] inst_waddr;
wire [MICW-1:0] inst_wdata;
wire [MRFIDW-1:0] mrf_wen;
wire [MRFAW-1:0] mrf_waddr;
wire [DOTW*EW-1:0] mrf_wdata;
wire input_wen0;
wire input_wrdy0;
wire [DOTW*EW-1:0]input_wdata0;
wire input_wen1;
wire input_wrdy1;
wire [DOTW*EW-1:0] input_wdata1;
wire output_ren0;
wire output_rrdy0;
wire [DOTW*EW:0] output_rdata0;
wire output_ren1;
wire output_rrdy1;
wire [DOTW*EW:0] output_rdata1;
wire npu_start, npu_reset;

shim shim_inst (
  .clk(clk),
  .rst(soft_rst),
  // Interface to DMA-W buffer
  .dma_wb_valid(dma_write_buffer_valid),
  .dma_wb_data(dma_write_buffer_rdata),
  .dma_wb_raddr(dma_write_buffer_raddr),
  .dma_wb_last(dma_write_buffer_last),
  .dma_wb_ren(dma_write_buffer_ren),
  // Interface to DMA-R buffer
  .dma_rb_ready(dma_read_buffer_ready),
  .dma_rb_data(dma_read_buffer_wdata),
  .dma_rb_waddr(dma_read_buffer_waddr),
  .dma_rb_last(dma_read_buffer_last),
  .dma_rb_wen(dma_read_buffer_wen),
  .dma_rb_ben(dma_read_buffer_wben),
  // Interface to NPU
  .mrf_wdata(mrf_wdata),
  .mrf_wen(mrf_wen),
  .mrf_waddr(mrf_waddr),
  .inst_wdata(inst_wdata),
  .inst_wen(inst_wen),
  .inst_waddr(inst_waddr),
  .input_data0(input_wdata0),
  .input_wen0(input_wen0),
  .input_rdy0(input_wrdy0),
  .input_data1(input_wdata1),
  .input_wen1(input_wen1),
  .input_rdy1(input_wrdy1),
  .output_data0(output_rdata0),
  .output_ren0(output_ren0),
  .output_rdy0(output_rrdy0),
  .output_data1(output_rdata1),
  .output_ren1(output_ren1),
  .output_rdy1(output_rrdy1),
  .npu_start(npu_start),
  .npu_reset(npu_reset)
);

npu real_npu_inst (
  .clk(clk),
  .rst(npu_reset),
  // Input Instructions
  .i_minst_chain_wr_en(inst_wen),
  .i_minst_chain_wr_din(inst_wdata),
  .i_minst_chain_wr_addr(inst_waddr),
  // Input Data
  .i_ld_in_wr_en(input_wen0),
  .o_ld_in_wr_rdy(input_wrdy0),
  .i_ld_in_wr_din(input_wdata0),
  .i_ld_in_wr_en1(input_wen1),
  .o_ld_in_wr_rdy1(input_wrdy1),
  .i_ld_in_wr_din1(input_wdata1),
  // Output Data
  .i_ld_out_rd_en(output_ren0),
  .o_ld_out_rd_rdy(output_rrdy0),
  .o_ld_out_rd_dout(output_rdata0),
  .i_ld_out_rd_en1(output_ren1),
  .o_ld_out_rd_rdy1(output_rrdy1),
  .o_ld_out_rd_dout1(output_rdata1),
  // MRF Data & Control
  .i_mrf_wr_addr(mrf_waddr), 
  .i_mrf_wr_data(mrf_wdata), 
  .i_mrf_wr_en(mrf_wen),
  // Top-level Control
  .diag_mode(4),
  .pc_start_offset(0),
  .i_start(npu_start)
);

endmodule
