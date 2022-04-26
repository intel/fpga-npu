`include "npu.vh"

module shim #(
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
    parameter INST_ADDRW = `INST_ADDRW,
	 // Shim parameters
	parameter PCIE_DWIDTH = 512,
	parameter PCIE_WBENW  = PCIE_DWIDTH / 8,
	parameter PCIE_DEPTH  = 8192,
	parameter PCIE_AWIDTH = $clog2(PCIE_DEPTH),
	parameter MRF_DWIDTH  = DOTW*EW,
	parameter MRF_DEPTH   = MRFD,
	parameter MRF_AWIDTH  = $clog2(MRF_DEPTH),
	parameter NUM_MRF		 = NTILE*NDPE,
	parameter MRF_IDWIDTH = $clog2(NUM_MRF),
	parameter INST_DWIDTH = MICW,
	parameter INST_AWIDTH = $clog2(INST_DEPTH),
	parameter IN_DWIDTH   = DOTW*EW,
	parameter OUT_DWIDTH  = DOTW*EW
)(
	input  clk,
	input  rst,
	// Interface to DMA-W buffer
	input  [1:0] dma_wb_valid,
	input  [PCIE_DWIDTH-1:0] dma_wb_data,
	output [PCIE_AWIDTH-1:0] dma_wb_raddr,
	output [1:0] dma_wb_last,
	output dma_wb_ren,
	// Interface to DMA-R buffer
	input  [1:0] dma_rb_ready,
	output [PCIE_DWIDTH-1:0] dma_rb_data,
	output [PCIE_AWIDTH-1:0] dma_rb_waddr,
	output [1:0] dma_rb_last,
	output dma_rb_wen,
	output [PCIE_WBENW-1:0] dma_rb_ben,
	// Interface to NPU MRFs
	output [MRF_DWIDTH-1:0] mrf_wdata,
	output [MRFIDW-1:0] mrf_wen,
	output [MRF_AWIDTH-1:0] mrf_waddr,
	// Interface to NPU Instruction Memory
	output [INST_DWIDTH-1:0] inst_wdata,
	output inst_wen,
	output [INST_AWIDTH-1:0] inst_waddr,
	// Interface to NPU Input FIFOs
	output [IN_DWIDTH-1:0] input_data0,
	output input_wen0,
	input  input_rdy0,
	output [IN_DWIDTH-1:0] input_data1,
	output input_wen1,
	input  input_rdy1,
	// Interface to NPU Output FIFOs
	input  [OUT_DWIDTH:0] output_data0,
	output output_ren0,
	input  output_rdy0,
	input  [OUT_DWIDTH:0] output_data1,
	output output_ren1,
	input  output_rdy1,
	// NPU start signal
	output npu_start,
	output npu_reset
);

localparam DEST_MRF = 3'b001, DEST_INST = 3'b010, DEST_IN0 = 3'b011, DEST_IN1 = 3'b100, DEST_CONFIG_IN = 3'b101, DEST_CONFIG_OUT = 3'b110;
localparam BUF_SIZE = 4096;
localparam B0_START = 0;
localparam B0_END = B0_START + BUF_SIZE - 1;
localparam B1_START = B0_START + BUF_SIZE;
localparam B1_END = B0_START + 2 * BUF_SIZE - 1;

// Output registers
logic [PCIE_AWIDTH-1:0] r_dma_wb_raddr, r_dma_rb_waddr, r_dma_wb_offset, r_dma_rb_offset;
logic [1:0] r_dma_wb_last, r_dma_rb_last;
logic r_dma_rb_wen;
logic [PCIE_DWIDTH:0] r_dma_rb_data;
logic r_dma_wb_ren, rr_dma_wb_ren, r_output_ren0, r_output_ren1;
logic [PCIE_WBENW-1:0] r_dma_rb_ben;

localparam OUT_PIPELINE = 7;

