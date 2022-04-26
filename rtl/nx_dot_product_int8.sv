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

module nx_dot_product_int8 #(
    parameter NUM = 16,
    parameter LATENCY = 4+$clog2((NUM-1)/6+1)
)(
	input           clk,
	input signed  [7:0] din_a[0:NUM-1],
	input signed  [7:0] din_b[0:NUM-1],
	output signed [15+$clog2(NUM):0] dout
);

localparam MIN_LATENCY = 4+$clog2((NUM-1)/6+1);
localparam DSP_NUM = (NUM - 1) / 6 + 1;

localparam NUM_6 = DSP_NUM * 6;

wire signed  [7:0] din_a_w[0:NUM_6-1];
wire signed  [7:0] din_b_w[0:NUM_6-1];

wire signed [18:0] dsp_out[0:DSP_NUM-1];
genvar i;
generate

for (i = 0; i < NUM_6; i=i+1) begin: loop1
    if (i < NUM) begin
        assign din_a_w[i] = din_a[i];
        assign din_b_w[i] = din_b[i];
    end
    else
    begin
        assign din_a_w[i] = 0;
        assign din_b_w[i] = 0;
    end
    
end

for (i = 0; i < DSP_NUM; i=i+1) begin: loop2
    if ((i < DSP_NUM-1) || (NUM_6 - NUM != 5)) begin
        nx_dot6_int8 dot (
            .clk(clk),
            .din_a1(din_a_w[6*i]),
            .din_b1(din_b_w[6*i]),
            .din_a2(din_a_w[6*i+1]),
            .din_b2(din_b_w[6*i+1]),
            .din_a3(din_a_w[6*i+2]),
            .din_b3(din_b_w[6*i+2]),
            .din_a4(din_a_w[6*i+3]),
            .din_b4(din_b_w[6*i+3]),
            .din_a5(din_a_w[6*i+4]),
            .din_b5(din_b_w[6*i+4]),
            .din_a6(din_a_w[6*i+5]),
            .din_b6(din_b_w[6*i+5]),
            .dout(dsp_out[i])
        );
    end else begin
        axbs #(.SIZE_A(8), .SIZE_B(8)) mult (
            .clk(clk),
            .din_a(din_a_w[6*i]),
            .din_b(din_b_w[6*i]),
            .dout(dsp_out[i][15:0])
        );
        assign dsp_out[i][18:16] = {3{dsp_out[i][15]}};        
    end
end

wire signed [15+$clog2(NUM):0] dout_ww;

if (DSP_NUM > 1) begin
    wire signed [18+$clog2(DSP_NUM):0] dout_w;
    adder_tree #(.SIZE(19), .NUM(DSP_NUM)) adder_tree_inst ( 
       .clk(clk),
       .din(dsp_out),
       .dout(dout_w)
    );
    assign dout_ww = dout_w[15+$clog2(NUM):0];
end else begin
    assign dout_ww = dsp_out[0][15+$clog2(NUM):0];
end

integer j;
if (LATENCY < MIN_LATENCY) begin
    initial begin
        $fatal("Specified latency %0d is too small", LATENCY);
    end
end if (LATENCY == MIN_LATENCY) begin
    assign dout = dout_ww;
end else begin
    reg signed [15+$clog2(NUM):0] dout_r[0:LATENCY-MIN_LATENCY-1];
    always @(posedge clk) begin
		dout_r[0] <= dout_ww;
        for (j = 1; j < LATENCY-MIN_LATENCY; j=j+1) begin
            dout_r[j] <= dout_r[j-1];
        end
	end
    assign dout = dout_r[LATENCY-MIN_LATENCY-1];
end


endgenerate

endmodule

