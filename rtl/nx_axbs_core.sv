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

module nx_axbs_core #(
    parameter SIZE_A = 15,
    parameter SIZE_B = 15,
	 parameter SIZE_O = SIZE_A + SIZE_B
)(
	input           clk,
	input signed [SIZE_A-1:0] din_a,
	input signed [SIZE_B-1:0] din_b,
	output reg signed [SIZE_A+SIZE_B-1:0] dout
);
localparam NUM_A = (SIZE_A - 2) / 7 + 1;
localparam NUM_B = (SIZE_B - 2) / 7 + 1;

genvar i, j;
generate

localparam LATENCY = (NUM_A <= NUM_B) ? 4+$clog2((NUM_A-1)/6+1) : 4+$clog2((NUM_B-1)/6+1);

wire signed [7:0] din_a_w[0:NUM_A-1];
wire signed [7:0] din_b_w[0:NUM_B-1];


for (i = 0; i < NUM_A; i=i+1) begin : assign_a
    if (i < NUM_A - 1)
        assign din_a_w[i] = {1'b0, din_a[7*i+6:7*i]};
    else 
        assign din_a_w[i] = din_a[7*i+7:7*i];
end
    
for (i = 0; i < NUM_B; i=i+1) begin : assign_b
    if (i < NUM_B - 1)
        assign din_b_w[i] = {1'b0, din_b[7*i+6:7*i]};
    else
        assign din_b_w[i] = din_b[7*i+7:7*i];
end


wire signed [20:0] dot_product_out[0:NUM_A+NUM_B-1];

wire signed [7*(NUM_A+NUM_B)-1:0] dout1;
wire signed [7*(NUM_A+NUM_B):0] dout2;
wire signed [7*(NUM_A+NUM_B+1)-1:0] dout3;
wire signed [7*(NUM_A+NUM_B+1):0] dout4;
    
assign dout2[6:0] = 0;
assign dout3[13:0] = 0;
assign dout4[14:0] = 0;

if (7*(NUM_A+NUM_B)-1 >= 7*(NUM_A+NUM_B-2)+7)
    assign dout1[7*(NUM_A+NUM_B)-1:7*(NUM_A+NUM_B-2)+7] = 0;

assign dout2[7*(NUM_A+NUM_B)] = 0;
  
for (i = 0; i < NUM_A+NUM_B-1; i=i+1) begin: loopa
    
    nx_axbs_slice #(.NUM_A(NUM_A), .NUM_B(NUM_B), .INDEX(i), .SIZE_OUT(21), .LATENCY(LATENCY)) dot_product(
        .clk(clk),
        .din_a(din_a_w),
        .din_b(din_b_w),
        .dout(dot_product_out[i])
    );
    
    assign {dout3[7*i+20:7*i+14], dout2[7*i+13:7*i+7], dout1[7*i+6:7*i]} = dot_product_out[i];
    assign {dout4[7*i+21:7*i+15]} = {dot_product_out[i][20], 6'b0};
end

reg signed [SIZE_A+SIZE_B-1:0] dout12;
reg signed [SIZE_A+SIZE_B-1:0] dout31;

always @(posedge clk) begin
    
    dout12 <= SIZE_O'(dout1 + dout2);
    dout31 <= SIZE_O'(dout3 - dout4);
    dout <= dout12 + dout31;
end

endgenerate

endmodule
