`include "npu.vh"

module bram_accum # (
	parameter ACCW = `ACCW,
	parameter NDPE = `NDPE,
	parameter DOTW = `DOTW,
	parameter PRIME_DOTW = `PRIME_DOTW,
	parameter DOT_PER_DSP = `DOT_PER_DSP,
	parameter NUM_DSP = `NUM_DSP,
    parameter NUM_CHUNKS = NDPE/DOTW,
	parameter NUM_ACCUM = `NUM_ACCUM,
	parameter ACCIDW = `ACCIDW
)(
	input  clk,
    input  rst,
    input  [3+ACCIDW-1:0] accum_ctrl [0:3*NDPE-1], //[3] valid, [2:1] op, [0] sel
    input  [3*ACCW*NDPE-1:0] accum_in,
	output [NDPE-1:0] valid_out,
	output [3*ACCW*NDPE-1:0] accum_out
);

localparam ACCUM_DEPTH = NUM_ACCUM*2;
localparam ACCUM_ADDRW = $clog2(ACCUM_DEPTH);
localparam BRAM_LATENCY = 2;
localparam [1:0] ACC_OP_SET = 0, ACC_OP_UPD = 1, ACC_OP_WB  = 2, ACC_OP_SET_AND_WB = 3;

reg [ACCUM_ADDRW-1:0] accum_rd_addr [0:3*NDPE-1];
wire [ACCW-1:0] accum_rd_data [0:3*NDPE-1];

reg [3*ACCW*NDPE-1:0] r_accum_in [0:BRAM_LATENCY];
reg [ACCUM_ADDRW-1:0] r_accum_rd_addr [0:BRAM_LATENCY][0:3*NDPE-1];
reg [3+ACCIDW-1:0] r_accum_ctrl [0:BRAM_LATENCY][0:3*NDPE-1];
reg [ACCW-1:0] accum_wr_data [0:3*NDPE-1];
reg [NDPE-1:0] valid [0:BRAM_LATENCY];

wire [3*ACCW*NDPE-1:0] accum_res;

integer a, p;
always @ (posedge clk) begin
	if (rst) begin
		for(a = 0; a < 3*NDPE; a = a + 1) begin
			accum_rd_addr[a] <= 0;
		end
		for(p = 0; p < BRAM_LATENCY+1; p = p + 1) begin
			valid[p] <= 'd0;
		end
	end else begin
		for(a = 0; a < 3*NDPE; a = a + 1) begin
			// If valid input, increment read address
			if(accum_ctrl[a][3+ACCIDW-1]) begin
				if(accum_rd_addr[a] == accum_ctrl[a][ACCIDW-1:0]-1) begin
					accum_rd_addr[a] <= 0;
				end else begin
					accum_rd_addr[a] <= ACCUM_ADDRW'(accum_rd_addr[a] + 1'b1);
				end
			end

			// Pipeline ctrl, address and input to align with read value (then an extra pipeline for addition)
			r_accum_rd_addr[0][a] <= accum_rd_addr[a];
			r_accum_in[0] <= accum_in;
			r_accum_ctrl[0][a] <= accum_ctrl[a];
			for(p = 1; p < BRAM_LATENCY+1; p = p + 1) begin
				r_accum_rd_addr[p][a] <= r_accum_rd_addr[p-1][a];
				r_accum_in[p] <= r_accum_in[p-1];
				r_accum_ctrl[p][a] <= r_accum_ctrl[p-1][a];
			end

			// Perform addition
			accum_wr_data[a] <= ((r_accum_ctrl[BRAM_LATENCY-1][a][ACCIDW+:2] == ACC_OP_SET) 
				|| (r_accum_ctrl[BRAM_LATENCY-1][a][ACCIDW+:2] == ACC_OP_SET_AND_WB))?
				r_accum_in[BRAM_LATENCY-1][a*ACCW+:ACCW]:
				r_accum_in[BRAM_LATENCY-1][a*ACCW+:ACCW] + accum_rd_data[a];
		end

		// Valid pipeline
		for(a = 0; a < NDPE; a = a + 1) begin
			valid[0][a] <= ((accum_ctrl[a*3][ACCIDW+:2] == ACC_OP_WB) || (accum_ctrl[a*3][ACCIDW+:2] == ACC_OP_SET_AND_WB)) 
				&& (accum_ctrl[a*3][3+ACCIDW-1]);
			for(p = 1; p < BRAM_LATENCY+1; p = p + 1) begin
				valid[p][a] <= valid[p-1][a];
			end
		end
	end
end

genvar accum_id;
generate
	for(accum_id = 0; accum_id < 3*NDPE; accum_id = accum_id + 1) begin: gen_accum_ram
		ram #(
			.ID 		(accum_id), 
			.DW 		(ACCW), 
			.AW 		(ACCUM_ADDRW), 
			.DEPTH 		(ACCUM_DEPTH),
			.MODULE_ID 	("accum")
		) accum_ram (
			.wr_en   	(r_accum_ctrl[BRAM_LATENCY][accum_id][3+ACCIDW-1]),
			.wr_addr 	(r_accum_rd_addr[BRAM_LATENCY][accum_id]),
			.wr_data 	(accum_wr_data[accum_id]),
			.rd_addr 	(accum_rd_addr[accum_id]),
			.rd_data 	(accum_rd_data[accum_id]),
			.clk 		(clk), 
			.rst 		(rst)
		);

		assign accum_res[accum_id*ACCW+:ACCW] = accum_wr_data[accum_id];
	end
endgenerate

reg [3*ACCW*NDPE-1:0] accum_out_arranged;
always @(*) begin
    for (p = 0; p < NUM_CHUNKS*3; p = p + 3) begin
        accum_out_arranged[(p*ACCW*DOTW)+:(ACCW*DOTW)] = accum_res[(p/3*ACCW*DOTW)+:(ACCW*DOTW)];
        accum_out_arranged[((p+1)*ACCW*DOTW)+:(ACCW*DOTW)] = accum_res[(ACCW*NDPE)+(p/3*ACCW*DOTW)+:(ACCW*DOTW)];
        accum_out_arranged[((p+2)*ACCW*DOTW)+:(ACCW*DOTW)] = accum_res[(2*ACCW*NDPE)+(p/3*ACCW*DOTW)+:(ACCW*DOTW)];
    end
end

assign valid_out = valid[BRAM_LATENCY];
assign accum_out = accum_out_arranged;

`ifdef DISPLAY_MVU
always @(posedge clk) begin
  if (accum_ctrl[0][3+ACCIDW-1]) begin
    $display("[%0t][ACCUM] addr: %d, size: %d", 
    	$time,
    	accum_rd_addr[0],
    	accum_ctrl[0][ACCIDW-1:0]);
  end
end
`endif

endmodule