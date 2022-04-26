`include "npu.vh"

module dpe #(
	parameter DATAW = `EW,
	parameter LANES = `DOTW,
	parameter DOTW = `PRIME_DOTW,
	parameter OUTW = 25,
	parameter REDW = `ACCW,
	parameter DOT_PER_DSP = `DOT_PER_DSP,
	parameter NUM_DSP = LANES / DOTW,
	parameter MULT_LATENCY = `MULT_LATENCY,
	parameter SIM_FLAG = 0,
	parameter TILE_ID = 0,
	parameter DPE_ID = 0
)(
	input clk,
	input reset,
	input ena,
	input [DATAW*LANES-1:0] din_a,
	input valid_a,
	input [DATAW*DOTW-1:0] din_b,
	input reg_ctrl,
	input load_sel,
	input dpe_val,
	output [DOT_PER_DSP*REDW-1:0] dout,
	output val_res
);

localparam PIPELINE_DEPTH = (NUM_DSP+1)*DOT_PER_DSP + 3;
localparam WEIGHT_PIPELINE_DEPTH = (NUM_DSP+1)*DOT_PER_DSP-1;

wire [87:0] cascade_weight[0:NUM_DSP];
wire [95:0] first_dsp_input;
wire [NUM_DSP*DOT_PER_DSP*REDW-1:0] dsp_outputs;
reg [DOT_PER_DSP*REDW-1:0] red_outputs;
reg val_red;
assign first_dsp_input = {16'b0, din_b};

reg [DOT_PER_DSP*OUTW-1:0] dsp_dout [NUM_DSP-1:0];

reg reg_ctrl_chain [0:DOT_PER_DSP-1];
reg ena_chain [0:DOT_PER_DSP-1];
reg valid_a_chain [0:MULT_LATENCY];
reg r_load_sel;

//reg [DATAW*LANES-1:0] din_a_balance [0:(2*(NUM_DSP-1))-1];
reg load_sel_balance [0:(2*(NUM_DSP-1))-1];
reg reg_ctrl_balance [0:(2*(NUM_DSP-1))-1];
wire [95:0] cascade_data [0:NUM_DSP-1];

integer p;
always@(posedge clk) begin
	if(reset) begin
		for(p = 0; p < DOT_PER_DSP; p = p + 1) begin
			reg_ctrl_chain[p] <= 0;
			ena_chain[p] <= 0;
		end
		for(p = 0; p <= MULT_LATENCY; p = p + 1) begin
			valid_a_chain[p] <= 0;
		end
		r_load_sel <= 0;
	end else begin
		reg_ctrl_chain[0] <= reg_ctrl;
		ena_chain[0] <= ena;
		valid_a_chain[0] <= valid_a;
		for(p = 1; p < DOT_PER_DSP; p = p + 1) begin
			reg_ctrl_chain[p] <= reg_ctrl_chain[p-1];
			ena_chain[p] <= ena_chain[p-1];
		end
		for(p = 1; p <= MULT_LATENCY; p = p + 1) begin
			valid_a_chain[p] <= valid_a_chain[p-1];
		end
		r_load_sel <= load_sel;
	end
end 

integer c;
always @ (posedge clk) begin
	if (reset) begin
		for(c = 0; c < 2*(NUM_DSP-1); c = c + 1) begin
			load_sel_balance[c] <= 0;
			reg_ctrl_balance[c] <= 0;
		end
	end else begin
		//din_a_balance[0] <= din_a;
		load_sel_balance[0] <= load_sel;
		reg_ctrl_balance[0] <= reg_ctrl_chain[DOT_PER_DSP-2];
		for(c = 1; c < 2*(NUM_DSP-1); c = c + 1) begin
			//din_a_balance[c] <= din_a_balance[c-1];
			load_sel_balance[c] <= load_sel_balance[c-1];
			reg_ctrl_balance[c] <= reg_ctrl_balance[c-1];
		end
	end
end

(*preserve*) reg [1:0] const_feed_sel;
always @ (posedge clk) begin
	const_feed_sel <= 2'b01;
end

// The first DSP block is used to feed inputs from VRF serially
genvar k;
generate
for(k = 0; k < 1; k = k + 1) begin:gen_first_dsp
	if(SIM_FLAG) begin
		prime_dsp_tensor_int8 # (
			.DSP_CASCADE("cascade_disabled")
		)first_dsp_wys (
			.clk(clk),
			.clr(reset),
			.data_in(first_dsp_input),
			.load_buf_sel(1'b0),
			.load_bb_one(1'b1),
			.load_bb_two(1'b0),
			.feed_sel(2'b00),
			.zero_en(1'b1),
			.cascade_weight_out(cascade_weight[0])
		);
	end else begin
		fourteennm_dsp_prime #(
			  .dsp_mode("tensor_fxp"),
			  .dsp_sel_int4("select_int8"),
			  .dsp_fp32_sub_en("float_sub_disabled"),
			  .dsp_cascade("cascade_disabled")
		) first_dsp_wys (    
			  .ena(1'b1),
			  .clk(clk),
			  .data_in(first_dsp_input),
			  .clr({reset,reset}),
			  .load_buf_sel(1'b0),
			  .mode_switch(1'b0),
			  .load_bb_one(1'b1),
			  .load_bb_two(1'b0),
			  .feed_sel(2'b00),
			  .zero_en(1'b1),
			  .acc_en(1'b0),
			  .cascade_weight_out(cascade_weight[0])
		);
	end
end
endgenerate

genvar j;
generate
for(j = 0; j < NUM_DSP; j = j + 1) begin:gen_dsp
	if(SIM_FLAG) begin
		if(j == 0) begin
			prime_dsp_tensor_int8 # (
				.TILE_ID(TILE_ID),
				.DPE_ID(DPE_ID),
				.DSP_CASCADE("cascade_disabled")
			)dsp_prime_wys (
				.clk(clk),
				.clr(reset),
				.ena(ena_chain[DOT_PER_DSP-1]),
				.data_in({16'b0, din_a[(NUM_DSP-j)*DATAW*DOTW-1: (NUM_DSP-(j+1))*DATAW*DOTW]}),
				.load_buf_sel(load_sel),
				.load_bb_one(~reg_ctrl_chain[DOT_PER_DSP-2] && ena_chain[DOT_PER_DSP-2]),
				.load_bb_two( reg_ctrl_chain[DOT_PER_DSP-2] && ena_chain[DOT_PER_DSP-2]),
				.feed_sel(const_feed_sel),
				.zero_en(1'b0),
				.cascade_weight_in(cascade_weight[j]),
				.cascade_weight_out(cascade_weight[j+1]),
				.result_h(dsp_dout[j][74:38]),
				.result_l(dsp_dout[j][37:0]),
				.cascade_data_out(cascade_data[j])
			);
		end else begin
			prime_dsp_tensor_int8 # (
				.TILE_ID(TILE_ID),
				.DPE_ID(DPE_ID),
				.DSP_CASCADE("cascade_enabled")
			)dsp_prime_wys (
				.clk(clk),
				.clr(reset),
				.ena(ena_chain[DOT_PER_DSP-1]),
				//.data_in({16'b0, din_a_balance[2*j-1][(NUM_DSP-j)*DATAW*DOTW-1: (NUM_DSP-(j+1))*DATAW*DOTW]}),
				.data_in({16'b0, din_a[(NUM_DSP-j)*DATAW*DOTW-1: (NUM_DSP-(j+1))*DATAW*DOTW]}),
				.load_buf_sel(load_sel_balance[2*j-1]),
				.load_bb_one(~reg_ctrl_balance[2*j-2] && ~reg_ctrl_chain[DOT_PER_DSP-2] && ena_chain[DOT_PER_DSP-2]),
				.load_bb_two( reg_ctrl_balance[2*j-2] &&  reg_ctrl_chain[DOT_PER_DSP-2] && ena_chain[DOT_PER_DSP-2]),
				.feed_sel(const_feed_sel),
				.zero_en(1'b0),
				.cascade_weight_in(cascade_weight[j]),
				.cascade_weight_out(cascade_weight[j+1]),
				.result_h(dsp_dout[j][74:38]),
				.result_l(dsp_dout[j][37:0]),
				.cascade_data_in(cascade_data[j-1]),
				.cascade_data_out(cascade_data[j])
			);
		end 
	end else begin
		if(j == 0) begin
			fourteennm_dsp_prime #(
				.dsp_mode("tensor_fxp"),
				.dsp_sel_int4("select_int8"),
				.dsp_fp32_sub_en("float_sub_disabled"),
				.dsp_cascade("cascade_disabled")
			) dsp_prime_wys (        
				.ena(1'b1),
				.clk(clk),
				.clr({reset,reset}),
				.data_in({16'b0, din_a[(NUM_DSP-j)*DATAW*DOTW-1: (NUM_DSP-(j+1))*DATAW*DOTW]}),
				.load_buf_sel(load_sel),
				.mode_switch(1'b0),
				.load_bb_one(~reg_ctrl_chain[DOT_PER_DSP-2] && ena_chain[DOT_PER_DSP-2]),
				.load_bb_two( reg_ctrl_chain[DOT_PER_DSP-2] && ena_chain[DOT_PER_DSP-2]),
				.feed_sel(const_feed_sel),
				.zero_en(1'b0),
				.acc_en(1'b0),
				.cascade_weight_in(cascade_weight[j]),
				.cascade_weight_out(cascade_weight[j+1]),
				.result_h(dsp_dout[j][74:38]),
				.result_l(dsp_dout[j][37:0]),
				.cascade_data_out(cascade_data[j])
			); 
		end else begin
			fourteennm_dsp_prime #(
				.dsp_mode("tensor_fxp"),
				.dsp_sel_int4("select_int8"),
				.dsp_fp32_sub_en("float_sub_disabled"),
				.dsp_cascade("cascade_enabled")
			) dsp_prime_wys (        
				.ena(1'b1),
				.clk(clk),
				.clr({reset,reset}),
				//.data_in({16'b0, din_a_balance[2*j-1][(NUM_DSP-j)*DATAW*DOTW-1: (NUM_DSP-(j+1))*DATAW*DOTW]}),
				.data_in({16'b0, din_a[(NUM_DSP-j)*DATAW*DOTW-1: (NUM_DSP-(j+1))*DATAW*DOTW]}),
				.load_buf_sel(load_sel_balance[2*j-1]),
				.mode_switch(1'b0),
				.load_bb_one(~reg_ctrl_balance[2*j-2] && ~reg_ctrl_chain[DOT_PER_DSP-2] && ena_chain[DOT_PER_DSP-2]),
				.load_bb_two( reg_ctrl_balance[2*j-2] &&  reg_ctrl_chain[DOT_PER_DSP-2] && ena_chain[DOT_PER_DSP-2]),
				.feed_sel(const_feed_sel),
				.zero_en(1'b0),
				.acc_en(1'b0),
				.cascade_weight_in(cascade_weight[j]),
				.cascade_weight_out(cascade_weight[j+1]),
				.result_h(dsp_dout[j][74:38]),
				.result_l(dsp_dout[j][37:0]),
				.cascade_data_in(cascade_data[j-1]),
				.cascade_data_out(cascade_data[j])
			); 
		end
	end
end
endgenerate

assign dout = { {(REDW-OUTW){dsp_dout[NUM_DSP-1][74]}}, dsp_dout[NUM_DSP-1][74:50],
				{(REDW-OUTW){dsp_dout[NUM_DSP-1][49]}}, dsp_dout[NUM_DSP-1][49:25], 
				{(REDW-OUTW){dsp_dout[NUM_DSP-1][24]}}, dsp_dout[NUM_DSP-1][24: 0]};
assign val_res = valid_a_chain [MULT_LATENCY];

`ifdef DISPLAY_MVU   
always @(posedge clk) begin
	if(DPE_ID == 0 && val_res) begin
		$display("[%0t][DPE] dout: %b %b %b %b %b", 
			$time, dout, dsp_dout[0], dsp_dout[1], dsp_dout[2], dsp_dout[3]);
	end
