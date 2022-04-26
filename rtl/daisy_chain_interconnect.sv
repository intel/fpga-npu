
// This module implements a daisy chain interconnect from a source to multiple sinks with parameterizable latency per hop.
(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name DONT_MERGE_REGISTER ON" *) module daisy_chain_interconnect # (
	parameter DATAW = 32,
	parameter END_POINTS = 4,
	parameter LATENCY_PER_HOP = 2
) (
	input 				clk,
	input 				rst,
	input  [DATAW-1:0] 	i_daisy_chain_in,
	output [DATAW-1:0] 	o_daisy_chain_out [0:END_POINTS-1]
);

reg [DATAW-1:0] pipeline [0:LATENCY_PER_HOP*END_POINTS-1];

integer t;
always @ (posedge clk) begin
	// Set the input to the first pipeline stage
	pipeline[0] <= i_daisy_chain_in;
	// Progress the pipeline
	for (t = 1; t < LATENCY_PER_HOP*END_POINTS; t = t + 1) begin
		pipeline[t] <= pipeline[t-1];
	end
end

// Hook up outputs
genvar i;
generate
	for(i = 0; i < END_POINTS; i = i + 1) begin: gen_outputs
		assign o_daisy_chain_out[i] = pipeline[(LATENCY_PER_HOP-1)+i*LATENCY_PER_HOP];
	end
endgenerate

endmodule