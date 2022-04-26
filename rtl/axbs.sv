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

(* altera_attribute = "-name FRACTAL_SYNTHESIS ON; -name SYNCHRONIZER_IDENTIFICATION OFF" *)
module axbs #(
	parameter SIZE_A = 27,
	parameter SIZE_B = 27
) (
	input clk,
	input signed [SIZE_A-1:0] din_a,
	input signed [SIZE_B-1:0] din_b,
	output reg signed [SIZE_A+SIZE_B-1:0] dout
);

reg signed [SIZE_A+SIZE_B-1:0] dout_r;
reg signed [SIZE_A+SIZE_B-1:0] dout_rr;
reg signed [SIZE_A+SIZE_B-1:0] dout_rrr;

always @(posedge clk) begin
	dout_r <= din_a * din_b;
    dout_rr <= dout_r;
    dout_rrr <= dout_rr;
    dout <= dout_rrr;
end
endmodule