logic [MRF_DWIDTH-1:0] r_mrf_wdata  [0:OUT_PIPELINE-1];
logic [MRFIDW-1:0] r_mrf_wen [0:OUT_PIPELINE-1];
logic [MRF_AWIDTH-1:0] r_mrf_waddr [0:OUT_PIPELINE-1];
logic [INST_DWIDTH-1:0] r_inst_wdata [0:OUT_PIPELINE-1];
logic [INST_AWIDTH-1:0] r_inst_waddr [0:OUT_PIPELINE-1];
logic [IN_DWIDTH-1:0] r_input_data0 [0:OUT_PIPELINE-1];
logic [IN_DWIDTH-1:0] r_input_data1 [0:OUT_PIPELINE-1];
logic r_start [0:OUT_PIPELINE-1];
logic r_inst_wen [0:OUT_PIPELINE-1]; 
logic r_input_wen0 [0:OUT_PIPELINE-1];
logic r_input_wen1 [0:OUT_PIPELINE-1]; 
logic r_soft_reset [0:OUT_PIPELINE-1];


// Shim logic registers
logic dma_read_from_buffer, dma_write_to_buffer, npu_read_from_ofifo;
logic [2:0] destination;
logic [31:0] num_wb_lines, num_rb_lines;
logic [MRFIDW-1:0] id;
logic [MRF_AWIDTH-1:0] addr;
logic pause_flag;
logic [31:0] num_read_lines, num_written_lines;
logic halt, r_halt;

always @ (*) begin
	if (rst) begin
		destination <= DEST_MRF;
		id <= 'd0;
		addr <= 'd0;
		pause_flag <= 1'b0;
	end else begin
		destination <= dma_wb_data[2:0];
		id <= dma_wb_data[3+:MRFIDW];
		addr <= dma_wb_data[3+MRFIDW+:MRF_AWIDTH];
		pause_flag <= dma_wb_data[3+MRFIDW+MRF_AWIDTH];
	end
end

