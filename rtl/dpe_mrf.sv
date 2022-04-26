`include "npu.vh"

module dpe_mrf # (
	parameter MODULE_ID = "",
	parameter ID = 0,
	parameter DW = 32,
	parameter DEPTH = 512,
	parameter AW = 9,
	parameter EW = `EW,
	parameter DOTW = `DOTW,
	parameter NUM_DSP = DOTW/10
)(
	input           wr_en, 
	input  [AW-1:0] wr_addr, 
	input  [AW-1:0] rd_addr,
	input  [DW-1:0] wr_data,
	output [DW-1:0] rd_data,
	input 			clk, 
	input 			rst
);


reg  [AW-1:0] rd_addr_balance [0:(2*(NUM_DSP-1))-1];

integer c;
always @ (posedge clk) begin
	rd_addr_balance[0] <= rd_addr;
	for(c = 1; c < 2*(NUM_DSP-1); c = c + 1) begin
		rd_addr_balance[c] <= rd_addr_balance[c-1];
	end
end

genvar ram_id;
generate
	for (ram_id = 0; ram_id < NUM_DSP; ram_id = ram_id + 1) begin: gen_ram
		if (ram_id == 0) begin
			mrf_ram #(
				.ID(ID), 
				.DW(EW*10), 
				.AW(AW), 
				.DEPTH(DEPTH),
				.MODULE_ID("mvu-mrf"),
				.RAM_ID(ram_id)
			) ram_0 (
				.wr_en   (wr_en),
				.wr_addr (wr_addr),
				.wr_data (wr_data[(NUM_DSP-ram_id)*EW*10-1 : (NUM_DSP-(ram_id+1))*EW*10]),
				.rd_addr (rd_addr),
				.rd_data (rd_data[(NUM_DSP-ram_id)*EW*10-1 : (NUM_DSP-(ram_id+1))*EW*10]),
				.clk 	 (clk), 
				.rst 	 (rst)
			);
		end else begin
			mrf_ram #(
				.ID(ID), 
				.DW(EW*10), 
				.AW(AW), 
				.DEPTH(DEPTH),
				.MODULE_ID("mvu-mrf"),
				.RAM_ID(ram_id)
			) ram_i (
				.wr_en   (wr_en),
				.wr_addr (wr_addr),
				.wr_data (wr_data[(NUM_DSP-ram_id)*EW*10-1 : (NUM_DSP-(ram_id+1))*EW*10]),
				.rd_addr (rd_addr_balance[2*ram_id-1]),
				.rd_data (rd_data[(NUM_DSP-ram_id)*EW*10-1 : (NUM_DSP-(ram_id+1))*EW*10]),
				.clk 	 (clk), 
				.rst 	 (rst)
			);
		end
	end
endgenerate

endmodule

