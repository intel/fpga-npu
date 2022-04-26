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

module nx_axbs_slice #(
    parameter NUM_A = 2,
    parameter NUM_B = 2,
    parameter INDEX = 0,
    parameter SIZE_OUT = 16,
    parameter LATENCY = 4
)(
	input           clk,
	input signed  [7:0] din_a[0:NUM_A-1],
	input signed  [7:0] din_b[0:NUM_B-1],
    
	output signed [SIZE_OUT-1:0] dout
);

localparam MIN_A = (INDEX < NUM_B) ? 0 : (INDEX - NUM_B + 1);
localparam MAX_A = (INDEX < NUM_A) ? INDEX : NUM_A - 1;
localparam MAX_B = (INDEX < NUM_B) ? INDEX : NUM_B - 1;
localparam LOCAL_NUM = MAX_A - MIN_A + 1;

wire signed [7:0] din_a_local_w[0:LOCAL_NUM-1];
wire signed [7:0] din_b_local_w[0:LOCAL_NUM-1];

genvar j;
generate
for (j = 0; j < LOCAL_NUM; j=j+1) begin: loopb
    assign din_a_local_w[j] = {1'b0, din_a[j+MIN_A]};
    assign din_b_local_w[j] = {1'b0, din_b[MAX_B-j]};
end

wire signed [15+$clog2(LOCAL_NUM):0] dout_w;

nx_dot_product_int8 #(.NUM(LOCAL_NUM), .LATENCY(LATENCY)) dot_product(
    .clk(clk),
    .din_a(din_a_local_w),
    .din_b(din_b_local_w),
    .dout(dout_w[15+$clog2(LOCAL_NUM):0])
);    

if (SIZE_OUT > 16+$clog2(LOCAL_NUM))
    assign dout = { {(SIZE_OUT - $clog2(LOCAL_NUM) - 16) {dout_w[15+$clog2(LOCAL_NUM)]}}, dout_w};
else
    assign dout = dout_w;
endgenerate
endmodule