// Shim logic
always @ (posedge clk) begin
	if (rst) begin
		// Resetting logic registers
		dma_read_from_buffer <= 1'b0;
		dma_write_to_buffer <= 1'b0;
		npu_read_from_ofifo <= 1'b0;
		num_wb_lines <= BUF_SIZE;
		num_rb_lines <= BUF_SIZE;
		num_read_lines <= 'd0;
		num_written_lines <= 'd0;
		// Resetting output registers
		r_dma_wb_raddr <= B0_START;
		r_dma_rb_waddr <= B0_START;
		r_dma_wb_offset <= 'd0;
		r_dma_rb_offset <= 'd0;
		r_dma_wb_ren <= 1'b0;
		rr_dma_wb_ren <= 1'b0;
		r_dma_rb_wen <= 1'b0;
		r_dma_wb_last <= 2'b00;
		r_dma_rb_last <= 2'b00;
		r_dma_rb_data <= 'd0;
		r_mrf_wdata[0] <= 'd0;
		r_mrf_wen[0] <= 'd0;
		r_mrf_waddr[0] <= 'd0;
		r_inst_wdata[0] <= 'd0;
		r_inst_waddr[0] <= 'd0;
		r_input_data0[0] <= 'd0;
		r_input_data1[0] <= 'd0;
		r_inst_wen[0] <= 1'b0; 
		r_input_wen0[0] <= 1'b0;
		r_input_wen1[0] <= 1'b0;
		r_output_ren0 <= 1'b0;
		r_output_ren1 <= 1'b0;
		r_dma_rb_ben <= 'd0;
		halt <= 1'b0;
		r_halt <= 1'b0;
		r_start[0] <= 1'b0;
		r_soft_reset[0] <= 1'b0;
	end else begin
		// If NPU should read from buffer 0 and it is valid
		if (!dma_read_from_buffer && dma_wb_valid[0] && input_rdy0 && input_rdy1) begin
			
			if (num_read_lines == num_wb_lines-1) begin
				r_dma_wb_offset <= 0;
				r_dma_wb_raddr <= B1_START;
				dma_read_from_buffer <= !dma_read_from_buffer;
				num_read_lines <= 0;
				r_dma_wb_last <= 2'b01;
				//halt <= 1'b1;
				r_dma_wb_ren <= 1'b1;
			end else if (r_dma_wb_raddr == B0_END) begin
				r_dma_wb_offset <= 0;
				r_dma_wb_raddr <= B1_START;
				dma_read_from_buffer <= !dma_read_from_buffer;
				num_read_lines <= num_read_lines + 1'b1;
				r_dma_wb_last <= 2'b01;
				r_dma_wb_ren <= 1'b1;
			end else begin
				if (!halt) begin
					r_dma_wb_offset <= r_dma_wb_offset + 1'b1;
					num_read_lines <= num_read_lines + 1'b1;
				end else begin
					r_dma_wb_offset <= r_dma_wb_offset;
					num_read_lines <= num_read_lines;
				end
				if (!halt && !r_halt) begin
					r_dma_wb_ren <= 1'b1;
				end else begin
					r_dma_wb_ren <= 1'b0;
				end
				r_dma_wb_raddr <= PCIE_AWIDTH'(B0_START + r_dma_wb_offset + 1'b1);
				dma_read_from_buffer <= dma_read_from_buffer;
				r_dma_wb_last <= 2'b00;
			end
		// Else if NPU should read from buffer 1 and it is valid
		end else if (dma_read_from_buffer && dma_wb_valid[1] && input_rdy0 && input_rdy1) begin
			
			if (num_read_lines == num_wb_lines-1) begin
				r_dma_wb_offset <= 0;
				r_dma_wb_raddr <= B0_START;
				dma_read_from_buffer <= !dma_read_from_buffer;
				num_read_lines <= 0;
				r_dma_wb_last <= 2'b10;
				//halt <= 1'b1;
				r_dma_wb_ren <= 1'b1;
			end else if (r_dma_wb_raddr == B1_END) begin
				r_dma_wb_offset <= 0;
				r_dma_wb_raddr <= B0_START;
				dma_read_from_buffer <= !dma_read_from_buffer;
				num_read_lines <= num_read_lines + 1'b1;
				r_dma_wb_last <= 2'b10;
				r_dma_wb_ren <= 1'b1;
			end else begin
				if (!halt) begin
					r_dma_wb_offset <= r_dma_wb_offset + 1'b1;
					num_read_lines <= num_read_lines + 1'b1;
				end else begin
					r_dma_wb_offset <= r_dma_wb_offset;
					num_read_lines <= num_read_lines;
				end
				if (!halt && !r_halt) begin
					r_dma_wb_ren <= 1'b1;
				end else begin
					r_dma_wb_ren <= 1'b0;
				end
				r_dma_wb_raddr <= PCIE_AWIDTH'(B1_START + r_dma_wb_offset + 1'b1);
				dma_read_from_buffer <= dma_read_from_buffer;
				r_dma_wb_last <= 2'b00;
			end
		end else begin
			r_dma_wb_ren <= 1'b0;
			r_dma_wb_last <= 2'b00;
		end
		
		rr_dma_wb_ren <= r_dma_wb_ren;
		r_halt <= halt;
		
		// Steering read data to the correct NPU interface
		if (rr_dma_wb_ren) begin
			if (destination == DEST_CONFIG_IN) begin
				num_wb_lines <= dma_wb_data[34:3];
				halt <= 1'b0;
				r_start[0] <= 1'b0;
				r_mrf_wen[0] <= 'd0;
				r_input_wen0[0] <= 1'b0;
				r_input_wen1[0] <= 1'b0;
				r_inst_wen[0] <= 1'b0;
			end else if (destination == DEST_CONFIG_OUT) begin
				num_rb_lines <= dma_wb_data[34:3];
				r_start[0] <= 1'b0;
				r_mrf_wen[0] <= 'd0;
				r_input_wen0[0] <= 1'b0;
				r_input_wen1[0] <= 1'b0;
				r_inst_wen[0] <= 1'b0;
			end else if (destination == DEST_MRF) begin
				r_mrf_wdata[0] <= dma_wb_data[PCIE_DWIDTH-1:PCIE_DWIDTH-MRF_DWIDTH];
				r_mrf_waddr[0] <= addr;
				r_mrf_wen[0] <= id+1;
				r_inst_wen[0] <= 1'b0;
				r_input_wen0[0] <= 1'b0;
				r_input_wen1[0] <= 1'b0;
				r_start[0] <= 1'b0;
			end else if (destination == DEST_INST) begin
				r_inst_wdata[0] <= dma_wb_data[PCIE_DWIDTH-1:PCIE_DWIDTH-INST_DWIDTH];
				r_inst_waddr[0] <= addr[INST_AWIDTH-1:0];
				r_start[0] <= (addr[INST_AWIDTH-1:0] == num_wb_lines-2)? 1'b1: 1'b0;
				r_inst_wen[0] <= 1'b1;
				r_mrf_wen[0] <= 'd0;
				r_input_wen0[0] <= 1'b0;
				r_input_wen1[0] <= 1'b0;
			end else if (destination == DEST_IN0) begin
				r_input_data0[0] <= dma_wb_data[PCIE_DWIDTH-1:PCIE_DWIDTH-IN_DWIDTH];
				r_mrf_wen[0] <= 'd0;
				r_inst_wen[0] <= 1'b0;
				r_input_wen1[0] <= 1'b0;
				r_start[0] <= r_soft_reset[OUT_PIPELINE-1];
				if (pause_flag) begin
					halt <= 1'b1;
					r_dma_wb_offset <= r_dma_wb_offset - 2;
					num_read_lines <= num_read_lines - 2;
				end
				if (halt) begin
					r_input_wen0[0] <= 1'b0;
				end else begin
					r_input_wen0[0] <= 1'b1;
				end
			end else if (destination == DEST_IN1) begin
				r_input_data1[0] <= dma_wb_data[PCIE_DWIDTH-1:PCIE_DWIDTH-IN_DWIDTH];
				r_mrf_wen[0] <= 'd0;
				r_inst_wen[0] <= 1'b0;
				r_input_wen0[0] <= 1'b0;
				r_start[0] <= r_soft_reset[OUT_PIPELINE-1];
				if (pause_flag) begin
					halt <= 1'b1;
					r_dma_wb_offset <= r_dma_wb_offset - 2;
					num_read_lines <= num_read_lines - 2;
				end
				if (halt) begin
					r_input_wen1[0] <= 1'b0;
				end else begin
					r_input_wen1[0] <= 1'b1;
				end
			end else begin
				r_mrf_wen[0] <= 'd0;
				r_inst_wen[0] <= 1'b0;
				r_input_wen0[0] <= 1'b0;
				r_input_wen1[0] <= 1'b0;
				r_start[0] <= r_soft_reset[OUT_PIPELINE-1];
			end
		end else begin
			r_mrf_wen[0] <= 'd0;
			r_inst_wen[0] <= 1'b0;
			r_input_wen0[0] <= 1'b0;
			r_input_wen1[0] <= 1'b0;
			r_start[0] <= r_soft_reset[OUT_PIPELINE-1];
		end
		
		// Write to buffer 0
		if (!dma_write_to_buffer && dma_rb_ready[0] && ((!npu_read_from_ofifo && output_rdy0) || (npu_read_from_ofifo && output_rdy1))) begin
			
			// Set write enable, byte enable and address
			r_dma_rb_wen <= 1'b1;
			r_dma_rb_ben <= 64'hFFFFFFFFFFFFFFFF;
			r_dma_rb_waddr <= PCIE_AWIDTH'(B0_START + r_dma_rb_offset);
			// Signal FIFO and forward data
			if (npu_read_from_ofifo) begin
				r_output_ren0 <= 1'b0;
				r_output_ren1 <= 1'b1;
				r_dma_rb_data <= output_data1;
				if (r_dma_rb_data[OUT_DWIDTH]) begin
					halt <= 1'b0;
					r_soft_reset[0] <= 1'b1;
				end else begin
					r_soft_reset[0] <= 1'b0;
				end
			end else begin
				r_output_ren0 <= 1'b1;
				r_output_ren1 <= 1'b0;
				r_dma_rb_data <= output_data0;
			end
			// Flip source FIFO
			npu_read_from_ofifo <= !npu_read_from_ofifo;
			
			// Prepare next read
			if (num_written_lines == num_rb_lines-1) begin
				r_dma_rb_offset <= 0;			
				dma_write_to_buffer <= !dma_write_to_buffer;
				num_written_lines <= 0;
				r_dma_rb_last <= 2'b01;
			end else if (r_dma_rb_waddr == B0_END-1) begin
				r_dma_rb_offset <= 0;
				dma_write_to_buffer <= !dma_write_to_buffer;
				num_written_lines <= num_written_lines + 1'b1;
				r_dma_rb_last <= 2'b01;
			end else begin
				r_dma_rb_offset <= r_dma_rb_offset + 1'b1;	
				dma_write_to_buffer <= dma_write_to_buffer;
				num_written_lines <= num_written_lines + 1'b1;
				r_dma_rb_last <= 2'b00;
			end
			
		end else if (dma_write_to_buffer && dma_rb_ready[1] && ((!npu_read_from_ofifo && output_rdy0) || (npu_read_from_ofifo && output_rdy1))) begin
			
			// Set write enable, byte enable and address
			r_dma_rb_wen <= 1'b1;
			r_dma_rb_ben <= 64'hFFFFFFFFFFFFFFFF;
			r_dma_rb_waddr <= PCIE_AWIDTH'(B1_START + r_dma_rb_offset);
			// Signal FIFO and forward data
			if (npu_read_from_ofifo) begin
				r_output_ren0 <= 1'b0;
				r_output_ren1 <= 1'b1;
				r_dma_rb_data <= output_data1;
				if (r_dma_rb_data[OUT_DWIDTH]) begin
					halt <= 1'b0;
					r_soft_reset[0] <= 1'b1;
				end else begin
					r_soft_reset[0] <= 1'b0;
				end
			end else begin
				r_output_ren0 <= 1'b1;
				r_output_ren1 <= 1'b0;
				r_dma_rb_data <= output_data0;
			end
			// Flip source FIFO
			npu_read_from_ofifo <= !npu_read_from_ofifo;

			// Prepare next read
			if (num_written_lines == num_rb_lines-1) begin
				r_dma_rb_offset <= 0;			
				dma_write_to_buffer <= !dma_write_to_buffer;
				num_written_lines <= 0;
				r_dma_rb_last <= 2'b10;
			end else if (r_dma_rb_waddr == B1_END-1) begin
				r_dma_rb_offset <= 0;
				dma_write_to_buffer <= !dma_write_to_buffer;
				num_written_lines <= num_written_lines + 1'b1;
				r_dma_rb_last <= 2'b10;
			end else begin
				r_dma_rb_offset <= r_dma_rb_offset + 1'b1;	
				dma_write_to_buffer <= dma_write_to_buffer;
				num_written_lines <= num_written_lines + 1'b1;
				r_dma_rb_last <= 2'b00;
			end
			
		/*end else if (num_written_lines == num_rb_lines) begin
			r_dma_rb_wen <= 1'b1;
			r_dma_rb_ben <= 64'hFFFFFFFFFFFFFFFF;
			r_dma_rb_offset <= 0;
			r_dma_rb_waddr <= (dma_write_to_buffer)? B0_START: B1_START;
			r_dma_rb_last <= 2'b00;
			dma_write_to_buffer <= dma_write_to_buffer;
			num_written_lines <= num_written_lines + 1'b1;

		end else if (num_written_lines == num_rb_lines+1) begin
			r_dma_rb_wen <= 1'b1;
			r_dma_rb_ben <= 64'hFFFFFFFFFFFFFFFF;
			r_dma_rb_offset <= 0;
			r_dma_rb_waddr <= (dma_write_to_buffer)? B0_START: B1_START;
			r_dma_rb_last  <= (dma_write_to_buffer)? 2'b10: 2'b01;
			dma_write_to_buffer <= !dma_write_to_buffer;
			num_written_lines <= 0;

		end else if ((r_dma_rb_waddr == B0_END+1) || (r_dma_rb_waddr == B1_END+1)) begin
			r_dma_rb_wen <= 1'b0;
			r_dma_rb_ben <= 64'd0;
			r_dma_rb_offset <= 0;
			if(dma_write_to_buffer) begin
				r_dma_rb_waddr <= B0_START;
				r_dma_rb_last <= 2'b10;
			end else begin
				r_dma_rb_waddr <= B1_START;
				r_dma_rb_last <= 2'b01;
			end
			dma_write_to_buffer <= !dma_write_to_buffer;
			num_written_lines <= num_written_lines + 1'b1;*/
		end else begin
			r_dma_rb_wen <= 1'b0;
			r_dma_rb_ben <= 64'h0000000000000000;
			r_dma_rb_last <= 2'b00;
			r_output_ren0 <= 1'b0;
			r_output_ren1 <= 1'b0;
			r_soft_reset[0] <= 1'b0;
		end
	end