end
`endif

endmodule

module reduction #(
	parameter DW = 32,
	parameter L = 3,
	parameter N = 2
)(
	input  [DW*L*N-1:0] din,
	output reg [DW*L-1:0] dout,
	input  valid_in,
	output reg valid_out,
	input  clk, 
	input  rst
);
	reg [(N/2)*DW*L-1:0] sum;
	reg valid;

	genvar i, j;
	generate
		if (N == 1) begin
			always @(posedge clk) begin
				dout <= din;
			end
			always @(posedge clk) begin
				if (rst) valid_out <= 0;
				else valid_out <= valid_in;
			end
		end else if (N == 2) begin
			for (j = 0; j < L; j = j + 1) begin : gen_elements_w_two_vectors
				always @(posedge clk) begin
					dout[j*DW+:DW] <= din[j*DW+:DW] + din[DW*L+j*DW+:DW];
				end
			end	
			always @(posedge clk) begin
				if (rst) valid_out <= 0;
				else valid_out <= valid_in;
			end
		end else begin
			for (i = 0; i < N/2; i = i + 1) begin : gen_vectors
				for (j = 0; j < L; j = j + 1) begin : gen_elements_w_mul_vectors
					always @(posedge clk) begin
						sum[i*DW*L+j*DW+:DW] <= 
							din[(2*i)*DW*L+j*DW+:DW] + din[(2*i+1)*DW*L+j*DW+:DW];
					end
				end
			end
			always @(posedge clk) begin
				if (rst) valid <= 0;
				else valid <= valid_in;
			end

			reduction #(
				.DW(DW), .L(L), .N(N/2)
			) red (
				.din(sum), 
				.dout(dout), 
				.valid_in(valid), 
				.valid_out(valid_out), 
				.clk(clk), 
				.rst(rst)
			);
		end
	endgenerate
endmodule
