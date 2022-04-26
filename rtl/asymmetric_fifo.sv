`include "npu.vh"

module asymmetric_fifo # (
	parameter IDW   = 3*`ACCW,
	parameter ODW   = `ACCW,
	parameter DEPTH = `QDEPTH,
	parameter ID    = 0,
	parameter AW    = $clog2(DEPTH)
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

	wire [2:0] fifo_wr_ok;
	wire [2:0] fifo_rd_ok;
	wire [ODW-1:0] fifo_rd_data [0:2];
	wire [AW-1:0] fifo_usedw [0:2];

	reg [2:0] sel;

	fifo # (
		.ID       (ID), 
		.DW       (ODW), 
		.DEPTH    (DEPTH)
	) fifo0 (
		.clk      (clk), 
		.rst      (rst),
		.wr_en    (wr_en),
		.wr_data  (wr_data[ODW-1:0]),
		.wr_ok    (fifo_wr_ok[0]),

		.rd_ok    (fifo_rd_ok[0]),
		.rd_data  (fifo_rd_data[0]),
		.rd_en    (rd_en && sel[0]),
		.usedw    (fifo_usedw[0])
	);

	fifo # (
		.ID       (ID), 
		.DW       (ODW), 
		.DEPTH    (DEPTH)
	) fifo1 (
		.clk      (clk), 
		.rst      (rst),
		.wr_en    (wr_en),
		.wr_data  (wr_data[2*ODW-1:ODW]),
		.wr_ok    (fifo_wr_ok[1]),

		.rd_ok    (fifo_rd_ok[1]),
		.rd_data  (fifo_rd_data[1]),
		.rd_en    (rd_en && sel[1]),
		.usedw    (fifo_usedw[1])
	);

	fifo # (
		.ID       (ID), 
		.DW       (ODW), 
		.DEPTH    (DEPTH)
	) fifo2 (
		.clk      (clk), 
		.rst      (rst),
		.wr_en    (wr_en),
		.wr_data  (wr_data[3*ODW-1:2*ODW]),
		.wr_ok    (fifo_wr_ok[2]),
		.rd_ok    (fifo_rd_ok[2]),
		.rd_data  (fifo_rd_data[2]),
		.rd_en    (rd_en && sel[2]),
		.usedw    (fifo_usedw[2])
	);
	
	always @ (posedge clk) begin
		if (rst) begin
			sel <= 3'b001;
		end else begin
			if (rd_en) begin
				sel <= (sel == 3'b100)? 3'b001: (sel << 1);
			end
		end
	end

	reg rd_ok_out;
	reg [ODW-1:0] rd_data_out;
	reg [AW-1:0] usedw_out;
	always @ (*) begin
		if (sel == 3'b001) begin
			rd_ok_out <= fifo_rd_ok[0];
			rd_data_out <= fifo_rd_data[0];
			usedw_out <= fifo_usedw[0];
		end else if (sel == 3'b010) begin
			rd_ok_out <= fifo_rd_ok[1];
			rd_data_out <= fifo_rd_data[1];
			usedw_out <= fifo_usedw[1];
		end else begin
			rd_ok_out <= fifo_rd_ok[2];
			rd_data_out <= fifo_rd_data[2];
			usedw_out <= fifo_usedw[2];
		end
	end

	assign rd_ok = rd_ok_out;
	assign rd_data = rd_data_out;
	assign usedw = usedw_out;
	assign wr_ok = fifo_wr_ok[0];

endmodule