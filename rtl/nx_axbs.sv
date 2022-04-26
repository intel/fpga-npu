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

module nx_axbs #(
    parameter SIZE_A = 32,
    parameter SIZE_B = 32
)(
	input           clk,
	input signed [SIZE_A-1:0] din_a,
	input signed [SIZE_B-1:0] din_b,
	output signed [SIZE_A+SIZE_B-1:0] dout
);

generate

if ((SIZE_A > 512) && (SIZE_B > 512)) begin
    initial begin
        $fatal("Error: %0dx%0d multiplier is not supported", SIZE_A, SIZE_B);
    end
end

localparam NUM_A = (SIZE_A - 2) / 7 + 1;
localparam NUM_B = (SIZE_B - 2) / 7 + 1;

if ((NUM_A == 1) || (NUM_B == 1)) begin

    axbs #(.SIZE_A(SIZE_A), .SIZE_B(SIZE_B)) mult (
        .clk(clk),
        .din_a(din_a),
        .din_b(din_b),
        .dout(dout)
    );

end
else
begin
    localparam SIZE_A_PRIME = NUM_A * 7 + 1;
    localparam SIZE_B_PRIME = NUM_B * 7 + 1;

    wire signed [SIZE_A_PRIME-1:0] din_a_prime;
    wire signed [SIZE_B_PRIME-1:0] din_b_prime;

    assign din_a_prime = {din_a, {(SIZE_A_PRIME - SIZE_A){1'b0}}};
    assign din_b_prime = {din_b, {(SIZE_B_PRIME - SIZE_B){1'b0}}};

    wire signed [SIZE_A_PRIME+SIZE_B_PRIME-1:0] dout_prime;

    nx_axbs_core #(.SIZE_A(SIZE_A_PRIME), .SIZE_B(SIZE_B_PRIME)) mult (
        .clk(clk),
        .din_a(din_a_prime),
        .din_b(din_b_prime),
        .dout(dout_prime)
    );

    assign dout = dout_prime[SIZE_A_PRIME+SIZE_B_PRIME-1:SIZE_A_PRIME+SIZE_B_PRIME-SIZE_A-SIZE_B];
end
endgenerate

endmodule