end

integer p;
always @ (posedge clk) begin
	if (rst) begin
		for (p = 1; p < OUT_PIPELINE; p = p + 1) begin
			r_mrf_wdata[p] <= 'd0;
			r_mrf_wen[p] <= 1'b0;
			r_mrf_waddr[p] <= 'd0;
			r_inst_wdata[p] <= 'd0;
			r_inst_waddr[p] <= 'd0;
			r_input_data0[p] <= 'd0;
			r_input_data1[p] <= 'd0;
			r_inst_wen[p] <= 1'b0;
			r_input_wen0[p] <= 1'b0;
			r_input_wen1[p] <= 1'b0; 
			r_start[p] <= 1'b0;
			r_soft_reset[p] <= 1'b0;
		end
	end else begin
		for (p = 1; p < OUT_PIPELINE; p = p + 1) begin
			r_mrf_wdata[p] <= r_mrf_wdata[p-1];
			r_mrf_wen[p] <= r_mrf_wen[p-1];
			r_mrf_waddr[p] <= r_mrf_waddr[p-1];
			r_inst_wdata[p] <= r_inst_wdata[p-1];
			r_inst_waddr[p] <= r_inst_waddr[p-1];
			r_input_data0[p] <= r_input_data0[p-1];
			r_input_data1[p] <= r_input_data1[p-1];
			r_inst_wen[p] <= r_inst_wen[p-1];
			r_input_wen0[p] <= r_input_wen0[p-1];
			r_input_wen1[p] <= r_input_wen1[p-1]; 
			r_start[p] <= r_start[p-1];
			r_soft_reset[p] <= r_soft_reset[p-1];
		end
	end
