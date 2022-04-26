// Copyright 2020 Intel Corporation.
//
// This reference design file is subject licensed to you by the terms and
// conditions of the applicable License Terms and Conditions for Hardware
// Reference Designs and/or Design Examples (either as signed by you or
// found at https://www.altera.com/common/legal/leg-license_agreement.html ).
//
// As stated in the license, you agree to only use this reference design
// solely in conjunction with Intel FPGAs or Intel CPLDs.
//
// THE REFERENCE DESIGN IS PROVIDED "AS IS" WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTY OF ANY KIND INCLUDING WARRANTIES OF MERCHANTABILITY,
// NONINFRINGEMENT, OR FITNESS FOR A PARTICULAR PURPOSE. Intel does not
// warrant or assume responsibility for the accuracy or completeness of any
// information, links or other items within the Reference Design and any
// accompanying materials.
//
// In the event that you do not agree with such terms and conditions, do not
// use the reference design file.
/////////////////////////////////////////////////////////////////////////////

module nx_dot6_int8 (
	input           clk,
	input signed  [7:0] din_a1,
	input signed  [7:0]	din_b1,
	input signed  [7:0]	din_a2,
	input signed  [7:0] din_b2,
	input signed  [7:0] din_a3,
	input signed  [7:0] din_b3,
	input signed  [7:0] din_a4,
	input signed  [7:0] din_b4,
	input signed  [7:0] din_a5,
	input signed  [7:0] din_b5,
	input signed  [7:0] din_a6,
	input signed  [7:0] din_b6,
	output reg signed [18:0] dout
);

wire signed [18:0] dout_w;
wire [5:0] tmp;
fourteennm_dsp_prime #(
	.dsp_mode("vector_fxp"),
	.dsp_sel_int4("select_int8"),
	.dsp_fp32_sub_en("float_sub_disabled"),
	.dsp_cascade("cascade_disabled")
)
dsp_prime_wys0 (
	.ena(1'b1),
	.clk(clk),
	.data_in({din_b6,din_a6,din_b5,din_a5,din_b4,din_a4,din_b3,din_a3,din_b2,din_a2,din_b1,din_a1}),
	.clr({1'b0,1'b0}),
	.result_l({tmp,dout_w}),

	.load_buf_sel(1'b0),
	.mode_switch(1'b0),
	.load_bb_one(1'b0),
	.load_bb_two(1'b0),
	.feed_sel(2'b0),
	.zero_en(1'b0),
	.shared_exponent(8'h0),
	.cascade_weight_in(88'h0),
	.cascade_data_in(96'h0),
	.acc_en(1'b0),

	.cascade_weight_out(),
	.cascade_data_out()
);
always @(posedge clk) begin
	dout <= dout_w;
end

endmodule

