`include "npu.vh"

module inst_fifo # (
	parameter DW    = 64,   // FIFO data width
	parameter DEPTH = 512,    // FIFO depth
	parameter ID    = 0,      // Unique FIFO ID (used for debugging)
	parameter TARGET_FPGA = `TARGET_FPGA,
	parameter AW    = $clog2(DEPTH),
	parameter MLAB_FIFO_DEPTH = 7,
	parameter MLAB_FIFO_ADDRW = $clog2(MLAB_FIFO_DEPTH),
	parameter NTAG = `NTAG,
	parameter NTAGW = `NTAGW,
	parameter MODULE = "evrf"
) (
	input           clk,
	input           rst,
	input           wr_en,
	input  [DW-1:0] wr_data,
	output          wr_ok,
	input           rd_en,
	output [DW-1:0] rd_data,
	output          rd_ok,
	input [NTAGW-1:0] current_tag
);

	wire m20k_fifo_rd_ok, mlab_fifo_wr_ok, mlab_fifo_rd_ok;
	wire [DW-1:0] m20k_fifo_rd_data;
	reg rd_from_m20k, r_rd_from_m20k;

	reg [NTAGW-1:0] tag_lookahead [0:MLAB_FIFO_DEPTH-1];
	reg [MLAB_FIFO_ADDRW-1:0] rd_ptr, wr_ptr;

	reg inst_rd_ok;

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
		.rd_ok 		(mlab_fifo_rd_ok)
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

	integer i;
	always @ (posedge clk) begin
		if (rst) begin
			rd_ptr <= 'd0;
			wr_ptr <= 'd0;
			for (i = 0; i < MLAB_FIFO_DEPTH; i = i + 1) begin
				tag_lookahead[i] <= {(NTAGW){1'b1}};
			end
		end else begin
			if (r_rd_from_m20k) begin
				if(MODULE == "evrf") begin 
					tag_lookahead[wr_ptr] <= `evrf_uinst_tag(m20k_fifo_rd_data);
				end else if (MODULE == "mfu") begin
					tag_lookahead[wr_ptr] <= `mfu_uinst_tag(m20k_fifo_rd_data);
				end
				wr_ptr <= (wr_ptr == MLAB_FIFO_DEPTH-1)? 
					'd0: MLAB_FIFO_ADDRW'(wr_ptr + 1'b1);
			end

			if (rd_en) begin
				tag_lookahead[rd_ptr] <= {(NTAGW){1'b1}};
				rd_ptr <= (rd_ptr == MLAB_FIFO_DEPTH-1)? 
					'd0: MLAB_FIFO_ADDRW'(rd_ptr + 1'b1); 
			end
		end
	end

	wire state_t, state_tm1;
	assign state_tm1 = (current_tag >= tag_lookahead[rd_ptr]);
	assign state_t = (rd_ptr == MLAB_FIFO_DEPTH-1)? (current_tag >= tag_lookahead[0]) : (current_tag >= tag_lookahead[rd_ptr+1]);
	always @ (posedge clk) begin
		if (rst) begin
			inst_rd_ok <= 1'b0;
		end else begin
			inst_rd_ok <= state_t;
		end
	end

	assign rd_ok = inst_rd_ok;

endmodule