end

// Assign outputs
assign dma_wb_raddr = r_dma_wb_raddr;
assign dma_rb_waddr = r_dma_rb_waddr;
assign dma_wb_last = r_dma_wb_last;
assign dma_rb_last = r_dma_rb_last;
assign dma_rb_data = r_dma_rb_data[PCIE_DWIDTH-1:0];
assign dma_rb_wen = r_dma_rb_wen;
assign dma_rb_ben = r_dma_rb_ben;
assign dma_wb_ren = r_dma_wb_ren;

assign mrf_wdata = r_mrf_wdata[OUT_PIPELINE-1];
assign mrf_wen = r_mrf_wen[OUT_PIPELINE-1];
assign mrf_waddr = r_mrf_waddr[OUT_PIPELINE-1];
assign inst_wdata = r_inst_wdata[OUT_PIPELINE-1];
assign inst_waddr = r_inst_waddr[OUT_PIPELINE-1];
assign input_data0 = r_input_data0[OUT_PIPELINE-1];
assign input_data1 = r_input_data1[OUT_PIPELINE-1];
assign inst_wen = r_inst_wen[OUT_PIPELINE-1];
assign input_wen0 = r_input_wen0[OUT_PIPELINE-1];
assign input_wen1 = r_input_wen1[OUT_PIPELINE-1]; 
assign output_ren0 = r_output_ren0; 
assign output_ren1 = r_output_ren1;
assign npu_start = r_start[OUT_PIPELINE-1];
assign npu_reset = r_soft_reset[0] || rst;

endmodule