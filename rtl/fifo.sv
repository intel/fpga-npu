`include "npu.vh"

// This is a show-ahead FIFO based on the SCFIFO Quartus IP core. 
// The rd_en signal is considered as an acknowledgement (i.e. equivalent to a queue pop)
module fifo # (
	parameter DW    = 1280,   // FIFO data width
	parameter DEPTH = 512,    // FIFO depth
	parameter ID    = 0,      // Unique FIFO ID (used for debugging)
	parameter TARGET_FPGA = `TARGET_FPGA,
	parameter AW    = $clog2(DEPTH)
) (
	input           clk,
	input           rst,
	input           wr_en,
	input  [DW-1:0] wr_data,
	output          wr_ok,
	input           rd_en,
	output [DW-1:0] rd_data,
	output          rd_ok,
	output [AW-1:0] usedw
);

	wire empty;
	wire [DW-1:0] data_out;
	wire almost_full;
	wire [1:0]ecc_status; wire almost_empty, full; // temp signals to avoid warnings

	scfifo  scfifo_component (
		.clock        (clk),
		.data         (wr_data),
		.rdreq        (rd_en),
		.wrreq        (wr_en),
		.empty        (empty),
		.q            (data_out),
		.almost_full  (almost_full),
		.sclr         (rst),
		.usedw		  (usedw),
		.aclr			  (1'b0),
		.almost_empty (almost_empty),
		.full			  (full)
	);   
	defparam
		scfifo_component.add_ram_output_register = "ON",
		scfifo_component.enable_ecc = "FALSE",
		scfifo_component.intended_device_family = (TARGET_FPGA == "S10-Prime")? "Stratix 10": TARGET_FPGA,
		scfifo_component.lpm_hint = "RAM_BLOCK_TYPE=M20K",
		scfifo_component.lpm_numwords = DEPTH,
		scfifo_component.lpm_showahead = "ON",
		scfifo_component.lpm_type = "SCFIFO",
		scfifo_component.lpm_width = DW,
		scfifo_component.lpm_widthu = AW,
		scfifo_component.overflow_checking = "ON",
		scfifo_component.underflow_checking = "ON",
		scfifo_component.use_eab  = "ON",
		scfifo_component.almost_full_value = (DEPTH-10);

	assign rd_data = data_out;
	assign rd_ok   = ~empty;
	assign wr_ok   = ~almost_full;

endmodule

module showahead_fifo # (
	parameter DW    = 1280,   // FIFO data width
	parameter DEPTH = 512,    // FIFO depth
	parameter ID    = 0,      // Unique FIFO ID (used for debugging)
	parameter TARGET_FPGA = `TARGET_FPGA,
	parameter AW    = $clog2(DEPTH),
	parameter MLAB_FIFO_DEPTH = 7,
	parameter MLAB_FIFO_ADDRW = $clog2(MLAB_FIFO_DEPTH)
) (
	input           clk,
	input           rst,
	input           wr_en,
	input  [DW-1:0] wr_data,
	output          wr_ok,
	input           rd_en,
	output [DW-1:0] rd_data,
	output          rd_ok,
	output [MLAB_FIFO_ADDRW-1:0] usedw
);

	wire m20k_fifo_rd_ok, mlab_fifo_wr_ok;
	wire [DW-1:0] m20k_fifo_rd_data;
	reg rd_from_m20k, r_rd_from_m20k;

	normal_fifo # (
		.DW 		(DW),
		.DEPTH 		(DEPTH),
		.ID 		(ID),
		.TARGET_FPGA(TARGET_FPGA),
		.AW 		(AW)
	) m20k_fifo (
		.clk 		(clk),
		.rst 		(rst),
		.wr_en 		(wr_en),
		.wr_data 	(wr_data),
		.wr_ok 		(wr_ok),
		.rd_en 		(rd_from_m20k),
		.rd_data 	(m20k_fifo_rd_data),
		.rd_ok 		(m20k_fifo_rd_ok)
	);

	mlab_fifo # (
		.DW 		(DW),
		.DEPTH 		(MLAB_FIFO_DEPTH),
		.ID 		(ID),
		.TARGET_FPGA(TARGET_FPGA),
		.AW 		(MLAB_FIFO_ADDRW)
	) mlab_fifo (
		.clk 		(clk),
		.rst 		(rst),
		.wr_en 		(r_rd_from_m20k),
		.wr_data 	(m20k_fifo_rd_data),
		.wr_ok 		(mlab_fifo_wr_ok),
		.rd_en 		(rd_en),
		.rd_data 	(rd_data),
		.rd_ok 		(rd_ok),
		.usedw 		(usedw)
	);

	always @ (posedge clk) begin
		if (rst) begin
			rd_from_m20k <= 1'b0;
			r_rd_from_m20k <= 1'b0;
		end else begin
			rd_from_m20k <= m20k_fifo_rd_ok && mlab_fifo_wr_ok;
			r_rd_from_m20k <= rd_from_m20k;
		end
	end

endmodule

module mlab_fifo # (
	parameter DW    = 1280,   // FIFO data width
	parameter DEPTH = 512,    // FIFO depth
	parameter ID    = 0,      // Unique FIFO ID (used for debugging)
	parameter TARGET_FPGA = `TARGET_FPGA,
	parameter AW    = $clog2(DEPTH)
) (
	input           clk,
	input           rst,
	input           wr_en,
	input  [DW-1:0] wr_data,
	output          wr_ok,
	input           rd_en,
	output [DW-1:0] rd_data,
	output          rd_ok,
	output [AW-1:0]   usedw
);

	wire empty;
	wire [DW-1:0] data_out;
	wire almost_full;
	wire [1:0]ecc_status; wire almost_empty, full; // temp signals to avoid warnings

	scfifo  scfifo_component (
		.clock        (clk),
		.data         (wr_data),
		.rdreq        (rd_en),
		.wrreq        (wr_en),
		.empty        (empty),
		.q            (data_out),
		.almost_full  (almost_full),
		.usedw		  (usedw),
		.sclr         (rst),
		.aclr			  (1'b0),
		.almost_empty (almost_empty),
		.full 		  (full)
	);   
	defparam
		scfifo_component.add_ram_output_register = "ON",
		scfifo_component.enable_ecc = "FALSE",
		scfifo_component.intended_device_family = (TARGET_FPGA == "S10-Prime")? "Stratix 10": TARGET_FPGA,
		scfifo_component.ram_block_type = "MLAB",
		scfifo_component.lpm_numwords = DEPTH,
		scfifo_component.lpm_showahead = "ON",
		scfifo_component.lpm_type = "SCFIFO",
		scfifo_component.lpm_width = DW,
		scfifo_component.lpm_widthu = AW,
		scfifo_component.overflow_checking = "ON",
		scfifo_component.underflow_checking = "ON",
		scfifo_component.use_eab  = "OFF",
		scfifo_component.almost_full_value = DEPTH-2;

	assign rd_data = data_out;
	assign rd_ok   = ~empty;
	assign wr_ok   = ~almost_full;

endmodule

module normal_fifo # (
	parameter DW    = 1280,   // FIFO data width
	parameter DEPTH = 512,    // FIFO depth
	parameter ID    = 0,      // Unique FIFO ID (used for debugging)
	parameter TARGET_FPGA = `TARGET_FPGA,
	parameter AW    = $clog2(DEPTH)
) (
	input           clk,
	input           rst,
	input           wr_en,
	input  [DW-1:0] wr_data,
	output          wr_ok,
	input           rd_en,
	output [DW-1:0] rd_data,
	output          rd_ok
);

	wire empty;
	wire [DW-1:0] data_out;
	wire almost_full;
	wire [1:0]ecc_status; wire almost_empty, full; // temp signals to avoid warnings

	scfifo  scfifo_component (
		.clock        (clk),
		.data         (wr_data),
		.rdreq        (rd_en),
		.wrreq        (wr_en),
		.empty        (empty),
		.q            (data_out),
		.almost_full  (almost_full),
		.sclr         (rst),
		.aclr 		  (1'b0),
		.almost_empty (almost_empty),
		.full 		  (full)
	);   
	defparam
		scfifo_component.add_ram_output_register = "ON",
		scfifo_component.enable_ecc = "FALSE",
		scfifo_component.intended_device_family = (TARGET_FPGA == "S10-Prime")? "Stratix 10": TARGET_FPGA,
		scfifo_component.lpm_hint = "RAM_BLOCK_TYPE=M20K",
		scfifo_component.lpm_numwords = DEPTH,
		scfifo_component.lpm_showahead = "OFF",
		scfifo_component.lpm_type = "SCFIFO",
		scfifo_component.lpm_width = DW,
		scfifo_component.lpm_widthu = $clog2(DEPTH),
		scfifo_component.overflow_checking = "ON",
		scfifo_component.underflow_checking = "ON",
		scfifo_component.use_eab  = "ON",
		scfifo_component.almost_full_value = (DEPTH-2);

	assign rd_data = data_out;
	assign rd_ok   = ~empty;
	assign wr_ok   = ~almost_full;

endmodule

// This is a show-ahead asymmetric FIFO module that uses the above FIFO module as a building block. 
// The input data width has to be a multiple of the output data width.
module asym_fifo # (
	parameter IDW   = 1280,   // FIFO input data width
	parameter ODW   = 1280,   // FIFO output data width
	parameter DEPTH = 512,    // FIFO depth
	parameter ID    = 0,      // Unique FIFO ID (used for debugging)
	parameter AW    = $clog2(DEPTH),
	parameter SELW  = `max($clog2(IDW/ODW),1)
) (
	input            clk,
	input            rst,
	input            wr_en,
	input  [IDW-1:0] wr_data,
	output           wr_ok,
	input            rd_en,
	output [ODW-1:0] rd_data, 
	output           rd_ok,
	output [AW-1:0]  usedw
);

	wire fifo_wr_ok, fifo_wr_en;
	wire fifo_rd_ok;
	reg  fifo_rd_en;
	wire [IDW-1:0] fifo_wr_data;
	wire [IDW-1:0] fifo_rd_data;

	fifo # (
		.ID       (ID), 
		.DW       (IDW), 
		.DEPTH    (DEPTH)
	) fifo (
		.clk      (clk), 
		.rst      (rst),
		.wr_en    (fifo_wr_en  ),
		.wr_data  (fifo_wr_data),
		.wr_ok    (fifo_wr_ok  ),
		.rd_ok    (fifo_rd_ok  ),
		.rd_data  (fifo_rd_data),
		.rd_en    (fifo_rd_en  ),
		.usedw    (usedw)
	);

	// fetch and keep actual queue's outputs
	reg [IDW-1:0] rd_data_reg, rd_data_reg_nxt;
	reg rd_ok_reg, rd_ok_reg_nxt;
	// keep track of a current position
	reg [SELW-1:0] rd_data_sel, rd_data_sel_nxt;

	// simple state machine
	always @(*) begin
		rd_ok_reg_nxt     = rd_ok_reg;
		rd_data_reg_nxt   = rd_data_reg;
		rd_data_sel_nxt   = rd_data_sel;
		fifo_rd_en        = 0;
		// initial state
		if (~rd_ok_reg) begin
			if (fifo_rd_ok) begin 
				// fetch a new value from fifo & initialize a counter
				rd_ok_reg_nxt     = 1'b1;
				rd_data_reg_nxt   = fifo_rd_data;
				rd_data_sel_nxt   = 0;
				// increment rd_ptr in the actural fifo queue
				fifo_rd_en        = 1;
			end
		end else begin // dequeue state
			if (rd_en) begin
				if (rd_data_sel == (IDW/ODW) - 1) begin
					// initialize a counter & go bakc to the initial state
					rd_ok_reg_nxt   = 1'b0;
					rd_data_sel_nxt = 0;
				end else begin
					// forward a bit selector
					rd_ok_reg_nxt   = 1'b1;
					rd_data_reg_nxt = rd_data_reg >> ODW;
					rd_data_sel_nxt = rd_data_sel + 1'b1;
				end
			end
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			rd_ok_reg <= 0;
		end else begin
			rd_ok_reg <= rd_ok_reg_nxt;
		end
		rd_data_reg <= rd_data_reg_nxt;
		rd_data_sel <= rd_data_sel_nxt;
	end

	// connect top-level outputs
	assign rd_ok = rd_ok_reg;
	assign rd_data = rd_data_reg[ODW-1:0];
	assign wr_ok = fifo_wr_ok;
	assign fifo_wr_data = wr_data;
	assign fifo_wr_en = wr_en;

endmodule



